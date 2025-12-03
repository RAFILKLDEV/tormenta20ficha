require("firecast.lua");
local __o_rrpgObjs = require("rrpgObjs.lua");
require("rrpgGUI.lua");
require("rrpgDialogs.lua");
require("rrpgLFM.lua");
require("ndb.lua");
require("locale.lua");
local __o_Utils = require("utils.lua");

local function constructNew_frmMonstros()
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
    obj:setFormType("sheetTemplate");
    obj:setDataType("MosterIa");
    obj:setName("frmMonstros");
    obj:setTitle("Tormenta 20 - MonsterIA");
    obj:setTheme("dark");
    obj:setWidth(1080);
    obj:setHeight(600);
    obj:setPadding({left=4, top=4, right=4, bottom=4});


        local ndb = require("ndb")

        -- Mostrar Mana apenas se o node tiver esse campo
        function atualizarMana(self)
            local sheet = self.sheet
            if sheet == nil then return end

            if sheet.mana == nil or sheet.mana == "" then
                self.edtMana.visible = false
            else
                self.edtMana.visible = true
            end
        end

        function copilarFicha(form)
            local node = form.box.node
            rebuildDynamicButtons(self.frmMonstros, node, sheet.dataIA)
        end

        -- Eventos de atualização
        function onNodeReady(self)
            atualizarMana(self)

            if self.sheet ~= nil then
                self.sheet:addEventListener("onChanged",
                    function(_, field)
                        if field == "mana" then
                            atualizarMana(self)
                        end
                    end)
            end
        end
    


    obj.layout1 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout1:setParent(obj);
    obj.layout1:setAlign("top");
    obj.layout1:setHeight(30);
    obj.layout1:setMargins({bottom=4});
    obj.layout1:setName("layout1");

    obj.button1 = GUI.fromHandle(_obj_newObject("button"));
    obj.button1:setParent(obj.layout1);
    obj.button1:setText("Novo Monstro");
    obj.button1:setWidth(120);
    obj.button1:setAlign("left");
    obj.button1:setName("button1");

    obj.button2 = GUI.fromHandle(_obj_newObject("button"));
    obj.button2:setParent(obj.layout1);
    obj.button2:setText("TESTE");
    obj.button2:setWidth(120);
    obj.button2:setAlign("left");
    obj.button2:setName("button2");

    obj.rclMonstros = GUI.fromHandle(_obj_newObject("recordList"));
    obj.rclMonstros:setParent(obj);
    obj.rclMonstros:setName("rclMonstros");
    obj.rclMonstros:setField("lista");
    obj.rclMonstros:setTemplateForm("frmMonstroItem");
    obj.rclMonstros:setSelectable(true);
    obj.rclMonstros:setLayout("horizontal");
    obj.rclMonstros:setAlign("top");
    obj.rclMonstros:setHeight(60);

    obj.box = GUI.fromHandle(_obj_newObject("dataScopeBox"));
    obj.box:setParent(obj);
    obj.box:setName("box");
    obj.box:setVisible(false);
    obj.box:setAlign("client");
    obj.box:setMargins({top=4});

    obj.scrollBox1 = GUI.fromHandle(_obj_newObject("scrollBox"));
    obj.scrollBox1:setParent(obj.box);
    obj.scrollBox1:setAlign("client");
    obj.scrollBox1:setName("scrollBox1");

    obj.rectangle1 = GUI.fromHandle(_obj_newObject("rectangle"));
    obj.rectangle1:setParent(obj.scrollBox1);
    obj.rectangle1:setAlign("client");
    obj.rectangle1:setColor("#202020");
    obj.rectangle1:setPadding({left=4, top=4, right=4, bottom=4});
    obj.rectangle1:setName("rectangle1");

    obj.scrollBox2 = GUI.fromHandle(_obj_newObject("scrollBox"));
    obj.scrollBox2:setParent(obj.rectangle1);
    obj.scrollBox2:setAlign("client");
    obj.scrollBox2:setName("scrollBox2");

    obj.layout2 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout2:setParent(obj.scrollBox2);
    obj.layout2:setAlign("top");
    obj.layout2:setHeight(20);
    obj.layout2:setName("layout2");

    obj.label1 = GUI.fromHandle(_obj_newObject("label"));
    obj.label1:setParent(obj.layout2);
    obj.label1:setText("Texto para IA:");
    obj.label1:setAlign("left");
    obj.label1:setWidth(200);
    obj.label1:setName("label1");

    obj.layout3 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout3:setParent(obj.scrollBox2);
    obj.layout3:setAlign("top");
    obj.layout3:setHeight(120);
    obj.layout3:setName("layout3");

    obj.edtTextoIA = GUI.fromHandle(_obj_newObject("textEditor"));
    obj.edtTextoIA:setParent(obj.layout3);
    obj.edtTextoIA:setName("edtTextoIA");
    obj.edtTextoIA:setField("textoBrutoIA");
    obj.edtTextoIA:setAlign("left");
    obj.edtTextoIA:setWidth(900);

    obj.layout4 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout4:setParent(obj.scrollBox2);
    obj.layout4:setAlign("top");
    obj.layout4:setHeight(30);
    obj.layout4:setMargins({bottom=4});
    obj.layout4:setName("layout4");

    obj.button3 = GUI.fromHandle(_obj_newObject("button"));
    obj.button3:setParent(obj.layout4);
    obj.button3:setText("Gerar com IA");
    obj.button3:setAlign("left");
    obj.button3:setWidth(180);
    obj.button3:setFontColor("#00FFAA");
    obj.button3:setName("button3");

    obj.layout5 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout5:setParent(obj.scrollBox2);
    obj.layout5:setAlign("top");
    obj.layout5:setHeight(50);
    obj.layout5:setName("layout5");

    obj.button4 = GUI.fromHandle(_obj_newObject("button"));
    obj.button4:setParent(obj.layout5);
    obj.button4:setText("Copilar Ficha");
    obj.button4:setAlign("left");
    obj.button4:setWidth(120);
    obj.button4:setName("button4");

    obj.layout6 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout6:setParent(obj.scrollBox2);
    obj.layout6:setAlign("top");
    obj.layout6:setHeight(30);
    obj.layout6:setMargins({top=4});
    obj.layout6:setName("layout6");

    obj.label2 = GUI.fromHandle(_obj_newObject("label"));
    obj.label2:setParent(obj.layout6);
    obj.label2:setAlign("left");
    obj.label2:setWidth(50);
    obj.label2:setText("Nome:");
    obj.label2:setName("label2");

    obj.edit1 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit1:setParent(obj.layout6);
    obj.edit1:setAlign("left");
    obj.edit1:setWidth(300);
    obj.edit1:setField("nome");
    obj.edit1:setName("edit1");

    obj.layout7 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout7:setParent(obj.scrollBox2);
    obj.layout7:setAlign("top");
    obj.layout7:setHeight(30);
    obj.layout7:setName("layout7");

    obj.label3 = GUI.fromHandle(_obj_newObject("label"));
    obj.label3:setParent(obj.layout7);
    obj.label3:setAlign("left");
    obj.label3:setWidth(50);
    obj.label3:setText("ND:");
    obj.label3:setName("label3");

    obj.edit2 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit2:setParent(obj.layout7);
    obj.edit2:setAlign("left");
    obj.edit2:setWidth(50);
    obj.edit2:setField("nd");
    obj.edit2:setMargins({left=4});
    obj.edit2:setName("edit2");

    obj.label4 = GUI.fromHandle(_obj_newObject("label"));
    obj.label4:setParent(obj.layout7);
    obj.label4:setAlign("left");
    obj.label4:setWidth(50);
    obj.label4:setText("Tipo:");
    obj.label4:setMargins({left=10});
    obj.label4:setName("label4");

    obj.edit3 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit3:setParent(obj.layout7);
    obj.edit3:setAlign("left");
    obj.edit3:setWidth(120);
    obj.edit3:setField("tipo");
    obj.edit3:setName("edit3");

    obj.label5 = GUI.fromHandle(_obj_newObject("label"));
    obj.label5:setParent(obj.layout7);
    obj.label5:setAlign("left");
    obj.label5:setWidth(100);
    obj.label5:setText("Tamanho:");
    obj.label5:setMargins({left=10});
    obj.label5:setName("label5");

    obj.edit4 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit4:setParent(obj.layout7);
    obj.edit4:setAlign("left");
    obj.edit4:setWidth(120);
    obj.edit4:setField("tamanho");
    obj.edit4:setName("edit4");

    obj.layout8 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout8:setParent(obj.scrollBox2);
    obj.layout8:setAlign("top");
    obj.layout8:setHeight(30);
    obj.layout8:setMargins({top=4});
    obj.layout8:setName("layout8");

    obj.label6 = GUI.fromHandle(_obj_newObject("label"));
    obj.label6:setParent(obj.layout8);
    obj.label6:setAlign("left");
    obj.label6:setWidth(50);
    obj.label6:setText("PV:");
    obj.label6:setName("label6");

    obj.edit5 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit5:setParent(obj.layout8);
    obj.edit5:setAlign("left");
    obj.edit5:setWidth(60);
    obj.edit5:setField("pv");
    obj.edit5:setMargins({left=4});
    obj.edit5:setName("edit5");

    obj.label7 = GUI.fromHandle(_obj_newObject("label"));
    obj.label7:setParent(obj.layout8);
    obj.label7:setText("Mana:");
    obj.label7:setAlign("left");
    obj.label7:setWidth(60);
    obj.label7:setName("label7");

    obj.edtMana = GUI.fromHandle(_obj_newObject("edit"));
    obj.edtMana:setParent(obj.layout8);
    obj.edtMana:setName("edtMana");
    obj.edtMana:setAlign("left");
    obj.edtMana:setWidth(80);
    obj.edtMana:setField("mana");
    obj.edtMana:setVisible(true);

    obj.label8 = GUI.fromHandle(_obj_newObject("label"));
    obj.label8:setParent(obj.layout8);
    obj.label8:setAlign("left");
    obj.label8:setWidth(50);
    obj.label8:setText("CA:");
    obj.label8:setMargins({left=10});
    obj.label8:setName("label8");

    obj.edit6 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit6:setParent(obj.layout8);
    obj.edit6:setAlign("left");
    obj.edit6:setWidth(60);
    obj.edit6:setField("ca");
    obj.edit6:setName("edit6");

    obj.label9 = GUI.fromHandle(_obj_newObject("label"));
    obj.label9:setParent(obj.layout8);
    obj.label9:setAlign("left");
    obj.label9:setWidth(110);
    obj.label9:setText("Deslocamento:");
    obj.label9:setMargins({left=10});
    obj.label9:setName("label9");

    obj.edit7 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit7:setParent(obj.layout8);
    obj.edit7:setAlign("left");
    obj.edit7:setWidth(120);
    obj.edit7:setField("deslocamento");
    obj.edit7:setName("edit7");

    obj.layout9 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout9:setParent(obj.scrollBox2);
    obj.layout9:setAlign("top");
    obj.layout9:setHeight(20);
    obj.layout9:setMargins({top=6});
    obj.layout9:setName("layout9");

    obj.label10 = GUI.fromHandle(_obj_newObject("label"));
    obj.label10:setParent(obj.layout9);
    obj.label10:setText("Atributos:");
    obj.label10:setAlign("left");
    obj.label10:setWidth(200);
    obj.label10:setName("label10");

    obj.layout10 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout10:setParent(obj.scrollBox2);
    obj.layout10:setAlign("top");
    obj.layout10:setHeight(30);
    obj.layout10:setName("layout10");

    obj.label11 = GUI.fromHandle(_obj_newObject("label"));
    obj.label11:setParent(obj.layout10);
    obj.label11:setText("FOR");
    obj.label11:setAlign("left");
    obj.label11:setWidth(30);
    obj.label11:setName("label11");

    obj.edit8 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit8:setParent(obj.layout10);
    obj.edit8:setField("att_for");
    obj.edit8:setAlign("left");
    obj.edit8:setWidth(40);
    obj.edit8:setMargins({left=2, right=8});
    obj.edit8:setName("edit8");

    obj.label12 = GUI.fromHandle(_obj_newObject("label"));
    obj.label12:setParent(obj.layout10);
    obj.label12:setText("DES");
    obj.label12:setAlign("left");
    obj.label12:setWidth(30);
    obj.label12:setName("label12");

    obj.edit9 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit9:setParent(obj.layout10);
    obj.edit9:setField("att_des");
    obj.edit9:setAlign("left");
    obj.edit9:setWidth(40);
    obj.edit9:setMargins({left=2, right=8});
    obj.edit9:setName("edit9");

    obj.label13 = GUI.fromHandle(_obj_newObject("label"));
    obj.label13:setParent(obj.layout10);
    obj.label13:setText("CON");
    obj.label13:setAlign("left");
    obj.label13:setWidth(30);
    obj.label13:setName("label13");

    obj.edit10 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit10:setParent(obj.layout10);
    obj.edit10:setField("att_con");
    obj.edit10:setAlign("left");
    obj.edit10:setWidth(40);
    obj.edit10:setMargins({left=2, right=8});
    obj.edit10:setName("edit10");

    obj.label14 = GUI.fromHandle(_obj_newObject("label"));
    obj.label14:setParent(obj.layout10);
    obj.label14:setText("INT");
    obj.label14:setAlign("left");
    obj.label14:setWidth(30);
    obj.label14:setName("label14");

    obj.edit11 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit11:setParent(obj.layout10);
    obj.edit11:setField("att_int");
    obj.edit11:setAlign("left");
    obj.edit11:setWidth(40);
    obj.edit11:setMargins({left=2, right=8});
    obj.edit11:setName("edit11");

    obj.label15 = GUI.fromHandle(_obj_newObject("label"));
    obj.label15:setParent(obj.layout10);
    obj.label15:setText("SAB");
    obj.label15:setAlign("left");
    obj.label15:setWidth(30);
    obj.label15:setName("label15");

    obj.edit12 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit12:setParent(obj.layout10);
    obj.edit12:setField("att_sab");
    obj.edit12:setAlign("left");
    obj.edit12:setWidth(40);
    obj.edit12:setMargins({left=2, right=8});
    obj.edit12:setName("edit12");

    obj.label16 = GUI.fromHandle(_obj_newObject("label"));
    obj.label16:setParent(obj.layout10);
    obj.label16:setText("CAR");
    obj.label16:setAlign("left");
    obj.label16:setWidth(30);
    obj.label16:setName("label16");

    obj.edit13 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit13:setParent(obj.layout10);
    obj.edit13:setField("att_car");
    obj.edit13:setAlign("left");
    obj.edit13:setWidth(40);
    obj.edit13:setMargins({left=2});
    obj.edit13:setName("edit13");

    obj.layout11 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout11:setParent(obj.scrollBox2);
    obj.layout11:setAlign("top");
    obj.layout11:setHeight(20);
    obj.layout11:setMargins({top=8});
    obj.layout11:setName("layout11");

    obj.label17 = GUI.fromHandle(_obj_newObject("label"));
    obj.label17:setParent(obj.layout11);
    obj.label17:setText("Resistências:");
    obj.label17:setAlign("left");
    obj.label17:setWidth(200);
    obj.label17:setName("label17");

    obj.layout12 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout12:setParent(obj.scrollBox2);
    obj.layout12:setAlign("top");
    obj.layout12:setHeight(30);
    obj.layout12:setName("layout12");

    obj.label18 = GUI.fromHandle(_obj_newObject("label"));
    obj.label18:setParent(obj.layout12);
    obj.label18:setText("Fort:");
    obj.label18:setAlign("left");
    obj.label18:setWidth(40);
    obj.label18:setName("label18");

    obj.edit14 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit14:setParent(obj.layout12);
    obj.edit14:setField("res_fort");
    obj.edit14:setAlign("left");
    obj.edit14:setWidth(50);
    obj.edit14:setMargins({left=2, right=15});
    obj.edit14:setName("edit14");

    obj.label19 = GUI.fromHandle(_obj_newObject("label"));
    obj.label19:setParent(obj.layout12);
    obj.label19:setText("Ref:");
    obj.label19:setAlign("left");
    obj.label19:setWidth(40);
    obj.label19:setName("label19");

    obj.edit15 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit15:setParent(obj.layout12);
    obj.edit15:setField("res_ref");
    obj.edit15:setAlign("left");
    obj.edit15:setWidth(50);
    obj.edit15:setMargins({left=2, right=15});
    obj.edit15:setName("edit15");

    obj.label20 = GUI.fromHandle(_obj_newObject("label"));
    obj.label20:setParent(obj.layout12);
    obj.label20:setText("Von:");
    obj.label20:setAlign("left");
    obj.label20:setWidth(40);
    obj.label20:setName("label20");

    obj.edit16 = GUI.fromHandle(_obj_newObject("edit"));
    obj.edit16:setParent(obj.layout12);
    obj.edit16:setField("res_von");
    obj.edit16:setAlign("left");
    obj.edit16:setWidth(50);
    obj.edit16:setMargins({left=2});
    obj.edit16:setName("edit16");

    obj.layout13 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout13:setParent(obj.scrollBox2);
    obj.layout13:setAlign("top");
    obj.layout13:setHeight(20);
    obj.layout13:setMargins({top=8});
    obj.layout13:setName("layout13");

    obj.label21 = GUI.fromHandle(_obj_newObject("label"));
    obj.label21:setParent(obj.layout13);
    obj.label21:setText("Ações / Rolagens:");
    obj.label21:setAlign("left");
    obj.label21:setWidth(200);
    obj.label21:setName("label21");

    obj.layout14 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout14:setParent(obj.scrollBox2);
    obj.layout14:setAlign("top");
    obj.layout14:setHeight(200);
    obj.layout14:setMargins({bottom=8});
    obj.layout14:setName("layout14");

    obj.flwDin = GUI.fromHandle(_obj_newObject("flowLayout"));
    obj.flwDin:setParent(obj.layout14);
    obj.flwDin:setName("flwDin");
    obj.flwDin:setAlign("left");
    obj.flwDin:setWidth(900);
    obj.flwDin:setMaxControlsPerLine(3);
    obj.flwDin:setMinWidth(150);

    obj.layout15 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout15:setParent(obj.scrollBox2);
    obj.layout15:setAlign("top");
    obj.layout15:setHeight(20);
    obj.layout15:setMargins({top=8});
    obj.layout15:setName("layout15");

    obj.label22 = GUI.fromHandle(_obj_newObject("label"));
    obj.label22:setParent(obj.layout15);
    obj.label22:setText("Equipamentos:");
    obj.label22:setAlign("left");
    obj.label22:setWidth(200);
    obj.label22:setName("label22");

    obj.layout16 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout16:setParent(obj.scrollBox2);
    obj.layout16:setAlign("top");
    obj.layout16:setHeight(90);
    obj.layout16:setName("layout16");

    obj.edtEquip = GUI.fromHandle(_obj_newObject("textEditor"));
    obj.edtEquip:setParent(obj.layout16);
    obj.edtEquip:setName("edtEquip");
    obj.edtEquip:setField("equipamentos");
    obj.edtEquip:setAlign("left");
    obj.edtEquip:setWidth(900);
    obj.edtEquip:setHeight(80);

    obj.layout17 = GUI.fromHandle(_obj_newObject("layout"));
    obj.layout17:setParent(obj.scrollBox2);
    obj.layout17:setAlign("top");
    obj.layout17:setHeight(30);
    obj.layout17:setMargins({top=6});
    obj.layout17:setName("layout17");

    obj.button5 = GUI.fromHandle(_obj_newObject("button"));
    obj.button5:setParent(obj.layout17);
    obj.button5:setText("Excluir");
    obj.button5:setAlign("left");
    obj.button5:setWidth(120);
    obj.button5:setFontColor("#FF4444");
    obj.button5:setName("button5");

    obj._e_event0 = obj.button1:addEventListener("onClick",
        function (event)
            self.rclMonstros:append();
        end);

    obj._e_event1 = obj.button2:addEventListener("onClick",
        function (event)
            local rectangle = GUI.newRectangle()
                            rectangle.align = "top"
                            rectangle.height = 30
                            rectangle.name = "rectTeste"
                            rectangle.padding = { left = 10, right = 10, top = 5, bottom = 5 }
                            rectangle.margins = { top = 5 }
                            rectangle.parent = self.flwDin
            
                            local label = GUI.newLabel()
                            label.text = acoes[i].nome
                            label.align = "left"
                            label.width = 220
                            label.parent = rectangle
        end);

    obj._e_event2 = obj.rclMonstros:addEventListener("onSelect",
        function ()
            local node = self.rclMonstros.selectedNode
                        self.box.node = node
                        self.box.visible = (node ~= nil)
        end);

    obj._e_event3 = obj.button3:addEventListener("onClick",
        function (event)
            askAndCallIA(self, self.box.node)
        end);

    obj._e_event4 = obj.button4:addEventListener("onClick",
        function (event)
            copilarFicha(self)
        end);

    obj._e_event5 = obj.button5:addEventListener("onClick",
        function (event)
            if self.box.node then
                                                local apagar = self.box.node
                                                self.box.node = nil
                                                self.box.visible = false
                                                ndb.deleteNode(apagar)
                                            end
        end);

    function obj:_releaseEvents()
        __o_rrpgObjs.removeEventListenerById(self._e_event5);
        __o_rrpgObjs.removeEventListenerById(self._e_event4);
        __o_rrpgObjs.removeEventListenerById(self._e_event3);
        __o_rrpgObjs.removeEventListenerById(self._e_event2);
        __o_rrpgObjs.removeEventListenerById(self._e_event1);
        __o_rrpgObjs.removeEventListenerById(self._e_event0);
    end;

    obj._oldLFMDestroy = obj.destroy;

    function obj:destroy() 
        self:_releaseEvents();

        if (self.handle ~= 0) and (self.setNodeDatabase ~= nil) then
          self:setNodeDatabase(nil);
        end;

        if self.layout8 ~= nil then self.layout8:destroy(); self.layout8 = nil; end;
        if self.edit4 ~= nil then self.edit4:destroy(); self.edit4 = nil; end;
        if self.layout11 ~= nil then self.layout11:destroy(); self.layout11 = nil; end;
        if self.edit10 ~= nil then self.edit10:destroy(); self.edit10 = nil; end;
        if self.edtTextoIA ~= nil then self.edtTextoIA:destroy(); self.edtTextoIA = nil; end;
        if self.flwDin ~= nil then self.flwDin:destroy(); self.flwDin = nil; end;
        if self.layout3 ~= nil then self.layout3:destroy(); self.layout3 = nil; end;
        if self.layout17 ~= nil then self.layout17:destroy(); self.layout17 = nil; end;
        if self.label11 ~= nil then self.label11:destroy(); self.label11 = nil; end;
        if self.edit15 ~= nil then self.edit15:destroy(); self.edit15 = nil; end;
        if self.layout9 ~= nil then self.layout9:destroy(); self.layout9 = nil; end;
        if self.edit8 ~= nil then self.edit8:destroy(); self.edit8 = nil; end;
        if self.edit5 ~= nil then self.edit5:destroy(); self.edit5 = nil; end;
        if self.layout10 ~= nil then self.layout10:destroy(); self.layout10 = nil; end;
        if self.layout4 ~= nil then self.layout4:destroy(); self.layout4 = nil; end;
        if self.box ~= nil then self.box:destroy(); self.box = nil; end;
        if self.layout16 ~= nil then self.layout16:destroy(); self.layout16 = nil; end;
        if self.button1 ~= nil then self.button1:destroy(); self.button1 = nil; end;
        if self.label1 ~= nil then self.label1:destroy(); self.label1 = nil; end;
        if self.scrollBox1 ~= nil then self.scrollBox1:destroy(); self.scrollBox1 = nil; end;
        if self.rclMonstros ~= nil then self.rclMonstros:destroy(); self.rclMonstros = nil; end;
        if self.label10 ~= nil then self.label10:destroy(); self.label10 = nil; end;
        if self.edit14 ~= nil then self.edit14:destroy(); self.edit14 = nil; end;
        if self.edit9 ~= nil then self.edit9:destroy(); self.edit9 = nil; end;
        if self.label22 ~= nil then self.label22:destroy(); self.label22 = nil; end;
        if self.edit2 ~= nil then self.edit2:destroy(); self.edit2 = nil; end;
        if self.layout13 ~= nil then self.layout13:destroy(); self.layout13 = nil; end;
        if self.button4 ~= nil then self.button4:destroy(); self.button4 = nil; end;
        if self.label4 ~= nil then self.label4:destroy(); self.label4 = nil; end;
        if self.label15 ~= nil then self.label15:destroy(); self.label15 = nil; end;
        if self.layout5 ~= nil then self.layout5:destroy(); self.layout5 = nil; end;
        if self.edtEquip ~= nil then self.edtEquip:destroy(); self.edtEquip = nil; end;
        if self.button2 ~= nil then self.button2:destroy(); self.button2 = nil; end;
        if self.label2 ~= nil then self.label2:destroy(); self.label2 = nil; end;
        if self.label13 ~= nil then self.label13:destroy(); self.label13 = nil; end;
        if self.edit13 ~= nil then self.edit13:destroy(); self.edit13 = nil; end;
        if self.rectangle1 ~= nil then self.rectangle1:destroy(); self.rectangle1 = nil; end;
        if self.edit3 ~= nil then self.edit3:destroy(); self.edit3 = nil; end;
        if self.label8 ~= nil then self.label8:destroy(); self.label8 = nil; end;
        if self.layout12 ~= nil then self.layout12:destroy(); self.layout12 = nil; end;
        if self.label19 ~= nil then self.label19:destroy(); self.label19 = nil; end;
        if self.label5 ~= nil then self.label5:destroy(); self.label5 = nil; end;
        if self.label14 ~= nil then self.label14:destroy(); self.label14 = nil; end;
        if self.button5 ~= nil then self.button5:destroy(); self.button5 = nil; end;
        if self.layout6 ~= nil then self.layout6:destroy(); self.layout6 = nil; end;
        if self.edit6 ~= nil then self.edit6:destroy(); self.edit6 = nil; end;
        if self.button3 ~= nil then self.button3:destroy(); self.button3 = nil; end;
        if self.label3 ~= nil then self.label3:destroy(); self.label3 = nil; end;
        if self.label12 ~= nil then self.label12:destroy(); self.label12 = nil; end;
        if self.edit12 ~= nil then self.edit12:destroy(); self.edit12 = nil; end;
        if self.label20 ~= nil then self.label20:destroy(); self.label20 = nil; end;
        if self.layout1 ~= nil then self.layout1:destroy(); self.layout1 = nil; end;
        if self.label9 ~= nil then self.label9:destroy(); self.label9 = nil; end;
        if self.label18 ~= nil then self.label18:destroy(); self.label18 = nil; end;
        if self.layout15 ~= nil then self.layout15:destroy(); self.layout15 = nil; end;
        if self.label6 ~= nil then self.label6:destroy(); self.label6 = nil; end;
        if self.label17 ~= nil then self.label17:destroy(); self.label17 = nil; end;
        if self.scrollBox2 ~= nil then self.scrollBox2:destroy(); self.scrollBox2 = nil; end;
        if self.layout7 ~= nil then self.layout7:destroy(); self.layout7 = nil; end;
        if self.edit7 ~= nil then self.edit7:destroy(); self.edit7 = nil; end;
        if self.label21 ~= nil then self.label21:destroy(); self.label21 = nil; end;
        if self.edit11 ~= nil then self.edit11:destroy(); self.edit11 = nil; end;
        if self.edtMana ~= nil then self.edtMana:destroy(); self.edtMana = nil; end;
        if self.layout2 ~= nil then self.layout2:destroy(); self.layout2 = nil; end;
        if self.edit1 ~= nil then self.edit1:destroy(); self.edit1 = nil; end;
        if self.layout14 ~= nil then self.layout14:destroy(); self.layout14 = nil; end;
        if self.label7 ~= nil then self.label7:destroy(); self.label7 = nil; end;
        if self.label16 ~= nil then self.label16:destroy(); self.label16 = nil; end;
        if self.edit16 ~= nil then self.edit16:destroy(); self.edit16 = nil; end;
        self:_oldLFMDestroy();
    end;

    obj:endUpdate();

    return obj;
end;

function newfrmMonstros()
    local retObj = nil;
    __o_rrpgObjs.beginObjectsLoading();

    __o_Utils.tryFinally(
      function()
        retObj = constructNew_frmMonstros();
      end,
      function()
        __o_rrpgObjs.endObjectsLoading();
      end);

    assert(retObj ~= nil);
    return retObj;
end;

local _frmMonstros = {
    newEditor = newfrmMonstros, 
    new = newfrmMonstros, 
    name = "frmMonstros", 
    dataType = "MosterIa", 
    formType = "sheetTemplate", 
    formComponentName = "form", 
    cacheMode = "none", 
    title = "Tormenta 20 - MonsterIA", 
    description=""};

frmMonstros = _frmMonstros;
Firecast.registrarForm(_frmMonstros);
Firecast.registrarDataType(_frmMonstros);

return _frmMonstros;
