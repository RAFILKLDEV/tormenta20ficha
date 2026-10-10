------------------------------------------------------------
-- MonsterIA.lua
------------------------------------------------------------

local ndb      = require("ndb")
local dialogs  = require("dialogs")
local internet = require("internet")
local json     = require("json")
local GUI      = require("gui")
local Firecast = require("firecast")
local rrpg     = require("rrpg")
local SceneLib = require("scene")

GEMINI_PROXY_URL = GEMINI_PROXY_URL or "http://localhost:3000/gemini"
SAO_NODE_PROXY_URL = SAO_NODE_PROXY_URL or "http://localhost:3000/sao-node/monster-xml"
-- A ponte de transferências é autenticada somente no lado do Firecast.  O token
-- nunca é persistido em nodes nem enviado ao navegador SAO-NODE.
SAO_NODE_BRIDGE_URL = SAO_NODE_BRIDGE_URL or "http://localhost:3000"
SAO_NODE_BRIDGE_TOKEN = SAO_NODE_BRIDGE_TOKEN or ""
local saoNodeConsumerId = nil
local saoNodeBridgePolling = false
local saoNodeBridgeTimer = nil
local saoNodeSeenTransfers = {}
local saoNodeBridgePrompting = false
local aplicarXMLNaFichaComConfirmacao

------------------------------------------------------------
-- UTILS
------------------------------------------------------------

local function cleanText(s)
    if not s then return "" end
    s = s:gsub("\r", " "):gsub("\n", " ")
    s = s:gsub("%s+", " ")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function xmlDecode(s)
    if type(s) ~= "string" then return "" end
    return s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '\"')
        :gsub("&apos;", "'"):gsub("&amp;", "&")
end

local function normalize(s)
    if not s then return "" end
    s = cleanText(s)
    return s:lower()
end

local function arredondarInteiro(valor)
    return math.floor((tonumber(valor) or 0) + 0.5)
end

local function talemark(codigo)
    return "[" .. utf8.char(0xA7) .. codigo .. "]"
end

local CORES_ROLAGEM = {
    ataque = "K3",
    dano = "K4",
    pericia = "K2",
    resistencia = "K7",
    padrao = "K1"
}

local DEBUG_IMPERSONACAO = false
local _debugImpersonacaoJaMostrou = false

local function colorirResultado(texto, categoria)
    local cor = CORES_ROLAGEM[categoria] or CORES_ROLAGEM.padrao
    return string.format("%s%s%s", talemark(cor), texto or "", talemark("K1"))
end

local function colorirRotulo(texto, categoria)
    local cor = CORES_ROLAGEM[categoria] or CORES_ROLAGEM.padrao
    return string.format("%s%s%s", talemark(cor), texto or "", talemark("K1"))
end

local function montarCabecalhoRolagem(rotulo, categoria)
    local titulo = cleanText(rotulo)
    local prefixo, resto = titulo:match("^(.-:%s*)(.*)$")

    if prefixo ~= nil then
        return string.format("%s%s", colorirRotulo(prefixo, categoria), resto or "")
    end

    return colorirRotulo(titulo, categoria)
end

local function formatarExpressaoDano(texto)
    local expr = cleanText(texto)

    expr = expr:gsub("%s*([%+%-])%s*", " %1 ")
    expr = expr:gsub("%s+", " ")
    expr = expr:gsub("(%d+)([dD]%d+)", "%1" .. talemark("K2") .. "%2" .. talemark("K1"))

    return expr
end

local function montarLinhaDano(nomeAtaque, expressao, resultados, total)
    local titulo = cleanText(nomeAtaque)
    local tituloFmt = titulo

    if titulo:match("^[Dd]") then
        tituloFmt = "[Â§K2]" .. titulo .. "[Â§K1]"
    end

    local linha = string.format("%s - %s", titulo, formatarExpressaoDano(expressao))
    local resultadoFinal = colorirResultado(string.format("%s%d%s", talemark("B"), total, talemark("B")), "dano")

    if resultados ~= nil then
        resultadoFinal = string.format("[ %s ] = %s", resultados, resultadoFinal)
    end

    return string.format("%s = %s", linha, resultadoFinal)
end

local function montarLinhaAtaque(nomeAtaque, expressao, resultados, total)
    local titulo = cleanText(nomeAtaque)
    local linha = string.format("[Â§K3]Ataque: [Â§K1]%s - %s", titulo, formatarExpressaoDano(expressao))
    local resultadoFinal = colorirResultado(string.format("%s%d%s", talemark("B"), total, talemark("B")), "ataque")

    if resultados ~= nil then
        resultadoFinal = string.format("[ %s ] = %s", resultados, resultadoFinal)
    end

    return string.format("%s = %s", linha, resultadoFinal)
end

local function categoriaDaRolagem(rotulo)
    local txt = normalize(rotulo)

    if txt:find("fortitude", 1, true) or txt:find("reflexos", 1, true) or txt:find("vontade", 1, true) then
        return "resistencia"
    end

    return "pericia"
end

montarLinhaDano = function(nomeAtaque, expressao, resultados, total)
    local titulo = cleanText(nomeAtaque)
    local linha = string.format("%s - %s", montarCabecalhoRolagem("Dano: " .. titulo, "dano"), formatarExpressaoDano(expressao))
    local resultadoFinal = colorirResultado(string.format("%s%d%s", talemark("B"), total, talemark("B")), "dano")

    if resultados ~= nil then
        resultadoFinal = string.format("[ %s ] = %s", resultados, resultadoFinal)
    end

    return string.format("%s = %s", linha, resultadoFinal)
end

montarLinhaAtaque = function(nomeAtaque, expressao, resultados, total)
    local titulo = cleanText(nomeAtaque)
    local linha = string.format("%s - %s", montarCabecalhoRolagem("Ataque: " .. titulo, "ataque"), formatarExpressaoDano(expressao))
    local resultadoFinal = colorirResultado(string.format("%s%d%s", talemark("B"), total, talemark("B")), "ataque")

    if resultados ~= nil then
        resultadoFinal = string.format("[ %s ] = %s", resultados, resultadoFinal)
    end

    return string.format("%s = %s", linha, resultadoFinal)
end

local function montarLinhaRolagemGenerica(rotulo, expressao, resultados, total, categoria)
    local linha = string.format("%s - %s", montarCabecalhoRolagem(rotulo, categoria), formatarExpressaoDano(expressao))
    local resultadoFinal = colorirResultado(string.format("%s%d%s", talemark("B"), total, talemark("B")), categoria)

    if resultados ~= nil then
        resultadoFinal = string.format("[ %s ] = %s", resultados, resultadoFinal)
    end

    return string.format("%s = %s", linha, resultadoFinal)
end

