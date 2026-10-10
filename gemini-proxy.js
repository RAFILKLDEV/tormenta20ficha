// index.js - Proxy Gemini → Firecast (somente XML de criatura)

const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const app = express();
app.use(express.json({ limit: "10mb" }));

// Credenciais são sempre fornecidas pelo ambiente do processo; nunca pelo navegador.
const API_KEY = process.env.GEMINI_API_KEY || "";

// Config de integração com o SAO-NODE (busca de monstros já cadastrados).
// SAO_NODE_SESSION_COOKIE deve ser o valor do cookie de sessão (sao_session=...)
// de um usuário com papel de mestre na campanha usada.
const SAO_NODE_BASE_URL = process.env.SAO_NODE_BASE_URL || "http://localhost:3001";
const SAO_NODE_SESSION_COOKIE = process.env.SAO_NODE_SESSION_COOKIE || "";
const SAO_NODE_BRIDGE_TOKEN = process.env.SAO_NODE_BRIDGE_TOKEN || "";
const FIRECAST_BRIDGE_TOKEN = process.env.FIRECAST_BRIDGE_TOKEN || SAO_NODE_BRIDGE_TOKEN;
const PROXY_ALLOWED_ORIGINS = new Set(
    (process.env.PROXY_ALLOWED_ORIGINS || "http://localhost:5173,http://127.0.0.1:5173")
        .split(",").map((origin) => origin.trim()).filter(Boolean)
);

// A transferência não contém credenciais nem é aceita duas vezes. O XML fica
// somente no processo do proxy até o plugin confirmar aplicação ou expirar.
const transfers = new Map();
const TRANSFER_TTL_MS = Number(process.env.FIRECAST_TRANSFER_TTL_MS || 10 * 60 * 1000);
const MAX_TRANSFER_QUEUE = 100;

function randomToken(bytes = 32) { return crypto.randomBytes(bytes).toString("base64url"); }
function bearer(req) {
    const value = String(req.headers.authorization || "");
    return value.startsWith("Bearer ") ? value.slice(7) : "";
}
function originAllowed(req) {
    const origin = req.headers.origin;
    // Native Firecast requests do not send Origin; browser requests must.
    return !origin || PROXY_ALLOWED_ORIGINS.has(origin);
}
function requireFirecast(req, res) {
    if (!FIRECAST_BRIDGE_TOKEN) {
        res.status(503).json({ error: "firecast_bridge_nao_configurado" });
        return false;
    }
    const supplied = Buffer.from(bearer(req));
    const expected = Buffer.from(FIRECAST_BRIDGE_TOKEN);
    if (supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) {
        res.status(401).json({ error: "firecast_nao_autorizado" });
        return false;
    }
    return true;
}
function cleanupTransfers() {
    const now = Date.now();
    for (const [id, transfer] of transfers) {
        if (now - transfer.createdAt > TRANSFER_TTL_MS || ["applied", "rejected", "failed"].includes(transfer.status) && now - transfer.updatedAt > TRANSFER_TTL_MS) transfers.delete(id);
    }
}
function setCors(req, res) {
    const origin = req.headers.origin;
    if (origin && PROXY_ALLOWED_ORIGINS.has(origin)) {
        res.set("Access-Control-Allow-Origin", origin);
        res.set("Vary", "Origin");
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    }
}
app.use((req, res, next) => { setCors(req, res); if (req.method === "OPTIONS") return res.sendStatus(204); next(); });

async function saoNodeRequest(pathname, options = {}) {
    if (!SAO_NODE_BRIDGE_TOKEN) {
        const error = new Error("SAO_NODE_BRIDGE_TOKEN não configurado");
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
        error.data = data;
        throw error;
    }
    return data;
}

