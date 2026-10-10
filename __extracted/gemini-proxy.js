// index.js - Proxy Gemini → Firecast (somente XML de criatura)

const express = require("express");
const fs = require("fs");
const path = require("path");

const app = express();
app.use(express.json({ limit: "10mb" }));

// SUA API KEY
const API_KEY = process.env.GEMINI_API_KEY || "";

console.log("====================================");
console.log(" Proxy Gemini Iniciado ");
console.log(" API_KEY carregada? ", API_KEY ? "SIM" : "NÃO");
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


app.listen(3000, () => {
    console.log("====================================");
    console.log("🚀 Gemini Proxy rodando na porta 7000");
    console.log("====================================");
});
