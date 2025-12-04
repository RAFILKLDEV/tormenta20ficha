------------------------------------------------------------
-- MonsterIA.lua
------------------------------------------------------------

local ndb      = require("ndb")
local dialogs  = require("dialogs")
local internet = require("internet")
local json     = require("json")
local GUI      = require("gui")
local Firecast = require("firecast")

GEMINI_PROXY_URL = GEMINI_PROXY_URL or "http://localhost:3000/gemini"

------------------------------------------------------------
-- UTILS
------------------------------------------------------------

local function cleanText(s)
    if not s then return "" end
    s = s:gsub("\r", " "):gsub("\n", " ")
    s = s:gsub("%s+", " ")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize(s)
    if not s then return "" end
    s = cleanText(s)
    return s:lower()
end

local function dbg(...) end -- se quiser, coloca showMessage aqui

------------------------------------------------------------
-- HTTP WRAPPER
------------------------------------------------------------

local function httpPOST(url, jsonStr, success, fail)
    local req = internet.newHTTPRequest("POST", url)
    if req == nil then
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
        if fail then fail(err) end
    end

    req:setRequestHeader("Content-Type", "application/json; charset=utf-8")
    req:send(jsonStr)
end

------------------------------------------------------------
-- XML PARSER
------------------------------------------------------------

local function extractTag(xml, tag)
    if not xml then return "" end
    local v = xml:match("<" .. tag .. ">%s*(.-)%s*</" .. tag .. ">")
    if not v then return "" end
    return cleanText(v)
end

local function extractBlock(xml, tag)
    if not xml then return nil end
    return xml:match("<" .. tag .. ">(.-)</" .. tag .. ">")
end

local function extractList(xml, tag)
    local res = {}
    local block = extractBlock(xml, tag)
    if not block then return res end

    for itemText in block:gmatch("<item>%s*(.-)%s*</item>") do
        res[#res + 1] = cleanText(itemText)
    end

    return res
end

local function extractNumberTag(xml, tag)
    local txt = extractTag(xml, tag)
    local num = txt:match("(-?%d+)")
    return tonumber(num) or 0
end

------------------------------------------------------------
-- PARSE XML DA CRIATURA
------------------------------------------------------------

local function parseCriaturaXML(xml)
    local data = {}

    data.nome         = extractTag(xml, "nome")
    data.nd           = extractNumberTag(xml, "nd")
    data.tipo         = extractTag(xml, "tipo")
    data.tamanho      = extractTag(xml, "tamanho")
    data.descricao    = extractTag(xml, "descricao")

    data.mana         = extractNumberTag(xml, "mana")

    data.pv           = extractNumberTag(xml, "pv")
    data.ca           = extractNumberTag(xml, "ca")
    data.deslocamento = extractTag(xml, "deslocamento")

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
    -- DEFESAS: primeiro <defesas>, depois fallback em resistências
    --------------------------------------------------------
    local defBlock = extractBlock(xml, "defesas") or ""
    data.fort = extractNumberTag(defBlock, "fort")
    data.ref  = extractNumberTag(defBlock, "ref")
    data.von  = extractNumberTag(defBlock, "von")

    for _, r in ipairs(data.resistencias) do
        local rlow = r:lower()
        local v = tonumber(r:match("([+-]?%d+)")) or 0

        if data.fort == 0 and rlow:find("fort") then data.fort = v end
        if data.ref  == 0 and rlow:find("ref")  then data.ref  = v end
        if data.von  == 0 and (rlow:find("von") or rlow:find("vont")) then
            data.von = v
        end
    end

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
                nome  = extractTag(item, "nome"),
                bonus = extractTag(item, "bonus"),
                dano  = extractTag(item, "dano"),
                tipo  = extractTag(item, "tipo")
            }
            data.ataques[#data.ataques + 1] = atk
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
                nome      = extractTag(item, "nome"),
                descricao = extractTag(item, "descricao")
            }
            data.habilidades[#data.habilidades + 1] = hab
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
    return data
end

------------------------------------------------------------
-- BOTÕES DINÂMICOS
------------------------------------------------------------

-- helper central: limpa e recria os botões para o node atual
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

function rebuildDynamicButtons(ficha, nodo, data)
    local flw = GUI.findControlByName("flwDin", ficha)
    if not flw then return end

    -- limpa tudo
    for _, c in ipairs(flw:getChildren()) do
        c:destroy()
    end

    -- Perícias
    for _, p in ipairs(data.pericias or {}) do
        addRectangle(flw, "Perícia: " .. p, data)
    end

    -- Ataques
    for _, atk in ipairs(data.ataques or {}) do
        addRectangle(flw, "Atk: " .. (atk.nome or ""), data)
    end

    -- Habilidades
    for _, hab in ipairs(data.habilidades or {}) do
        addRectangle(flw, "Hab: " .. (hab.nome or ""), data)
    end
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

    nodo.dataIA = data

    -- recria botões sempre a partir do node
    rebuildButtonsFromNode(ficha, nodo)
end

------------------------------------------------------------
-- CHAMAR IA
------------------------------------------------------------

local function chamarOpenAI(ficha, nodo, texto)
    if not nodo then
        showMessage("ERRO: node nil")
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
            nodo.xmlCriatura = xml
            local data = parseCriaturaXML(xml)

            if not data or (data.nome or "") == "" then
                showMessage("ERRO: XML inválido retornado pela IA.")
                return
            end

            preencherFicha(ficha, nodo, data)
        end,
        function(err)
            showMessage("[ERRO IA] " .. tostring(err))
        end
    )
