// Reliable local launcher for the Firecast bridge.
// It never edits the transfer queue: a failed start can be retried safely.
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { spawn } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const proxyScript = path.join(root, "gemini-proxy.js");
const port = Number(process.env.PORT || 7000);
const host = process.env.HOST || "127.0.0.1";
const logFile = path.resolve(process.env.FIRECAST_START_LOG || path.join(root, ".sao-node-proxy-start.log"));

function log(message) {
    const line = `[${new Date().toISOString()}] ${message}\n`;
    try {
        fs.appendFileSync(logFile, line, "utf8");
    } catch (error) {
        console.error("Não foi possível registrar o início do proxy:", error.message);
    }
    process.stdout.write(line);
}

function probe() {
    if (!Number.isInteger(port) || port < 1 || port > 65535) return Promise.resolve({ state: "invalid" });
    return new Promise((resolve) => {
        const request = http.get({ host, port, path: "/sao-node/status", timeout: 700 }, (response) => {
            let body = "";
            response.setEncoding("utf8");
            response.on("data", (chunk) => { body += chunk; });
            response.on("end", () => {
                if (response.statusCode !== 200) return resolve({ state: "occupied", statusCode: response.statusCode });
                try {
                    const parsed = JSON.parse(body);
                    if (parsed && parsed.proxy === true) return resolve({ state: "running", status: parsed });
                } catch { /* another service may return non-JSON */ }
                resolve({ state: "occupied", statusCode: response.statusCode });
            });
        });
        request.once("timeout", () => request.destroy(new Error("timeout")));
        request.once("error", (error) => {
            if (error.code === "ECONNREFUSED" || error.code === "ENOTFOUND") return resolve({ state: "free" });
            resolve({ state: "occupied", error: error.message });
        });
    });
}

async function main() {
    if (!fs.existsSync(proxyScript)) {
        log(`Falha: arquivo do proxy não encontrado em ${proxyScript}`);
        process.exitCode = 1;
        return;
    }

    const check = await probe();
    if (check.state === "invalid") {
        log(`Falha: PORT inválida (${process.env.PORT || port}).`);
        process.exitCode = 1;
        return;
    }
    if (check.state === "running") {
        log(`Proxy já está ativo em ${host}:${port}; fila preservada.`);
        return;
    }
    if (check.state !== "free") {
        log(`Falha: ${host}:${port} está ocupado por outro serviço${check.error ? ` (${check.error})` : ""}. Fila preservada.`);
        process.exitCode = 1;
        return;
    }

    log(`Iniciando proxy em ${host}:${port}; fila preservada em ${process.env.FIRECAST_QUEUE_FILE || path.join(root, ".sao-node-transfers.json")}.`);
    const childArgs = ["--env-file-if-exists=.env", proxyScript];
    const child = spawn(process.execPath, childArgs, { cwd: root, env: process.env, stdio: "inherit" });
    const forward = (signal) => { if (!child.killed) child.kill(signal); };
    process.once("SIGINT", () => forward("SIGINT"));
    process.once("SIGTERM", () => forward("SIGTERM"));
    child.once("error", (error) => {
        log(`Falha ao iniciar o processo do proxy: ${error.message}. Fila preservada.`);
        process.exitCode = 1;
    });
    child.once("exit", (code, signal) => {
        if (signal) log(`Proxy encerrado por ${signal}.`);
        else if (code !== 0) log(`Proxy encerrou com código ${code}. Fila preservada.`);
        process.exitCode = typeof code === "number" ? code : 1;
    });
}

main().catch((error) => {
    log(`Falha inesperada ao iniciar o proxy: ${error.message}. Fila preservada.`);
    process.exitCode = 1;
});

