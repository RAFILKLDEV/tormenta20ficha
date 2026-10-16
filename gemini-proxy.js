// Local bridge: SAO-NODE -> MonsterIA/Firecast.
// No credentials are exchanged: all processes run on the same computer.
const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const app = express();
app.use(express.json({ limit: "25mb" }));
const API_KEY = process.env.GEMINI_API_KEY || "";
// Configuração mantida para as rotas legadas de consulta/ticket do SAO-NODE.
// A fila local nova não depende desses segredos; eles só são usados quando
// um consumidor antigo envia ticket ou pede /sao-node/monster-xml.
const SAO_NODE_BASE_URL = process.env.SAO_NODE_BASE_URL || "http://localhost:3001";
const SAO_NODE_SESSION_COOKIE = process.env.SAO_NODE_SESSION_COOKIE || "";
const SAO_NODE_BRIDGE_TOKEN = process.env.SAO_NODE_BRIDGE_TOKEN || "";
const FIRECAST_BRIDGE_TOKEN = process.env.FIRECAST_BRIDGE_TOKEN || SAO_NODE_BRIDGE_TOKEN;
const PROXY_ALLOWED_ORIGINS = new Set(
    (process.env.PROXY_ALLOWED_ORIGINS || "http://localhost:5173,http://127.0.0.1:5173")
        .split(",").map((origin) => origin.trim()).filter(Boolean)
);
const MAX_TRANSFER_QUEUE = Number(process.env.FIRECAST_MAX_QUEUE || 100);
const LEASE_MS = Number(process.env.FIRECAST_TRANSFER_LEASE_MS || 30000);
const TRANSFER_TTL_MS = Number(process.env.FIRECAST_TRANSFER_TTL_MS || 24 * 60 * 60 * 1000);
const HEARTBEAT_TTL_MS = Number(process.env.FIRECAST_HEARTBEAT_TTL_MS || 15000);
const IMAGE_PROXY_TIMEOUT_MS = Number(process.env.FIRECAST_IMAGE_PROXY_TIMEOUT_MS || 10000);
const IMAGE_PROXY_MAX_BYTES = Number(process.env.FIRECAST_IMAGE_PROXY_MAX_BYTES || 10 * 1024 * 1024);
const IMAGE_PROXY_CACHE_TTL_MS = Number(process.env.FIRECAST_IMAGE_PROXY_CACHE_TTL_MS || 10 * 60 * 1000);
const QUEUE_FILE = path.resolve(process.env.FIRECAST_QUEUE_FILE || path.join(process.cwd(), ".sao-node-transfers.json"));
const transfers = new Map();
const consumers = new Map();
const imageCache = new Map();
function now() { return Date.now(); }
function newTransferId() { return crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(18).toString("hex"); }
function asString(value, max = 10000) { if (value === undefined || value === null) return ""; return String(value).slice(0, max); }
function normalizeImageUrl(value) {
    const text = asString(value, 20000).trim();
    if (!text) return "";
    try {
        const parsed = new URL(text);
        if (parsed.protocol === "http:" && parsed.hostname === "127.0.0.1" && parsed.port === "3001" && parsed.pathname.startsWith("/api/v1/firecast/images/")) parsed.hostname = "localhost";
        return parsed.toString();
    } catch { return text; }
}
function asBoolean(value) {
    if (value === true || value === 1) return true;
    if (typeof value === "string") return ["true", "1", "sim", "yes", "ready"].includes(value.trim().toLowerCase());
    return false;
}
function originAllowed(req) {
    const origin = req.headers.origin;
    return !origin || PROXY_ALLOWED_ORIGINS.has(origin);
}
function bearer(req) {
    const value = String(req.headers.authorization || "");
    return value.startsWith("Bearer ") ? value.slice(7) : "";
}
function requireFirecast(req, res, allowReadyHeartbeat = false) {
    // Instalações locais novas não precisam de segredo entre Firecast e o
    // proxy. Se o administrador configurou o token legado, preservamos a
    // exigência para os consumidores antigos.
    if (!FIRECAST_BRIDGE_TOKEN) return true;
    const consumerId = asString(req.body?.consumerId || req.query?.consumerId, 200).trim();
    const consumer = consumerId ? consumers.get(consumerId) : null;
    if (consumer && consumer.ready === true && now() - consumer.lastSeenAt <= HEARTBEAT_TTL_MS) return true;
    if (allowReadyHeartbeat && asBoolean(req.body?.ready)) return true;
    if (bearer(req) !== FIRECAST_BRIDGE_TOKEN) {
        res.status(401).json({ error: "firecast_nao_autorizado" });
        return false;
    }
    return true;
}
function randomToken(bytes = 32) {
    return crypto.randomBytes(bytes).toString("base64url");
}
async function saoNodeRequest(pathname, options = {}) {
    if (!SAO_NODE_BRIDGE_TOKEN) {
        const error = new Error("SAO_NODE_BRIDGE_TOKEN nao configurado");
        error.code = "sao_node_bridge_nao_configurado";
        throw error;
    }
    const response = await fetch(`${SAO_NODE_BASE_URL}${pathname}`, {
        ...options,
        headers: {
            ...(options.headers || {}),
            "Content-Type": "application/json",
            Authorization: `Bearer ${SAO_NODE_BRIDGE_TOKEN}`
        }
    });
    const text = await response.text();
    let data;
    try { data = JSON.parse(text); } catch { data = { raw: text }; }
    if (!response.ok) {
        const error = new Error(data?.error?.message || data?.error || `SAO-NODE HTTP ${response.status}`);
        error.status = response.status;
        error.code = data?.error?.code || data?.code || `sao_node_http_${response.status}`;
        throw error;
    }
    return data;
}
function rememberConsumer(consumerId, timestamp, ready) {
    const previous = consumers.get(consumerId) || {};
    const consumer = {
        consumerId,
        lastSeenAt: timestamp,
        // A heartbeat explicitly controls readiness.  Omitting it preserves
        // the old connection semantics while correctly reporting not-ready.
        ready: ready === undefined ? previous.ready === true : ready === true
    };
    consumers.set(consumerId, consumer);
    return consumer;
}
function loadQueue() {
    try {
        if (!fs.existsSync(QUEUE_FILE)) return;
        const parsed = JSON.parse(fs.readFileSync(QUEUE_FILE, "utf8"));
        const list = Array.isArray(parsed) ? parsed : parsed?.transfers;
        if (!Array.isArray(list)) return;
        let released = false;
        for (const transfer of list) {
            if (!transfer || typeof transfer.transferId !== "string" || !transfer.transferId) continue;
            // No consumer survives a proxy restart, so a claimed item must be
            // available to the next Firecast poll immediately.
            if (transfer.status === "claimed") {
                transfer.status = "queued";
                transfer.claimedBy = null;
                transfer.claimedAt = 0;
                transfer.updatedAt = Date.now();
                released = true;
            }
            transfers.set(transfer.transferId, transfer);
        }
        if (released) persistQueue();
    } catch (error) { console.warn("Não foi possível carregar a fila persistida:", error.message); }
}
function persistQueue() {
    const temporary = QUEUE_FILE + "." + process.pid + ".tmp";
    try {
        fs.mkdirSync(path.dirname(QUEUE_FILE), { recursive: true });
        fs.writeFileSync(temporary, JSON.stringify({ version: 1, transfers: [...transfers.values()] }, null, 2), "utf8");
        fs.renameSync(temporary, QUEUE_FILE);
        return true;
    } catch (error) {
        try { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); } catch { /* best effort */ }
        console.error("Não foi possível persistir a fila:", error.message);
        return false;
    }
}
function cleanupTransfers() {
    const snapshot = [...transfers.entries()].map(([id, transfer]) => [id, { ...transfer }]);
    const timestamp = now(); let changed = false;
    for (const [id, transfer] of transfers) {
        if (transfer.status === "claimed" && Number(transfer.claimedAt || 0) + LEASE_MS <= timestamp) {
            transfer.status = "queued"; transfer.claimedBy = null; transfer.claimedAt = 0; transfer.updatedAt = timestamp; changed = true;
        }
        if (["applied", "failed", "rejected"].includes(transfer.status) && timestamp - Number(transfer.updatedAt || transfer.createdAt || timestamp) > TRANSFER_TTL_MS) { transfers.delete(id); changed = true; }
    }
    if (changed && !persistQueue()) {
        transfers.clear();
        for (const [id, transfer] of snapshot) transfers.set(id, transfer);
        return false;
    }
    return true;
}
function setCors(req, res) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (req.method === "OPTIONS") return res.sendStatus(204);
    return null;
}
app.use((req, res, next) => setCors(req, res) || next());
function transferPayload(body, transferId, timestamp) {
    const monster = body.monster && typeof body.monster === "object" ? body.monster : {};
    const media = monster.media && typeof monster.media === "object" ? monster.media : {};
    const imageUrl = normalizeImageUrl([body.imageUrl, body.imageURL, body.imagemURL, body.image, monster.imageUrl, monster.imageURL, monster.imagemURL, monster.image, media.imageUrl, media.imageURL, media.url, media.image]
        .map((value) => asString(value, 20000).trim()).find(Boolean) || "");
    return {
        transferId, xml: asString(body.xml, 2000000), campaignId: asString(body.campaignId, 500), monsterId: asString(body.monsterId, 500),
        monsterName: asString(body.monsterName || body.monster?.name || "Criatura", 500) || "Criatura", imageUrl,
        originalSheet: body.originalSheet ?? null, saoNodeSourceJson: body.saoNodeSourceJson ?? null, monster: body.monster ?? null, status: "queued", createdAt: timestamp, updatedAt: timestamp,
        claimedBy: null, claimedAt: 0, message: ""
    };
}
// Recebe uma transferência completa (contrato novo) ou resgata um ticket do
// contrato antigo. Nos dois casos a fila persistida é a mesma.
app.post("/sao-node/transfers", async (req, res) => {
    if (!cleanupTransfers()) return res.status(503).json({ error: "fila_nao_persistida" });
    const body = req.body && typeof req.body === "object" ? req.body : {};
    if (!originAllowed(req)) return res.status(403).json({ error: "origem_nao_autorizada" });
    if (typeof body.ticket === "string" && body.ticket.trim() !== "") {
        if (!originAllowed(req)) return res.status(403).json({ error: "origem_nao_autorizada" });
        if (!SAO_NODE_BRIDGE_TOKEN) return res.status(503).json({ error: "sao_node_bridge_nao_configurado" });
        const activeCount = [...transfers.values()].filter((item) => item.status === "queued" || item.status === "claimed").length;
        if (activeCount >= MAX_TRANSFER_QUEUE) return res.status(429).json({ error: "fila_firecast_cheia" });
        try {
            const issued = await saoNodeRequest("/api/v1/firecast/transfers/redeem", {
                method: "POST", body: JSON.stringify({ ticket: body.ticket })
            });
            const transferId = asString(issued.transferId, 500) || newTransferId();
            const existing = transfers.get(transferId);
            if (existing) return res.status(202).json({ ok: true, transferId, status: existing.status, monsterName: existing.monsterName });
            const transfer = transferPayload({ ...issued, xml: issued.xml || "", transferId }, transferId, now());
            transfer.receiptToken = randomToken(32);
            transfers.set(transferId, transfer);
            if (!persistQueue()) {
                transfers.delete(transferId);
                return res.status(503).json({ error: "fila_nao_persistida" });
            }
            return res.status(202).json({ ok: true, transferId, receiptToken: transfer.receiptToken, status: "queued", monsterName: transfer.monsterName });
        } catch (error) {
            const status = error.status === 401 || error.status === 403 ? error.status : error.status || 502;
            return res.status(status).json({ error: error.code || "sao_node_indisponivel", message: error.message });
        }
    }

    const transferId = asString(body.transferId, 500) || newTransferId();
    if (!body.xml || typeof body.xml !== "string") return res.status(400).json({ error: "xml_ausente" });
    const existing = transfers.get(transferId);
    if (existing) return res.status(202).json({ ok: true, transferId, status: existing.status, monsterName: existing.monsterName });
    const activeCount = [...transfers.values()].filter((item) => item.status === "queued" || item.status === "claimed").length;
    if (activeCount >= MAX_TRANSFER_QUEUE) return res.status(429).json({ error: "fila_firecast_cheia" });
    const transfer = transferPayload(body, transferId, now()); transfers.set(transferId, transfer);
    if (!persistQueue()) {
        transfers.delete(transferId);
        return res.status(503).json({ error: "fila_nao_persistida" });
    }
    return res.status(202).json({ ok: true, transferId, status: "queued", monsterName: transfer.monsterName });
});
app.post("/sao-node/consumer/heartbeat", (req, res) => {
    if (!requireFirecast(req, res, true)) return;
    const consumerId = asString(req.body?.consumerId, 200).trim();
    if (!consumerId) return res.status(400).json({ error: "consumer_id_ausente" });
    const lastSeenAt = now();
    const consumer = rememberConsumer(consumerId, lastSeenAt, req.body?.ready === undefined ? undefined : asBoolean(req.body.ready));
    return res.json({ ok: true, consumerId, firecastConnected: true, firecastReady: consumer.ready, ready: consumer.ready, lastSeenAt });
});
app.get("/sao-node/transfers/next", (req, res) => {
    if (!requireFirecast(req, res)) return;
    if (!cleanupTransfers()) return res.status(503).json({ error: "fila_nao_persistida" });
    const consumerId = asString(req.query.consumerId, 200).trim();
    if (!consumerId) return res.status(400).json({ error: "consumer_id_ausente" });
    const timestamp = now(); rememberConsumer(consumerId, timestamp);
    const transfer = [...transfers.values()].find((item) => item.status === "queued");
    if (!transfer) return res.status(204).end();
    const previousClaim = { status: transfer.status, claimedBy: transfer.claimedBy, claimedAt: transfer.claimedAt, updatedAt: transfer.updatedAt };
    transfer.status = "claimed"; transfer.claimedBy = consumerId; transfer.claimedAt = timestamp; transfer.updatedAt = timestamp;
    if (!persistQueue()) {
        Object.assign(transfer, previousClaim);
        return res.status(503).json({ error: "fila_nao_persistida" });
    }
    return res.json({ ok: true, ...transfer });
});
app.get("/sao-node/transfers/:transferId", (req, res) => {
    if (!cleanupTransfers()) return res.status(503).json({ error: "fila_nao_persistida" });
    const transfer = transfers.get(req.params.transferId);
    if (!transfer) return res.status(404).json({ error: "transferencia_nao_encontrada" });
    if (transfer.receiptToken) {
        if (!originAllowed(req)) return res.status(403).json({ error: "origem_nao_autorizada" });
        const supplied = bearer(req) || asString(req.query.receipt, 500);
        if (supplied !== transfer.receiptToken) return res.status(401).json({ error: "recibo_invalido" });
        return res.json({ ok: true, transferId: transfer.transferId, status: transfer.status, monsterName: transfer.monsterName, message: transfer.message });
    }
    return res.json({ ok: true, ...transfer });
});
app.post("/sao-node/transfers/:transferId/ack", (req, res) => {
    if (!requireFirecast(req, res)) return;
    if (!cleanupTransfers()) return res.status(503).json({ error: "fila_nao_persistida" });
    const transfer = transfers.get(req.params.transferId);
    if (!transfer) return res.status(404).json({ error: "transferencia_nao_encontrada" });
    const consumerId = asString(req.body?.consumerId, 200).trim(); const status = asString(req.body?.status, 30).trim().toLowerCase();
    if (!consumerId || !["applied", "failed", "rejected"].includes(status)) return res.status(400).json({ error: "confirmacao_invalida" });
    if (["applied", "failed", "rejected"].includes(transfer.status)) {
        if (transfer.status !== status) return res.status(409).json({ error: "transferencia_ja_confirmada", status: transfer.status });
        return res.json({ ok: true, transferId: transfer.transferId, status: transfer.status, message: transfer.message });
    }
    if (transfer.status !== "claimed" || transfer.claimedBy !== consumerId) return res.status(409).json({ error: "confirmacao_invalida" });
    const previousAck = { status: transfer.status, message: transfer.message, updatedAt: transfer.updatedAt };
    transfer.status = status; transfer.message = asString(req.body?.message, 1000); transfer.updatedAt = now();
    if (!persistQueue()) {
        Object.assign(transfer, previousAck);
        return res.status(503).json({ error: "fila_nao_persistida" });
    }
    return res.json({ ok: true, transferId: transfer.transferId, status, message: transfer.message });
});
app.get("/sao-node/status", (req, res) => {
    if (!cleanupTransfers()) return res.status(503).json({ error: "fila_nao_persistida" });
    const timestamp = now();
    const active = [...consumers.values()].filter((c) => timestamp - c.lastSeenAt <= HEARTBEAT_TTL_MS);
    const consumer = active[0] || null;
    const readyConsumer = active.find((c) => c.ready === true) || null;
    return res.json({
        ok: true,
        proxy: true,
        firecastConnected: Boolean(consumer),
        firecastReady: Boolean(readyConsumer),
        consumerId: consumer ? consumer.consumerId : null,
        consumer: consumer ? { id: consumer.consumerId, lastSeenAt: consumer.lastSeenAt, ready: consumer.ready === true } : null,
        readyConsumerId: readyConsumer ? readyConsumer.consumerId : null,
        queued: [...transfers.values()].filter((item) => item.status === "queued").length,
        transfers: transfers.size
    });
});
loadQueue();

