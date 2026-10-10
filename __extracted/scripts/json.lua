local json = {}

----------------------------------------------------------
-- DETECÇÃO DE ARRAY
----------------------------------------------------------
local function isArray(tbl)
    if type(tbl) ~= "table" then return false end

    local count = 0
    for k,_ in pairs(tbl) do
        if type(k) ~= "number" then return false end
        count = count + 1
    end
    return count == #tbl
end

----------------------------------------------------------
-- ENCODER: retorna string JSON válida
----------------------------------------------------------
local function encodeValue(val)
    local t = type(val)

    if t == "string" then
        val = val:gsub("\\","\\\\")
                 :gsub("\"","\\\"")
                 :gsub("\n","\\n")
                 :gsub("\r","")
        return '"' .. val .. '"'
    end

    if t == "number" or t == "boolean" then
        return tostring(val)
    end

    if t == "nil" then
        return "null"
    end

    if t == "table" then
        local parts = {}

        if isArray(val) then
            for i = 1, #val do
                parts[#parts+1] = encodeValue(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k,v in pairs(val) do
                parts[#parts+1] = '"' .. tostring(k) .. '":' .. encodeValue(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end

    error("Tipo não suportado no JSON: " .. t)
end

function json.encode(tbl)
    return encodeValue(tbl)
end

----------------------------------------------------------
-- DECODER: usa load() — funciona perfeito no Firecast
----------------------------------------------------------
function json.decode(str)
    local f, err = load("return " .. str, "json", "t", {})
    if not f then
        error("json.decode erro: " .. tostring(err))
    end
    return f()
end

return json
