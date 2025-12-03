require("firecast.lua");
local __o_rrpgObjs = require("rrpgObjs.lua");
require("rrpgGUI.lua");
require("rrpgDialogs.lua");
require("rrpgLFM.lua");
require("ndb.lua");
require("locale.lua");
local __o_Utils = require("utils.lua");

local function constructNew_frmItemAtaque()
    local obj = GUI.fromHandle(_obj_newObject("form"));
    local self = obj;
    local sheet = nil;

    rawset(obj, "_oldSetNodeObjectFunction", obj.setNodeObject);

    function obj:setNodeObject(nodeObject)
        sheet = nodeObject;
        self.sheet = nodeObject;
        self:_oldSetNodeObjectFunction(nodeObject);
    end;

    function obj:setNodeDatabase(nodeObject)
        self:setNodeObject(nodeObject);
    end;

    _gui_assignInitialParentForForm(obj.handle);
    obj:beginUpdate();
    obj:setName("frmItemAtaque");
    obj:setWidth(350);
    obj:setHeight(60);
    obj:setTheme("dark");

    obj.layout1 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout1:setParent(obj);
    obj.layout1:setAlign("client");
    obj.layout1:setName("layout1");

    obj.edtNome = GUI.fromHandle(_obj_newObject("edit"));
    obj.edtNome:setParent(obj.layout1);
    obj.edtNome:setName("edtNome");
    obj.edtNome:setField("nome");
    obj.edtNome:setWidth(120);
    obj.edtNome:setVertTextAlign("center");
    obj.edtNome:setHint("Nome do ataque");

    obj.edtBonus = GUI.fromHandle(_obj_newObject("edit"));
    obj.edtBonus:setParent(obj.layout1);
    obj.edtBonus:setName("edtBonus");
    obj.edtBonus:setField("bonus");
    obj.edtBonus:setWidth(40);
    obj.edtBonus:setMargins({left=4});
    obj.edtBonus:setVertTextAlign("center");
    obj.edtBonus:setHint("Bônus");

    obj.edtDano = GUI.fromHandle(_obj_newObject("edit"));
    obj.edtDano:setParent(obj.layout1);
    obj.edtDano:setName("edtDano");
    obj.edtDano:setField("dano");
    obj.edtDano:setWidth(100);
    obj.edtDano:setMargins({left=4});
    obj.edtDano:setVertTextAlign("center");
    obj.edtDano:setHint("Dano");

    obj.edtTipo = GUI.fromHandle(_obj_newObject("edit"));
    obj.edtTipo:setParent(obj.layout1);
    obj.edtTipo:setName("edtTipo");
    obj.edtTipo:setField("tipo");
    obj.edtTipo:setWidth(80);
    obj.edtTipo:setMargins({left=4});
    obj.edtTipo:setVertTextAlign("center");
    obj.edtTipo:setHint("Tipo");

    obj.button1 = GUI.fromHandle(_obj_newObject("button"));
    obj.button1:setParent(obj.layout1);
    obj.button1:setText("X");
    obj.button1:setWidth(22);
    obj.button1:setAlign("right");
    obj.button1:setMargins({left=4});
    obj.button1:setVertTextAlign("center");
    obj.button1:setName("button1");

    obj._e_event0 = obj.button1:addEventListener("onClick",
        function (event)
            ndb.deleteNode(self.sheet)
        end);

    function obj:_releaseEvents()
        __o_rrpgObjs.removeEventListenerById(self._e_event0);
    end;

    obj._oldLFMDestroy = obj.destroy;

    function obj:destroy() 
        self:_releaseEvents();

        if (self.handle ~= 0) and (self.setNodeDatabase ~= nil) then
          self:setNodeDatabase(nil);
        end;

        if self.edtNome ~= nil then self.edtNome:destroy(); self.edtNome = nil; end;
        if self.edtTipo ~= nil then self.edtTipo:destroy(); self.edtTipo = nil; end;
        if self.button1 ~= nil then self.button1:destroy(); self.button1 = nil; end;
        if self.edtDano ~= nil then self.edtDano:destroy(); self.edtDano = nil; end;
        if self.edtBonus ~= nil then self.edtBonus:destroy(); self.edtBonus = nil; end;
        if self.layout1 ~= nil then self.layout1:destroy(); self.layout1 = nil; end;
        self:_oldLFMDestroy();
    end;

    obj:endUpdate();

    return obj;
end;

function newfrmItemAtaque()
    local retObj = nil;
    __o_rrpgObjs.beginObjectsLoading();

    __o_Utils.tryFinally(
      function()
        retObj = constructNew_frmItemAtaque();
      end,
      function()
        __o_rrpgObjs.endObjectsLoading();
      end);

    assert(retObj ~= nil);
    return retObj;
end;

local _frmItemAtaque = {
    newEditor = newfrmItemAtaque, 
    new = newfrmItemAtaque, 
    name = "frmItemAtaque", 
    dataType = "", 
    formType = "undefined", 
    formComponentName = "form", 
    cacheMode = "none", 
    title = "", 
    description=""};

frmItemAtaque = _frmItemAtaque;
Firecast.registrarForm(_frmItemAtaque);

return _frmItemAtaque;
