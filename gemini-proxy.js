// index.js - Proxy Gemini → Firecast (somente XML de criatura)

const express = require("express");
// Em Node 18+ fetch já existe globalmente. Se estiver em versão menor, descomente:
// const fetch = (...args) => import("node-fetch").then(m => m.default(...args));

const app = express();
app.use(express.json({ limit: "10mb" }));

const API_KEY = "AIzaSyDrmL6DM1mTS2hTuKMa6_UbZgtsCvWcZxQ"; // coloque sua key aqui

console.log("====================================");
console.log(" Proxy Gemini Iniciado ");
console.log(" API_KEY carregada? ", API_KEY ? "SIM" : "NÃO");
console.log("====================================");

app.post("/gemini", async (req, res) => {
    try {
        const userPrompt = req.body.prompt;

        console.log("--------------------------------------------------");
        console.log("🔵 Requisição recebida no /gemini");
        console.log("📨 Prompt recebido:", userPrompt);

        if (!userPrompt || typeof userPrompt !== "string") {
            return res
                .status(400)
                .set("Content-Type", "application/xml; charset=utf-8")
                .send('<erro>prompt_ausente</erro>');
        }

        // TEMPLATE FIXO: obriga o modelo a responder SOMENTE XML
        const xmlTemplate = `
Você deve gerar EXCLUSIVAMENTE XML no formato Tormenta 20 abaixo:

<criatura>
    <nome></nome>
    <nd></nd>
    <tipo></tipo>
    <tamanho></tamanho>
    <descricao></descricao>
    <atributos>
        <for></for><des></des><con></con>
        <int></int><sab></sab><car></car>
    </atributos>
    <pv></pv>
    <ca></ca>
    <deslocamento></deslocamento>
    <sentidos><item></item></sentidos>
    <pericias><item></item></pericias>
    <resistencias><item></item></resistencias>
    <imunidades><item></item></imunidades>
    <ataques>
        <item><nome></nome><bonus></bonus><dano></dano><tipo></tipo></item>
    </ataques>
    <habilidades>
        <item><nome></nome><descricao></descricao></item>
    </habilidades>
</criatura>

Responda APENAS com esse XML, sem explicações, sem markdown.

Agora, preencha com base na criatura abaixo:

`;

        const fullPrompt = xmlTemplate + userPrompt;

        const url =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" +
            API_KEY;

        const payload = {
            contents: [
                {
                    role: "user",
                    parts: [{ text: fullPrompt }]
                }
            ]
        };

        console.log("🌐 Enviando requisição ao Google Gemini...");
        console.log("URL:", url);
        console.log("📦 Payload enviado:", JSON.stringify(payload, null, 2));

        const response = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        console.log("🔄 Status da resposta do Google:", response.status);
        console.log("📥 Corpo recebido do Google:");
        console.log(JSON.stringify(data, null, 2));

        // Extrai texto do Gemini
        const part =
            data &&
            data.candidates &&
            data.candidates[0] &&
            data.candidates[0].content &&
            data.candidates[0].content.parts &&
            data.candidates[0].content.parts[0] &&
            data.candidates[0].content.parts[0].text;

        if (!part || typeof part !== "string") {
            console.log("⚠ Gemini não retornou texto em candidates[0].content.parts[0].text");
            return res
                .status(500)
                .set("Content-Type", "application/xml; charset=utf-8")
                .send('<erro>gemini_sem_texto</erro>');
        }

        // Limpa markdown tipo ```xml ... ```
        let text = part.replace(/```xml/gi, "").replace(/```/g, "").trim();

        // Garante que vamos mandar só <criatura>...</criatura>
        const start = text.indexOf("<criatura>");
        const end = text.indexOf("</criatura>");

        if (start !== -1 && end !== -1) {
            text = text.slice(start, end + "</criatura>".length);
        } else {
            console.log("⚠ Não encontrei <criatura>...</criatura> na resposta. Enviando bruto.");
        }

        console.log("📝 XML FINAL ENVIADO AO FIRECAST:");
        console.log(text);

        res
            .status(200)
            .set("Content-Type", "application/xml; charset=utf-8")
            .send(text);

    } catch (err) {
        console.error("🔥 ERRO NO PROXY:", err);
        res
            .status(500)
            .set("Content-Type", "application/xml; charset=utf-8")
            .send(`<erro>${err.message || String(err)}</erro>`);
    }
});

app.listen(3000, () => {
    console.log("====================================");
    console.log("🚀 Gemini Proxy rodando na porta 3000");
    console.log("====================================");
});
