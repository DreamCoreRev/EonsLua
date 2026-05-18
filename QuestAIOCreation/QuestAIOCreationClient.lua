--[[
    QuestAIOCreationClient.lua
    Système de création de quêtes en jeu via AIO — côté CLIENT
    TrinityCore 3.3.5 / ElunaTrinityWotlk
    Commande GM : .questcreator
    UI 100% Blizzard frames, aucun AddOn requis
]]

local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local QuestHandlers = AIO.AddHandlers("QuestCreatorAIO", {})

-- ============================================================
-- CONSTANTES UI
-- ============================================================

local FRAME_W   = 1020
local FRAME_H   = 720
local TAB_COUNT = 6

-- Couleurs WoW
local COLOR_GOLD   = {r=1,   g=0.82, b=0}
local COLOR_GREEN  = {r=0,   g=1,    b=0}
local COLOR_RED    = {r=1,   g=0.2,  b=0.2}
local COLOR_GREY   = {r=0.6, g=0.6,  b=0.6}

-- ============================================================
-- STATE LOCAL
-- ============================================================

local UI = {}         -- références aux widgets
local CurrentQuest = {}  -- données de la quête en cours d'édition
local QuestList    = {}  -- liste des quêtes chargées
local CurrentTab   = 1
local IsEditing    = false  -- true = édition, false = nouvelle quête

-- ============================================================
-- UTILITAIRES UI
-- ============================================================

local function MakeLabel(parent, text, x, y, color)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    lbl:SetText(text)
    if color then lbl:SetTextColor(color.r, color.g, color.b) end
    return lbl
end

local function MakeEditBox(parent, x, y, w, h, label)
    if label then
        MakeLabel(parent, label, x, y, COLOR_GOLD)
        y = y + 16
    end
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(500)
    return eb
end

local function MakeMultiLine(parent, x, y, w, h, label)
    if label then
        MakeLabel(parent, label, x, y, COLOR_GOLD)
        y = y + 16
    end

    -- Conteneur global (bordure + fond)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(w, h)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    container:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left=2, right=2, top=2, bottom=2},
    })
    container:SetBackdropColor(0, 0, 0, 0.55)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)

    -- ScrollBar manuelle à droite (16px de large, rentrée de 2px)
    local sb = CreateFrame("Slider", nil, container, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT",    container, "TOPRIGHT",    -3, -16)
    sb:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -3,  16)
    sb:SetWidth(14)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(12)

    -- ScrollFrame sans template (pas de scrollbar intégrée)
    local sf = CreateFrame("ScrollFrame", nil, container)
    sf:SetPoint("TOPLEFT",     container, "TOPLEFT",     4,  -4)
    sf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -20, 4)

    -- EditBox à l'intérieur
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetWidth(sf:GetWidth() or (w - 24))
    eb:SetHeight(h * 4)   -- hauteur interne grande pour le scroll
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetMaxLetters(5000)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)

    -- Lier ScrollBar ↔ ScrollFrame
    sf:SetScript("OnScrollRangeChanged", function(self, xrange, yrange)
        local max = yrange or 0
        sb:SetMinMaxValues(0, max)
        if max == 0 then sb:Hide() else sb:Show() end
    end)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        sb:SetValue(offset)
    end)
    sb:SetScript("OnValueChanged", function(self, val)
        sf:SetVerticalScroll(val)
    end)

    -- Scroll à la molette
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(self, delta)
        local cur = sf:GetVerticalScroll()
        local _, max = sb:GetMinMaxValues()
        local new = math.max(0, math.min(max, cur - delta * 20))
        sf:SetVerticalScroll(new)
        sb:SetValue(new)
    end)

    return eb, sf
end

