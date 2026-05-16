local AIO = AIO or require("AIO");

if AIO.AddAddon() then
    return
end

local h_expmodifier = AIO.AddHandlers("h_expmodifier", {});

local f_expmodifier = CreateFrame("Frame", "f_expmodifier", UIParent, "UIPanelDialogTemplate");

f_expmodifier:SetSize(250, 400);
f_expmodifier:RegisterForDrag("LeftButton");
f_expmodifier:SetPoint("CENTER");
f_expmodifier:SetToplevel(true);
f_expmodifier:SetClampedToScreen(true);
-- Enable dragging of frame
f_expmodifier:SetMovable(true);
f_expmodifier:EnableMouse(true);
f_expmodifier:SetScript("OnDragStart", f_expmodifier.StartMoving);
f_expmodifier:SetScript("OnHide", f_expmodifier.StopMovingOrSizing);
f_expmodifier:SetScript("OnDragStop", f_expmodifier.StopMovingOrSizing);
f_expmodifier:Hide();

local f_expmodifier_TitleBar = f_expmodifier:CreateFontString("f_expmodifier_TitleBar", "OVERLAY")
f_expmodifier_TitleBar:SetFont("Fonts\\FRIZQT__.TTF", 13)
f_expmodifier_TitleBar:SetSize(190, 5)
f_expmodifier_TitleBar:SetPoint("TOP", f_expmodifier, "TOP", -5, -13)
f_expmodifier_TitleBar:SetText("|cffFFC125Multiplicateur d'expérience|r")

local f_expmodifier_InnerText = f_expmodifier:CreateFontString("f_expmodifier_InnerText")
f_expmodifier_InnerText:SetFont("Fonts\\FRIZQT__.TTF", 12.3)
f_expmodifier_InnerText:SetSize(190, 0)
f_expmodifier_InnerText:SetPoint("CENTER", 0, 105)
f_expmodifier_InnerText:SetText("Vous permet de modifier votre multiplicateur d'expérience.\n\nCela vous permettra d'acquérir plus d'expérience ou moins, c'est selon votre choix.")

local f_expmodifier_InnerText2 = f_expmodifier:CreateFontString("f_expmodifier_InnerText2")
f_expmodifier_InnerText2:SetFont("Fonts\\FRIZQT__.TTF", 12.3)
f_expmodifier_InnerText2:SetSize(190, 0)
f_expmodifier_InnerText2:SetPoint("CENTER", 0, 20)
f_expmodifier_InnerText2:SetText("|CFFa8a8ffVotre multiplicateur actuel : ")

local f_expmodifier_InnerMyRate = f_expmodifier:CreateFontString("f_expmodifier_InnerMyRate", function() AIO.Handle("h_expmodifier", "getRateModifier", 1) end)
f_expmodifier_InnerMyRate:SetFont("Fonts\\FRIZQT__.TTF", 20)
f_expmodifier_InnerMyRate:SetSize(190, 0)
f_expmodifier_InnerMyRate:SetPoint("CENTER", 0, -10)

local f_expmodifier_Button1 = CreateFrame("Button", "f_expmodifier_Button1", f_expmodifier)
f_expmodifier_Button1:SetSize(170, 30)
f_expmodifier_Button1:SetPoint("CENTER", 0, -70)
f_expmodifier_Button1:EnableMouse(true)
f_expmodifier_Button1:SetNormalTexture("Interface/BUTTONS/UI-DialogBox-Button-Up")
f_expmodifier_Button1:SetHighlightTexture("Interface/BUTTONS/UI-DialogBox-Button-Highlight")
f_expmodifier_Button1:SetPushedTexture("Interface/BUTTONS/UI-DialogBox-Button-Down")
f_expmodifier_Button1:SetScript("OnMouseUp", function() AIO.Handle("h_expmodifier", "setRateModifier", 1) end)

local f_expmodifier_Text1 = f_expmodifier_Button1:CreateFontString("f_expmodifier_Text1")
f_expmodifier_Text1:SetFont("Fonts\\FRIZQT__.TTF", 12)
f_expmodifier_Text1:SetSize(190, 10)
f_expmodifier_Text1:SetPoint("CENTER", 0, 5)
f_expmodifier_Text1:SetText("Multiplicateur x1")

local f_expmodifier_Button2 = CreateFrame("Button", "f_expmodifier_Button2", f_expmodifier)
f_expmodifier_Button2:SetSize(150, 30)
f_expmodifier_Button2:SetPoint("CENTER", 0, -100)
f_expmodifier_Button2:EnableMouse(true)
f_expmodifier_Button2:SetNormalTexture("Interface/BUTTONS/UI-DialogBox-Button-Up")
f_expmodifier_Button2:SetHighlightTexture("Interface/BUTTONS/UI-DialogBox-Button-Highlight")
f_expmodifier_Button2:SetPushedTexture("Interface/BUTTONS/UI-DialogBox-Button-Down")
f_expmodifier_Button2:SetScript("OnMouseUp", function() AIO.Handle("h_expmodifier", "setRateModifier", 2) end)