// Firecast downloads image URLs directly. Some source URLs only work from the
// machine running the proxy, so relay the bytes locally while preserving the
// original URL in the ficha.
app.get("/sao-node/image", async (req, res) => {
    const rawUrl = asString(req.query.url, 20000).trim();
    let imageUrl;
    try { imageUrl = new URL(rawUrl); } catch { return res.status(400).json({ error: "imagem_url_invalida" }); }
    if (!/^https?:$/.test(imageUrl.protocol)) return res.status(400).json({ error: "imagem_protocolo_invalido" });
    if (imageUrl.protocol === "http:" && imageUrl.hostname === "127.0.0.1" && imageUrl.port === "3001" && imageUrl.pathname.startsWith("/api/v1/firecast/images/")) {
        imageUrl.hostname = "localhost";
    }

    const cacheKey = imageUrl.toString();
    const cached = imageCache.get(cacheKey);
    if (cached && cached.expiresAt > now()) {
        return res.status(200).set("Content-Type", cached.contentType).set("Cache-Control", "public, max-age=600").send(cached.body);
    }
    imageCache.delete(cacheKey);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), IMAGE_PROXY_TIMEOUT_MS);
    try {
        const response = await fetch(cacheKey, {
            redirect: "follow",
            signal: controller.signal,
            headers: { Accept: "image/*,*/*;q=0.8" }
        });
        if (!response.ok) return res.status(502).json({ error: "imagem_origem_http", status: response.status });
        const contentType = String(response.headers.get("content-type") || "").split(";", 1)[0].toLowerCase();
        if (!contentType.startsWith("image/")) return res.status(502).json({ error: "imagem_tipo_invalido", contentType });
        const length = Number(response.headers.get("content-length") || 0);
        if (length > IMAGE_PROXY_MAX_BYTES) return res.status(413).json({ error: "imagem_grande_demais" });
        const body = Buffer.from(await response.arrayBuffer());
        if (body.length > IMAGE_PROXY_MAX_BYTES) return res.status(413).json({ error: "imagem_grande_demais" });
        imageCache.set(cacheKey, { body, contentType, expiresAt: now() + IMAGE_PROXY_CACHE_TTL_MS });
        return res.status(200).set("Content-Type", contentType).set("Cache-Control", "public, max-age=600").send(body);
    } catch (error) {
        const detail = error.name === "AbortError" ? "timeout" : error.message;
        return res.status(502).json({ error: "imagem_proxy_erro", message: detail });
    } finally {
        clearTimeout(timeout);
    }
});

