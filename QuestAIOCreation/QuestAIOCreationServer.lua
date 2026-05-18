--[[
    QuestAIOCreationServer.lua
    Système de création de quêtes en jeu via AIO
    TrinityCore 3.3.5 / ElunaTrinityWotlk
    Commande GM : .questcreator
]]

if not AIO then return end
if not AIO.IsServer() then return end   -- CRUCIAL
if not AIO.IsMainState() then return end -- CRUCIAL

local QuestHandlers = AIO.AddHandlers("QuestCreatorAIO", {})

-- ============================================================
-- UTILITAIRES
-- ============================================================

local function EscapeSQL(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("'",  "\\'")
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    return str
end

local function GetNextQuestID()
    local query = WorldDBQuery("SELECT MAX(ID) FROM quest_template")
    if query then
        local maxId = query:GetUInt32(0)
        return (maxId or 0) + 1
    end
    return 1
end

-- ============================================================
-- COMMANDE CHAT : .questcreator
-- Event 42 = PLAYER_EVENT_ON_COMMAND sous ElunaTrinityWotlk
-- Signature : function(event, player, command)
-- Retourner true pour consommer la commande (sinon erreur "does not exist")
-- ============================================================

local function IsAllowed(player)
    -- Seuls les comptes avec SecurityLevel >= 3 (GM) peuvent utiliser cet outil
    return player:IsGM() or player:GetGMRank() >= 3
end

local function OnCommand(event, player, command)
    if command ~= "questcreator" then
        return false
    end
    if not IsAllowed(player) then
        player:SendBroadcastMessage("|cffff4444[QuestCreator]|r Accès refusé. Niveau GM requis.")
        return true  -- consommer la commande quand même
    end
    AIO.Handle(player, "QuestCreatorAIO", "OpenUI", {})
    return true
end

RegisterPlayerEvent(42, OnCommand)

-- ============================================================
-- FALLBACK : commande via message de chat normal
-- Si la commande GM n'est pas en DB, taper "questcreator" en /say
-- suffit pour les GMs (event 18 = PLAYER_EVENT_ON_CHAT)
-- ============================================================
local function OnChat(event, player, msg, msgType, lang)
    if not IsAllowed(player) then return end
    if msg:lower() == "questcreator" or msg:lower() == ".questcreator" then
        AIO.Handle(player, "QuestCreatorAIO", "OpenUI", {})
        return true  -- empêche l'affichage du message
    end
end
RegisterPlayerEvent(18, OnChat)

-- ============================================================
-- HANDLERS AIO
-- Signature : function(player, data)
-- 'player' = objet Player Eluna, 'data' = table envoyée par le client
-- ============================================================

function QuestHandlers.RequestQuestList(player, data)
    if not IsAllowed(player) then return end

    local quests = {}
    local query = WorldDBQuery(
        "SELECT ID, LogTitle, QuestLevel, MinLevel " ..
        "FROM quest_template ORDER BY ID DESC LIMIT 200"
    )
    if query then
        repeat
            table.insert(quests, {
                id    = query:GetUInt32(0),
                title = query:GetString(1),
                level = query:GetInt16(2),
                min   = query:GetUInt8(3),
            })
        until not query:NextRow()
    end
    AIO.Handle(player, "QuestCreatorAIO", "ReceiveQuestList", quests)
end

function QuestHandlers.SearchQuest(player, data)
    if not IsAllowed(player) then return end

    if not data then return end

    local results = {}
    local query

    if data.searchId and tonumber(data.searchId) then
        query = WorldDBQuery(string.format(
            "SELECT ID, LogTitle, QuestLevel, MinLevel FROM quest_template WHERE ID = %d",
            tonumber(data.searchId)
        ))
    elseif data.searchName and data.searchName ~= "" then
        query = WorldDBQuery(string.format(
            "SELECT ID, LogTitle, QuestLevel, MinLevel FROM quest_template " ..
            "WHERE LogTitle LIKE '%%%s%%' LIMIT 50",
            EscapeSQL(data.searchName)
        ))
    end

    if query then
        repeat
            table.insert(results, {
                id    = query:GetUInt32(0),
                title = query:GetString(1),
                level = query:GetInt16(2),
                min   = query:GetUInt8(3),
            })
        until not query:NextRow()
    end
    AIO.Handle(player, "QuestCreatorAIO", "ReceiveQuestList", results)
end

function QuestHandlers.LoadQuest(player, data)
    if not IsAllowed(player) then return end

    if not data or not data.id then return end

    local questId = tonumber(data.id)
    if not questId then return end

    local qt = WorldDBQuery(string.format(
        "SELECT ID, QuestType, QuestLevel, MinLevel, QuestSortID, QuestInfoID, " ..
        "SuggestedGroupNum, RewardXPDifficulty, RewardMoney, RewardBonusMoney, " ..
        "RewardSpell, Flags, TimeAllowed, AllowableRaces, " ..
        "LogTitle, LogDescription, QuestDescription, AreaDescription, QuestCompletionLog, " ..
        "RequiredNpcOrGo1, RequiredNpcOrGo2, RequiredNpcOrGo3, RequiredNpcOrGo4, " ..
        "RequiredNpcOrGoCount1, RequiredNpcOrGoCount2, RequiredNpcOrGoCount3, RequiredNpcOrGoCount4, " ..
        "RequiredItemId1, RequiredItemId2, RequiredItemId3, RequiredItemId4, " ..
        "RequiredItemCount1, RequiredItemCount2, RequiredItemCount3, RequiredItemCount4, " ..
        "RewardItem1, RewardAmount1, RewardItem2, RewardAmount2, " ..
        "RewardItem3, RewardAmount3, RewardItem4, RewardAmount4, " ..
        "RewardChoiceItemID1, RewardChoiceItemQuantity1, " ..
        "RewardChoiceItemID2, RewardChoiceItemQuantity2, " ..
        "RewardChoiceItemID3, RewardChoiceItemQuantity3, " ..
        "ObjectiveText1, ObjectiveText2, ObjectiveText3, ObjectiveText4, " ..
        "RewardTitle, RewardTalents, RewardArenaPoints, " ..
        "RewardFactionID1, RewardFactionValue1, " ..
        "RewardFactionID2, RewardFactionValue2 " ..
        "FROM quest_template WHERE ID = %d", questId
    ))
    if not qt then
        AIO.Handle(player, "QuestCreatorAIO", "Error", {msg = "Quête introuvable: " .. questId})
        return
    end

    local addon = WorldDBQuery(string.format(
        "SELECT PrevQuestID, NextQuestID, ExclusiveGroup, MaxLevel, AllowableClasses, " ..
        "SourceSpellID, RewardMailTemplateID, RequiredSkillID, RequiredSkillPoints, " ..
        "RequiredMinRepFaction, RequiredMinRepValue, SpecialFlags " ..
        "FROM quest_template_addon WHERE ID = %d", questId
    ))

    local starters = {}
    local sq = WorldDBQuery(string.format("SELECT id FROM creature_queststarter WHERE quest = %d", questId))
    if sq then repeat table.insert(starters, sq:GetUInt32(0)) until not sq:NextRow() end

    local enders = {}
    local eq = WorldDBQuery(string.format("SELECT id FROM creature_questender WHERE quest = %d", questId))
    if eq then repeat table.insert(enders, eq:GetUInt32(0)) until not eq:NextRow() end

    local rewardText = ""
    local orq = WorldDBQuery(string.format("SELECT RewardText FROM quest_offer_reward WHERE ID = %d", questId))
    if orq then rewardText = orq:GetString(0) or "" end

    local locTitle, locDesc, locObj, locCompleted = "", "", "", ""
    local lq = WorldDBQuery(string.format(
        "SELECT Title, Details, Objectives, CompletedText " ..
        "FROM quest_template_locale WHERE ID = %d AND locale = 'frFR'", questId
    ))
    if lq then
        locTitle     = lq:GetString(0) or ""
        locDesc      = lq:GetString(1) or ""
        locObj       = lq:GetString(2) or ""
        locCompleted = lq:GetString(3) or ""
    end

    local result = {
        ID = qt:GetUInt32(0), QuestType = qt:GetUInt8(1), QuestLevel = qt:GetInt16(2),
        MinLevel = qt:GetUInt8(3), QuestSortID = qt:GetInt16(4), QuestInfoID = qt:GetUInt16(5),
        SuggestedGroupNum = qt:GetUInt8(6), RewardXPDifficulty = qt:GetUInt8(7),
        RewardMoney = qt:GetInt32(8), RewardBonusMoney = qt:GetUInt32(9),
        RewardSpell = qt:GetInt32(10), Flags = qt:GetUInt32(11),
        TimeAllowed = qt:GetUInt32(12), AllowableRaces = qt:GetUInt32(13),
        LogTitle = qt:GetString(14) or "", LogDescription = qt:GetString(15) or "",
        QuestDescription = qt:GetString(16) or "", AreaDescription = qt:GetString(17) or "",
        QuestCompletionLog = qt:GetString(18) or "",
        ReqNpc1 = qt:GetInt32(19), ReqNpc2 = qt:GetInt32(20),
        ReqNpc3 = qt:GetInt32(21), ReqNpc4 = qt:GetInt32(22),
        ReqNpcCount1 = qt:GetUInt16(23), ReqNpcCount2 = qt:GetUInt16(24),
        ReqNpcCount3 = qt:GetUInt16(25), ReqNpcCount4 = qt:GetUInt16(26),
        ReqItem1 = qt:GetUInt32(27), ReqItem2 = qt:GetUInt32(28),
        ReqItem3 = qt:GetUInt32(29), ReqItem4 = qt:GetUInt32(30),
        ReqItemCount1 = qt:GetUInt16(31), ReqItemCount2 = qt:GetUInt16(32),
        ReqItemCount3 = qt:GetUInt16(33), ReqItemCount4 = qt:GetUInt16(34),
        RewItem1 = qt:GetUInt32(35), RewAmount1 = qt:GetUInt16(36),
        RewItem2 = qt:GetUInt32(37), RewAmount2 = qt:GetUInt16(38),
        RewItem3 = qt:GetUInt32(39), RewAmount3 = qt:GetUInt16(40),
        RewItem4 = qt:GetUInt32(41), RewAmount4 = qt:GetUInt16(42),
        RewChoiceItem1 = qt:GetUInt32(43), RewChoiceQty1 = qt:GetUInt16(44),
        RewChoiceItem2 = qt:GetUInt32(45), RewChoiceQty2 = qt:GetUInt16(46),
        RewChoiceItem3 = qt:GetUInt32(47), RewChoiceQty3 = qt:GetUInt16(48),
        ObjText1 = qt:GetString(49) or "", ObjText2 = qt:GetString(50) or "",
        ObjText3 = qt:GetString(51) or "", ObjText4 = qt:GetString(52) or "",
        RewardTitle = qt:GetUInt8(53), RewardTalents = qt:GetUInt8(54),
        RewardArenaPoints = qt:GetUInt16(55),
        RewFactionID1 = qt:GetUInt16(56), RewFactionVal1 = qt:GetInt32(57),
        RewFactionID2 = qt:GetUInt16(58), RewFactionVal2 = qt:GetInt32(59),
        PrevQuestID = addon and addon:GetInt32(0) or 0,
        NextQuestID = addon and addon:GetUInt32(1) or 0,
        ExclusiveGroup = addon and addon:GetInt32(2) or 0,
        MaxLevel = addon and addon:GetUInt8(3) or 0,
        AllowableClasses = addon and addon:GetUInt32(4) or 0,
        SourceSpellID = addon and addon:GetUInt32(5) or 0,
        RewardMailTemplateID = addon and addon:GetUInt32(6) or 0,
        RequiredSkillID = addon and addon:GetUInt16(7) or 0,
        RequiredSkillPoints = addon and addon:GetUInt16(8) or 0,
        ReqMinRepFaction = addon and addon:GetUInt16(9) or 0,
        ReqMinRepValue = addon and addon:GetInt32(10) or 0,
        SpecialFlags = addon and addon:GetUInt8(11) or 0,
        Starters = starters, Enders = enders,
        RewardText = rewardText,
        LocTitle = locTitle, LocDesc = locDesc,
        LocObj = locObj, LocCompleted = locCompleted,
    }

    AIO.Handle(player, "QuestCreatorAIO", "ReceiveQuestData", result)
end

function QuestHandlers.SaveQuest(player, data)
    if not IsAllowed(player) then return end

    if not data then return end

    local isNew   = (not data.ID or tonumber(data.ID) == 0)
    local questId = isNew and GetNextQuestID() or tonumber(data.ID)

    local function def(v, d) local n = tonumber(v); return (n ~= nil) and n or (d or 0) end
    local function defStr(v) return EscapeSQL(v or "") end

    WorldDBExecute(string.format([[
REPLACE INTO `quest_template` (
    `ID`,`QuestType`,`QuestLevel`,`MinLevel`,`QuestSortID`,`QuestInfoID`,
    `SuggestedGroupNum`,`RewardXPDifficulty`,`RewardMoney`,`RewardBonusMoney`,
    `RewardSpell`,`Flags`,`TimeAllowed`,`AllowableRaces`,
    `LogTitle`,`LogDescription`,`QuestDescription`,`AreaDescription`,`QuestCompletionLog`,
    `RequiredNpcOrGo1`,`RequiredNpcOrGo2`,`RequiredNpcOrGo3`,`RequiredNpcOrGo4`,
    `RequiredNpcOrGoCount1`,`RequiredNpcOrGoCount2`,`RequiredNpcOrGoCount3`,`RequiredNpcOrGoCount4`,
    `RequiredItemId1`,`RequiredItemId2`,`RequiredItemId3`,`RequiredItemId4`,
    `RequiredItemCount1`,`RequiredItemCount2`,`RequiredItemCount3`,`RequiredItemCount4`,
    `RewardItem1`,`RewardAmount1`,`RewardItem2`,`RewardAmount2`,
    `RewardItem3`,`RewardAmount3`,`RewardItem4`,`RewardAmount4`,
    `RewardChoiceItemID1`,`RewardChoiceItemQuantity1`,
    `RewardChoiceItemID2`,`RewardChoiceItemQuantity2`,
    `RewardChoiceItemID3`,`RewardChoiceItemQuantity3`,
    `ObjectiveText1`,`ObjectiveText2`,`ObjectiveText3`,`ObjectiveText4`,
    `RewardTitle`,`RewardTalents`,`RewardArenaPoints`,
    `RewardFactionID1`,`RewardFactionValue1`,
    `RewardFactionID2`,`RewardFactionValue2`,
    `VerifiedBuild`
) VALUES (
    %d,%d,%d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    '%s','%s','%s','%s','%s',
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,%d,%d,
    %d,%d,
    %d,%d,
    %d,%d,
    '%s','%s','%s','%s',
    %d,%d,%d,
    %d,%d,
    %d,%d,
    0
)]],
        questId,
        def(data.QuestType,2), def(data.QuestLevel,1), def(data.MinLevel,0),
        def(data.QuestSortID,0), def(data.QuestInfoID,0),
        def(data.SuggestedGroupNum,0), def(data.RewardXPDifficulty,0),
        def(data.RewardMoney,0), def(data.RewardBonusMoney,0),
        def(data.RewardSpell,0), def(data.Flags,0),
        def(data.TimeAllowed,0), def(data.AllowableRaces,0),
        defStr(data.LogTitle), defStr(data.LogDescription),
        defStr(data.QuestDescription), defStr(data.AreaDescription),
        defStr(data.QuestCompletionLog),
        def(data.ReqNpc1,0), def(data.ReqNpc2,0), def(data.ReqNpc3,0), def(data.ReqNpc4,0),
        def(data.ReqNpcCount1,0), def(data.ReqNpcCount2,0), def(data.ReqNpcCount3,0), def(data.ReqNpcCount4,0),
        def(data.ReqItem1,0), def(data.ReqItem2,0), def(data.ReqItem3,0), def(data.ReqItem4,0),
        def(data.ReqItemCount1,0), def(data.ReqItemCount2,0), def(data.ReqItemCount3,0), def(data.ReqItemCount4,0),
        def(data.RewItem1,0), def(data.RewAmount1,0), def(data.RewItem2,0), def(data.RewAmount2,0),
        def(data.RewItem3,0), def(data.RewAmount3,0), def(data.RewItem4,0), def(data.RewAmount4,0),
        def(data.RewChoiceItem1,0), def(data.RewChoiceQty1,0),
        def(data.RewChoiceItem2,0), def(data.RewChoiceQty2,0),
        def(data.RewChoiceItem3,0), def(data.RewChoiceQty3,0),
        defStr(data.ObjText1), defStr(data.ObjText2), defStr(data.ObjText3), defStr(data.ObjText4),
        def(data.RewardTitle,0), def(data.RewardTalents,0), def(data.RewardArenaPoints,0),
        def(data.RewFactionID1,0), def(data.RewFactionVal1,0),
        def(data.RewFactionID2,0), def(data.RewFactionVal2,0)
    ))

    WorldDBExecute(string.format([[
REPLACE INTO `quest_template_addon` (
    `ID`,`MaxLevel`,`AllowableClasses`,`SourceSpellID`,
    `PrevQuestID`,`NextQuestID`,`ExclusiveGroup`,
    `RewardMailTemplateID`,`RewardMailDelay`,
    `RequiredSkillID`,`RequiredSkillPoints`,
    `RequiredMinRepFaction`,`RequiredMaxRepFaction`,
    `RequiredMinRepValue`,`RequiredMaxRepValue`,
    `ProvidedItemCount`,`SpecialFlags`
) VALUES (%d,%d,%d,%d, %d,%d,%d, %d,0, %d,%d, %d,0, %d,0, 0,%d)]],
        questId,
        def(data.MaxLevel,0), def(data.AllowableClasses,0), def(data.SourceSpellID,0),
        def(data.PrevQuestID,0), def(data.NextQuestID,0), def(data.ExclusiveGroup,0),
        def(data.RewardMailTemplateID,0),
        def(data.RequiredSkillID,0), def(data.RequiredSkillPoints,0),
        def(data.ReqMinRepFaction,0), def(data.ReqMinRepValue,0),
        def(data.SpecialFlags,0)
    ))

    if data.RewardText and data.RewardText ~= "" then
        WorldDBExecute(string.format(
            "REPLACE INTO `quest_offer_reward` (`ID`,`RewardText`,`VerifiedBuild`) VALUES (%d,'%s',0)",
            questId, defStr(data.RewardText)
        ))
    end

    WorldDBExecute(string.format("DELETE FROM `creature_queststarter` WHERE `quest` = %d", questId))
    if data.Starters and type(data.Starters) == "table" then
        for _, npcId in ipairs(data.Starters) do
            local id = tonumber(npcId)
            if id and id > 0 then
                WorldDBExecute(string.format(
                    "INSERT IGNORE INTO `creature_queststarter` (`id`,`quest`) VALUES (%d,%d)", id, questId
                ))
            end
        end
    end

    WorldDBExecute(string.format("DELETE FROM `creature_questender` WHERE `quest` = %d", questId))
    if data.Enders and type(data.Enders) == "table" then
        for _, npcId in ipairs(data.Enders) do
            local id = tonumber(npcId)
            if id and id > 0 then
                WorldDBExecute(string.format(
                    "INSERT IGNORE INTO `creature_questender` (`id`,`quest`) VALUES (%d,%d)", id, questId
                ))
            end
        end
    end

    local hasLocale = (data.LocTitle and data.LocTitle ~= "") or
                      (data.LocDesc  and data.LocDesc  ~= "") or
                      (data.LocObj   and data.LocObj   ~= "") or
                      (data.LocCompleted and data.LocCompleted ~= "")
    if hasLocale then
        WorldDBExecute(string.format(
            "REPLACE INTO `quest_template_locale` " ..
            "(`ID`,`locale`,`Title`,`Details`,`Objectives`,`CompletedText`,`VerifiedBuild`) " ..
            "VALUES (%d,'frFR','%s','%s','%s','%s',0)",
            questId, defStr(data.LocTitle), defStr(data.LocDesc),
            defStr(data.LocObj), defStr(data.LocCompleted)
        ))
    end

    player:SendBroadcastMessage(string.format(
        "|cff00ff00[QuestCreator]|r Quête #%d sauvegardée ! Tapez |cffffd700.reload quest_template|r pour l'activer.",
        questId
    ))

    AIO.Handle(player, "QuestCreatorAIO", "SaveSuccess", {
        id    = questId,
        title = data.LogTitle or ("Quête #" .. questId),
        isNew = isNew,
    })
end

function QuestHandlers.DeleteQuest(player, data)
    if not IsAllowed(player) then return end

    if not data or not data.id then return end
    local questId = tonumber(data.id)
    if not questId or questId <= 0 then return end

    WorldDBExecute(string.format("DELETE FROM `quest_template`            WHERE `ID`    = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `quest_template_addon`      WHERE `ID`    = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `quest_template_locale`     WHERE `ID`    = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `quest_offer_reward`        WHERE `ID`    = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `quest_offer_reward_locale` WHERE `ID`    = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `creature_queststarter`     WHERE `quest` = %d", questId))
    WorldDBExecute(string.format("DELETE FROM `creature_questender`       WHERE `quest` = %d", questId))

    player:SendBroadcastMessage(string.format("|cffff4444[QuestCreator]|r Quête #%d supprimée.", questId))
    AIO.Handle(player, "QuestCreatorAIO", "DeleteSuccess", {id = questId})
end

-- ============================================================
print("[QuestCreatorAIO] Serveur chargé — commande : .questcreator")