local ndb = require("ndb")
local dialogs = require("dialogs")
local internet = require("internet")
local json = require("json")
local GUI = require("gui")
local Firecast = require("firecast")

GEMINI_PROXY_URL = GEMINI_PROXY_URL or "http://localhost:3000/gemini"

------------------------------------------------------------
-- DEBUG OPCIONAL
------------------------------------------------------------
local function dbg(label, value)
    -- showMessage(tostring(label) .. " = " .. tostring(value))
end

------------------------------------------------------------
-- HTTP POST usando internet.newHTTPRequest
------------------------------------------------------------
local function httpPOST(url, jsonStr, success, fail)
    local req = internet.newHTTPRequest("POST", url)

    if req == nil then
        showMessage("[HTTP] newHTTPRequest retornou NIL")
        if fail then fail("newHTTPRequest nil") end
        return
    end

    req.onResponse = function()
        local status = req.status or 0

        if status ~= 200 then
            if fail then fail("HTTP " .. tostring(status)) end
            return
        end

        if success then success(req.responseText) end
    end

    req.onError = function(err)
        showMessage("[HTTP] onError: " .. tostring(err))
        if fail then fail(err) end
    end

    req:setRequestHeader("Content-Type", "application/json; charset=utf-8")
    req:send(jsonStr)
end

------------------------------------------------------------
-- FUNÇÕES DE PARSE XML
------------------------------------------------------------

local function extractTag(xml, tag)
    if not xml then return "" end
    local pattern = "<" .. tag .. ">%s*(.-)%s*</" .. tag .. ">"
    local v = xml:match(pattern)
    if not v then return "" end
    v = v:gsub("\r", " "):gsub("\n", " ")
    v = v:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return v
end

local function extractBlock(xml, tag)
    if not xml then return nil end
    local pattern = "<" .. tag .. ">(.-)</" .. tag .. ">"
    return xml:match(pattern)
end

local function extractList(xml, tag)
    local res = {}
    local block = extractBlock(xml, tag)
    if not block then return res end

    for itemText in block:gmatch("<item>%s*(.-)%s*</item>") do
        itemText = itemText:gsub("\r", " "):gsub("\n", " ")
        itemText = itemText:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        table.insert(res, itemText)
    end

    return res
end

local function extractNumberTag(xml, tag)
    local txt = extractTag(xml, tag)
    if not txt or txt == "" then return 0 end
    local num = txt:match("(-?%d+)")
    return tonumber(num) or 0
end