end

------------------------------------------------------------
-- Função pública usada pelo formulário
------------------------------------------------------------

function askAndCallIA(ficha, nodo)
    local txt = nodo and nodo.textoBrutoIA or ""
    chamarOpenAI(ficha, nodo, txt)
end

------------------------------------------------------------
-- BOTÕES (AÇÕES / ROLAGENS)
------------------------------------------------------------

function addRectangle(flw, texto, data)
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

    local label = GUI.newLabel()
    label.text = texto
    label.align = "client"
    label.horzTextAlign = "leading"
    label.parent = rectangle

    local nomeLimp = cleanText(texto:gsub("^%w+:%s*", ""))

    rectangle.onClick = function()
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
            local num = tonumber(nomeLimp:match("([+-]?%d+)$")) or 0
            chat:rolarDados("1d20+" .. num, "Perícia: " .. nomeLimp)
            return
        end

        ----------------------------------------------------
        -- ATAQUE
        ----------------------------------------------------
        if texto:match("^Atk:") then
            for _, atk in ipairs(data.ataques or {}) do
                if normalize(atk.nome) == normalize(nomeLimp) then
                    local bonus = tonumber(atk.bonus) or 0
                    chat:rolarDados("1d20+" .. bonus, "Ataque: " .. (atk.nome or ""))

                    local danos = {}
                    for d in (atk.dano or ""):gmatch("(%d+d%d+[%+%-]?%d*)") do
                        danos[#danos + 1] = d
                    end

                    if #danos == 0 then
                        chat:enviarMensagem("Dano: " .. (atk.dano or ""))
                    else
                        for _, roll in ipairs(danos) do
                            chat:rolarDados(roll, "Dano de " .. (atk.nome or ""))
                        end
                    end

                    return
                end
            end

            showMessage("Ataque não encontrado.")
            return
        end

        ----------------------------------------------------
        -- HABILIDADE
        ----------------------------------------------------
        if texto:match("^Hab:") then
            for _, hab in ipairs(data.habilidades or {}) do
                if normalize(hab.nome) == normalize(nomeLimp) then
                    chat:enviarMensagem(
                        string.format("[§K2]Habilidade: %s[§K1][§B]\n%s",
                                      hab.nome or "", hab.descricao or ""))
                    return
                end
            end

            chat:enviarMensagem("Habilidade: " .. nomeLimp)
        end
    end

    return rectangle
end