function xmlError(res, status, code) {
    return res.status(status)
        .set("Content-Type", "application/xml; charset=utf-8")
        .send(`<erro codigo="${code}">${code}</erro>`);
}

// Rota legada usada pelo botão de consulta manual do formulário.
app.get("/sao-node/monster-xml", async (req, res) => {
    try {
        const campaignId = asString(req.query.campaignId, 500).trim();
        const monsterId = asString(req.query.monsterId, 500).trim();
        if (!campaignId || !monsterId) return xmlError(res, 400, "parametros_ausentes");
        if (!SAO_NODE_SESSION_COOKIE) return xmlError(res, 500, "sao_node_sem_sessao");
        const url = `${SAO_NODE_BASE_URL}/api/v1/campaigns/${encodeURIComponent(campaignId)}/monsters/${encodeURIComponent(monsterId)}/firecast.xml`;
        const response = await fetch(url, { method: "GET", headers: { cookie: SAO_NODE_SESSION_COOKIE } });
        if (response.status === 401 || response.status === 403) return xmlError(res, response.status, "sao_node_nao_autorizado");
        if (response.status === 404) return xmlError(res, 404, "sao_node_monstro_nao_encontrado");
        if (!response.ok) return xmlError(res, response.status || 502, "sao_node_erro");
        return res.status(200).set("Content-Type", "application/xml; charset=utf-8").send(await response.text());
    } catch (error) {
        console.error("ERRO AO BUSCAR MONSTRO NO SAO-NODE:", error.message);
        return xmlError(res, 500, "sao_node_proxy_erro");
    }
});