local f_expmodifier_Text2 = f_expmodifier_Button2:CreateFontString("f_expmodifier_Text2")
f_expmodifier_Text2:SetFont("Fonts\\FRIZQT__.TTF", 12)
f_expmodifier_Text2:SetSize(190, 10)
f_expmodifier_Text2:SetPoint("CENTER", 0, 5)
f_expmodifier_Text2:SetText("Multiplicateur x2")

local f_expmodifier_Button3 = CreateFrame("Button", "f_expmodifier_Button3", f_expmodifier)
f_expmodifier_Button3:SetSize(150, 30)
f_expmodifier_Button3:SetPoint("CENTER", 0, -130)
f_expmodifier_Button3:EnableMouse(true)
f_expmodifier_Button3:SetNormalTexture("Interface/BUTTONS/UI-DialogBox-Button-Up")
f_expmodifier_Button3:SetHighlightTexture("Interface/BUTTONS/UI-DialogBox-Button-Highlight")
f_expmodifier_Button3:SetPushedTexture("Interface/BUTTONS/UI-DialogBox-Button-Down")
f_expmodifier_Button3:SetScript("OnMouseUp", function() AIO.Handle("h_expmodifier", "setRateModifier", 3) end)

local f_expmodifier_Text3 = f_expmodifier_Button3:CreateFontString("f_expmodifier_Text3")
f_expmodifier_Text3:SetFont("Fonts\\FRIZQT__.TTF", 12)
f_expmodifier_Text3:SetSize(190, 10)
f_expmodifier_Text3:SetPoint("CENTER", 0, 5)
f_expmodifier_Text3:SetText("Multiplicateur x3")

local f_expmodifier_Button4 = CreateFrame("Button", "f_expmodifier_Button4", f_expmodifier, "UIPanelCloseButton")
f_expmodifier_Button4:SetSize(150, 30)
f_expmodifier_Button4:SetPoint("CENTER", 0, -180)
f_expmodifier_Button4:EnableMouse(true)
f_expmodifier_Button4:SetNormalTexture("Interface/BUTTONS/UI-DialogBox-Button-Up")
f_expmodifier_Button4:SetHighlightTexture("Interface/BUTTONS/UI-DialogBox-Button-Highlight")
f_expmodifier_Button4:SetPushedTexture("Interface/BUTTONS/UI-DialogBox-Button-Down")
f_expmodifier_Button4:SetScript("OnMouseUp", function() AIO.Handle("Kaev", "AttributesDecrease", 1) end)

local f_expmodifier_Text4 = f_expmodifier_Button4:CreateFontString("f_expmodifier_Text4")
f_expmodifier_Text4:SetFont("Fonts\\FRIZQT__.TTF", 12)
f_expmodifier_Text4:SetSize(190, 10)
f_expmodifier_Text4:SetPoint("CENTER", 0, 5)
f_expmodifier_Text4:SetText("Fermer")

AIO.SavePosition(f_expmodifier);

-- ============================================================
--  BOUTON SUR LE PLAYERFRAME
--  Positionné sous le portrait du joueur (bas-gauche du cadre)
--  Le PlayerFrame fait ~119x90px. Le portrait est à TOPLEFT+7,-7.
--  On ancre le bouton sous le portrait, décalé vers le bas.
-- ============================================================
local expPlayerBtn = CreateFrame("Button", "ExpModifierPlayerFrameButton", PlayerFrame)
expPlayerBtn:SetSize(42, 42)
-- Sous le portrait, à gauche (correspond à la zone entourée en rouge)
expPlayerBtn:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", -8, 18)
expPlayerBtn:SetFrameStrata("MEDIUM")
expPlayerBtn:SetFrameLevel(10)

expPlayerBtn:SetNormalTexture("interface\\RateExpUI\\exp_button")
expPlayerBtn:SetHighlightTexture("interface\\RateExpUI\\exp_button")
expPlayerBtn:GetHighlightTexture():SetAlpha(0.4)
expPlayerBtn:SetPushedTexture("interface\\RateExpUI\\exp_button")
expPlayerBtn:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)

expPlayerBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("|cffFFC125Multiplicateur d'expérience|r", 1, 1, 1)
    GameTooltip:AddLine("Cliquez ici pour modifier votre multiplicateur d'expérience.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
expPlayerBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
expPlayerBtn:SetScript("OnClick", function()
    if f_expmodifier:IsShown() then
        f_expmodifier:Hide()
    else
        AIO.Handle("h_expmodifier", "getRateModifier", 1)
        f_expmodifier:Show()
    end
end)

-- ============================================================
--  HANDLERS AIO
-- ============================================================

function h_expmodifier.ShowFrame(player)
    f_expmodifier:Show()
end

function h_expmodifier.setMyRate(player, test1)
    f_expmodifier_InnerMyRate:SetText("|CFFa8a8ff "..test1.."")
end