local function formatarResultadosDosDados(rolagem)
    local grupos = {}

    for _, op in ipairs(rolagem.ops or {}) do
        if op.tipo == "dado" and type(op.resultados) == "table" and #op.resultados > 0 then
            local resultados = {}

            for i, resultado in ipairs(op.resultados) do
                resultados[i] = tostring(arredondarInteiro(resultado))
            end

            grupos[#grupos + 1] = table.concat(resultados, ", ")
        end
    end

    if #grupos == 0 then
        return nil
    end

    return table.concat(grupos, " | ")
end

local function resolverBibPersonagem(obj)
    if obj == nil then
        return nil
    end

    local personagem = rrpg.getPersonagemDe(obj)
    if personagem ~= nil then
        return personagem
    end

    local bibItem = rrpg.getBibliotecaItemDe(obj)
    if bibItem ~= nil and bibItem.isType ~= nil and bibItem:isType("personagem") then
        return bibItem
    end

    return nil
end

local function resolverControleRaiz(contexto)
    local atual = contexto
    local ultimo = contexto

    while atual ~= nil and atual.getParent ~= nil do
        ultimo = atual
        atual = atual:getParent()
    end

    return ultimo
end

local function resolverPersonagemPrincipalDoJogador(chat, contexto)
    local mesa = nil

    if chat ~= nil and chat.room ~= nil then
        mesa = chat.room
    elseif contexto ~= nil then
        mesa = Firecast.getMesaDe(contexto)
    end

    if mesa == nil or mesa.me == nil then
        return nil
    end

    local personagemId = tonumber(mesa.me.personagemPrincipal or 0) or 0
    if personagemId == 0 then
        return nil
    end

    local function buscarNaBiblioteca(item)
        if item == nil then
            return nil
        end

        local codigoInterno = tonumber(item.codigoInterno or 0) or 0
        if codigoInterno == personagemId and item.isType ~= nil and item:isType("personagem") then
            return item
        end

        for _, filho in ipairs(item.filhos or {}) do
            local achado = buscarNaBiblioteca(filho)
            if achado ~= nil then
                return achado
            end
        end

        return nil
    end

    if mesa.findBibliotecaItem ~= nil then
        local personagem = mesa:findBibliotecaItem(personagemId)
        if personagem ~= nil and personagem.isType ~= nil and personagem:isType("personagem") then
            return personagem
        end
    end

    local personagem = buscarNaBiblioteca(mesa.biblioteca)
    if personagem ~= nil then
        return personagem
    end

    personagem = rrpg.objectFromID(personagemId)
    if personagem ~= nil and personagem.isType ~= nil and personagem:isType("personagem") then
        return personagem
    end

    return nil
end

local function resolverPersonagemDaFicha(nodo, contexto, chat)
    local personagem = resolverBibPersonagem(contexto)

    if personagem ~= nil then
        return personagem
    end

    local raizDoControle = resolverControleRaiz(contexto)
    personagem = resolverBibPersonagem(raizDoControle)

    if personagem ~= nil then
        return personagem
    end

    if nodo == nil then
        return nil
    end

    personagem = resolverBibPersonagem(nodo)

    if personagem ~= nil then
        return personagem
    end

    local raiz = ndb.getRoot(nodo)
    if raiz ~= nil then
        personagem = resolverBibPersonagem(raiz)
        if personagem ~= nil then
            return personagem
        end

        local pai = ndb.getParent(raiz)
        while pai ~= nil do
            personagem = resolverBibPersonagem(pai)
            if personagem ~= nil then
                return personagem
            end
            pai = ndb.getParent(pai)
        end
    end

    return resolverPersonagemPrincipalDoJogador(chat, contexto)
end

local function resolverImpersonationDaFicha(nodo, contexto, chat, npcInfo)
    local personagem = resolverPersonagemDaFicha(nodo, contexto, chat)
    local nomeNpc = cleanText((npcInfo and npcInfo.name) or (personagem and personagem.nome) or (nodo and nodo.nome) or "")
    local avatarNpc = cleanText((npcInfo and npcInfo.avatar) or (personagem and personagem.avatar) or (nodo and nodo.imagemURL) or "")

    if avatarNpc == "" and nodo ~= nil then
        avatarNpc = cleanText(nodo.imagemURL or "")
    end

    if nomeNpc == "" then
        nomeNpc = "Criatura"
    end

    if nodo ~= nil and avatarNpc ~= "" and cleanText(nodo.imagemURL or "") ~= avatarNpc then
        nodo.imagemURL = avatarNpc
    end

    return {
        mode = "character",
        name = nomeNpc,
        avatar = avatarNpc
    }
end

local function diagnosticarImpersonacao(nodo, contexto, chat, impersonation)
    if not DEBUG_IMPERSONACAO or _debugImpersonacaoJaMostrou then
        return
    end

    if cleanText(impersonation.name or "") ~= "Criatura" and cleanText(impersonation.avatar or "") ~= "" then
        return
    end

    _debugImpersonacaoJaMostrou = true

    local personagem = resolverPersonagemDaFicha(nodo, contexto, chat)
    local mesa = nil
    local meuJogador = nil
    local personagemPrincipalId = 0

    if chat ~= nil and chat.room ~= nil then
        mesa = chat.room
    elseif contexto ~= nil then
        mesa = Firecast.getMesaDe(contexto)
    end

    if mesa ~= nil then
        meuJogador = mesa.me
    end

    if meuJogador ~= nil then
        personagemPrincipalId = tonumber(meuJogador.personagemPrincipal or 0) or 0
    end

    showMessage(table.concat({
        "[DEBUG NPC]",
        "impersonation.name = " .. tostring(impersonation.name or ""),
        "impersonation.avatar = " .. tostring(impersonation.avatar or ""),
        "personagem = " .. tostring(personagem and personagem.nome or "nil"),
        "personagem.avatar = " .. tostring(personagem and personagem.avatar or "nil"),
        "nodo.nome = " .. tostring(nodo and nodo.nome or "nil"),
        "nodo.imagemURL = " .. tostring(nodo and nodo.imagemURL or "nil"),
        "personagemPrincipal = " .. tostring(personagemPrincipalId)
    }, "\n"))
end

function resolverNomeNpcDaFicha(nodo, contexto, chat, npcInfo)
    local impersonation = resolverImpersonationDaFicha(nodo, contexto, chat, npcInfo)
    return cleanText(impersonation.name or "Criatura")
end

local function enviarLinhaComoNpc(chat, nodo, linha, opts, contexto, npcInfo)
    local impersonation = resolverImpersonationDaFicha(nodo, contexto, chat, npcInfo)
    local nomeNpc = cleanText(impersonation.name or "")

    diagnosticarImpersonacao(nodo, contexto, chat, impersonation)

    if cleanText(impersonation.name or "") ~= "" then
        local ok = pcall(function()
            chat:asyncSendStd(linha, {impersonation = impersonation})
        end)

        if not ok then
            chat:enviarMensagemNPC(nomeNpc, linha)
        end
    elseif cleanText(nomeNpc) ~= "" then
        chat:enviarMensagemNPC(nomeNpc, linha)
    else
        chat:writeEx(linha, opts)
    end
end

local function exibirDanoLocal(chat, nodo, nomeAtaque, expressao, contexto, npcInfo)
    local texto = cleanText(expressao)

    if texto == "" then
        return
    end

    local opts = {
        defaultTextStyle = {
            color = "White",
            fontStyle = {}
        }
    }

    local rolagem = rrpg.interpretarRolagem(texto)

    if rolagem ~= nil and rolagem:getPossuiAlgumDado() then
        rolagem:rolarLocalmente()
        local resultados = formatarResultadosDosDados(rolagem)
        local total = arredondarInteiro(rolagem:getResultado())
        local linha = montarLinhaDano(nomeAtaque or "", texto, resultados, total)

        enviarLinhaComoNpc(chat, nodo, linha, opts, contexto, npcInfo)
    else
        local linha = string.format("%s - %s", nomeAtaque or "", formatarExpressaoDano(texto))
        enviarLinhaComoNpc(chat, nodo, linha, opts, contexto, npcInfo)
    end
end

local function exibirAtaqueLocal(chat, nodo, nomeAtaque, expressao, contexto, npcInfo)
    local texto = cleanText(expressao)

    if texto == "" then
        return
    end

    local opts = {
        defaultTextStyle = {
            color = "White",
            fontStyle = {}
        }
    }

    local rolagem = rrpg.interpretarRolagem(texto)

    if rolagem ~= nil and rolagem:getPossuiAlgumDado() then
        rolagem:rolarLocalmente()
        local resultados = formatarResultadosDosDados(rolagem)
        local total = arredondarInteiro(rolagem:getResultado())
        local linha = montarLinhaAtaque(nomeAtaque or "", texto, resultados, total)
        enviarLinhaComoNpc(chat, nodo, linha, opts, contexto, npcInfo)
    end
end

function rolarExpressaoComoNpc(chat, nodo, rotulo, expressao, contexto, npcInfo)
    local texto = cleanText(expressao)

    if chat == nil or texto == "" then
        return
    end

    local opts = {
        defaultTextStyle = {
            color = "White",
            fontStyle = {}
        }
    }

    local rolagem = rrpg.interpretarRolagem(texto)

    if rolagem ~= nil and rolagem:getPossuiAlgumDado() then
        rolagem:rolarLocalmente()

        local resultados = formatarResultadosDosDados(rolagem)
        local total = arredondarInteiro(rolagem:getResultado())
        local categoria = categoriaDaRolagem(rotulo)
        local linha = montarLinhaRolagemGenerica(rotulo, texto, resultados, total, categoria)
        enviarLinhaComoNpc(chat, nodo, linha, opts, contexto, npcInfo)
    end
end

local function dbg(...) end -- se quiser, coloca showMessage aqui

------------------------------------------------------------
-- HTTP WRAPPER
------------------------------------------------------------

local function urlEncode(s)
    s = tostring(s or "")
    s = s:gsub("\n", "\r\n")
    s = s:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

local function httpPOST(url, jsonStr, success, fail)
    local req = internet.newHTTPRequest("POST", url)
    if req == nil then
        if fail then fail("newHTTPRequest nil") end
        return
    end

    req.onResponse = function()
        local status = req.status or 0

        if status ~= 200 then
            if fail then fail("HTTP " .. tostring(status), status, req.responseText) end
            return
        end

        if success then success(req.responseText) end
    end

    req.onError = function(err)
        if fail then fail(err) end
    end

    req:setRequestHeader("Content-Type", "application/json; charset=utf-8")
    req:send(jsonStr)
end

local function httpPOSTAuthenticated(url, jsonStr, token, success, fail)
    local req = internet.newHTTPRequest("POST", url)
    if req == nil then if fail then fail("newHTTPRequest nil") end return end
    req.onResponse = function()
        local status = req.status or 0
        if status < 200 or status >= 300 then
            if fail then fail("HTTP " .. tostring(status), status, req.responseText) end
            return
        end
        if success then success(req.responseText, status) end
    end
    req.onError = function(err) if fail then fail(err) end end
    req:setRequestHeader("Content-Type", "application/json; charset=utf-8")
    if token and token ~= "" then req:setRequestHeader("Authorization", "Bearer " .. token) end
    req:send(jsonStr or "")
end

local function httpGET(url, success, fail)
    local req = internet.newHTTPRequest("GET", url)
    if req == nil then
        if fail then fail("newHTTPRequest nil") end
        return
    end

    req.onResponse = function()
        local status = req.status or 0

        if status ~= 200 then
            if fail then fail("HTTP " .. tostring(status), status, req.responseText) end
            return
        end

        if success then success(req.responseText) end
    end

    req.onError = function(err)
        if fail then fail(err) end
    end

    req:send("")
end

local function httpGETAuthenticated(url, token, success, fail)
    local req = internet.newHTTPRequest("GET", url)
    if req == nil then if fail then fail("newHTTPRequest nil") end return end
    req.onResponse = function()
        local status = req.status or 0
        if status < 200 or status >= 300 then
            if fail then fail("HTTP " .. tostring(status), status, req.responseText) end
            return
        end
        if success then success(req.responseText, status) end
    end
    req.onError = function(err) if fail then fail(err) end end
    if token and token ~= "" then req:setRequestHeader("Authorization", "Bearer " .. token) end
    req:send("")
end

local function extractErroXML(xml)
    if type(xml) ~= "string" then
        return ""
    end

    local codigo = xml:match("<erro[^>]*codigo%s*=%s*\"([^\"]+)\"")
    if codigo ~= nil and codigo ~= "" then
        return cleanText(codigo)
    end

    codigo = xml:match("<erro[^>]*>%s*(.-)%s*</erro>")
    return cleanText(codigo or "")
end

local function mensagemAmigavelGemini(err, status, responseText)
    local codigo = extractErroXML(responseText)
    local textoErro = cleanText(tostring(err or ""))
    local statusNum = tonumber(status or textoErro:match("HTTP%s+(%d+)") or 0) or 0

    if codigo == "prompt_ausente" then
        return "Cole o texto da criatura antes de pedir para a IA montar a ficha."
    end

    if codigo == "gemini_sem_texto" or codigo == "gemini_resposta_vazia" then
        return "O Gemini respondeu, mas nao trouxe uma ficha valida. Tente novamente ou reduza o texto da criatura."
    end

    if codigo == "gemini_sem_xml" or codigo == "xml_incompleto" then
        return "O Gemini respondeu fora do formato esperado. Tente novamente; se persistir, simplifique o texto de entrada."
    end

    if codigo == "gemini_auth" or statusNum == 401 or statusNum == 403 then
        return "A chave do Gemini foi recusada. Verifique a API key no proxy e reinicie o servidor local."
    end

    if codigo == "gemini_quota" or statusNum == 429 then
        return "O limite do Gemini foi atingido agora. Aguarde um pouco e tente novamente."
    end

    if codigo == "gemini_api" then
        return "O Gemini recusou a solicitacao agora. Tente novamente em instantes ou revise o texto da criatura."
    end

    if codigo == "gemini_indisponivel" or statusNum == 503 then
        return "O Gemini esta sobrecarregado no momento. Aguarde alguns instantes e tente novamente."
    end

    if codigo == "gemini_bloqueado" then
        return "O Gemini bloqueou a resposta por seguranca. Revise o texto da criatura e tente novamente."
    end

    if codigo == "proxy_erro" then
        return "O proxy local do Gemini encontrou um problema. Reinicie o proxy e tente novamente."
    end

    if textoErro:find("newHTTPRequest", 1, true) then
        return "Nao consegui iniciar a conexao com o proxy local do Gemini."
    end

    if textoErro:find("HTTP", 1, true) or statusNum >= 500 then
        return "O proxy local do Gemini encontrou um problema. Verifique se ele esta aberto e tente novamente."
    end

    return "Nao consegui falar com o Gemini agora. Verifique o proxy local e tente novamente."
end

local function mensagemAmigavelSaoNode(err, status, responseText)
    local codigo = extractErroXML(responseText)
    local textoErro = cleanText(tostring(err or ""))
    local statusNum = tonumber(status or textoErro:match("HTTP%s+(%d+)") or 0) or 0

    if codigo == "parametros_ausentes" then
        return "Informe a campanha e o ID do monstro no SAO-NODE antes de buscar a ficha."
    end

    if codigo == "sao_node_sem_sessao" then
        return "O proxy local nao tem uma sessao configurada para o SAO-NODE. Configure SAO_NODE_SESSION_COOKIE e reinicie o proxy."
    end

    if codigo == "sao_node_nao_autorizado" or statusNum == 401 or statusNum == 403 then
        return "A sessao do SAO-NODE nao tem permissao de mestre nessa campanha, ou expirou."
    end

    if codigo == "sao_node_monstro_nao_encontrado" or statusNum == 404 then
        return "Nao encontrei esse monstro na campanha informada do SAO-NODE."
    end

    if codigo == "sao_node_erro" or codigo == "sao_node_proxy_erro" then
        return "O SAO-NODE recusou a solicitacao agora. Tente novamente em instantes."
    end

    if textoErro:find("newHTTPRequest", 1, true) then
        return "Nao consegui iniciar a conexao com o proxy local do SAO-NODE."
    end

    if textoErro:find("HTTP", 1, true) or statusNum >= 500 then
        return "O proxy local do SAO-NODE encontrou um problema. Verifique se ele esta aberto e tente novamente."
    end

    return "Nao consegui buscar o monstro no SAO-NODE agora. Verifique o proxy local e tente novamente."
end

------------------------------------------------------------
-- XML PARSER
------------------------------------------------------------

local function extractTag(xml, tag)
    if not xml then return "" end
    local v = xml:match("<" .. tag .. "[^>]*>%s*(.-)%s*</" .. tag .. ">")
    if not v then return "" end
    return xmlDecode(cleanText(v))
end

-- Extracts a payload without collapsing line breaks.  This is used for fields
-- such as originalSheet and the JSON/source text where whitespace is data.
local function extractRawTag(xml, tag)
    if not xml then return "" end
    local v = xml:match("<" .. tag .. "[^>]*>(.-)</" .. tag .. ">")
    if not v then return "" end
    local cdata = v:match("^<!%[CDATA%[(.*)%]%]>$")
    if cdata ~= nil then v = cdata end
    return xmlDecode(v)
end

local function ensureTokenUserData(token)
    if token == nil then
        return nil
    end

    local ok = pcall(function()
        local dl = token:newUserDataLink("deslocamento")
        if dl ~= nil then
            dl:destroy()
        end
    end)

    if not ok then
        return nil
    end

    return token.userData
end

local TOKEN_FIELD_PREFIX = "monsterIA_"
local TOKEN_ATTACKS_FIELD = TOKEN_FIELD_PREFIX .. "ataques"
local TOKEN_ATTACK_COUNT_FIELD = TOKEN_FIELD_PREFIX .. "ataques_qtd"
local TOKEN_NAME_FIELD = TOKEN_FIELD_PREFIX .. "nome"
local TOKEN_AVATAR_FIELD = TOKEN_FIELD_PREFIX .. "avatar"
local TOKEN_MENU_CATEGORIES = {
    {key = "perfil", title = "Perfil", color = "#D0D5DD", itemColor = "#EAECF0"},
    {key = "atributos", title = "Atributos", color = "#F2C94C", itemColor = "#FDE68A"},
    {key = "resistencias", title = "Resistencias", color = "#EB5757", itemColor = "#FCA5A5"},
    {key = "pericias", title = "Pericias", color = "#56CCF2", itemColor = "#BAE6FD"},
    {key = "ataques", title = "Ataques", color = "#F2994A", itemColor = "#FDBA74"},
    {key = "habilidades", title = "Habilidades", color = "#BB6BD9", itemColor = "#E9D5FF"},
    {key = "sentidos", title = "Sentidos", color = "#6FCF97", itemColor = "#BBF7D0"},
    {key = "equipamentos", title = "Equipamentos", color = "#A3E635", itemColor = "#D9F99D"}
}
local TOKEN_MENU_ITEM_FIELDS = {
    "nome",
    "texto",
    "tipo",
    "rolagem",
    "quantidade",
    "bonus",
    "dano",
    "alcance",
    "critico",
    "descricao",
    "observacoes",
    "rolagemAtaque",
    "rolagensDano"
}
local TOKEN_ATTACK_LINE_SEPARATOR = "[[MI_ATTACK]]"
local TOKEN_ATTACK_FIELD_SEPARATOR = "[[MI_FIELD]]"
local TOKEN_ATTACK_FIELDS = {
    "nome",
    "quantidade",
    "bonus",
    "dano",
    "tipo",
    "alcance",
    "critico",
    "descricao",
    "observacoes",
    "rolagemAtaque",
    "rolagensDano"
}

local showTokenAttackPopup = nil

local KNOWN_DAMAGE_TYPES = {
    "Eletricidade",
    "Perfuracao",
    "PerfuraÃ§Ã£o",
    "Essencia",
    "EssÃªncia",
    "Impacto",
    "Corte",
    "Fogo",
    "Frio",
    "Acido",
    "Ãcido",
    "Veneno",
    "Sonico",
    "SÃ´nico",
    "Mental",
    "Trevas",
    "Luz"
}

local function normalizeRollExpression(expr)
    local texto = cleanText(expr or "")

    if texto == "" then
        return ""
    end

    texto = texto:gsub("%s+", "")

    if texto:match("^%d+[dD]%d+[%+%-]?%d*$") then
        return texto
    end

    if texto:match("^1[dD]20[%+%-]?%d*$") then
        return texto
    end

    return ""
end

local function parseBonusNumber(bonus)
    local texto = cleanText(tostring(bonus or ""))
    local numero = texto:match("([+-]?%d+)")

    return tonumber(numero) or 0
end

local function buildAttackRoll(bonus)
    return "1d20+" .. tostring(parseBonusNumber(bonus))
end

local function extractDamageRolls(texto)
    local rolls = {}
    local base = cleanText(texto or "")

    for roll in base:gmatch("(%d+[dD]%d+%s*[%+%-]?%s*%d*)") do
        local normalized = normalizeRollExpression(roll)
        if normalized ~= "" then
            rolls[#rolls + 1] = normalized
        end
    end

    return rolls
end

local function encodeDamageRolls(rolls)
    return table.concat(rolls or {}, ";")
end

local function decodeDamageRolls(texto)
    local rolls = {}
    local base = cleanText(texto or "")

    for roll in base:gmatch("([^;]+)") do
        local normalized = normalizeRollExpression(roll)
        if normalized ~= "" then
            rolls[#rolls + 1] = normalized
        end
    end

    return rolls
end

local function prepareAttackRollFields(atk)
    if type(atk) ~= "table" then
        return atk
    end

    atk.bonus = cleanText(atk.bonus or ""):gsub("%s+", "")
    atk.dano = cleanText(atk.dano or ""):gsub("%s+", "")

    if cleanText(atk.rolagemAtaque or "") == "" then
        atk.rolagemAtaque = buildAttackRoll(atk.bonus)
    else
        atk.rolagemAtaque = normalizeRollExpression(atk.rolagemAtaque)
    end

    local danos = decodeDamageRolls(atk.rolagensDano or "")
    if #danos == 0 then
        danos = extractDamageRolls(atk.dano)
    end

    atk.rolagensDano = encodeDamageRolls(danos)

    return atk
end

local function prepareTokenUserDataFields(token, fields)
    if token == nil then
        return false
    end

    return pcall(function()
        for _, field in ipairs(fields or {}) do
            local dl = token:newUserDataLink(field)
            if dl ~= nil then
                dl:destroy()
            end
        end
    end)
end

local function tokenAttackField(index, field)
    return TOKEN_FIELD_PREFIX .. "ataque_" .. tostring(index) .. "_" .. field
end

local function tokenMenuCountField(categoryKey)
    return TOKEN_FIELD_PREFIX .. "menu_" .. categoryKey .. "_qtd"
end

local function tokenMenuField(categoryKey, index, field)
    return TOKEN_FIELD_PREFIX .. "menu_" .. categoryKey .. "_" .. tostring(index) .. "_" .. field
end

local function buildTokenAttackUserDataFields(count)
    local fields = {TOKEN_ATTACK_COUNT_FIELD}

    for i = 1, count do
        for _, field in ipairs(TOKEN_ATTACK_FIELDS) do
            fields[#fields + 1] = tokenAttackField(i, field)
        end
    end

    return fields
end

local function buildTokenMenuUserDataFields(categories)
    local fields = {}

    for _, def in ipairs(TOKEN_MENU_CATEGORIES) do
        local items = categories and categories[def.key] or {}
        fields[#fields + 1] = tokenMenuCountField(def.key)

        for i = 1, #(items or {}) do
            for _, field in ipairs(TOKEN_MENU_ITEM_FIELDS) do
                fields[#fields + 1] = tokenMenuField(def.key, i, field)
            end
        end
    end

    return fields
end

local function safeTokenUserData(token)
    if token == nil then
        return nil
    end

    local ok, userData = pcall(function()
        return token.userData
    end)

    if ok and type(userData) == "table" then
        return userData
    end

    return nil
end

local function normalizeAttackForToken(atk)
    if type(atk) ~= "table" then
        return nil
    end

    local nome = cleanText(atk.nome or "")

    if nome == "" then
        return nil
    end

    return prepareAttackRollFields({
        nome = nome,
        quantidade = cleanText(atk.quantidade or ""),
        bonus = cleanText(atk.bonus or ""),
        dano = cleanText(atk.dano or ""),
        tipo = cleanText(atk.tipo or ""),
        alcance = cleanText(atk.alcance or ""),
        critico = cleanText(atk.critico or ""),
        descricao = cleanText(atk.descricao or ""),
        observacoes = cleanText(atk.observacoes or ""),
        rolagemAtaque = cleanText(atk.rolagemAtaque or ""),
        rolagensDano = cleanText(atk.rolagensDano or "")
    })
end

local function splitTokenAttackLine(line)
    local fields = {}
    local inicio = 1

    while true do
        local pos = line:find(TOKEN_ATTACK_FIELD_SEPARATOR, inicio, true)

        if pos == nil then
            fields[#fields + 1] = line:sub(inicio)
            break
        end

        fields[#fields + 1] = line:sub(inicio, pos - 1)
        inicio = pos + 1
    end

    return fields
end

local function encodeTokenAttacks(ataques)
    local linhas = {}

    for _, atk in ipairs(ataques or {}) do
        local campos = {}

        for _, campo in ipairs(TOKEN_ATTACK_FIELDS) do
            campos[#campos + 1] = cleanText(atk[campo] or "")
        end

        linhas[#linhas + 1] = table.concat(campos, TOKEN_ATTACK_FIELD_SEPARATOR)
    end

    return table.concat(linhas, TOKEN_ATTACK_LINE_SEPARATOR)
end

local function decodeTokenAttacks(raw)
    local ataques = {}

    if type(raw) ~= "string" or raw == "" then
        return ataques
    end

    local inicio = 1

    while inicio <= #raw do
        local pos = raw:find(TOKEN_ATTACK_LINE_SEPARATOR, inicio, true)
        local linha = nil

        if pos == nil then
            linha = raw:sub(inicio)
            inicio = #raw + 1
        else
            linha = raw:sub(inicio, pos - 1)
            inicio = pos + 1
        end

        local campos = splitTokenAttackLine(linha)
        local atk = {}

        for i, campo in ipairs(TOKEN_ATTACK_FIELDS) do
            atk[campo] = campos[i] or ""
        end

        local ataque = normalizeAttackForToken(atk)
        if ataque ~= nil then
            ataques[#ataques + 1] = ataque
        end
    end

    return ataques
end

local function writeTokenAttacksToUserData(token, userData, ataques)
    if type(userData) ~= "table" then
        return
    end

    ataques = ataques or {}

    prepareTokenUserDataFields(token, buildTokenAttackUserDataFields(#ataques))

    userData[TOKEN_ATTACK_COUNT_FIELD] = tostring(#ataques)
    userData[TOKEN_ATTACKS_FIELD] = ""

    for i, atk in ipairs(ataques) do
        local ataque = normalizeAttackForToken(atk)

        if ataque ~= nil then
            for _, field in ipairs(TOKEN_ATTACK_FIELDS) do
                userData[tokenAttackField(i, field)] = cleanText(ataque[field] or "")
            end
        end
    end
end

local function readTokenAttacksFromUserDataFields(userData)
    local ataques = {}

    if type(userData) ~= "table" then
        return ataques
    end

    local count = tonumber(userData[TOKEN_ATTACK_COUNT_FIELD] or 0) or 0

    for i = 1, count do
        local atk = {}

        for _, field in ipairs(TOKEN_ATTACK_FIELDS) do
            atk[field] = userData[tokenAttackField(i, field)] or ""
        end

        local ataque = normalizeAttackForToken(atk)
        if ataque ~= nil then
            ataques[#ataques + 1] = ataque
        end
    end

    return ataques
end

local function normalizeMenuItem(item)
    if type(item) ~= "table" then
        return nil
    end

    local nome = cleanText(item.nome or item.texto or "")
    local texto = cleanText(item.texto or "")

    if (nome == "" and texto == "") or normalize(nome) == "nenhum" or normalize(texto) == "nenhum" then
        return nil
    end

    local normalized = {}

    for _, field in ipairs(TOKEN_MENU_ITEM_FIELDS) do
        normalized[field] = cleanText(item[field] or "")
    end

    normalized.nome = nome
    normalized.texto = texto ~= "" and texto or nome

    return normalized
end

local function addMenuItem(list, item)
    local normalized = normalizeMenuItem(item)

    if normalized ~= nil then
        list[#list + 1] = normalized
    end
end

local function writeTokenMenuCategoriesToUserData(token, userData, categories)
    if type(userData) ~= "table" then
        return
    end

    prepareTokenUserDataFields(token, buildTokenMenuUserDataFields(categories))

    for _, def in ipairs(TOKEN_MENU_CATEGORIES) do
        local items = categories and categories[def.key] or {}

        userData[tokenMenuCountField(def.key)] = tostring(#items)

        for i, item in ipairs(items) do
            local normalized = normalizeMenuItem(item)

            if normalized ~= nil then
                for _, field in ipairs(TOKEN_MENU_ITEM_FIELDS) do
                    userData[tokenMenuField(def.key, i, field)] = cleanText(normalized[field] or "")
                end
            end
        end
    end
end

local function readTokenMenuCategoriesFromUserData(userData)
    local categories = {}

    if type(userData) ~= "table" then
        return categories
    end

    for _, def in ipairs(TOKEN_MENU_CATEGORIES) do
        local items = {}
        local count = tonumber(userData[tokenMenuCountField(def.key)] or 0) or 0

        for i = 1, count do
            local item = {}

            for _, field in ipairs(TOKEN_MENU_ITEM_FIELDS) do
                item[field] = userData[tokenMenuField(def.key, i, field)] or ""
            end

            addMenuItem(items, item)
        end

        if #items > 0 then
            categories[def.key] = items
        end
    end

    return categories
end

local function parseAttackFromTextItem(itemText)
    local texto = cleanText(itemText or "")

    if texto == "" then
        return nil
    end

    local bonusStart, bonusEnd = texto:find("[+-]%s*%d+")
    local danoStart, danoEnd = texto:find("%d+[dD]%d+%s*[%+%-]?%s*%d*")
    local quantidade = texto:match("[xX](%d+)")
    local bonus = ""
    local dano = ""
    local tipo = ""
    local nome = texto

    if bonusStart ~= nil then
        bonus = cleanText(texto:sub(bonusStart, bonusEnd):gsub("%s+", ""))
        nome = cleanText(texto:sub(1, bonusStart - 1))
    elseif danoStart ~= nil then
        nome = cleanText(texto:sub(1, danoStart - 1))
    end

    if danoStart ~= nil then
        dano = cleanText(texto:sub(danoStart, danoEnd):gsub("%s+", ""))
        tipo = cleanText(texto:sub(danoEnd + 1):gsub("^%)", ""):gsub("^%(", ""))
    end

    nome = cleanText(nome:gsub("%s+[xX]%d+%s*$", ""))

    if nome == "" then
        nome = texto
    end

    return normalizeAttackForToken({
        nome = nome,
        quantidade = quantidade or "",
        bonus = bonus,
        dano = dano,
        tipo = tipo,
        alcance = "",
        critico = "",
        descricao = "",
        observacoes = ""
    })
end

local function extractLeadingDamageType(texto)
    local base = cleanText(texto or "")

    if base == "" then
        return "", ""
    end

    local lower = normalize(base)

    for _, tipo in ipairs(KNOWN_DAMAGE_TYPES) do
        local tipoNorm = normalize(tipo)

        if lower:sub(1, #tipoNorm) == tipoNorm then
            return tipo, cleanText(base:sub(#tipo + 1))
        end
    end

    return "", base
end

local function parseAttackSequenceFromText(texto)
    local ataques = {}
    local restante = cleanText(texto or "")
    local guard = 0

    while restante ~= "" and guard < 20 do
        guard = guard + 1

        local nome, quantidade, sinal, bonusDano, danoResto, depois =
            restante:match("^(.-)%s*[xX]?(%d+)%s*([+-])(%d+)([dD]%d+%s*[%+%-]?%s*%d*)%s*(.*)$")
        local bonus = nil
        local dano = nil

        if nome ~= nil and bonusDano ~= nil and #bonusDano > 1 then
            bonus = sinal .. bonusDano:sub(1, #bonusDano - 1)
            dano = bonusDano:sub(#bonusDano) .. danoResto
        else
            nome, quantidade, bonus, dano, depois =
                restante:match("^(.-)%s*[xX]?(%d+)%s*([+-]%s*%d+).-(%d+[dD]%d+%s*[%+%-]?%s*%d*)%s*(.*)$")
        end

        if nome == nil then
            nome, bonus, dano, depois =
                restante:match("^(.-)%s+([+-]%s*%d+).-(%d+[dD]%d+%s*[%+%-]?%s*%d*)%s*(.*)$")
            quantidade = ""
        end

        if nome == nil then
            local ataque = parseAttackFromTextItem(restante)
            if ataque ~= nil then
                ataques[#ataques + 1] = ataque
            end
            break
        end

        local tipo, proximo = extractLeadingDamageType(depois)
        local ataque = normalizeAttackForToken({
            nome = nome,
            quantidade = quantidade or "",
            bonus = cleanText((bonus or ""):gsub("%s+", "")),
            dano = cleanText((dano or ""):gsub("%s+", "")),
            tipo = tipo,
            alcance = "",
            critico = "",
            descricao = "",
            observacoes = ""
        })

        if ataque ~= nil then
            ataques[#ataques + 1] = ataque
        end

        if proximo == "" or proximo == restante then
            break
        end

        restante = proximo
    end

    return ataques
end

local function parseAttacksFromText(texto)
    local ataques = {}
    local base = cleanText(texto or "")

    if base == "" then
        return ataques
    end

    base = base:gsub("%s*[|;]%s*", "\n")

    for itemText in base:gmatch("([^\n]+)") do
        local lista = parseAttackSequenceFromText(itemText)

        for _, ataque in ipairs(lista) do
            ataques[#ataques + 1] = ataque
        end
    end

    return ataques
end

local function buildTokenAttackPayload(nodo)
    local data = nil

    if nodo ~= nil then
        if cleanText(nodo.xmlCriatura or "") ~= "" and rebuildDataIAFromXML ~= nil then
            data = rebuildDataIAFromXML(nodo)
        end

        if type(data) ~= "table" then
            data = nodo.dataIA
        end

        if type(data) ~= "table" then
            local ataquesNode = decodeTokenAttacks(nodo[TOKEN_ATTACKS_FIELD] or "")
            if #ataquesNode > 0 then
                return ataquesNode
            end
        end
    end

    local ataques = {}

    if type(data) == "table" then
        for _, atk in ipairs(data.ataques or {}) do
            local ataque = normalizeAttackForToken(atk)
            if ataque ~= nil then
                if ataque.rolagensDano == "" and ataque.nome:match("%d+[dD]%d+") then
                    local reparsed = parseAttacksFromText(ataque.nome)

                    for _, ataqueReparsed in ipairs(reparsed) do
                        ataques[#ataques + 1] = ataqueReparsed
                    end
                else
                    ataques[#ataques + 1] = ataque
                end
            end
        end
    end

    if #ataques == 0 and nodo ~= nil then
        ataques = parseAttacksFromText(nodo.ataques_texto or "")
    end

    return ataques
end

local function splitTokenTextList(texto, splitCommas)
    local res = {}
    local base = cleanText(texto or "")

    if base == "" then
        return res
    end

    base = base:gsub("%s*[|;]%s*", "\n")

    if splitCommas then
        base = base:gsub("%s*,%s*", "\n")
    end

    for item in base:gmatch("([^\n]+)") do
        item = cleanText(item)

        if item ~= "" and normalize(item) ~= "nenhum" then
            res[#res + 1] = item
        end
    end

    return res
end

local function resolveDataForTokenPayload(nodo)
    if nodo == nil then
        return nil
    end

    if cleanText(nodo.xmlCriatura or "") ~= "" and rebuildDataIAFromXML ~= nil then
        return rebuildDataIAFromXML(nodo)
    end

    if type(nodo.dataIA) == "table" then
        return nodo.dataIA
    end

    return nil
end

local function rollFromTrailingBonus(texto)
    local bonus = cleanText(texto or ""):match("([+-]?%d+)%s*$")

    if bonus == nil then
        return ""
    end

    return buildAttackRoll(bonus)
end

local function buildTokenMenuCategories(nodo, ataques)
    local data = resolveDataForTokenPayload(nodo) or {}
    local categories = {
        perfil = {},
        atributos = {},
        resistencias = {},
        pericias = {},
        ataques = {},
        habilidades = {},
        sentidos = {},
        equipamentos = {}
    }

    local function addScalar(categoryKey, label, value)
        local text = cleanText(tostring(value or ""))

        if text ~= "" and normalize(text) ~= "nenhum" then
            addMenuItem(categories[categoryKey], {nome = label, texto = label .. ": " .. text})
        end
    end

    if nodo ~= nil then
        addScalar("perfil", "Nome", nodo.nome or data.nome or "")
        addScalar("perfil", "ND", tostring(nodo.nd or data.nd or ""))
        addScalar("perfil", "Tipo", nodo.tipo or data.tipo or "")
        addScalar("perfil", "Tamanho", nodo.tamanho or data.tamanho or "")
        addScalar("perfil", "PV", tostring(nodo.pv or data.pv or ""))
        addScalar("perfil", "Mana", tostring(nodo.mana or data.mana or ""))
        addScalar("perfil", "Defesa", tostring(nodo.ca or data.ca or ""))
        addScalar("perfil", "Deslocamento", nodo.deslocamento or data.deslocamento or "")
        addScalar("perfil", "Descricao", nodo.descricao or data.descricao or "")

        local attrs = {
            {"FOR", nodo.att_for or (data.atributos and data.atributos["for"])},
            {"DES", nodo.att_des or (data.atributos and data.atributos["des"])},
            {"CON", nodo.att_con or (data.atributos and data.atributos["con"])},
            {"INT", nodo.att_int or (data.atributos and data.atributos["int"])},
            {"SAB", nodo.att_sab or (data.atributos and data.atributos["sab"])},
            {"CAR", nodo.att_car or (data.atributos and data.atributos["car"])}
        }

        for _, attr in ipairs(attrs) do
            local valor = tonumber(attr[2])
            if valor ~= nil then
                addMenuItem(categories.atributos, {
                    nome = attr[1] .. " " .. tostring(valor),
                    texto = attr[1] .. ": " .. tostring(valor),
                    rolagem = buildAttackRoll(valor)
                })
            end
        end

        local saves = {
            {"Fortitude", nodo.res_fort or data.fort},
            {"Reflexos", nodo.res_ref or data.ref},
            {"Vontade", nodo.res_von or data.von}
        }

        for _, save in ipairs(saves) do
            local valor = tonumber(save[2])
            if valor ~= nil then
                addMenuItem(categories.resistencias, {
                    nome = save[1] .. " " .. tostring(valor),
                    texto = save[1] .. ": " .. tostring(valor),
                    rolagem = buildAttackRoll(valor)
                })
            end
        end

        for _, item in ipairs(data.resistencias or splitTokenTextList(nodo.resistencias_texto, true)) do
            addMenuItem(categories.resistencias, {nome = item, texto = item, tipo = "resistencia"})
        end

        for _, item in ipairs(data.imunidades or splitTokenTextList(nodo.imunidades_texto, true)) do
            addMenuItem(categories.resistencias, {nome = "Imunidade: " .. item, texto = item, tipo = "imunidade"})
        end

        for _, item in ipairs(data.pericias or splitTokenTextList(nodo.pericias_texto, true)) do
            addMenuItem(categories.pericias, {nome = item, texto = item, rolagem = rollFromTrailingBonus(item)})
        end

        for _, atk in ipairs(ataques or {}) do
            addMenuItem(categories.ataques, atk)
        end

        if type(data.habilidades) == "table" and #data.habilidades > 0 then
            for _, hab in ipairs(data.habilidades) do
                addMenuItem(categories.habilidades, {
                    nome = hab.nome or "",
                    texto = hab.texto or hab.descricao or hab.nome or "",
                    tipo = hab.tipo or "",
                    descricao = hab.descricao or "",
                    observacoes = hab.observacoes or ""
                })
            end
        else
            for _, item in ipairs(splitTokenTextList(nodo.habilidades_texto, false)) do
                addMenuItem(categories.habilidades, {nome = item, texto = item})
            end
        end

        for _, item in ipairs(data.sentidos or splitTokenTextList(nodo.sentidos, true)) do
            addMenuItem(categories.sentidos, {nome = item, texto = item})
        end

        for _, item in ipairs(data.equipamentos or splitTokenTextList(nodo.equipamentos, true)) do
            addMenuItem(categories.equipamentos, {nome = item, texto = item})
        end
    end

    return categories
end

local function readTokenAttacks(token)
    local userData = safeTokenUserData(token)

    if userData == nil then
        return {}
    end

    return readTokenAttacksFromUserDataFields(userData)
end

local function getTokenNpcInfo(token)
    local userData = safeTokenUserData(token) or {}
    local nome = cleanText(userData[TOKEN_NAME_FIELD] or "")
    local avatar = cleanText(userData[TOKEN_AVATAR_FIELD] or "")

    if nome == "" and token ~= nil then
        nome = cleanText(token.name or "")
    end

    return {
        name = nome ~= "" and nome or "Criatura",
        avatar = avatar
    }
end

local function findSelectedToken()
    local scenes = SceneLib.getLoadedScenes() or {}

    for _, scene in ipairs(scenes) do
        local items = scene.items
        local selection = items and items.selection or nil

        for _, item in ipairs(selection or {}) do
            if item ~= nil and item.isObjectAlive and item:isType("token") then
                return item
            end
        end
    end

    return nil
end

local function buildFichaSavePayload(nodo)
    return {
        nome = nodo.nome or "",
        nd = tonumber(nodo.nd) or 0,
        tipo = nodo.tipo or "",
        tamanho = nodo.tamanho or "",
        descricao = nodo.descricao or "",
        pv = tonumber(nodo.pv) or 0,
        mana = tonumber(nodo.mana) or 0,
        defesa = tonumber(nodo.ca) or 0,
        iniciativa = tonumber(nodo.iniciativa) or 0,
        percepcao = tonumber(nodo.percepcao) or 0,
        deslocamento = nodo.deslocamento or "",
        att_for = tonumber(nodo.att_for) or 0,
        att_des = tonumber(nodo.att_des) or 0,
        att_con = tonumber(nodo.att_con) or 0,
        att_int = tonumber(nodo.att_int) or 0,
        att_sab = tonumber(nodo.att_sab) or 0,
        att_car = tonumber(nodo.att_car) or 0,
        res_fort = tonumber(nodo.res_fort) or 0,
        res_ref = tonumber(nodo.res_ref) or 0,
        res_von = tonumber(nodo.res_von) or 0,
        equipamentos = nodo.equipamentos or "",
        sentidos = nodo.sentidos or "",
        pericias_texto = nodo.pericias_texto or "",
        resistencias_texto = nodo.resistencias_texto or "",
        imunidades_texto = nodo.imunidades_texto or "",
        ataques_texto = nodo.ataques_texto or "",
        habilidades_texto = nodo.habilidades_texto or "",
        magias_texto = nodo.magias_texto or "",
        originalSheet = nodo.originalSheet or "",
        dadosAdicionais = nodo.dadosAdicionais or "",
        saoNodeSourceJson = nodo.saoNodeSourceJson or "",
        monsterIA_ataques = nodo[TOKEN_ATTACKS_FIELD] or "",
        comoJogar = nodo.comoJogar or "",
        textoBrutoIA = nodo.textoBrutoIA or "",
        xmlCriatura = nodo.xmlCriatura or "",
        imagemURL = nodo.imagemURL or ""
    }
end

function salvarFichaLocalmente(nodo)
    if nodo == nil then
        showMessage("Nenhuma ficha selecionada.")
        return
    end

    local body = json.encode({ ficha = buildFichaSavePayload(nodo) })

    httpPOST(
        "http://localhost:3000/save-ficha",
        body,
        function(responseText)
            local ok, payload = pcall(function() return json.decode(responseText) end)

            if ok and type(payload) == "table" and payload.ok then
                showMessage("Ficha salva em: " .. tostring(payload.fileName or payload.filePath or "saved-fichas"))
            else
                showMessage("Ficha salva, mas a resposta do proxy foi inesperada.")
            end
        end,
        function(err)
            showMessage("Nao consegui salvar a ficha agora. Verifique se o proxy local esta aberto e tente novamente.")
        end
    )
end

function aplicarFichaNoTokenSelecionado(nodo)
    if nodo == nil then
        showMessage("Nenhuma ficha selecionada.")
        return
    end

    local token = findSelectedToken()
    if token == nil then
        showMessage("Nenhum token selecionado em uma cena aberta.")
        return
    end

    local nome = cleanText(nodo.nome or "")
    local tamanho = cleanText(nodo.tamanho or "")
    local deslocamento = cleanText(nodo.deslocamento or "")
    local pv = tostring(tonumber(nodo.pv) or 0)
    local mana = tostring(tonumber(nodo.mana) or 0)
    local ca = tostring(tonumber(nodo.ca) or 0)
    local nomeToken = nome

    if tamanho ~= "" then
        nomeToken = nomeToken .. " (" .. tamanho .. ")"
    end

    if deslocamento ~= "" then
        nomeToken = nomeToken .. " - " .. deslocamento
    end

    token:beginUpdate()
    token.name = nomeToken ~= "" and nomeToken or token.name

    token.barColor1 = "#FF0000"
    token.barValue1 = pv
    token.barMax1 = pv

    token.barColor2 = "#0000FF"
    token.barValue2 = mana
    token.barMax2 = mana

    token.barColor3 = "#00FF00"
    token.barValue3 = ca
    token.barMax3 = ""

    local imagemURL = cleanText(nodo.imagemURL or "")
    if imagemURL ~= "" and token.image ~= nil then
        pcall(function()
            token.image.url = imagemURL
        end)
    end
    token:endUpdate()

    local ataques = buildTokenAttackPayload(nodo)
    local menuCategories = buildTokenMenuCategories(nodo, ataques)

    prepareTokenUserDataFields(token, {
        "deslocamento",
        TOKEN_NAME_FIELD,
        TOKEN_AVATAR_FIELD,
        TOKEN_ATTACKS_FIELD,
        TOKEN_ATTACK_COUNT_FIELD
    })

    local userData = ensureTokenUserData(token)
    if type(userData) == "table" then
        userData.deslocamento = deslocamento
        userData[TOKEN_NAME_FIELD] = nome
        userData[TOKEN_AVATAR_FIELD] = cleanText(nodo.imagemURL or "")
        writeTokenAttacksToUserData(token, userData, ataques)
        writeTokenMenuCategoriesToUserData(token, userData, menuCategories)

        if #ataques == 0 then
            showMessage("Ficha aplicada ao token, mas nenhum ataque foi encontrado para enviar.")
            return
        end
    end

    if showTokenAttackPopup ~= nil then
        setTimeout(function()
            if token ~= nil and token.isObjectAlive and token.selected then
                showTokenAttackPopup(token.scene, token)
            end
        end, 1)
    end

    showMessage("Ficha aplicada ao token selecionado. Ataques enviados para o token.")
end

local function extractCriaturaXML(xml)
    if not xml then return "" end

    local criatura = xml:match("<criatura[^>]*>%s*(.-)%s*</criatura>")
    if criatura then
        return criatura
    end

    return xml
end

local function extractBlock(xml, tag)
    if not xml then return nil end
    return xml:match("<" .. tag .. "[^>]*>%s*(.-)%s*</" .. tag .. ">")
end

local function splitPlainList(text)
    local res = {}
    local base = cleanText(text)

    if base == "" then
        return res
    end

    base = base:gsub("%s*[|;]%s*", "\n")
    base = base:gsub("%s*,%s*", "\n")

    for item in base:gmatch("([^\n]+)") do
        item = cleanText(item)
        if item ~= "" then
            res[#res + 1] = item
        end
    end

    if #res == 0 and base ~= "" then
        res[1] = base
    end

    return res
end

local function flattenXMLText(xml)
    if not xml then return "" end
    local text = xml:gsub("<[^>]+>", " ")
    return cleanText(text)
end

local function extractList(xml, tag)
    local res = {}
    local block = extractBlock(xml, tag)
    if not block then return res end

    for itemText in block:gmatch("<item>%s*(.-)%s*</item>") do
        res[#res + 1] = cleanText(itemText)
    end

    if #res == 0 then
        res = splitPlainList(flattenXMLText(block))
    end

    return res
end

local function extractNumberTag(xml, tag)
    local txt = extractTag(xml, tag)
    local num = txt:match("(-?%d+)")
    return tonumber(num) or 0
end

local function inferAttackQuantidade(nome, descricao, observacoes)
    local base = cleanText(table.concat({
        nome or "",
        descricao or "",
        observacoes or ""
    }, " "))

    if base == "" then
        return ""
    end

    local qtd = base:match("(%d+)%s+ataques?")
    if qtd then
        return qtd
    end

    qtd = base:match("(%d+)%s+golpes?")
    if qtd then
        return qtd
    end

    qtd = cleanText(nome or ""):match("^(%d+)%s+")
    if qtd then
        return qtd
    end

    return ""
end

local function pickTopEntries(list, maxCount, formatter)
    local res = {}

    for i, item in ipairs(list or {}) do
        if i > maxCount then
            break
        end

        local text = formatter(item)
        if cleanText(text) ~= "" then
            res[#res + 1] = text
        end
    end

    return res
end

local function buildHowToPlayText(data)
    if type(data) ~= "table" then
        return ""
    end

    local linhas = {}
    local nome = cleanText(data.nome or "Criatura")

    linhas[#linhas + 1] = "Como jogar com " .. nome

    local perfil = {}
    if cleanText(data.tipo or "") ~= "" then perfil[#perfil + 1] = data.tipo end
    if cleanText(data.tamanho or "") ~= "" then perfil[#perfil + 1] = data.tamanho end
    if tonumber(data.nd or 0) > 0 then perfil[#perfil + 1] = "ND " .. tostring(data.nd) end
    if #perfil > 0 then
        linhas[#linhas + 1] = ""
        linhas[#linhas + 1] = "Perfil: " .. table.concat(perfil, ", ")
    end

    local resumoCombate = {}
    if tonumber(data.pv or 0) > 0 then resumoCombate[#resumoCombate + 1] = "PV " .. tostring(data.pv) end
    if tonumber(data.ca or 0) > 0 then resumoCombate[#resumoCombate + 1] = "Defesa " .. tostring(data.ca) end
    if cleanText(data.deslocamento or "") ~= "" then resumoCombate[#resumoCombate + 1] = "Deslocamento " .. data.deslocamento end
    if #resumoCombate > 0 then
        linhas[#linhas + 1] = "Combate: " .. table.concat(resumoCombate, ", ")
    end

    local resists = {}
    if tonumber(data.fort or 0) ~= 0 then resists[#resists + 1] = "Fort " .. tostring(data.fort) end
    if tonumber(data.ref or 0) ~= 0 then resists[#resists + 1] = "Ref " .. tostring(data.ref) end
    if tonumber(data.von or 0) ~= 0 then resists[#resists + 1] = "Von " .. tostring(data.von) end
    if #resists > 0 then
        linhas[#linhas + 1] = "Resistencias: " .. table.concat(resists, ", ")
    end

    local ataques = pickTopEntries(data.ataques, 3, function(atk)
        local partes = {}
        if cleanText(atk.nome or "") ~= "" then partes[#partes + 1] = atk.nome end
        if cleanText(atk.quantidade or "") ~= "" then partes[#partes + 1] = atk.quantidade .. " ataque(s)" end
        if cleanText(atk.bonus or "") ~= "" then partes[#partes + 1] = "bonus " .. atk.bonus end
        if cleanText(atk.dano or "") ~= "" then partes[#partes + 1] = "dano " .. atk.dano end
        return table.concat(partes, ", ")
    end)

    if #ataques > 0 then
        linhas[#linhas + 1] = ""
        linhas[#linhas + 1] = "Prioridade ofensiva:"
        for _, atk in ipairs(ataques) do
            linhas[#linhas + 1] = "- " .. atk
        end
    end

    local habilidades = pickTopEntries(data.habilidades, 5, function(hab)
        local partes = {}
        if cleanText(hab.nome or "") ~= "" then partes[#partes + 1] = hab.nome end
        if cleanText(hab.custo or "") ~= "" then partes[#partes + 1] = "custo " .. hab.custo end
        if cleanText(hab.descricao or "") ~= "" then partes[#partes + 1] = hab.descricao end
        return table.concat(partes, " - ")
    end)

    if #habilidades > 0 then
        linhas[#linhas + 1] = ""
        linhas[#linhas + 1] = "Recursos e truques:"
        for _, hab in ipairs(habilidades) do
            linhas[#linhas + 1] = "- " .. hab
        end
    end

    local pericias = pickTopEntries(data.pericias, 4, function(p)
        return p
    end)

    if #pericias > 0 then
        linhas[#linhas + 1] = ""
        linhas[#linhas + 1] = "Fora do dano direto:"
        linhas[#linhas + 1] = "- Use as melhores pericias: " .. table.concat(pericias, ", ")
    end

    if cleanText(data.sentidos and table.concat(data.sentidos, ", ") or "") ~= "" then
        linhas[#linhas + 1] = "- Explore os sentidos especiais: " .. table.concat(data.sentidos, ", ")
    end

    if cleanText(data.resistencias and table.concat(data.resistencias, ", ") or "") ~= "" then
        linhas[#linhas + 1] = "- Leve em conta resistencias/imunidades: " .. table.concat(data.resistencias, ", ")
    end

    return table.concat(linhas, "\n")
end

------------------------------------------------------------
-- PARSE XML DA CRIATURA
------------------------------------------------------------

local function parseCriaturaXML(xml)
    xml = extractCriaturaXML(xml)

    local data = {}

    data.nome         = extractTag(xml, "nome")
    data.nd           = extractNumberTag(xml, "nd")
    data.tipo         = extractTag(xml, "tipo")
    data.tamanho      = extractTag(xml, "tamanho")
    data.descricao    = extractRawTag(xml, "descricao")

    data.mana         = extractNumberTag(xml, "mana")

    data.pv           = extractNumberTag(xml, "pv")
    data.ca           = extractNumberTag(xml, "ca")
    if data.ca == 0 then
        data.ca = extractNumberTag(xml, "defesa")
    end
    data.deslocamento = extractTag(xml, "deslocamento")
    data.iniciativa   = extractNumberTag(xml, "iniciativa")
    data.percepcao    = extractNumberTag(xml, "percepcao")
    data.imagemURL    = extractTag(xml, "imagemURL")
    if data.imagemURL == "" then data.imagemURL = extractTag(xml, "imagem") end
    data.originalSheet = extractRawTag(xml, "originalSheet")
    data.dadosAdicionais = extractRawTag(xml, "dadosAdicionais")
    data.saoNodeSourceJson = extractRawTag(xml, "saoNodeSourceJson")

    local atr = extractBlock(xml, "atributos") or ""
    data.atributos = {
        ["for"] = extractNumberTag(atr, "for"),
        ["des"] = extractNumberTag(atr, "des"),
        ["con"] = extractNumberTag(atr, "con"),
        ["int"] = extractNumberTag(atr, "int"),
        ["sab"] = extractNumberTag(atr, "sab"),
        ["car"] = extractNumberTag(atr, "car")
    }

    data.sentidos     = extractList(xml, "sentidos")
    data.pericias     = extractList(xml, "pericias")
    data.resistencias = extractList(xml, "resistencias")
    data.imunidades   = extractList(xml, "imunidades")

    --------------------------------------------------------
    -- DEFESAS: primeiro <defesas>, depois fallback em resistÃªncias
    --------------------------------------------------------
    local defBlock = extractBlock(xml, "defesas") or ""
    data.fort = extractNumberTag(defBlock, "fort")
    data.ref  = extractNumberTag(defBlock, "ref")
    data.von  = extractNumberTag(defBlock, "von")
    data.defesas = {
        fort = data.fort,
        ref = data.ref,
        von = data.von
    }

    for _, r in ipairs(data.resistencias) do
        local rlow = r:lower()
        local v = tonumber(r:match("([+-]?%d+)")) or 0

        if data.fort == 0 and rlow:find("fort") then data.fort = v end
        if data.ref  == 0 and rlow:find("ref")  then data.ref  = v end
        if data.von  == 0 and (rlow:find("von") or rlow:find("vont")) then
            data.von = v
        end
    end

    data.defesas.fort = data.fort
    data.defesas.ref = data.ref
    data.defesas.von = data.von

    --------------------------------------------------------
    -- Equipamentos (sempre array)
    --------------------------------------------------------
    data.equipamentos = extractList(xml, "equipamentos")

    if #data.equipamentos == 0 then
        local eqTexto = extractTag(xml, "equipamentos")
        if eqTexto ~= "" then
            for item in eqTexto:gmatch("([^;,]+)") do
                data.equipamentos[#data.equipamentos + 1] = cleanText(item)
            end
        end
    end

    if #data.equipamentos == 0 then
        data.equipamentos[1] = "nenhum"
    end

    --------------------------------------------------------
    -- Ataques
    --------------------------------------------------------
    data.ataques = {}
    local atkBlock = extractBlock(xml, "ataques")
    if atkBlock then
        for item in atkBlock:gmatch("<item>(.-)</item>") do
            local atk = {
                nome        = extractTag(item, "nome"),
                quantidade  = extractTag(item, "quantidade"),
                bonus       = extractTag(item, "bonus"),
                dano        = extractTag(item, "dano"),
                tipo        = extractTag(item, "tipo"),
                alcance     = extractTag(item, "alcance"),
                critico     = extractTag(item, "critico"),
                descricao   = extractRawTag(item, "descricao"),
                observacoes = extractRawTag(item, "observacoes")
            }

            if atk.quantidade == "" then
                atk.quantidade = inferAttackQuantidade(atk.nome, atk.descricao, atk.observacoes)
            end

            prepareAttackRollFields(atk)

            atk.texto = cleanText(table.concat({
                atk.nome,
                atk.quantidade ~= "" and ("x" .. atk.quantidade) or "",
                atk.bonus ~= "" and atk.bonus or "",
                atk.dano,
                atk.tipo,
                atk.alcance,
                atk.critico,
                atk.descricao,
                atk.observacoes
            }, " "))

            data.ataques[#data.ataques + 1] = atk
        end

        if #data.ataques == 0 then
            for _, itemText in ipairs(splitPlainList(flattenXMLText(atkBlock))) do
                data.ataques[#data.ataques + 1] = {
                    nome = itemText,
                    quantidade = inferAttackQuantidade(itemText, "", ""),
                    bonus = "",
                    dano = "",
                    tipo = "",
                    alcance = "",
                    critico = "",
                    descricao = "",
                    observacoes = "",
                    rolagemAtaque = "",
                    rolagensDano = "",
                    texto = itemText
                }
                prepareAttackRollFields(data.ataques[#data.ataques])
            end
        end
    end

    --------------------------------------------------------
    -- Habilidades
    --------------------------------------------------------
    data.habilidades = {}
    local habBlock = extractBlock(xml, "habilidades")
    if habBlock then
        for item in habBlock:gmatch("<item>(.-)</item>") do
            local hab = {
                nome        = extractTag(item, "nome"),
                descricao   = extractRawTag(item, "descricao"),
                tipo        = extractTag(item, "tipo"),
                custo       = extractTag(item, "custo"),
                recarga     = extractTag(item, "recarga"),
                gatilho     = extractTag(item, "gatilho"),
                observacoes = extractRawTag(item, "observacoes")
            }

            hab.texto = cleanText(table.concat({
                hab.nome,
                hab.tipo,
                hab.custo,
                hab.recarga,
                hab.gatilho,
                hab.descricao,
                hab.observacoes
            }, " "))

            data.habilidades[#data.habilidades + 1] = hab
        end

        if #data.habilidades == 0 then
            for _, itemText in ipairs(splitPlainList(flattenXMLText(habBlock))) do
                data.habilidades[#data.habilidades + 1] = {
                    nome = itemText,
                    descricao = "",
                    tipo = "",
                    custo = "",
                    recarga = "",
                    gatilho = "",
                    observacoes = "",
                    texto = itemText
                }
            end
        end
    end

    -- Magias não possuem uma área dedicada na ficha atual; preservamos cada
    -- campo integralmente no texto adicional e em dataIA para futuras views.
    data.magias = {}
    local magBlock = extractBlock(xml, "magias")
    if magBlock then
        for item in magBlock:gmatch("<item>(.-)</item>") do
            local magia = {
                nome = extractTag(item, "nome"), descricao = extractRawTag(item, "descricao"),
                custo = extractTag(item, "custo"), alcance = extractTag(item, "alcance"),
                alvo = extractTag(item, "alvo"), duracao = extractTag(item, "duracao"),
                observacoes = extractRawTag(item, "observacoes")
            }
            magia.texto = cleanText(table.concat({magia.nome, magia.descricao, magia.custo,
                magia.alcance, magia.alvo, magia.duracao, magia.observacoes}, " "))
            data.magias[#data.magias + 1] = magia
        end
    end

    return data
end

------------------------------------------------------------
-- dataIA no node (a partir de xmlCriatura)
------------------------------------------------------------

function rebuildDataIAFromXML(node)
    if node == nil then return nil end
    if node.xmlCriatura == nil or node.xmlCriatura == "" then
        return nil
    end

    local data = parseCriaturaXML(node.xmlCriatura)
    node.dataIA = data
    node.comoJogar = buildHowToPlayText(data)
    node[TOKEN_ATTACKS_FIELD] = encodeTokenAttacks(data.ataques or {})
    return data
end

------------------------------------------------------------
-- BOTÃ•ES DINÃ‚MICOS
------------------------------------------------------------

-- helper central: limpa e recria os botÃµes para o node atual
function rebuildButtonsFromNode(ficha, nodo)
    if not ficha then return end

    local data

    if nodo ~= nil then
        -- SEMPRE tenta reconstruir do XML salvo
        data = rebuildDataIAFromXML(nodo) or nodo.dataIA

        if type(data) ~= "table" then
            data = {pericias = {}, ataques = {}, habilidades = {}}
        end

        nodo.dataIA = data
    else
        data = {pericias = {}, ataques = {}, habilidades = {}}
    end

    rebuildDynamicButtons(ficha, nodo, data)
end

local function addActionRollColumns(parent, title, items, color, data, nodo, prefix, extraColumns)
    local maxItemsPerColumn = 6

    if #items == 0 then
        items = {}
    end

    extraColumns = extraColumns or {}

    if #items == 0 and #extraColumns == 0 then
        return
    end

    local row = GUI.newFlowLayout()
    row.align = "none"
    row.width = 900
    row.autoHeight = true
    row.maxControlsPerLine = 3
    row.minWidth = 270
    row.margins = {bottom = 8}
    row.parent = parent

    local columnCount = math.ceil(#items / maxItemsPerColumn)

    for columnIndex = 1, columnCount do
        local itemCount = math.min(maxItemsPerColumn, #items - ((columnIndex - 1) * maxItemsPerColumn))
        local column = GUI.newLayout()
        column.align = "none"
        column.vertAlign = "leading"
        column.width = 270
        column.height = 32 + (itemCount * 38)
        column.margins = {right = 8, bottom = 8}
        column.parent = row

        local header = GUI.newLabel()
        header.align = "top"
        header.height = 24
        header.text = title .. (columnCount > 1 and (" " .. tostring(columnIndex)) or "")
        header.fontColor = color
        header.fontStyle = "bold"
        header.parent = column

        local startIndex = ((columnIndex - 1) * maxItemsPerColumn) + 1
        local endIndex = math.min(startIndex + maxItemsPerColumn - 1, #items)

        for i = startIndex, endIndex do
            addRectangle(column, prefix .. items[i], data, nodo, {
                align = "top",
                fontColor = color,
                width = 260
            })
        end
    end

    for _, extra in ipairs(extraColumns) do
        local extraItems = extra.items or {}
        if #extraItems > 0 then
            local itemCount = #extraItems
            local column = GUI.newLayout()
            column.align = "none"
            column.vertAlign = "leading"
            column.width = 270
            column.height = 32 + (itemCount * 38)
            column.margins = {right = 8, bottom = 8}
            column.parent = row

            local header = GUI.newLabel()
            header.align = "top"
            header.height = 24
            header.text = extra.title or title
            header.fontColor = extra.color or color
            header.fontStyle = "bold"
            header.parent = column

            for _, item in ipairs(extraItems) do
                addRectangle(column, (extra.prefix or prefix) .. item, data, nodo, {
                    align = "top",
                    fontColor = extra.color or color,
                    width = 260
                })
            end
        end
    end
end

local function buildUntrainedAttributeSkills(data, nodo)
    data = data or {}
    local nd = tonumber((data and data.nd) or (nodo and nodo.nd) or 0) or 0
    local base = math.floor(nd / 2) + 2
    local attrs = {
        {"Pericia de Forca", (data.atributos and data.atributos["for"]) or (nodo and nodo.att_for)},
        {"Pericia de Destreza", (data.atributos and data.atributos["des"]) or (nodo and nodo.att_des)},
        {"Pericia de Constituicao", (data.atributos and data.atributos["con"]) or (nodo and nodo.att_con)},
        {"Pericia de Inteligencia", (data.atributos and data.atributos["int"]) or (nodo and nodo.att_int)},
        {"Pericia de Sabedoria", (data.atributos and data.atributos["sab"]) or (nodo and nodo.att_sab)},
        {"Pericia de Carisma", (data.atributos and data.atributos["car"]) or (nodo and nodo.att_car)}
    }
    local skills = {}

    for _, attr in ipairs(attrs) do
        local valor = tonumber(attr[2]) or 0
        local total = valor + base
        local sinal = total >= 0 and "+" or ""
        skills[#skills + 1] = attr[1] .. " " .. sinal .. tostring(total)
    end

    return skills
end

function rebuildDynamicButtons(ficha, nodo, data)
    local flw = GUI.findControlByName("flwDin", ficha)
    if not flw then return end

    flw.maxControlsPerLine = 1

    for _, c in ipairs(flw:getChildren()) do
        c:destroy()
    end

    local pericias = {}
    for _, p in ipairs(data.pericias or {}) do
        pericias[#pericias + 1] = p
    end

    local periciasAtributo = buildUntrainedAttributeSkills(data, nodo)

    local ataques = {}
    for _, atk in ipairs(data.ataques or {}) do
        ataques[#ataques + 1] = atk.nome or ""
    end

    local habilidades = {}
    for _, hab in ipairs(data.habilidades or {}) do
        habilidades[#habilidades + 1] = hab.nome or ""
    end

    addActionRollColumns(flw, "Pericias", pericias, "#56CCF2", data, nodo, "Pericia: ", {
        {title = "Pericias de atributo", items = periciasAtributo, prefix = "Pericia: ", color = "#93C5FD"}
    })
    addActionRollColumns(flw, "Ataques", ataques, "#EB5757", data, nodo, "Atk: ")
    addActionRollColumns(flw, "Habilidades", habilidades, "#BB6BD9", data, nodo, "Hab: ")

    flw:needRepaint()
end

------------------------------------------------------------
-- PREENCHER FICHA
------------------------------------------------------------

local function preencherFicha(ficha, nodo, data)
    if not nodo or not data then return end

    nodo.nome         = data.nome or ""
    nodo.nd           = data.nd or 0
    nodo.tipo         = data.tipo or ""
    nodo.tamanho      = data.tamanho or ""
    nodo.descricao    = data.descricao or ""
    nodo.deslocamento = data.deslocamento or ""
    nodo.iniciativa   = data.iniciativa or 0
    nodo.percepcao    = data.percepcao or 0

    nodo.mana = data.mana or 0

    nodo.pv  = data.pv or 0
    nodo.ca  = data.ca or 0

    nodo.att_for = data.atributos["for"] or 0
    nodo.att_des = data.atributos["des"] or 0
    nodo.att_con = data.atributos["con"] or 0
    nodo.att_int = data.atributos["int"] or 0
    nodo.att_sab = data.atributos["sab"] or 0
    nodo.att_car = data.atributos["car"] or 0

    nodo.res_fort = data.fort or 0
    nodo.res_ref  = data.ref  or 0
    nodo.res_von  = data.von  or 0

    nodo.equipamentos = table.concat(data.equipamentos or {}, ", ")
    nodo.sentidos = table.concat(data.sentidos or {}, ", ")
    nodo.pericias_texto = table.concat(data.pericias or {}, ", ")
    nodo.resistencias_texto = table.concat(data.resistencias or {}, ", ")
    nodo.imunidades_texto = table.concat(data.imunidades or {}, ", ")
    nodo.magias_texto = table.concat((function()
        local lista = {}
        for _, magia in ipairs(data.magias or {}) do lista[#lista + 1] = magia.texto or magia.nome or "" end
        return lista
    end)(), " | ")
    nodo.ataques_texto = table.concat((function()
        local lista = {}
        for _, atk in ipairs(data.ataques or {}) do
            lista[#lista + 1] = atk.texto or atk.nome or ""
        end
        return lista
    end)(), " | ")
    nodo.habilidades_texto = table.concat((function()
        local lista = {}
        for _, hab in ipairs(data.habilidades or {}) do
            lista[#lista + 1] = hab.texto or hab.nome or ""
        end
        return lista
    end)(), " | ")
    -- Campos sem equivalente no template continuam acessíveis e exportáveis.
    nodo.originalSheet = data.originalSheet or ""
    nodo.dadosAdicionais = data.dadosAdicionais or ""
    nodo.saoNodeSourceJson = data.saoNodeSourceJson or ""
    if data.imagemURL and data.imagemURL ~= "" then nodo.imagemURL = data.imagemURL end
    nodo[TOKEN_ATTACKS_FIELD] = encodeTokenAttacks(data.ataques or {})
    nodo.comoJogar = buildHowToPlayText(data)

    nodo.dataIA = data

    -- recria botÃµes sempre a partir do node
    rebuildButtonsFromNode(ficha, nodo)
end

------------------------------------------------------------
-- APLICAR XML NA FICHA (compartilhado entre Gemini e SAO-NODE)
------------------------------------------------------------

local function aplicarXMLNaFicha(ficha, nodo, xml)
    local erro = extractErroXML(xml)
    if erro ~= "" then
        return false, erro
    end

    nodo.xmlCriatura = xml
    local data = parseCriaturaXML(xml)

    if not data or (data.nome or "") == "" then
        return false, nil
    end

    preencherFicha(ficha, nodo, data)
    return true
end

------------------------------------------------------------
-- CHAMAR IA
------------------------------------------------------------

local function chamarOpenAI(ficha, nodo, texto)
    if not nodo then
        showMessage("Nao encontrei a ficha selecionada para preencher.")
        return
    end

    if not texto or texto == "" then
        showMessage("Cole o texto da criatura no campo 'Texto para IA'.")
        return
    end

    local body = json.encode({ prompt = texto })

    httpPOST(
        GEMINI_PROXY_URL,
        body,
        function(xml)
            aplicarXMLNaFichaComConfirmacao(ficha, nodo, xml, function(ok, erro)
                if not ok then
                    if erro then
                        showMessage(mensagemAmigavelGemini(erro, 200, xml))
                    else
                        showMessage("A IA respondeu, mas nao consegui montar uma ficha valida. Tente novamente ou ajuste o texto da criatura.")
                    end
                end
            end)
        end,
        function(err, status, responseText)
            showMessage(mensagemAmigavelGemini(err, status, responseText))
        end
    )
end

------------------------------------------------------------
-- FunÃ§Ã£o pÃºblica usada pelo formulÃ¡rio
------------------------------------------------------------

function askAndCallIA(ficha, nodo)
    local txt = nodo and nodo.textoBrutoIA or ""
    chamarOpenAI(ficha, nodo, txt)
end

------------------------------------------------------------
-- BUSCAR MONSTRO JA CADASTRADO NO SAO-NODE
------------------------------------------------------------

local function buscarDoSaoNode(ficha, nodo, campaignId, monsterId)
    if not nodo then
        showMessage("Nao encontrei a ficha selecionada para preencher.")
        return
    end

    if not campaignId or campaignId == "" or not monsterId or monsterId == "" then
        showMessage("Informe a campanha e o ID do monstro no SAO-NODE antes de buscar a ficha.")
        return
    end

    local url = SAO_NODE_PROXY_URL
        .. "?campaignId=" .. urlEncode(campaignId)
        .. "&monsterId=" .. urlEncode(monsterId)

    httpGET(
        url,
        function(xml)
            aplicarXMLNaFichaComConfirmacao(ficha, nodo, xml, function(ok, erro)
                if not ok then
                    if erro then
                        showMessage(mensagemAmigavelSaoNode(erro, 200, xml))
                    else
                        showMessage("O SAO-NODE respondeu, mas nao consegui montar uma ficha valida para esse monstro.")
                    end
                end
            end)
        end,
        function(err, status, responseText)
            showMessage(mensagemAmigavelSaoNode(err, status, responseText))
        end
    )
end

------------------------------------------------------------
-- FunÃ§Ã£o pÃºblica usada pelo formulÃ¡rio
------------------------------------------------------------

function askSaoNodeAndFill(ficha, nodo)
    local campaignId = nodo and nodo.saoNodeCampaignId or ""
    local monsterId = nodo and nodo.saoNodeMonsterId or ""
    buscarDoSaoNode(ficha, nodo, campaignId, monsterId)
end

------------------------------------------------------------
-- PONTE AUTENTICADA SAO-NODE -> FIRECAST
------------------------------------------------------------

local function bridgeNewConsumerId()
    math.randomseed(os.time())
    return string.format("firecast-%d-%d-%d", os.time(), math.random(100000, 999999), math.random(100000, 999999))
end

local function bridgeTokenReady(ficha, callback)
    if SAO_NODE_BRIDGE_TOKEN ~= nil and SAO_NODE_BRIDGE_TOKEN ~= "" then
        callback(SAO_NODE_BRIDGE_TOKEN)
        return
    end
    if saoNodeBridgePrompting then return end
    saoNodeBridgePrompting = true
    dialogs.inputQuery("Conectar ao SAO-NODE", "Token da ponte Firecast (fica somente nesta sessão):", "", function(value)
        saoNodeBridgePrompting = false
        if value and value ~= "" then
            SAO_NODE_BRIDGE_TOKEN = tostring(value)
            callback(SAO_NODE_BRIDGE_TOKEN)
        else
            showMessage("Informe o token da ponte para receber transferências do SAO-NODE.")
        end
    end, function()
        saoNodeBridgePrompting = false
    end, false)
end

local function bridgeAck(transferId, status, message)
    if not transferId or transferId == "" or not saoNodeConsumerId then return end
    local body = json.encode({consumerId = saoNodeConsumerId, status = status, message = message or ""})
    httpPOSTAuthenticated(SAO_NODE_BRIDGE_URL .. "/sao-node/transfers/" .. urlEncode(transferId) .. "/ack", body,
        SAO_NODE_BRIDGE_TOKEN, function() end, function() end)
end

local function nodeHasMeaningfulData(node)
    if type(node) ~= "table" then return false end
    return cleanText(node.nome or "") ~= ""
        or tonumber(node.pv or 0) ~= 0
        or tonumber(node.ca or 0) ~= 0
        or cleanText(node.descricao or "") ~= ""
        or cleanText(node.xmlCriatura or "") ~= ""
        or cleanText(node.originalSheet or "") ~= ""
        or cleanText(node.dadosAdicionais or "") ~= ""
        or cleanText(node.imagemURL or "") ~= ""
end

aplicarXMLNaFichaComConfirmacao = function(ficha, nodo, xml, onDone)
    local function finish()
        if ficha and ficha.rclMonstros and ficha.rclMonstros.selectedNode ~= nodo then
            if onDone then onDone(false, "a ficha selecionada mudou durante a confirmação") end
            return
        end
        local ok, erro = aplicarXMLNaFicha(ficha, nodo, xml)
        if onDone then onDone(ok, erro) end
    end
    if nodeHasMeaningfulData(nodo) then
        dialogs.confirmYesNo("A ficha selecionada já está preenchida. Substituir os dados atuais?", function(confirmed)
            if confirmed then finish() elseif onDone then onDone(false, "substituição cancelada") end
        end)
    else
        finish()
    end
end

local function bridgeCanWrite(ficha)
    local mesa = nil
    pcall(function() mesa = Firecast.getMesaDe(ficha) end)
    if mesa == nil or mesa.me == nil then return true end
    -- Em mesas reais somente o mestre pode consumir e substituir fichas.
    if mesa.me.isMestre ~= nil then return mesa.me.isMestre == true end
    if mesa.me.isMaster ~= nil then return mesa.me.isMaster == true end
    return true
end

local function applyBridgeTransfer(ficha, transfer)
    local transferId = tostring(transfer.transferId or transfer.id or "")
    local xml = transfer.xml or transfer.xmlCriatura or ""
    if transferId == "" or xml == "" then
        bridgeAck(transferId, "failed", "transferência sem XML ou identificador")
        return
    end
    if saoNodeSeenTransfers[transferId] then return end
    local node = ficha and ficha.rclMonstros and ficha.rclMonstros.selectedNode
    if node == nil then
        -- Não confirme ainda: a fila mantém um lease e tentará novamente
        -- quando o mestre selecionar uma ficha.
        return
    end
    saoNodeSeenTransfers[transferId] = true
    local function doApply()
        if not ficha.rclMonstros or ficha.rclMonstros.selectedNode ~= node then
            bridgeAck(transferId, "rejected", "a ficha selecionada mudou durante a confirmação")
            return
        end
        local ok, erro = aplicarXMLNaFicha(ficha, node, xml)
        if ok then
            node.saoNodeTransferId = transferId
            bridgeAck(transferId, "applied", "Ficha aplicada no MonsterIA")
        else
            bridgeAck(transferId, "failed", tostring(erro or "XML inválido"))
            showMessage("Não consegui aplicar o monstro recebido do SAO-NODE.")
        end
    end
    if nodeHasMeaningfulData(node) then
        dialogs.confirmYesNo("A ficha selecionada já está preenchida. Substituir pelos dados recebidos do SAO-NODE?", function(confirmed)
            if confirmed then doApply() else bridgeAck(transferId, "rejected", "substituição cancelada pelo mestre") end
        end)
    else
        doApply()
    end
end

local function pollSaoNodeBridge(ficha)
    bridgeTokenReady(ficha, function(token)
        if not saoNodeConsumerId then saoNodeConsumerId = bridgeNewConsumerId() end
        local heartbeatBody = json.encode({consumerId = saoNodeConsumerId})
        httpPOSTAuthenticated(SAO_NODE_BRIDGE_URL .. "/sao-node/consumer/heartbeat", heartbeatBody, token,
            function()
                local url = SAO_NODE_BRIDGE_URL .. "/sao-node/transfers/next?consumerId=" .. urlEncode(saoNodeConsumerId)
                httpGETAuthenticated(url, token, function(body)
                    local ok, payload = pcall(function() return json.decode(body or "") end)
                    if ok and type(payload) == "table" then
                        local transfer = payload.transfer or payload
                        if type(transfer) == "table" and (transfer.transferId or transfer.id) then
                            applyBridgeTransfer(ficha, transfer)
                        end
                    end
                end, function(err, status)
                    if status and status ~= 404 and status ~= 204 then
                        -- O polling é silencioso; erros explícitos aparecem apenas no botão manual.
                    end
                end)
            end, function() end)
    end)
end

function iniciarRecepcaoSaoNode(ficha)
    if not bridgeCanWrite(ficha) then
        showMessage("Somente o mestre pode receber monstros do SAO-NODE.")
        return
    end
    if saoNodeBridgePolling then return end
    saoNodeBridgePolling = true
    pollSaoNodeBridge(ficha)
    saoNodeBridgeTimer = setInterval(function() pollSaoNodeBridge(ficha) end, 3000)
end

function receberDoSaoNode(ficha)
    if not bridgeCanWrite(ficha) then
        showMessage("Somente o mestre pode receber monstros do SAO-NODE.")
        return
    end
    pollSaoNodeBridge(ficha)
end

------------------------------------------------------------
-- BOTÃ•ES (AÃ‡Ã•ES / ROLAGENS)
------------------------------------------------------------

local activeDetailPopup = nil

local function closeActiveDetailPopup()
    if activeDetailPopup ~= nil then
        activeDetailPopup:close()
        activeDetailPopup = nil
    end
end

local function limparPrefixoBotao(texto)
    return cleanText((texto or ""):gsub("^[^:]+:%s*", ""))
end

local function buildDetailText(texto, data)
    local nomeLimp = limparPrefixoBotao(texto)

    if texto:match("^Per") then
        return "Pericia", nomeLimp
    end

    if texto:match("^Atk:") then
        for _, atk in ipairs(data.ataques or {}) do
            if normalize(atk.nome) == normalize(nomeLimp) then
                local linhas = {}

                if atk.nome ~= "" then linhas[#linhas + 1] = "Nome: " .. atk.nome end
                if atk.quantidade ~= "" then linhas[#linhas + 1] = "Ataques: " .. atk.quantidade end
                if atk.bonus ~= "" then linhas[#linhas + 1] = "Bonus: " .. atk.bonus end
                if atk.dano ~= "" then linhas[#linhas + 1] = "Dano: " .. atk.dano end
                if atk.tipo ~= "" then linhas[#linhas + 1] = "Tipo: " .. atk.tipo end
                if atk.alcance ~= "" then linhas[#linhas + 1] = "Alcance: " .. atk.alcance end
                if atk.critico ~= "" then linhas[#linhas + 1] = "Critico: " .. atk.critico end
                if atk.descricao ~= "" then linhas[#linhas + 1] = "Descricao: " .. atk.descricao end
                if atk.observacoes ~= "" then linhas[#linhas + 1] = "Observacoes: " .. atk.observacoes end

                return "Ataque", table.concat(linhas, "\n")
            end
        end

        return "Ataque", nomeLimp
    end

    if texto:match("^Hab:") then
        for _, hab in ipairs(data.habilidades or {}) do
            if normalize(hab.nome) == normalize(nomeLimp) then
                local linhas = {}

                if hab.nome ~= "" then linhas[#linhas + 1] = "Nome: " .. hab.nome end
                if hab.tipo ~= "" then linhas[#linhas + 1] = "Tipo: " .. hab.tipo end
                if hab.custo ~= "" then linhas[#linhas + 1] = "Custo: " .. hab.custo end
                if hab.recarga ~= "" then linhas[#linhas + 1] = "Recarga: " .. hab.recarga end
                if hab.gatilho ~= "" then linhas[#linhas + 1] = "Gatilho: " .. hab.gatilho end
                if hab.descricao ~= "" then linhas[#linhas + 1] = "Descricao: " .. hab.descricao end
                if hab.observacoes ~= "" then linhas[#linhas + 1] = "Observacoes: " .. hab.observacoes end

                return "Habilidade", table.concat(linhas, "\n")
            end
        end

        return "Habilidade", nomeLimp
    end

    if texto:match("^Mag:") then
        for _, magia in ipairs(data.magias or {}) do
            if normalize(magia.nome) == normalize(nomeLimp) then
                local linhas = {}

                if magia.nome ~= "" then linhas[#linhas + 1] = "Nome: " .. magia.nome end
                if magia.custo ~= "" then linhas[#linhas + 1] = "Custo: " .. magia.custo end
                if magia.alcance ~= "" then linhas[#linhas + 1] = "Alcance: " .. magia.alcance end
                if magia.alvo ~= "" then linhas[#linhas + 1] = "Alvo: " .. magia.alvo end
                if magia.duracao ~= "" then linhas[#linhas + 1] = "Duracao: " .. magia.duracao end
                if magia.descricao ~= "" then linhas[#linhas + 1] = "Descricao: " .. magia.descricao end

                return "Magia", table.concat(linhas, "\n")
            end
        end

        return "Magia", nomeLimp
    end

    return "Detalhes", nomeLimp
end

local function showDetailPopup(control, texto, data)
    local titulo, conteudo = buildDetailText(texto, data)

    if cleanText(conteudo or "") == "" then
        return
    end

    closeActiveDetailPopup()

    local popup = GUI.newPopupForm()
    popup.width = 420
    local lineCount = 1
    for _ in tostring(conteudo):gmatch("\n") do
        lineCount = lineCount + 1
    end
    popup.height = math.min(520, math.max(180, 92 + (lineCount * 18)))
    popup.theme = "dark"
    popup.cancelable = true
    popup.drawContainer = true
    popup.resizable = false
    popup.movable = false

    local layout = GUI.newLayout()
    layout.align = "client"
    layout.padding = {left = 12, right = 12, top = 12, bottom = 12}
    layout.parent = popup

    local lblTitulo = GUI.newLabel()
    lblTitulo.align = "top"
    lblTitulo.height = 24
    lblTitulo.text = titulo
    lblTitulo.fontSize = 16
    lblTitulo.fontStyle = "bold"
    lblTitulo.parent = layout

    local txtConteudo = GUI.newTextEditor()
    txtConteudo.align = "client"
    txtConteudo.readOnly = true
    txtConteudo.text = conteudo
    txtConteudo.parent = layout

    popup.onClose = function()
        if activeDetailPopup == popup then
            activeDetailPopup = nil
        end

        popup:destroy()
    end

    activeDetailPopup = popup
    GUI.showPopup(popup, {placement = "mouse"})
end

local function rollAttackFromData(chat, nodo, atk, contexto, npcInfo)
    if chat == nil or type(atk) ~= "table" then
        return false
    end

    atk = prepareAttackRollFields(atk)

    local rolagemAtaque = cleanText(atk.rolagemAtaque or "")
    if rolagemAtaque == "" then
        rolagemAtaque = buildAttackRoll(atk.bonus)
    end

    exibirAtaqueLocal(chat, nodo, atk.nome or "", rolagemAtaque, contexto, npcInfo)

    local danos = decodeDamageRolls(atk.rolagensDano or "")

    if #danos == 0 then
        danos = extractDamageRolls(atk.dano or "")
    end

    if #danos == 0 and cleanText(atk.dano or "") ~= "" then
        exibirDanoLocal(chat, nodo, atk.nome or "", atk.dano or "", contexto, npcInfo)
    else
        for _, roll in ipairs(danos) do
            exibirDanoLocal(chat, nodo, atk.nome or "", roll, contexto, npcInfo)
        end
    end

    return true
end

function addRectangle(flw, texto, data, nodo, opts)
    opts = opts or {}

    local rectangle = GUI.newButton()
    rectangle.align = opts.align or "none"
    rectangle.width = opts.width or 260
    rectangle.height = 30
    rectangle.text = texto
    rectangle.fontColor = opts.fontColor or "white"
    rectangle.horzTextAlign = "leading"
    rectangle.textTrimming = "character"
    rectangle.canFocus = false
    rectangle.margins = {top = 4, bottom = 4, right = 4}
    rectangle.parent = flw

    local nomeLimp = limparPrefixoBotao(texto)

    rectangle:addEventListener("onMenu", function(_, _, event)
        showDetailPopup(rectangle, texto, data)

        if type(event) == "table" then
            event.handled = true
        end
    end)

    rectangle.onClick = function()
        local mesa = Firecast.getMesaDe(rectangle)
        if not mesa or not mesa.activeChat then
            showMessage("Chat nÃ£o encontrado.")
            return
        end

        local chat = mesa.activeChat

        ----------------------------------------------------
        -- PERÃCIA
        ----------------------------------------------------
        if texto:match("^Pericia:") or texto:match("^PerÃ­cia:") then
            local num = tonumber(nomeLimp:match("([+-]?%d+)$")) or 0
            local nomePericia = cleanText(nomeLimp:gsub("%s*[+-]?%d+%s*$", ""))
            rolarExpressaoComoNpc(chat, nodo, "Pericia: " .. nomePericia, "1d20+" .. num, rectangle, {
                name = data.nome or (nodo and nodo.nome),
                avatar = nodo and nodo.imagemURL
            })
            return
        end

        ----------------------------------------------------
        -- ATAQUE
        ----------------------------------------------------
        if texto:match("^Atk:") then
            for _, atk in ipairs(data.ataques or {}) do
                if normalize(atk.nome) == normalize(nomeLimp) then
                    do
                        rollAttackFromData(chat, nodo, atk, rectangle, {
                            name = data.nome or (nodo and nodo.nome),
                            avatar = nodo and nodo.imagemURL
                        })
                        return
                    end

                    local bonus = tonumber(atk.bonus) or 0
                    exibirAtaqueLocal(chat, nodo, "[Â§K4]" .. atk.nome .. "[Â§K1]" or "", "1d20+" .. bonus, rectangle, {
                        name = data.nome or (nodo and nodo.nome),
                        avatar = nodo and nodo.imagemURL
                    })

                    local danos = {}
                    for d in (atk.dano or ""):gmatch("(%d+d%d+[%+%-]?%d*)") do
                        danos[#danos + 1] = d
                    end

                    if #danos == 0 then
                        exibirDanoLocal(chat, nodo, atk.nome or "", atk.dano or "", rectangle, {
                            name = data.nome or (nodo and nodo.nome),
                            avatar = nodo and nodo.imagemURL
                        })
                    else
                        for _, roll in ipairs(danos) do
                            exibirDanoLocal(chat, nodo, atk.nome or "", roll, rectangle, {
                                name = data.nome or (nodo and nodo.nome),
                                avatar = nodo and nodo.imagemURL
                            })
                        end
                    end

                    return
                end
            end

            showMessage("Ataque nÃ£o encontrado.")
            return
        end

        ----------------------------------------------------
        -- HABILIDADE
        ----------------------------------------------------
        if texto:match("^Hab:") then
            for _, hab in ipairs(data.habilidades or {}) do
                if normalize(hab.nome) == normalize(nomeLimp) then
                    chat:enviarMensagem(
                        string.format("[Â§K2]Habilidade: %s[Â§K1][Â§B]\n%s",
                                      hab.nome or "", hab.descricao or ""))
                    return
                end
            end

            chat:enviarMensagem("Habilidade: " .. nomeLimp)
        end
    end

    flw:needRepaint();

    return rectangle
end

------------------------------------------------------------
-- MENU DE ATAQUES NO TOKEN
------------------------------------------------------------

local activeTokenAttackPopup = nil
local activeTokenAttackScene = nil
local activeTokenAttackTokenId = nil

local function closeActiveTokenAttackPopup()
    local popup = activeTokenAttackPopup
    local scene = activeTokenAttackScene

    activeTokenAttackPopup = nil
    activeTokenAttackScene = nil
    activeTokenAttackTokenId = nil

    if popup ~= nil then
        local closed = false

        if scene ~= nil and scene.viewport ~= nil and scene.viewport.closeForm ~= nil then
            closed = pcall(function()
                scene.viewport:closeForm(popup)
            end)
        end

        if not closed then
            pcall(function()
                popup:close()
            end)
        end

        pcall(function()
            popup:destroy()
        end)
    end
end

local function resolveMesaChatFromSceneToken(scene, token)
    local mesa = nil

    if token ~= nil then
        mesa = Firecast.getMesaDe(token)
    end

    if mesa == nil and scene ~= nil then
        mesa = Firecast.getMesaDe(scene)
    end

    if mesa ~= nil then
        return mesa.activeChat
    end

    return nil
end

local function formatTokenAttackButtonText(atk)
    local partes = {cleanText(atk.nome or "")}
    local bonus = cleanText(atk.bonus or "")
    local dano = cleanText(atk.dano or "")

    if bonus ~= "" then
        partes[#partes + 1] = bonus
    end

    if dano ~= "" then
        partes[#partes + 1] = "(" .. dano .. ")"
    end

    return table.concat(partes, " ")
end

local function readTokenMenuCategories(token)
    local userData = safeTokenUserData(token)

    if userData == nil then
        return {}
    end

    return readTokenMenuCategoriesFromUserData(userData)
end

local function formatTokenMenuItemText(categoryKey, item)
    if categoryKey == "ataques" then
        return formatTokenAttackButtonText(item)
    end

    local nome = cleanText(item.nome or "")
    local texto = cleanText(item.texto or "")

    if texto ~= "" and texto ~= nome and #texto <= 90 then
        return texto
    end

    return nome ~= "" and nome or texto
end

local function sendTokenInfoToChat(chat, token, item, npcInfo)
    local titulo = cleanText(item.nome or "")
    local texto = cleanText(item.texto or item.descricao or item.observacoes or "")

    if titulo == "" then
        titulo = "Informacao"
    end

    if texto ~= "" and texto ~= titulo then
        enviarLinhaComoNpc(chat, nil, titulo .. "\n" .. texto, nil, token, npcInfo)
    else
        enviarLinhaComoNpc(chat, nil, titulo, nil, token, npcInfo)
    end
end

local function executeTokenMenuItem(categoryKey, item, chat, token, npcInfo)
    if categoryKey == "ataques" then
        rollAttackFromData(chat, nil, item, token, npcInfo)
        return
    end

    local rolagem = cleanText(item.rolagem or "")

    if rolagem ~= "" then
        rolarExpressaoComoNpc(chat, nil, item.nome or "Rolagem", rolagem, token, npcInfo)
        return
    end

    sendTokenInfoToChat(chat, token, item, npcInfo)
end

local function createTokenMenuSection(parent, categoryKey, title, items, scene, token, npcInfo, expandedStates, rerender)
    if #items == 0 then
        return
    end

    local headerColor = "#FFFFFF"
    local itemColor = "#E5E7EB"

    for _, def in ipairs(TOKEN_MENU_CATEGORIES) do
        if def.key == categoryKey then
            headerColor = def.color or headerColor
            itemColor = def.itemColor or itemColor
            break
        end
    end

    local expanded = expandedStates[categoryKey] == true

    if expanded then
        for i = #items, 1, -1 do
            local item = items[i]
            local btn = GUI.newButton()
            btn.align = "top"
            btn.height = 30
            btn.margins = {top = 3, left = 8}
            btn.text = formatTokenMenuItemText(categoryKey, item)
            btn.fontColor = itemColor
            btn.horzTextAlign = "leading"
            btn.textTrimming = "character"
            btn.parent = parent

            btn.onClick = function()
                local chat = resolveMesaChatFromSceneToken(scene, token)

                if chat == nil then
                    showMessage("Chat nao encontrado.")
                    return
                end

                executeTokenMenuItem(categoryKey, item, chat, token, npcInfo)
            end
        end
    end

    local header = GUI.newButton()
    header.align = "top"
    header.height = 30
    header.margins = {top = 4}
    header.text = (expanded and "- " or "+ ") .. title .. " (" .. tostring(#items) .. ")"
    header.fontColor = headerColor
    header.fontStyle = "bold"
    header.horzTextAlign = "leading"
    header.parent = parent

    header.onClick = function()
        expandedStates[categoryKey] = not expandedStates[categoryKey]

        if rerender ~= nil then
            rerender()
        end
    end
end

showTokenAttackPopup = function(scene, token)
    if scene == nil or token == nil or not token.isObjectAlive then
        closeActiveTokenAttackPopup()
        return
    end

    local categories = readTokenMenuCategories(token)
    local ataques = readTokenAttacks(token)

    if next(categories) == nil and #ataques > 0 then
        categories.ataques = ataques
    end

    if next(categories) == nil then
        closeActiveTokenAttackPopup()
        return
    end

    closeActiveTokenAttackPopup()

    local popup = GUI.newPopupForm()
    popup.width = 360
    popup.height = 420
    popup.theme = "dark"
    popup.cancelable = true
    popup.drawContainer = true
    popup.resizable = false
    popup.movable = false

    local layout = GUI.newLayout()
    layout.align = "client"
    layout.padding = {left = 8, right = 8, top = 8, bottom = 8}
    layout.parent = popup

    local titulo = GUI.newLabel()
    titulo.align = "top"
    titulo.height = 22
    titulo.text = "Menu do token"
    titulo.fontSize = 13
    titulo.fontStyle = "bold"
    titulo.fontColor = "#FFFFFF"
    titulo.parent = layout

    local lista = GUI.newScrollBox()
    lista.align = "client"
    lista.parent = layout

    local npcInfo = getTokenNpcInfo(token)

    local expandedStates = {}
    local renderMenu = nil

    renderMenu = function()
        local children = {}

        for _, child in ipairs(lista:getChildren()) do
            children[#children + 1] = child
        end

        for _, child in ipairs(children) do
            child:destroy()
        end

        for i = #TOKEN_MENU_CATEGORIES, 1, -1 do
            local def = TOKEN_MENU_CATEGORIES[i]
            local items = categories[def.key] or {}

            createTokenMenuSection(lista, def.key, def.title, items, scene, token, npcInfo, expandedStates, renderMenu)
        end

        lista:needRepaint()
    end

    renderMenu()

    activeTokenAttackPopup = popup
    activeTokenAttackScene = scene
    activeTokenAttackTokenId = token.objectID

    local function onClosed()
        if activeTokenAttackPopup == popup then
            activeTokenAttackPopup = nil
            activeTokenAttackScene = nil
            activeTokenAttackTokenId = nil
        end

        pcall(function()
            popup:destroy()
        end)
    end

    local shown = false
    if scene.viewport ~= nil and scene.viewport.showForm ~= nil then
        shown = pcall(function()
            scene.viewport:showForm(popup, {placement = "mouse", onClose = onClosed})
        end)
    end

    if not shown then
        GUI.showPopup(popup, {placement = "mouse", onClose = onClosed})
    end

    setTimeout(function()
        if activeTokenAttackPopup == popup then
            renderMenu()
        end
    end, 1)
end

local function tokenFromSelection(scene, item)
    if item ~= nil and item.isObjectAlive and item.isType ~= nil and item:isType("token") then
        return item
    end

    local items = scene and scene.items or nil
    local selection = items and items.selection or nil

    for _, selected in ipairs(selection or {}) do
        if selected ~= nil and selected.isObjectAlive and selected.isType ~= nil and selected:isType("token") then
            return selected
        end
    end

    return nil
end

local function registerTokenAttackPopupPlugin()
    if MonsterIATokenAttackPluginHandle ~= nil then
        pcall(function()
            SceneLib.unregisterPlugin(MonsterIATokenAttackPluginHandle)
        end)
        MonsterIATokenAttackPluginHandle = nil
    end

    MonsterIATokenAttackPluginHandle = SceneLib.registerPlugin(function(scene)
        local items = scene and scene.items or nil

        if items == nil then
            return
        end

        items:addEventListener("OnItemSelected", function(item)
            setTimeout(function()
                local token = tokenFromSelection(scene, item)

                if token ~= nil and token.isObjectAlive and token.selected then
                    showTokenAttackPopup(scene, token)
                end
            end, 1)
        end)

        items:addEventListener("OnItemDeselected", function(item)
            if item == nil then
                closeActiveTokenAttackPopup()
            elseif activeTokenAttackTokenId ~= nil and item.objectID == activeTokenAttackTokenId then
                closeActiveTokenAttackPopup()
            end
        end)
    end)
end

registerTokenAttackPopupPlugin()