function classifyGeminiError(response, data) {
    const status = response?.status || 500;
    const apiStatus = data?.error?.status || "";

    if (status === 401 || status === 403 || apiStatus === "PERMISSION_DENIED" || apiStatus === "UNAUTHENTICATED") {
        return "gemini_auth";
    }

    if (status === 429 || apiStatus === "RESOURCE_EXHAUSTED") {
        return "gemini_quota";
    }

    if (status === 503 || apiStatus === "UNAVAILABLE") {
        return "gemini_indisponivel";
    }

    if (apiStatus === "FAILED_PRECONDITION") {
        return "gemini_bloqueado";
    }

    return "gemini_api";
}

app.post("/gemini", async (req, res) => {
    try {
        if (!API_KEY) return xmlError(res, 503, "gemini_sem_configuracao");
        console.log("==== NOVA REQUISIÇÃO RECEBIDA ====");

        const userPrompt = req.body.prompt;

        if (!userPrompt || typeof userPrompt !== "string") {
            return xmlError(res, 400, "prompt_ausente");
        }

        console.log("📨 Prompt recebido:");
        console.log(userPrompt);

        // ===========================================================
        // TEMPLATE ATUALIZADO (com mana, defesas e equipamentos)
        // ===========================================================
        const xmlTemplate = `
Você deve gerar EXCLUSIVAMENTE XML no formato Tormenta 20 abaixo.
TODAS as tags devem ser SEMPRE preenchidas.

<criatura>
    <nome></nome>
    <nd></nd>
    <tipo></tipo>
    <tamanho></tamanho>
    <descricao></descricao>

    <mana></mana>

    <atributos>
        <for></for><des></des><con></con>
        <int></int><sab></sab><car></car>
    </atributos>

    <pv></pv>
    <defesa></defesa>
    <deslocamento></deslocamento>

    <defesas>
        <fort></fort>
        <ref></ref>
        <von></von>
    </defesas>

    <equipamentos>
        <item></item>
    </equipamentos>

    <sentidos>
        <item></item>
    </sentidos>

    <pericias>
        <item></item>
    </pericias>

    <resistencias>
        <item></item>
    </resistencias>

    <imunidades>
        <item></item>
    </imunidades>

    <ataques>
        <item>
            <nome></nome>
            <quantidade></quantidade>
            <bonus></bonus>
            <dano></dano>
            <tipo></tipo>
        </item>
    </ataques>

    <habilidades>
        <item>
            <nome></nome>
            <descricao></descricao>
        </item>
    </habilidades>
</criatura>

REGRAS IMPORTANTES:
1. NÃO use markdown.
2. NÃO coloque explicações.
3. NÃO coloque nada fora do <criatura>.
4. Use <defesa> para o valor de Defesa da criatura.
5. Sempre preencha todas as tags, mesmo que seja "0" ou "nenhum".
6. Em cada <ataques><item>, preencha <quantidade> com quantos ataques essa acao faz (ex.: "1", "2", "3"). Se for apenas um, use "1".
`;

        // ===================================================
        // ENVIAR EM PARTES (necessário para Gemini não falhar)
        // ===================================================
        const payload = {
            contents: [
                {
                    role: "user",
                    parts: [
                        { text: xmlTemplate },
                        { text: "Agora preencha o XML acima com base no texto da criatura a seguir." },
                        { text: "TEXTO DA CRIATURA:" },
                        { text: userPrompt }
                    ]
                }
            ]
        };

        console.log("📦 Payload enviado:");
        console.log(JSON.stringify(payload, null, 2));

        const url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + API_KEY;

        const response = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });

        const data = await response.json();

        console.log("📥 Resposta COMPLETA do Gemini:");
        console.log(JSON.stringify(data, null, 2));

        if (!response.ok || data?.error) {
            const code = classifyGeminiError(response, data);
            console.log("Erro classificado para o Firecast:", code);
            return xmlError(res, response.status || 500, code);
        }

        const part =
            data?.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!part) {
            console.log("⚠ ERRO: Gemini não retornou texto.");
            return xmlError(res, 502, "gemini_sem_texto");
        }

        // Remover markdown
        let text = part
            .replace(/```xml/gi, "")
            .replace(/```/g, "")
            .trim();

        // Extrair somente o bloco <criatura>
        const start = text.indexOf("<criatura>");
        const end = text.indexOf("</criatura>");

        if (start === -1 || end === -1) {
            console.log("Resposta veio sem o XML completo.");
            return xmlError(res, 502, "gemini_sem_xml");
        }

        if (start !== -1 && end !== -1) {
            text = text.slice(start, end + "</criatura>".length);
        } else {
            console.log("⚠ Aviso: resposta veio sem o XML completo.");
        }

        console.log("📝 XML FINAL ENVIADO AO FIRECAST:");
        console.log(text);

        return res.status(200)
            .set("Content-Type", "application/xml; charset=utf-8")
            .send(text);


    } catch (err) {
        console.error("🔥 ERRO NO PROXY:", err);
        return xmlError(res, 500, "proxy_erro");
    }
});