// O frontend envia somente o ticket emitido pelo SAO-NODE após autenticação GM.
// O ticket é resgatado uma vez e vira uma fila consumível pelo MonsterIA.
app.post("/sao-node/transfers", async (req, res) => {
    if (!originAllowed(req)) return res.status(403).json({ error: "origem_nao_autorizada" });
    const ticket = typeof req.body?.ticket === "string" ? req.body.ticket : "";
    if (!ticket || ticket.length > 512) return res.status(400).json({ error: "ticket_ausente" });
    cleanupTransfers();
    if (transfers.size >= MAX_TRANSFER_QUEUE) return res.status(429).json({ error: "fila_firecast_cheia" });
    try {
        const issued = await saoNodeRequest("/api/v1/firecast/transfers/redeem", {
            method: "POST", body: JSON.stringify({ ticket })
        });
        const transferId = String(issued.transferId || randomToken(16));
        const receiptToken = randomToken(32);
        const now = Date.now();
        transfers.set(transferId, {
            transferId,
            receiptToken,
            xml: String(issued.xml || ""),
            campaignId: issued.campaignId,
            monsterId: issued.monsterId,
            monsterName: issued.monsterName || "Criatura",
            imageUrl: issued.imageUrl || "",
            status: "queued",
            createdAt: now,
            updatedAt: now,
            claimedBy: null,
            claimedAt: 0,
            message: ""
        });
        return res.status(202).json({ ok: true, transferId, receiptToken, status: "queued", monsterName: issued.monsterName || "Criatura" });
    } catch (error) {
        const status = error.status === 401 || error.status === 403 ? error.status : error.status || 502;
        return res.status(status).json({ error: error.code || "sao_node_indisponivel", message: error.message });
    }
});

// Endpoints consumidos pelo plugin. O token é configurado apenas no proxy e no
// Firecast, nunca enviado ao frontend SAO-NODE.
app.post("/sao-node/consumer/heartbeat", (req, res) => {
    if (!requireFirecast(req, res)) return;
    const consumerId = String(req.body?.consumerId || "").trim();
    if (!consumerId || consumerId.length > 200) return res.status(400).json({ error: "consumer_id_ausente" });
    cleanupTransfers();
    return res.json({ ok: true, consumerId });
});

app.get("/sao-node/transfers/next", (req, res) => {
    if (!requireFirecast(req, res)) return;
    cleanupTransfers();
    const consumerId = String(req.query.consumerId || "").trim();
    if (!consumerId || consumerId.length > 200) return res.status(400).json({ error: "consumer_id_ausente" });
    const now = Date.now();
    let transfer = [...transfers.values()].find((item) => item.status === "queued" || (item.status === "claimed" && item.claimedAt + 30_000 < now));
    if (!transfer) return res.status(204).end();
    transfer.status = "claimed";
    transfer.claimedBy = consumerId;
    transfer.claimedAt = now;
    transfer.updatedAt = now;
    return res.json({ ok: true, transferId: transfer.transferId, xml: transfer.xml, monsterName: transfer.monsterName, imageUrl: transfer.imageUrl });
});

app.get("/sao-node/transfers/:transferId", (req, res) => {
    if (!originAllowed(req)) return res.status(403).json({ error: "origem_nao_autorizada" });
    cleanupTransfers();
    const transfer = transfers.get(req.params.transferId);
    if (!transfer) return res.status(404).json({ error: "transferencia_expirada" });
    if (bearer(req) !== transfer.receiptToken && req.query.receipt !== transfer.receiptToken) return res.status(401).json({ error: "recibo_invalido" });
    return res.json({ ok: true, transferId: transfer.transferId, status: transfer.status, monsterName: transfer.monsterName, message: transfer.message });
});

