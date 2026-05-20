-- WarchiefCommandAllianceClient.lua
-- Calqué sur le pattern DestinyPandaClient.lua (fonctionnel)

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

local WarchiefCommandAllianceHandlers = AIO.AddHandlers("WarchiefCommandAllianceHandler", {})

-- Création du cadre principal (au niveau du module, comme DestinyPandaClient)
local frame = CreateFrame("Frame", "WarchiefCommandBoardAllianceFrame", UIParent)
frame:SetSize(580, 600)
frame:SetPoint("CENTER")
frame:SetFrameLevel(100)
frame:SetMovable(false)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetAllPoints(true)
frame.bg:SetTexture("Interface\\garrison\\alliancebfamissionframeUITemplate.blp")

-- Texte principal
local mainTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
mainTitle:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 70, 468)
mainTitle:SetText("Le chef de guerre a besoin de vous ! Prenez un dépliant.")
mainTitle:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

-- Bouton de fermeture
local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetSize(25, 25)
closeButton:SetPoint("TOPRIGHT", 0, -75)
closeButton:SetScript("OnClick", function()
    frame:Hide()
end)

-- ========================
-- Titre : Uldum
-- ========================
-- local title1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
-- title1:SetPoint("TOPLEFT", frame, "TOPLEFT", 95, -172)
-- title1:SetText("Uldum")
-- title1:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
-- 
-- local flyerAUldum = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
-- flyerAUldum:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -280)
-- flyerAUldum:SetWidth(150)
-- flyerAUldum:SetJustifyH("LEFT")
-- flyerAUldum:SetFont("Fonts\\FRIZQT__.TTF", 10, "NONE")
-- flyerAUldum:SetTextColor(0.1, 0.2, 0.5, 1)
-- flyerAUldum:SetText("Les anciennes terres d'Uldum ont été mises au jour, livrant leurs trésors ancestraux et la technologie des Titans aux armées de l'Alliance et de la Horde.\n\nRejoignez la caravane d'Adarrah en Tanaris et emparez-vous d'Uldum et de ses ressources pour l'Alliance.")
-- 
-- local button1 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
-- button1:SetSize(120, 30)
-- button1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 54, 80)
-- button1:SetText("Aller à Uldum")
-- button1:SetScript("OnClick", function()
--     AIO.Handle("WarchiefCommandAllianceHandler", "AcceptQuest", 27721)
--     frame:Hide()
-- end)

-- ========================
-- Titre : Mont Hyjal
-- ========================
-- local title2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
-- title2:SetPoint("LEFT", title1, "RIGHT", 125, 0)
-- title2:SetText("Mont Hyjal")
-- title2:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
-- 
-- local flyerAHyjal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
-- flyerAHyjal:SetPoint("TOPLEFT", frame, "TOPLEFT", 215, -280)
-- flyerAHyjal:SetWidth(150)
-- flyerAHyjal:SetJustifyH("LEFT")
-- flyerAHyjal:SetFont("Fonts\\FRIZQT__.TTF", 10, "NONE")
-- flyerAHyjal:SetTextColor(0.1, 0.2, 0.5, 1)
-- flyerAHyjal:SetText("Les sbires d'Aile de mort au mont Hyjal cherchent à faire ployer Azeroth sous la puissance dévastatrice du seigneur du Feu !\n\nParlez à l'émissaire cénarien Sabot-Noir pour accéder au mont Hyjal.")
-- 
-- local button2 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
-- button2:SetSize(120, 30)
-- button2:SetPoint("LEFT", button1, "RIGHT", 58, 0)
-- button2:SetText("Aller à Hyjal")
-- button2:SetScript("OnClick", function()
--     AIO.Handle("WarchiefCommandAllianceHandler", "AcceptQuest", 27726)
--     frame:Hide()
-- end)

-- ========================
-- Titre : Le Tréfonds
-- ========================
-- local title3 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
-- title3:SetPoint("LEFT", title2, "RIGHT", 113, 0)
-- title3:SetText("Le Tréfonds")
-- title3:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
-- 
-- local flyerAMaelstrom = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
-- flyerAMaelstrom:SetPoint("TOPLEFT", frame, "TOPLEFT", 390, -280)
-- flyerAMaelstrom:SetWidth(150)
-- flyerAMaelstrom:SetJustifyH("LEFT")
-- flyerAMaelstrom:SetFont("Fonts\\FRIZQT__.TTF", 10, "NONE")
-- flyerAMaelstrom:SetTextColor(0.1, 0.2, 0.5, 1)
-- flyerAMaelstrom:SetText("Le Cercle terrestre mène une lutte acharnée pour juguler les énergies chaotiques qui se déversent par la faille reliant le Tréfonds à Azeroth, dans le Maelström.\n\nAidez-le à condamner la brèche et sauvez notre monde d'une destruction certaine.")
-- 
-- local button3 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
-- button3:SetSize(120, 30)
-- button3:SetPoint("LEFT", button2, "RIGHT", 56, 0)
-- button3:SetText("Aller au Tréfonds")
-- button3:SetScript("OnClick", function()
--     AIO.Handle("WarchiefCommandAllianceHandler", "AcceptQuest", 27727)
--     frame:Hide()
-- end)

-- Handler appelé par le serveur
function WarchiefCommandAllianceHandlers.OpenInterface()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