app.post("/save-ficha", async (req, res) => {
    try {
        const ficha = req.body?.ficha;

        if (!ficha || typeof ficha !== "object") {
            return res.status(400).json({ error: "ficha_ausente" });
        }

        const rawName = String(ficha.nome || "criatura").trim();
        const slug = rawName
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-+|-+$/g, "") || "criatura";

        const saveDir = path.resolve(process.cwd(), "saved-fichas");
        const filePath = path.join(saveDir, `${slug}.json`);

        fs.mkdirSync(saveDir, { recursive: true });
        fs.writeFileSync(filePath, JSON.stringify(ficha, null, 2), "utf8");

        return res.status(200).json({
            ok: true,
            fileName: path.basename(filePath),
            filePath
        });
    } catch (err) {
        console.error("ERRO AO SALVAR FICHA:", err);
        return res.status(500).json({ error: err.message });
    }
});



if (require.main === module) {
    const port = Number(process.env.PORT || 7000);
    const server = app.listen(port, "127.0.0.1");
    server.once("listening", () => {
        const address = server.address();
        const actualPort = typeof address === "object" && address !== null ? address.port : port;
        console.log("====================================");
        console.log("Proxy rodando na porta " + actualPort + " (127.0.0.1)");
        console.log("====================================");
    });
    server.once("error", (error) => {
        if (error.code === "EADDRINUSE") console.error("A porta " + port + " já está em uso. Feche o outro servidor ou defina PORT com outra porta.");
        else console.error("Não foi possível iniciar o proxy:", error.message);
        process.exit(1);
    });
}
module.exports = { app, transfers, consumers, cleanupTransfers, QUEUE_FILE };