app.post("/sao-node/transfers/:transferId/ack", async (req, res) => {
    if (!requireFirecast(req, res)) return;
    const transfer = transfers.get(req.params.transferId);
    if (!transfer) return res.status(404).json({ error: "transferencia_expirada" });
    const consumerId = String(req.body?.consumerId || "");
    const status = String(req.body?.status || "");
    if (!consumerId || transfer.claimedBy !== consumerId || !["applied", "rejected", "failed"].includes(status)) return res.status(409).json({ error: "confirmacao_invalida" });
    transfer.status = status;
    transfer.message = String(req.body?.message || "").slice(0, 1000);
    transfer.updatedAt = Date.now();
    // Auditoria/estado no servidor é best-effort: o recibo local já é válido.
    try {
        await saoNodeRequest(`/api/v1/firecast/transfers/${encodeURIComponent(transfer.transferId)}/ack`, {
            method: "POST", body: JSON.stringify({ consumerId, status, message: transfer.message })
        });
    } catch (error) {
        if (error.status && error.status !== 404) console.warn("Falha ao registrar recibo no SAO-NODE:", error.message);
    }
    return res.json({ ok: true, transferId: transfer.transferId, status: transfer.status });
});

console.log("====================================");
console.log(" Proxy Gemini Iniciado ");
console.log(" API_KEY carregada? ", API_KEY ? "SIM" : "NÃO");
console.log(" SAO_NODE_SESSION_COOKIE carregado? ", SAO_NODE_SESSION_COOKIE ? "SIM" : "NÃO");
console.log("====================================");


function xmlError(res, status, code) {
    return res.status(status)
        .set("Content-Type", "application/xml; charset=utf-8")
        .send(`<erro codigo="${code}">${code}</erro>`);
}

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

// Busca o XML <criatura> de um monstro já cadastrado no SAO-NODE,
// evitando a necessidade de reescrever o texto e reenviar para a IA.
app.get("/sao-node/monster-xml", async (req, res) => {
    try {
        const campaignId = req.query.campaignId;
        const monsterId = req.query.monsterId;

        if (!campaignId || !monsterId) {
            return xmlError(res, 400, "parametros_ausentes");
        }
        if (!SAO_NODE_SESSION_COOKIE) {
            console.log("⚠ SAO_NODE_SESSION_COOKIE não configurado no proxy.");
            return xmlError(res, 500, "sao_node_sem_sessao");
        }

        const url = `${SAO_NODE_BASE_URL}/api/v1/campaigns/${encodeURIComponent(campaignId)}/monsters/${encodeURIComponent(monsterId)}/firecast.xml`;

        console.log("🔎 Buscando monstro no SAO-NODE:", url);

        const response = await fetch(url, {
            method: "GET",
            headers: { cookie: SAO_NODE_SESSION_COOKIE }
        });

        if (response.status === 401 || response.status === 403) {
            return xmlError(res, response.status, "sao_node_nao_autorizado");
        }
        if (response.status === 404) {
            return xmlError(res, 404, "sao_node_monstro_nao_encontrado");
        }
        if (!response.ok) {
            return xmlError(res, response.status || 502, "sao_node_erro");
        }

        const xml = await response.text();

        console.log("📝 XML recebido do SAO-NODE:");
        console.log(xml);

        return res.status(200)
            .set("Content-Type", "application/xml; charset=utf-8")
            .send(xml);
    } catch (err) {
        console.error("🔥 ERRO AO BUSCAR MONSTRO NO SAO-NODE:", err);
        return xmlError(res, 500, "sao_node_proxy_erro");
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
    const server = app.listen(port);
    server.once("listening", () => {
        const address = server.address();
        const actualPort = typeof address === "object" && address !== null ? address.port : port;
        console.log("====================================");
        console.log(`🚀 Gemini Proxy rodando na porta ${actualPort}`);
        console.log("====================================");
    });

    server.once("error", (error) => {
        if (error.code === "EADDRINUSE") {
            console.error(`A porta ${port} já está em uso. Feche o outro servidor ou defina PORT com outra porta.`);
        } else {
            console.error("Não foi possível iniciar o proxy:", error.message);
        }
        process.exit(1);
    });
}

module.exports = { app, transfers, cleanupTransfers };