local function MakeButton(parent, text, x, y, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 100, h or 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    btn:SetText(text)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

local function MakeCheckBox(parent, label, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    cb.text:SetText(label)
    return cb
end

local function GetEB(eb)
    return eb:GetText() or ""
end

local function SetEB(eb, v)
    eb:SetText(tostring(v or ""))
end

-- ============================================================
-- LECTURE DES DONNÉES DU FORMULAIRE
-- ============================================================

local function CollectFormData()
    local d = {}

    -- Onglet 1 : Général
    d.ID               = tonumber(GetEB(UI.eb_ID)) or 0
    d.LogTitle         = GetEB(UI.eb_LogTitle)
    d.QuestLevel       = tonumber(GetEB(UI.eb_QuestLevel)) or 1
    d.MinLevel         = tonumber(GetEB(UI.eb_MinLevel)) or 0
    d.MaxLevel         = tonumber(GetEB(UI.eb_MaxLevel)) or 0
    d.QuestSortID      = tonumber(GetEB(UI.eb_QuestSortID)) or 0
    d.QuestInfoID      = tonumber(GetEB(UI.eb_QuestInfoID)) or 0
    d.QuestType        = tonumber(GetEB(UI.eb_QuestType)) or 2
    d.SuggestedGroupNum= tonumber(GetEB(UI.eb_SuggestedGroupNum)) or 0
    d.TimeAllowed      = tonumber(GetEB(UI.eb_TimeAllowed)) or 0
    d.Flags            = tonumber(GetEB(UI.eb_Flags)) or 0
    d.AllowableRaces   = tonumber(GetEB(UI.eb_AllowableRaces)) or 0
    d.AllowableClasses = tonumber(GetEB(UI.eb_AllowableClasses)) or 0
    d.RewardXPDifficulty = tonumber(GetEB(UI.eb_RewardXPDifficulty)) or 0

    -- Onglet 2 : Textes
    d.LogDescription   = GetEB(UI.eb_LogDescription)
    d.QuestDescription = GetEB(UI.eb_QuestDescription)
    d.AreaDescription  = GetEB(UI.eb_AreaDescription)
    d.QuestCompletionLog = GetEB(UI.eb_QuestCompletionLog)
    d.RewardText       = GetEB(UI.eb_RewardText)

    -- Onglet 3 : Objectifs
    d.ReqNpc1          = tonumber(GetEB(UI.eb_ReqNpc1)) or 0
    d.ReqNpcCount1     = tonumber(GetEB(UI.eb_ReqNpcCount1)) or 0
    d.ReqNpc2          = tonumber(GetEB(UI.eb_ReqNpc2)) or 0
    d.ReqNpcCount2     = tonumber(GetEB(UI.eb_ReqNpcCount2)) or 0
    d.ReqNpc3          = tonumber(GetEB(UI.eb_ReqNpc3)) or 0
    d.ReqNpcCount3     = tonumber(GetEB(UI.eb_ReqNpcCount3)) or 0
    d.ReqNpc4          = tonumber(GetEB(UI.eb_ReqNpc4)) or 0
    d.ReqNpcCount4     = tonumber(GetEB(UI.eb_ReqNpcCount4)) or 0
    d.ReqItem1         = tonumber(GetEB(UI.eb_ReqItem1)) or 0
    d.ReqItemCount1    = tonumber(GetEB(UI.eb_ReqItemCount1)) or 0
    d.ReqItem2         = tonumber(GetEB(UI.eb_ReqItem2)) or 0
    d.ReqItemCount2    = tonumber(GetEB(UI.eb_ReqItemCount2)) or 0
    d.ReqItem3         = tonumber(GetEB(UI.eb_ReqItem3)) or 0
    d.ReqItemCount3    = tonumber(GetEB(UI.eb_ReqItemCount3)) or 0
    d.ReqItem4         = tonumber(GetEB(UI.eb_ReqItem4)) or 0
    d.ReqItemCount4    = tonumber(GetEB(UI.eb_ReqItemCount4)) or 0
    d.ObjText1         = GetEB(UI.eb_ObjText1)
    d.ObjText2         = GetEB(UI.eb_ObjText2)
    d.ObjText3         = GetEB(UI.eb_ObjText3)
    d.ObjText4         = GetEB(UI.eb_ObjText4)

    -- Onglet 4 : Récompenses
    d.RewardMoney      = tonumber(GetEB(UI.eb_RewardMoney)) or 0
    d.RewardBonusMoney = tonumber(GetEB(UI.eb_RewardBonusMoney)) or 0
    d.RewardSpell      = tonumber(GetEB(UI.eb_RewardSpell)) or 0
    d.RewardTitle      = tonumber(GetEB(UI.eb_RewardTitle)) or 0
    d.RewardTalents    = tonumber(GetEB(UI.eb_RewardTalents)) or 0
    d.RewardArenaPoints= tonumber(GetEB(UI.eb_RewardArenaPoints)) or 0
    d.RewItem1         = tonumber(GetEB(UI.eb_RewItem1)) or 0
    d.RewAmount1       = tonumber(GetEB(UI.eb_RewAmount1)) or 0
    d.RewItem2         = tonumber(GetEB(UI.eb_RewItem2)) or 0
    d.RewAmount2       = tonumber(GetEB(UI.eb_RewAmount2)) or 0
    d.RewItem3         = tonumber(GetEB(UI.eb_RewItem3)) or 0
    d.RewAmount3       = tonumber(GetEB(UI.eb_RewAmount3)) or 0
    d.RewItem4         = tonumber(GetEB(UI.eb_RewItem4)) or 0
    d.RewAmount4       = tonumber(GetEB(UI.eb_RewAmount4)) or 0
    d.RewChoiceItem1   = tonumber(GetEB(UI.eb_RewChoiceItem1)) or 0
    d.RewChoiceQty1    = tonumber(GetEB(UI.eb_RewChoiceQty1)) or 0
    d.RewChoiceItem2   = tonumber(GetEB(UI.eb_RewChoiceItem2)) or 0
    d.RewChoiceQty2    = tonumber(GetEB(UI.eb_RewChoiceQty2)) or 0
    d.RewChoiceItem3   = tonumber(GetEB(UI.eb_RewChoiceItem3)) or 0
    d.RewChoiceQty3    = tonumber(GetEB(UI.eb_RewChoiceQty3)) or 0
    d.RewFactionID1    = tonumber(GetEB(UI.eb_RewFactionID1)) or 0
    d.RewFactionVal1   = tonumber(GetEB(UI.eb_RewFactionVal1)) or 0
    d.RewFactionID2    = tonumber(GetEB(UI.eb_RewFactionID2)) or 0
    d.RewFactionVal2   = tonumber(GetEB(UI.eb_RewFactionVal2)) or 0

    -- Onglet 5 : Chaîne / Prérequis
    d.PrevQuestID      = tonumber(GetEB(UI.eb_PrevQuestID)) or 0
    d.NextQuestID      = tonumber(GetEB(UI.eb_NextQuestID)) or 0
    d.ExclusiveGroup   = tonumber(GetEB(UI.eb_ExclusiveGroup)) or 0
    d.SourceSpellID    = tonumber(GetEB(UI.eb_SourceSpellID)) or 0
    d.RewardMailTemplateID = tonumber(GetEB(UI.eb_RewardMailTemplateID)) or 0
    d.RequiredSkillID  = tonumber(GetEB(UI.eb_RequiredSkillID)) or 0
    d.RequiredSkillPoints = tonumber(GetEB(UI.eb_RequiredSkillPoints)) or 0
    d.ReqMinRepFaction = tonumber(GetEB(UI.eb_ReqMinRepFaction)) or 0
    d.ReqMinRepValue   = tonumber(GetEB(UI.eb_ReqMinRepValue)) or 0
    d.SpecialFlags     = tonumber(GetEB(UI.eb_SpecialFlags)) or 0

    -- Onglet 6 : NPC liés + Locale
    local startersRaw = GetEB(UI.eb_Starters)
    local endersRaw   = GetEB(UI.eb_Enders)
    d.Starters = {}
    d.Enders   = {}
    for v in string.gmatch(startersRaw, "%d+") do
        table.insert(d.Starters, tonumber(v))
    end
    for v in string.gmatch(endersRaw, "%d+") do
        table.insert(d.Enders, tonumber(v))
    end
    d.LocTitle     = GetEB(UI.eb_LocTitle)
    d.LocDesc      = GetEB(UI.eb_LocDesc)
    d.LocObj       = GetEB(UI.eb_LocObj)
    d.LocCompleted = GetEB(UI.eb_LocCompleted)

    return d
end

-- ============================================================
-- REMPLIR LE FORMULAIRE
-- ============================================================

local function PopulateForm(q)
    if not q then return end
    CurrentQuest = q
    IsEditing = true

    -- Général
    SetEB(UI.eb_ID,                q.ID or 0)
    SetEB(UI.eb_LogTitle,          q.LogTitle or "")
    SetEB(UI.eb_QuestLevel,        q.QuestLevel or 1)
    SetEB(UI.eb_MinLevel,          q.MinLevel or 0)
    SetEB(UI.eb_MaxLevel,          q.MaxLevel or 0)
    SetEB(UI.eb_QuestSortID,       q.QuestSortID or 0)
    SetEB(UI.eb_QuestInfoID,       q.QuestInfoID or 0)
    SetEB(UI.eb_QuestType,         q.QuestType or 2)
    SetEB(UI.eb_SuggestedGroupNum, q.SuggestedGroupNum or 0)
    SetEB(UI.eb_TimeAllowed,       q.TimeAllowed or 0)
    SetEB(UI.eb_Flags,             q.Flags or 0)
    SetEB(UI.eb_AllowableRaces,    q.AllowableRaces or 0)
    SetEB(UI.eb_AllowableClasses,  q.AllowableClasses or 0)
    SetEB(UI.eb_RewardXPDifficulty,q.RewardXPDifficulty or 0)
    -- Textes
    SetEB(UI.eb_LogDescription,    q.LogDescription or "")
    SetEB(UI.eb_QuestDescription,  q.QuestDescription or "")
    SetEB(UI.eb_AreaDescription,   q.AreaDescription or "")
    SetEB(UI.eb_QuestCompletionLog,q.QuestCompletionLog or "")
    SetEB(UI.eb_RewardText,        q.RewardText or "")
    -- Objectifs NPC
    SetEB(UI.eb_ReqNpc1,       q.ReqNpc1 or 0)
    SetEB(UI.eb_ReqNpcCount1,  q.ReqNpcCount1 or 0)
    SetEB(UI.eb_ReqNpc2,       q.ReqNpc2 or 0)
    SetEB(UI.eb_ReqNpcCount2,  q.ReqNpcCount2 or 0)
    SetEB(UI.eb_ReqNpc3,       q.ReqNpc3 or 0)
    SetEB(UI.eb_ReqNpcCount3,  q.ReqNpcCount3 or 0)
    SetEB(UI.eb_ReqNpc4,       q.ReqNpc4 or 0)
    SetEB(UI.eb_ReqNpcCount4,  q.ReqNpcCount4 or 0)
    -- Objectifs Item
    SetEB(UI.eb_ReqItem1,      q.ReqItem1 or 0)
    SetEB(UI.eb_ReqItemCount1, q.ReqItemCount1 or 0)
    SetEB(UI.eb_ReqItem2,      q.ReqItem2 or 0)
    SetEB(UI.eb_ReqItemCount2, q.ReqItemCount2 or 0)
    SetEB(UI.eb_ReqItem3,      q.ReqItem3 or 0)
    SetEB(UI.eb_ReqItemCount3, q.ReqItemCount3 or 0)
    SetEB(UI.eb_ReqItem4,      q.ReqItem4 or 0)
    SetEB(UI.eb_ReqItemCount4, q.ReqItemCount4 or 0)
    SetEB(UI.eb_ObjText1,      q.ObjText1 or "")
    SetEB(UI.eb_ObjText2,      q.ObjText2 or "")
    SetEB(UI.eb_ObjText3,      q.ObjText3 or "")
    SetEB(UI.eb_ObjText4,      q.ObjText4 or "")
    -- Récompenses
    SetEB(UI.eb_RewardMoney,       q.RewardMoney or 0)
    SetEB(UI.eb_RewardBonusMoney,  q.RewardBonusMoney or 0)
    SetEB(UI.eb_RewardSpell,       q.RewardSpell or 0)
    SetEB(UI.eb_RewardTitle,       q.RewardTitle or 0)
    SetEB(UI.eb_RewardTalents,     q.RewardTalents or 0)
    SetEB(UI.eb_RewardArenaPoints, q.RewardArenaPoints or 0)
    SetEB(UI.eb_RewItem1,      q.RewItem1 or 0)
    SetEB(UI.eb_RewAmount1,    q.RewAmount1 or 0)
    SetEB(UI.eb_RewItem2,      q.RewItem2 or 0)
    SetEB(UI.eb_RewAmount2,    q.RewAmount2 or 0)
    SetEB(UI.eb_RewItem3,      q.RewItem3 or 0)
    SetEB(UI.eb_RewAmount3,    q.RewAmount3 or 0)
    SetEB(UI.eb_RewItem4,      q.RewItem4 or 0)
    SetEB(UI.eb_RewAmount4,    q.RewAmount4 or 0)
    SetEB(UI.eb_RewChoiceItem1,q.RewChoiceItem1 or 0)
    SetEB(UI.eb_RewChoiceQty1, q.RewChoiceQty1 or 0)
    SetEB(UI.eb_RewChoiceItem2,q.RewChoiceItem2 or 0)
    SetEB(UI.eb_RewChoiceQty2, q.RewChoiceQty2 or 0)
    SetEB(UI.eb_RewChoiceItem3,q.RewChoiceItem3 or 0)
    SetEB(UI.eb_RewChoiceQty3, q.RewChoiceQty3 or 0)
    SetEB(UI.eb_RewFactionID1, q.RewFactionID1 or 0)
    SetEB(UI.eb_RewFactionVal1,q.RewFactionVal1 or 0)
    SetEB(UI.eb_RewFactionID2, q.RewFactionID2 or 0)
    SetEB(UI.eb_RewFactionVal2,q.RewFactionVal2 or 0)
    -- Chaîne
    SetEB(UI.eb_PrevQuestID,          q.PrevQuestID or 0)
    SetEB(UI.eb_NextQuestID,          q.NextQuestID or 0)
    SetEB(UI.eb_ExclusiveGroup,       q.ExclusiveGroup or 0)
    SetEB(UI.eb_SourceSpellID,        q.SourceSpellID or 0)
    SetEB(UI.eb_RewardMailTemplateID, q.RewardMailTemplateID or 0)
    SetEB(UI.eb_RequiredSkillID,      q.RequiredSkillID or 0)
    SetEB(UI.eb_RequiredSkillPoints,  q.RequiredSkillPoints or 0)
    SetEB(UI.eb_ReqMinRepFaction,     q.ReqMinRepFaction or 0)
    SetEB(UI.eb_ReqMinRepValue,       q.ReqMinRepValue or 0)
    SetEB(UI.eb_SpecialFlags,         q.SpecialFlags or 0)
    -- NPC & Locale
    local starterStr = table.concat(q.Starters or {}, ", ")
    local enderStr   = table.concat(q.Enders   or {}, ", ")
    SetEB(UI.eb_Starters,    starterStr)
    SetEB(UI.eb_Enders,      enderStr)
    SetEB(UI.eb_LocTitle,    q.LocTitle or "")
    SetEB(UI.eb_LocDesc,     q.LocDesc or "")
    SetEB(UI.eb_LocObj,      q.LocObj or "")
    SetEB(UI.eb_LocCompleted,q.LocCompleted or "")

    if UI.lbl_status then
        UI.lbl_status:SetText("|cff00ff00Édition: [" .. (q.LogTitle or "???") .. "] ID#" .. (q.ID or "?"))
    end
end

local function ClearForm()
    IsEditing = false
    CurrentQuest = {}
    local fields = {
        "eb_ID","eb_LogTitle","eb_QuestLevel","eb_MinLevel","eb_MaxLevel",
        "eb_QuestSortID","eb_QuestInfoID","eb_QuestType","eb_SuggestedGroupNum",
        "eb_TimeAllowed","eb_Flags","eb_AllowableRaces","eb_AllowableClasses","eb_RewardXPDifficulty",
        "eb_LogDescription","eb_QuestDescription","eb_AreaDescription","eb_QuestCompletionLog","eb_RewardText",
        "eb_ReqNpc1","eb_ReqNpcCount1","eb_ReqNpc2","eb_ReqNpcCount2",
        "eb_ReqNpc3","eb_ReqNpcCount3","eb_ReqNpc4","eb_ReqNpcCount4",
        "eb_ReqItem1","eb_ReqItemCount1","eb_ReqItem2","eb_ReqItemCount2",
        "eb_ReqItem3","eb_ReqItemCount3","eb_ReqItem4","eb_ReqItemCount4",
        "eb_ObjText1","eb_ObjText2","eb_ObjText3","eb_ObjText4",
        "eb_RewardMoney","eb_RewardBonusMoney","eb_RewardSpell","eb_RewardTitle",
        "eb_RewardTalents","eb_RewardArenaPoints",
        "eb_RewItem1","eb_RewAmount1","eb_RewItem2","eb_RewAmount2",
        "eb_RewItem3","eb_RewAmount3","eb_RewItem4","eb_RewAmount4",
        "eb_RewChoiceItem1","eb_RewChoiceQty1","eb_RewChoiceItem2","eb_RewChoiceQty2",
        "eb_RewChoiceItem3","eb_RewChoiceQty3",
        "eb_RewFactionID1","eb_RewFactionVal1","eb_RewFactionID2","eb_RewFactionVal2",
        "eb_PrevQuestID","eb_NextQuestID","eb_ExclusiveGroup","eb_SourceSpellID",
        "eb_RewardMailTemplateID","eb_RequiredSkillID","eb_RequiredSkillPoints",
        "eb_ReqMinRepFaction","eb_ReqMinRepValue","eb_SpecialFlags",
        "eb_Starters","eb_Enders",
        "eb_LocTitle","eb_LocDesc","eb_LocObj","eb_LocCompleted",
    }
    -- Valeurs par défaut sensées
    local defaults = { eb_QuestLevel="1", eb_QuestType="2" }
    for _, k in ipairs(fields) do
        if UI[k] then
            SetEB(UI[k], defaults[k] or "")
        end
    end
    if UI.lbl_status then
        UI.lbl_status:SetText("|cffffff00Nouvelle quête")
    end
end

-- ============================================================
-- LISTE DES QUÊTES (panneau gauche)
-- ============================================================

local function RefreshQuestList()
    if not UI.listFrame then return end
    -- Effacer les anciens boutons
    for _, child in pairs({UI.listFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    UI.listButtons = {}

    local btnH = 22
    for i, q in ipairs(QuestList) do
        local btn = CreateFrame("Button", nil, UI.listFrame)
        btn:SetSize(UI.listFrame:GetWidth() - 4, btnH)
        btn:SetPoint("TOPLEFT", UI.listFrame, "TOPLEFT", 2, -((i - 1) * btnH))

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0, 0, 0, 0)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetAllPoints()
        txt:SetJustifyH("LEFT")
        txt:SetText(string.format("|cffcda400#%d|r %s |cff888888(niv.%d)|r",
            q.id, q.title or "???", q.level or 0))

        btn:SetScript("OnEnter", function(self)
            bg:SetTexture(0.2, 0.5, 1, 0.2)
        end)
        btn:SetScript("OnLeave", function(self)
            bg:SetTexture(0, 0, 0, 0)
        end)
        btn:SetScript("OnClick", function()
            AIO.Handle("QuestCreatorAIO", "LoadQuest", {id = q.id})
        end)
        btn:Show()
        table.insert(UI.listButtons, btn)
    end

    -- Adapter la hauteur du listFrame pour le scroll
    UI.listFrame:SetHeight(math.max(#QuestList * btnH, 10))
end

-- ============================================================
-- ONGLETS (tabs)
-- ============================================================

local TAB_NAMES = {
    "Général", "Textes", "Objectifs", "Récompenses", "Chaîne/Prérequis", "NPC & Locale"
}

local function ShowTab(idx)
    CurrentTab = idx
    for i = 1, TAB_COUNT do
        if UI.tabPanels[i] then
            if i == idx then
                UI.tabPanels[i]:Show()
            else
                UI.tabPanels[i]:Hide()
            end
        end
        if UI.tabs[i] then
            if i == idx then
                UI.tabs[i]:SetNormalFontObject("GameFontHighlight")
            else
                UI.tabs[i]:SetNormalFontObject("GameFontNormal")
            end
        end
    end
end

-- ============================================================
-- CONSTRUCTION DE L'UI PRINCIPALE
-- ============================================================

local function BuildUI()
    if UI.mainFrame then return end

    -- Fenêtre principale
    local f = CreateFrame("Frame", "QuestCreatorAIOFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = {left=11, right=12, top=12, bottom=11},
    })
    f:Hide()
    UI.mainFrame = f

    -- --------------------------------------------------------
    -- EN-TÊTE
    -- --------------------------------------------------------
    local titleBg = f:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -12)
    titleBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -13, -12)
    titleBg:SetHeight(36)
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBg:SetTexCoord(0.205, 0.795, 0, 0.63)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("|cffcda400Quest Creator AIO|r  |cff888888v2.0|r")

    -- Bouton fermer
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Status bar
    UI.lbl_status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.lbl_status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 34)
    UI.lbl_status:SetText("|cffffff00Nouvelle quête")

    -- --------------------------------------------------------
    -- PANNEAU GAUCHE : liste des quêtes
    -- --------------------------------------------------------
    local leftW = 240

    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT",    f, "TOPLEFT",    12, -52)
    leftPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12,  56)
    leftPanel:SetWidth(leftW)
    leftPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = {left=3, right=3, top=3, bottom=3},
    })

    -- Titre panneau gauche
    local listTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listTitle:SetPoint("TOP", leftPanel, "TOP", 0, -6)
    listTitle:SetText("|cffcda400— Quêtes —|r")

    -- Séparateur
    local sep1 = leftPanel:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep1:SetPoint("TOPLEFT",  leftPanel, "TOPLEFT",  5, -20)
    sep1:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -5, -20)
    sep1:SetHeight(8)

    -- Zone de recherche
    local searchLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -30)
    searchLabel:SetText("|cffaaaaaa Rechercher :|r")

    local searchEB = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
    searchEB:SetSize(leftW - 16, 20)
    searchEB:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -44)
    searchEB:SetAutoFocus(false)
    searchEB:SetMaxLetters(100)
    searchEB:SetScript("OnEnterPressed", function(self)
        local txt = self:GetText()
        if tonumber(txt) then
            AIO.Handle("QuestCreatorAIO", "SearchQuest", {searchId = tonumber(txt)})
        else
            AIO.Handle("QuestCreatorAIO", "SearchQuest", {searchName = txt})
        end
        self:ClearFocus()
    end)
    local searchHint = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("LEFT", searchEB, "LEFT", 4, 0)
    searchHint:SetText("|cff555555ID ou nom...|r")
    searchEB:SetScript("OnTextChanged", function(self)
        searchHint:SetShown(self:GetText() == "")
    end)

    -- Séparateur 2
    local sep2 = leftPanel:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep2:SetPoint("TOPLEFT",  leftPanel, "TOPLEFT",  5, -68)
    sep2:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -5, -68)
    sep2:SetHeight(8)

    -- Scroll liste (scrollbar manuelle, pas de débordement)
    local listSB = CreateFrame("Slider", nil, leftPanel, "UIPanelScrollBarTemplate")
    listSB:SetPoint("TOPRIGHT",    leftPanel, "TOPRIGHT",    -4, -80)
    listSB:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -4,  30)
    listSB:SetWidth(14)
    listSB:SetMinMaxValues(0, 0)
    listSB:SetValue(0)
    listSB:SetValueStep(22)

    local listSF = CreateFrame("ScrollFrame", nil, leftPanel)
    listSF:SetPoint("TOPLEFT",     leftPanel, "TOPLEFT",     4,  -78)
    listSF:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -20, 28)

    local listContent = CreateFrame("Frame", nil, listSF)
    listContent:SetSize(leftW - 28, 2000)
    listSF:SetScrollChild(listContent)
    UI.listFrame = listContent

    listSF:SetScript("OnScrollRangeChanged", function(self, xr, yr)
        local max = yr or 0
        listSB:SetMinMaxValues(0, max)
        listSB:SetShown(max > 0)
    end)
    listSF:SetScript("OnVerticalScroll", function(self, offset)
        listSB:SetValue(offset)
    end)
    listSB:SetScript("OnValueChanged", function(self, val)
        listSF:SetVerticalScroll(val)
    end)
    leftPanel:EnableMouseWheel(true)
    leftPanel:SetScript("OnMouseWheel", function(self, delta)
        local cur = listSF:GetVerticalScroll()
        local _, max = listSB:GetMinMaxValues()
        local new = math.max(0, math.min(max, cur - delta * 22))
        listSF:SetVerticalScroll(new)
        listSB:SetValue(new)
    end)

    -- Bouton recharger liste
    local reloadListBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    reloadListBtn:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  4, 4)
    reloadListBtn:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -4, 4)
    reloadListBtn:SetHeight(22)
    reloadListBtn:SetText("Recharger")
    reloadListBtn:SetScript("OnClick", function()
        AIO.Handle("QuestCreatorAIO", "RequestQuestList", {})
    end)

    -- --------------------------------------------------------
    -- ZONE DROITE : onglets + formulaire
    -- --------------------------------------------------------
    local rightX = leftW + 20
    local rightW = FRAME_W - leftW - 30
    local tabH   = 28

    -- Calcul hauteur contenu onglets
    local tabContentTop    = 52 + tabH
    local tabContentBottom = 56
    local tabContentH      = FRAME_H - tabContentTop - tabContentBottom

    -- Barre d'onglets
    UI.tabs      = {}
    UI.tabPanels = {}

    for i, name in ipairs(TAB_NAMES) do
        local tabW = math.floor(rightW / TAB_COUNT)
        local tab  = CreateFrame("Button", nil, f, "TabButtonTemplate")
        tab:SetText(name)
        tab:SetSize(tabW, tabH)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", rightX + (i - 1) * tabW, -52)
        tab:SetScript("OnClick", function() ShowTab(i) end)
        UI.tabs[i] = tab

        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT",     f, "TOPLEFT",     rightX,          -(52 + tabH))
        panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6,               56)
        panel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = {left=3, right=3, top=3, bottom=3},
        })
        panel:Hide()
        UI.tabPanels[i] = panel
    end

    -- ============================================================
    -- ONGLET 1 : GÉNÉRAL
    -- ============================================================
    do
        local p  = UI.tabPanels[1]
        local ROW = 30   -- hauteur par ligne
        local COL1x = 10
        local COL1lw = 190  -- largeur label colonne 1
        local COL2x = 390
        local COL2lw = 190  -- largeur label colonne 2
        local EBw = 100
        local py = 14

        -- Séparateur section Identité
        local s1 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        s1:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x, -py)
        s1:SetText("|cffcda400Identité|r")
        py = py + 18

        MakeLabel(p, "ID (0 = auto-assigné)", COL1x, py)
        UI.eb_ID = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "Titre affiché (LogTitle) *", COL2x, py)
        UI.eb_LogTitle = MakeEditBox(p, COL2x + COL2lw, py, rightW - COL2x - COL2lw - 16)
        py = py + ROW

        -- Séparateur Niveaux
        local s2 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        s2:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x, -py)
        s2:SetText("|cffcda400Niveaux|r")
        py = py + 18

        MakeLabel(p, "QuestLevel", COL1x, py)
        UI.eb_QuestLevel = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "MinLevel", COL2x, py)
        UI.eb_MinLevel = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW

        MakeLabel(p, "MaxLevel (addon)", COL1x, py)
        UI.eb_MaxLevel = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "SuggestedGroupNum", COL2x, py)
        UI.eb_SuggestedGroupNum = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW

        -- Séparateur Catégorie
        local s3 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        s3:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x, -py)
        s3:SetText("|cffcda400Catégorie & Type|r")
        py = py + 18

        MakeLabel(p, "QuestSortID", COL1x, py)
        UI.eb_QuestSortID = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "QuestInfoID", COL2x, py)
        UI.eb_QuestInfoID = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW

        MakeLabel(p, "QuestType", COL1x, py)
        UI.eb_QuestType = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "TimeAllowed (sec, 0=aucun)", COL2x, py)
        UI.eb_TimeAllowed = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW

        -- Séparateur Restrictions
        local s4 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        s4:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x, -py)
        s4:SetText("|cffcda400Restrictions & XP|r")
        py = py + 18

        MakeLabel(p, "Flags", COL1x, py)
        UI.eb_Flags = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "AllowableRaces (0=toutes)", COL2x, py)
        UI.eb_AllowableRaces = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW

        MakeLabel(p, "AllowableClasses (0=toutes)", COL1x, py)
        UI.eb_AllowableClasses = MakeEditBox(p, COL1x + COL1lw, py, EBw)
        MakeLabel(p, "RewardXPDifficulty (0-9)", COL2x, py)
        UI.eb_RewardXPDifficulty = MakeEditBox(p, COL2x + COL2lw, py, EBw)
        py = py + ROW + 8

        -- Zone d'aide
        local helpBg = p:CreateTexture(nil, "BACKGROUND")
        helpBg:SetPoint("TOPLEFT",  p, "TOPLEFT", COL1x,           -py)
        helpBg:SetPoint("TOPRIGHT", p, "TOPRIGHT", -COL1x,         -py)
        helpBg:SetHeight(62)
        helpBg:SetTexture(0, 0, 0, 0.35)

        local h1 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        h1:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x+6, -(py+4))
        h1:SetText("|cff888888Flags: 8=Sharable  32=Epic  512=Daily  4096=Weekly|r")

        local h2 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        h2:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x+6, -(py+18))
        h2:SetText("|cff888888QuestType: 0=Automatch  1=Daily  2=Normal  3=Hebdo  4=Spécial  5=Mensuel|r")

        local h3 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        h3:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x+6, -(py+32))
        h3:SetText("|cff888888Races: 1=Hum  2=Ork  4=Nain  8=Nelf  16=MortViv  32=Tau  64=Gnm  128=Trll  512=Belf  1024=Drae|r")

        local hStar = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        hStar:SetPoint("TOPLEFT", p, "TOPLEFT", COL1x+6, -(py+48))
        hStar:SetText("|cffff4444* champ obligatoire|r")
    end

    -- ============================================================
    -- ONGLET 2 : TEXTES
    -- ============================================================
    do
        local p   = UI.tabPanels[2]
        local px  = 10
        local py  = 10
        local W   = rightW - 24
        local HBig = 80
        local HMed = 65
        local HSmall = 55
        local GAP = 22

        MakeLabel(p, "LogDescription  (affiché dans le journal de quête)", px, py, COLOR_GOLD)
        UI.eb_LogDescription, _ = MakeMultiLine(p, px, py + GAP, W, HBig)
        py = py + GAP + HBig + 10

        MakeLabel(p, "QuestDescription  (détails complets, vu en ouvrant la quête)", px, py, COLOR_GOLD)
        UI.eb_QuestDescription, _ = MakeMultiLine(p, px, py + GAP, W, HBig)
        py = py + GAP + HBig + 10

        MakeLabel(p, "AreaDescription  (hint de zone)", px, py, COLOR_GOLD)
        local aW = math.floor((W - 10) / 2)
        UI.eb_AreaDescription, _ = MakeMultiLine(p, px, py + GAP, aW, HMed)

        MakeLabel(p, "QuestCompletionLog  (log à la complétion)", px + aW + 10, py, COLOR_GOLD)
        UI.eb_QuestCompletionLog, _ = MakeMultiLine(p, px + aW + 10, py + GAP, aW, HMed)
        py = py + GAP + HMed + 10

        MakeLabel(p, "RewardText  (texte du NPC lors de la remise de la quête)", px, py, COLOR_GOLD)
        UI.eb_RewardText, _ = MakeMultiLine(p, px, py + GAP, W, HSmall)
    end

    -- ============================================================
    -- ONGLET 3 : OBJECTIFS
    -- ============================================================
    do
        local p   = UI.tabPanels[3]
        local py  = 10
        local px  = 10
        local COL_NPC_X  = 10
        local COL_ITEM_X = math.floor(rightW / 2) + 10
        local EBid  = 100
        local EBqty = 60
        local LBL   = 120
        local ROW   = 28

        -- Deux colonnes côte à côte : NPC à gauche, Items à droite
        local titleNPC = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        titleNPC:SetPoint("TOPLEFT", p, "TOPLEFT", COL_NPC_X, -py)
        titleNPC:SetText("|cffcda400Objectifs NPC / GO|r  |cff888888(ID négatif = GameObject)|r")

        local titleITEM = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        titleITEM:SetPoint("TOPLEFT", p, "TOPLEFT", COL_ITEM_X, -py)
        titleITEM:SetText("|cffcda400Objectifs Items|r")
        py = py + 20

        -- En-têtes colonnes
        MakeLabel(p, "NpcOrGoID",    COL_NPC_X  + LBL,          py, COLOR_GREY)
        MakeLabel(p, "Quantité",     COL_NPC_X  + LBL + EBid + 8, py, COLOR_GREY)
        MakeLabel(p, "ItemID",       COL_ITEM_X + LBL,           py, COLOR_GREY)
        MakeLabel(p, "Quantité",     COL_ITEM_X + LBL + EBid + 8, py, COLOR_GREY)
        py = py + 18

        for i = 1, 4 do
            MakeLabel(p, "Objectif NPC " .. i, COL_NPC_X, py)
            UI["eb_ReqNpc"     .. i] = MakeEditBox(p, COL_NPC_X  + LBL,           py, EBid)
            UI["eb_ReqNpcCount".. i] = MakeEditBox(p, COL_NPC_X  + LBL + EBid + 8, py, EBqty)

            MakeLabel(p, "Item " .. i, COL_ITEM_X, py)
            UI["eb_ReqItem"     .. i] = MakeEditBox(p, COL_ITEM_X + LBL,           py, EBid)
            UI["eb_ReqItemCount".. i] = MakeEditBox(p, COL_ITEM_X + LBL + EBid + 8, py, EBqty)
            py = py + ROW
        end

        py = py + 14
        local titleOBJ = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        titleOBJ:SetPoint("TOPLEFT", p, "TOPLEFT", px, -py)
        titleOBJ:SetText("|cffcda400Textes d'objectif  |r|cff888888(affichés dans le tracker de quête)|r")
        py = py + 20

        local objW = math.floor((rightW - 28) / 2) - 4
        for i = 1, 4 do
            local ox = px + ((i-1) % 2) * (objW + 8)
            local oy = py + math.floor((i-1) / 2) * 30
            MakeLabel(p, "Texte obj. " .. i, ox, oy)
            UI["eb_ObjText" .. i] = MakeEditBox(p, ox + 90, oy, objW - 90)
        end
    end

    -- ============================================================
    -- ONGLET 4 : RÉCOMPENSES
    -- ============================================================
    do
        local p   = UI.tabPanels[4]
        local py  = 10
        local px  = 10
        local ROW = 28
        local EBw = 90
        local COL1 = 10
        local COL2 = math.floor(rightW / 2) + 10
        local LBL  = 185

        -- Section Monnaie / Sorts / Titres
        local s1 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s1:SetPoint("TOPLEFT", p, "TOPLEFT", px, -py)
        s1:SetText("|cffcda400Argent, XP & Divers|r")
        py = py + 20

        MakeLabel(p, "RewardMoney (cuivre)", COL1, py)
        UI.eb_RewardMoney = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "RewardBonusMoney", COL2, py)
        UI.eb_RewardBonusMoney = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW

        MakeLabel(p, "RewardSpell (spell ID)", COL1, py)
        UI.eb_RewardSpell = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "RewardTitle (title ID)", COL2, py)
        UI.eb_RewardTitle = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW

        MakeLabel(p, "RewardTalents", COL1, py)
        UI.eb_RewardTalents = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "RewardArenaPoints", COL2, py)
        UI.eb_RewardArenaPoints = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW + 8

        -- Items fixes | Items au choix en deux colonnes
        local s2 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s2:SetPoint("TOPLEFT", p, "TOPLEFT", COL1, -py)
        s2:SetText("|cffcda400Items fixes (donnés automatiquement)|r")

        local s3 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s3:SetPoint("TOPLEFT", p, "TOPLEFT", COL2, -py)
        s3:SetText("|cffcda400Items au choix (joueur choisit 1)|r")
        py = py + 18

        MakeLabel(p, "ItemID",   COL1 + 80, py, COLOR_GREY)
        MakeLabel(p, "Qté",      COL1 + 185, py, COLOR_GREY)
        MakeLabel(p, "ItemID",   COL2 + 80, py, COLOR_GREY)
        MakeLabel(p, "Qté",      COL2 + 185, py, COLOR_GREY)
        py = py + 16

        for i = 1, 4 do
            MakeLabel(p, "Fixe " .. i, COL1, py)
            UI["eb_RewItem"  .. i] = MakeEditBox(p, COL1 + 80,  py, 95)
            UI["eb_RewAmount".. i] = MakeEditBox(p, COL1 + 185, py, 55)
            if i <= 3 then
                MakeLabel(p, "Choix " .. i, COL2, py)
                UI["eb_RewChoiceItem".. i] = MakeEditBox(p, COL2 + 80,  py, 95)
                UI["eb_RewChoiceQty" .. i] = MakeEditBox(p, COL2 + 185, py, 55)
            end
            py = py + ROW
        end

        py = py + 8

        -- Réputation
        local s4 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s4:SetPoint("TOPLEFT", p, "TOPLEFT", px, -py)
        s4:SetText("|cffcda400Récompenses de réputation|r")
        py = py + 18

        MakeLabel(p, "FactionID",  COL1 + 80, py, COLOR_GREY)
        MakeLabel(p, "Valeur",     COL1 + 185, py, COLOR_GREY)
        MakeLabel(p, "FactionID",  COL2 + 80, py, COLOR_GREY)
        MakeLabel(p, "Valeur",     COL2 + 185, py, COLOR_GREY)
        py = py + 16

        MakeLabel(p, "Faction 1", COL1, py)
        UI.eb_RewFactionID1  = MakeEditBox(p, COL1 + 80,  py, 95)
        UI.eb_RewFactionVal1 = MakeEditBox(p, COL1 + 185, py, 75)
        MakeLabel(p, "Faction 2", COL2, py)
        UI.eb_RewFactionID2  = MakeEditBox(p, COL2 + 80,  py, 95)
        UI.eb_RewFactionVal2 = MakeEditBox(p, COL2 + 185, py, 75)
    end

    -- ============================================================
    -- ONGLET 5 : CHAÎNE / PRÉREQUIS
    -- ============================================================
    do
        local p   = UI.tabPanels[5]
        local py  = 10
        local ROW = 30
        local COL1 = 10
        local COL2 = math.floor(rightW / 2) + 10
        local LBL  = 210
        local EBw  = 110

        -- Chaîne
        local s1 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s1:SetPoint("TOPLEFT", p, "TOPLEFT", COL1, -py)
        s1:SetText("|cffcda400Chaîne de quêtes|r")
        py = py + 20

        MakeLabel(p, "PrevQuestID (quête précédente)", COL1, py)
        UI.eb_PrevQuestID = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "NextQuestID (quête suivante)", COL2, py)
        UI.eb_NextQuestID = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW

        MakeLabel(p, "ExclusiveGroup", COL1, py)
        UI.eb_ExclusiveGroup = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "SourceSpellID (sort qui offre la quête)", COL2, py)
        UI.eb_SourceSpellID = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW

        MakeLabel(p, "RewardMailTemplateID", COL1, py)
        UI.eb_RewardMailTemplateID = MakeEditBox(p, COL1 + LBL, py, EBw)
        py = py + ROW + 10

        -- Prérequis compétence
        local s2 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s2:SetPoint("TOPLEFT", p, "TOPLEFT", COL1, -py)
        s2:SetText("|cffcda400Prérequis compétence|r")
        py = py + 20

        MakeLabel(p, "RequiredSkillID", COL1, py)
        UI.eb_RequiredSkillID = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "RequiredSkillPoints", COL2, py)
        UI.eb_RequiredSkillPoints = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW + 10

        -- Prérequis réputation
        local s3 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s3:SetPoint("TOPLEFT", p, "TOPLEFT", COL1, -py)
        s3:SetText("|cffcda400Prérequis réputation|r")
        py = py + 20

        MakeLabel(p, "RequiredMinRepFaction", COL1, py)
        UI.eb_ReqMinRepFaction = MakeEditBox(p, COL1 + LBL, py, EBw)
        MakeLabel(p, "RequiredMinRepValue", COL2, py)
        UI.eb_ReqMinRepValue = MakeEditBox(p, COL2 + LBL, py, EBw)
        py = py + ROW + 10

        -- SpecialFlags
        local s4 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s4:SetPoint("TOPLEFT", p, "TOPLEFT", COL1, -py)
        s4:SetText("|cffcda400Flags spéciaux|r")
        py = py + 20

        MakeLabel(p, "SpecialFlags", COL1, py)
        UI.eb_SpecialFlags = MakeEditBox(p, COL1 + LBL, py, EBw)
        py = py + ROW + 8

        -- Aide
        local helpBg = p:CreateTexture(nil, "BACKGROUND")
        helpBg:SetPoint("TOPLEFT",  p, "TOPLEFT", COL1,  -py)
        helpBg:SetPoint("TOPRIGHT", p, "TOPRIGHT", -COL1, -py)
        helpBg:SetHeight(36)
        helpBg:SetTexture(0, 0, 0, 0.35)

        local h1 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        h1:SetPoint("TOPLEFT", p, "TOPLEFT", COL1+6, -(py+4))
        h1:SetText("|cff888888PrevQuestID négatif = quête complétée ou non prise requise|r")
        local h2 = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        h2:SetPoint("TOPLEFT", p, "TOPLEFT", COL1+6, -(py+18))
        h2:SetText("|cff888888SpecialFlags: 1=Répétable   2=NeedExplore   4=Timed|r")
    end

    -- ============================================================
    -- ONGLET 6 : NPC & LOCALE
    -- ============================================================
    do
        local p   = UI.tabPanels[6]
        local px  = 10
        local py  = 10
        local W   = rightW - 24
        local HML = 65
        local ROW = 22

        -- NPC
        local s1 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s1:SetPoint("TOPLEFT", p, "TOPLEFT", px, -py)
        s1:SetText("|cffcda400NPC liés à la quête|r")
        py = py + 20

        MakeLabel(p, "NPC Starters  (IDs séparés par virgules)", px, py)
        UI.eb_Starters = MakeEditBox(p, px, py + ROW, W)
        py = py + ROW + 30

        MakeLabel(p, "NPC Enders  (IDs séparés par virgules)", px, py)
        UI.eb_Enders = MakeEditBox(p, px, py + ROW, W)
        py = py + ROW + 36

        -- Locale
        local s2 = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
        s2:SetPoint("TOPLEFT", p, "TOPLEFT", px, -py)
        s2:SetText("|cffcda400Localisation frFR  |r|cff888888(optionnel — surcharge les textes pour les clients FR)|r")
        py = py + 20

        MakeLabel(p, "Titre (frFR)", px, py)
        UI.eb_LocTitle = MakeEditBox(p, px, py + ROW, W)
        py = py + ROW + 30

        local locW = math.floor((W - 10) / 2)
        MakeLabel(p, "Description (frFR)", px, py, COLOR_GOLD)
        UI.eb_LocDesc, _ = MakeMultiLine(p, px, py + ROW, locW, HML)

        MakeLabel(p, "Objectifs (frFR)", px + locW + 10, py, COLOR_GOLD)
        UI.eb_LocObj, _ = MakeMultiLine(p, px + locW + 10, py + ROW, locW, HML)
        py = py + ROW + HML + 10

        MakeLabel(p, "Texte complété (frFR)", px, py)
        UI.eb_LocCompleted = MakeEditBox(p, px, py + ROW, W)
    end

    -- ============================================================
    -- BARRE D'ACTIONS (bas de fenêtre)
    -- ============================================================
    local barY = FRAME_H - 50

    MakeButton(f, "|cff00ff00Nouvelle quête|r",   368, barY, 148, 26, function()
        ClearForm()
        ShowTab(1)
    end)

    MakeButton(f, "|cffcda400Sauvegarder|r",      538, barY, 148, 26, function()
        local d = CollectFormData()
        if d.LogTitle == "" then
            UI.lbl_status:SetText("|cffff4444Erreur: le titre (LogTitle) est obligatoire !|r")
            return
        end
        UI.lbl_status:SetText("|cffffff00Sauvegarde en cours...|r")
        AIO.Handle("QuestCreatorAIO", "SaveQuest", d)
    end)

    MakeButton(f, "|cffff4444Supprimer|r",        704, barY, 130, 26, function()
        local idTxt = GetEB(UI.eb_ID)
        local id = tonumber(idTxt)
        if not id or id <= 0 then
            UI.lbl_status:SetText("|cffff4444Erreur: aucune quête sélectionnée (ID=0)|r")
            return
        end
        StaticPopupDialogs["QUESTCREATOR_CONFIRM_DELETE"] = {
            text = "Supprimer la quête #" .. id .. " ?",
            button1 = "Oui", button2 = "Non",
            OnAccept = function()
                AIO.Handle("QuestCreatorAIO", "DeleteQuest", {id = id})
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("QUESTCREATOR_CONFIRM_DELETE")
    end)

    MakeButton(f, "Quêtes récentes",              852, barY, 148, 26, function()
        AIO.Handle("QuestCreatorAIO", "RequestQuestList", {})
    end)

    local reloadHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reloadHint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -760, 12)
    reloadHint:SetText("|cff888888Après sauvegarde : .reload quest_template|r")

    ShowTab(1)