------------------------------------------------------------
-- PARSE ESPECÍFICO DO XML DA CRIATURA
------------------------------------------------------------
local function parseCriaturaXML(xml)
    dbg("[parseCriaturaXML] tamanho XML", #tostring(xml))

    local data = {}

    -- campos simples
    data.nome = extractTag(xml, "nome")
    data.nd = extractNumberTag(xml, "nd")
    data.tipo = extractTag(xml, "tipo")
    data.tamanho = extractTag(xml, "tamanho")
    data.descricao = extractTag(xml, "descricao")
    data.pv = extractNumberTag(xml, "pv")
    data.ca = extractNumberTag(xml, "ca")
    data.deslocamento = extractTag(xml, "deslocamento")

    -- atributos
    local atributosBlock = extractBlock(xml, "atributos") or ""
    data.atributos = {
        ["for"] = extractNumberTag(atributosBlock, "for"),
        ["des"] = extractNumberTag(atributosBlock, "des"),
        ["con"] = extractNumberTag(atributosBlock, "con"),
        ["int"] = extractNumberTag(atributosBlock, "int"),
        ["sab"] = extractNumberTag(atributosBlock, "sab"),
        ["car"] = extractNumberTag(atributosBlock, "car")
    }

    -- listas simples
    data.sentidos = extractList(xml, "sentidos")
    data.pericias = extractList(xml, "pericias")
    data.resistencias = extractList(xml, "resistencias")
    data.imunidades = extractList(xml, "imunidades")

    -- ataques
    data.ataques = {}
    local ataquesBlock = extractBlock(xml, "ataques")

    if ataquesBlock then
        for itemXML in ataquesBlock:gmatch("<item>(.-)</item>") do
            local nome = extractTag(itemXML, "nome")
            local bonus = extractTag(itemXML, "bonus")
            local dano = extractTag(itemXML, "dano")
            local tipo = extractTag(itemXML, "tipo")

            table.insert(data.ataques, {
                nome = nome or "",
                bonus = bonus or "",
                dano = dano or "",
                tipo = tipo or ""
            })
        end
    end

    -- habilidades
    data.habilidades = {}
    local habBlock = extractBlock(xml, "habilidades")

    if habBlock then
        for itemXML in habBlock:gmatch("<item>(.-)</item>") do
            local nome = extractTag(itemXML, "nome")
            local descricao = extractTag(itemXML, "descricao")

            table.insert(data.habilidades,
                         {nome = nome or "", descricao = descricao or ""})
        end
    end

    return data
end

------------------------------------------------------------
-- CRIAR BOTÕES DINÂMICOS EM flwDin
------------------------------------------------------------
function rebuildDynamicButtons(ficha, nodo, data)
    local form = ficha
    if not form then return end

    local testeForma = GUI.findControlByName("flwDin", ficha)

    local filhos = testeForma:getChildren();
    local i;

    for i = 1, #filhos, 1 do filhos[i]:destroy(); end

    -- PERÍCIAS
    for _, pericia in ipairs(data.pericias or {}) do
        addRectangle(testeForma, "Perícia: " .. pericia, data)
    end

    -- ATAQUES
    for _, atk in ipairs(data.ataques or {}) do
        addRectangle(testeForma, "Atk: " .. (atk.nome or "Ataque"), data)
    end

    -- HABILIDADES
    for _, hab in ipairs(data.habilidades or {}) do
        addRectangle(testeForma, "Hab: " .. (hab.nome or "Habilidade"), data)
    end
end

------------------------------------------------------------
-- PREENCHER FICHA A PARTIR DE UMA TABELA "data"
------------------------------------------------------------
local function preencherFicha(ficha, nodo, data)
    if nodo == nil or data == nil then
        showMessage("[preencherFicha] nodo ou data NIL")
        return
    end

    nodo.nome = data.nome or ""
    nodo.nd = data.nd or 0
    nodo.tipo = data.tipo or ""
    nodo.tamanho = data.tamanho or ""
    nodo.descricao = data.descricao or ""
    nodo.deslocamento = data.deslocamento or ""

    nodo.pv = data.pv or 0
    nodo.ca = data.ca or 0

    if data.atributos then
        nodo.att_for = data.atributos["for"] or 0
        nodo.att_des = data.atributos["des"] or 0
        nodo.att_con = data.atributos["con"] or 0
        nodo.att_int = data.atributos["int"] or 0
        nodo.att_sab = data.atributos["sab"] or 0
        nodo.att_car = data.atributos["car"] or 0
    end

    nodo.dataIA = data or {}

    -- monta os botões dinâmicos
    rebuildDynamicButtons(ficha, nodo, data)
end

------------------------------------------------------------
-- CHAMAR IA (proxy retorna XML)
------------------------------------------------------------
local function chamarOpenAI(ficha, nodo, texto)
    if nodo == nil then
        showMessage("[chamarOpenAI] nodo NIL")
        return
    end

    if not texto or texto == "" then
        showMessage("ERRO: nenhum texto enviado.")
        return
    end

    local body = json.encode({prompt = texto})

    httpPOST(GEMINI_PROXY_URL, body, function(resposta)
        nodo.xmlCriatura = resposta or ""

        local data = parseCriaturaXML(resposta or "")
        if not data or (data.nome or "") == "" then
            showMessage(
                "[MonsterIA] ERRO: XML retornado sem <nome> ou inválido.")
            return
        end

        preencherFicha(ficha, nodo, data)
    end, function(err) showMessage("[ERRO] IA falhou: " .. tostring(err)) end)
end

------------------------------------------------------------
------------------------------------------------------------
function askAndCallIA(ficha, nodo)

    if nodo == nil then
        showMessage("ERRO: node NIL.")
        return
    end

    local txt = nodo.textoBrutoIA or ""

    if txt == "" then
        showMessage("Cole o texto da criatura em 'Texto para IA'.")
        return
    end

    chamarOpenAI(ficha, nodo, txt)
end

function addRectangle(flw, texto, nodo)
    local rectangle = GUI.newRectangle()
    rectangle.align = "none"
    rectangle.width = 260
    rectangle.height = 30
    rectangle.color = "#303030"
    rectangle.strokeColor = "#505050"
    rectangle.strokeSize = 1
    rectangle.cornerRadius = 4
    rectangle.padding = {left = 8, right = 8, top = 5, bottom = 5}
    rectangle.margins = {top = 4, bottom = 4, right = 4}
    rectangle.parent = flw

    ----------------------------------------------------
    -- CRIAR O TEXTO DO BOTÃO
    ----------------------------------------------------
    local label = GUI.newLabel()
    label.text = texto
    label.align = "client"
    label.horzTextAlign = "leading"
    label.parent = rectangle

    ----------------------------------------------------
    -- FORMATAR HABILIDADE (branco + negrito)
    ----------------------------------------------------
    if texto:match("^Hab:") then
        label.fontColor = "#FFFFFF"
        label.fontStyle = "bold"
    end

    ----------------------------------------------------
    -- DEFINIR HINT AUTOMÁTICO
    ----------------------------------------------------
    rectangle.hint = texto   -- texto visível ao passar o mouse

    ----------------------------------------------------
    -- DEFINIR DESCRIÇÃO COMPLETA COMO tooltip
    ----------------------------------------------------
    if texto:match("^Hab:") and nodo.habilidades then
        for _, hab in ipairs(nodo.habilidades) do
            local nomeLimp = texto:gsub("^%w+:%s*", "")
            if hab.nome == nomeLimp then
                rectangle.hint = hab.nome .. "\n\n" .. hab.descricao
                break
            end
        end
    end

    ----------------------------------------------------
    -- ON CLICK → ROLA / OU MOSTRA HABILIDADE
    ----------------------------------------------------
    rectangle.onClick = function()

        local bonus = 0
        local nomeLimp = texto:gsub("^%w+:%s*", "")

        local mesa = Firecast.getMesaDe(rectangle)
        if not mesa or not mesa.activeChat then
            showMessage("Chat não encontrado.")
            return
        end
        local chat = mesa.activeChat

        ----------------------------------------------------
        -- PERÍCIA
        ----------------------------------------------------
        if texto:match("^Perícia:") then
            local numero = nomeLimp:match("([+-]?%d+)$")
            bonus = tonumber(numero) or 0

            local roll = string.format("1d20+%d", bonus)
            chat:rolarDados(roll, "Perícia: " .. nomeLimp)
            return
        end

        ----------------------------------------------------
        -- ATAQUE
        ----------------------------------------------------
        if texto:match("^Atk:") then
            if nodo.ataques then
                for _, atk in ipairs(nodo.ataques) do
                    if atk.nome == nomeLimp then
                        local bonusAtk = tonumber(atk.bonus) or 0
                        local rollAtk = "1d20+" .. bonusAtk

                        -- rola ataque
                        chat:rolarDados(rollAtk, "Ataque: " .. atk.nome)

                        -- rola dano
                        if atk.dano then
                            local dano = atk.dano:match("(%d+d%d+[%+%-]?%d*)")

                            if dano then
                                chat:rolarDados(dano, "Dano de " .. atk.nome)
                            else
                                chat:enviarMensagem(
                                    "Descrição do dano: " .. atk.dano)
                            end
                        end

                        return
                    end
                end
            end

            showMessage("Ataque não encontrado no nodo.")
            return
        end

        ----------------------------------------------------
        -- HABILIDADE → MOSTRA DESCRIÇÃO NO CHAT
        ----------------------------------------------------
        if texto:match("^Hab:") then
            if nodo.habilidades then
                for _, hab in ipairs(nodo.habilidades) do
                    if hab.nome == nomeLimp then
                        chat:enviarMensagem(
                            string.format("[§K2]Habilidade: %s[§K1][§B]\n%s",
                                          hab.nome, hab.descricao))
                        return
                    end
                end
            end

            chat:enviarMensagem("Habilidade: " .. nomeLimp)
            return
        end
    end

    return rectangle
end


