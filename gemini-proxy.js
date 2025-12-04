// index.js - Proxy Gemini → Firecast (somente XML de criatura)

const express = require("express");

const app = express();
app.use(express.json({ limit: "10mb" }));

// SUA API KEY
const API_KEY = "AIzaSyDrmL6DM1mTS2hTuKMa6_UbZgtsCvWcZxQ";

console.log("====================================");
console.log(" Proxy Gemini Iniciado ");
console.log(" API_KEY carregada? ", API_KEY ? "SIM" : "NÃO");
console.log("====================================");


app.post("/gemini", async (req, res) => {
    try {
        console.log("==== NOVA REQUISIÇÃO RECEBIDA ====");

        const userPrompt = req.body.prompt;

        if (!userPrompt || typeof userPrompt !== "string") {
            return res.status(400)
                .set("Content-Type", "application/xml; charset=utf-8")
                .send("<erro>prompt_ausente</erro>");
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
    <ca></ca>
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
4. Sempre preencha todas as tags, mesmo que seja "0" ou "nenhum".
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

        const part =
            data?.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!part) {
            console.log("⚠ ERRO: Gemini não retornou texto.");
            return res.status(500)
                .set("Content-Type", "application/xml; charset=utf-8")
                .send("<erro>gemini_sem_texto</erro>");
        }

        // Remover markdown
        let text = part
            .replace(/```xml/gi, "")
            .replace(/```/g, "")
            .trim();

        // Extrair somente o bloco <criatura>
        const start = text.indexOf("<criatura>");
        const end = text.indexOf("</criatura>");

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
        return res.status(500)
            .set("Content-Type", "application/xml; charset=utf-8")
            .send(`<erro>${err.message}</erro>`);
    }
});


app.listen(3000, () => {
    console.log("====================================");
    console.log("🚀 Gemini Proxy rodando na porta 3000");
    console.log("====================================");
});