end

-- ============================================================
-- HANDLERS SERVEUR → CLIENT
-- ============================================================

function QuestHandlers.OpenUI(player, data)
    BuildUI()
    ClearForm()
    UI.mainFrame:Show()
    -- Charger la liste automatiquement à l'ouverture
    AIO.Handle("QuestCreatorAIO", "RequestQuestList", {})
end

function QuestHandlers.ReceiveQuestList(player, data)
    QuestList = data or {}
    if UI.mainFrame then
        RefreshQuestList()
        UI.lbl_status:SetText(string.format(
            "|cff00ff00%d quête(s) chargée(s)|r", #QuestList
        ))
    end
end

function QuestHandlers.ReceiveQuestData(player, data)
    BuildUI()
    if not UI.mainFrame:IsShown() then UI.mainFrame:Show() end
    PopulateForm(data)
    ShowTab(1)
end

function QuestHandlers.SaveSuccess(player, data)
    if UI.lbl_status then
        local msg = data.isNew and "Créée" or "Mise à jour"
        UI.lbl_status:SetText(string.format(
            "|cff00ff00%s: [%s] ID #%d — .reload quest_template pour activer|r",
            msg, data.title or "?", data.id or 0
        ))
    end
    -- Mettre à jour l'ID dans le formulaire si nouvelle quête
    if data.isNew and UI.eb_ID then
        SetEB(UI.eb_ID, data.id)
    end
    -- Rafraîchir la liste
    AIO.Handle("QuestCreatorAIO", "RequestQuestList", {})
end

function QuestHandlers.DeleteSuccess(player, data)
    if UI.lbl_status then
        UI.lbl_status:SetText(string.format(
            "|cffff4444Quête #%d supprimée.|r", data.id or 0
        ))
    end
    ClearForm()
    AIO.Handle("QuestCreatorAIO", "RequestQuestList", {})
end

function QuestHandlers.Error(player, data)
    if UI.lbl_status then
        UI.lbl_status:SetText("|cffff4444Erreur: " .. (data.msg or "inconnue") .. "|r")
    end
end

-- ============================================================
-- Log
-- ============================================================
--print("[QuestCreatorAIO] Client chargé. .questcreator pour ouvrir l'éditeur.")
