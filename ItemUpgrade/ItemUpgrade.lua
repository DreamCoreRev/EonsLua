-- ╔══════════════════════════════════════════════════════════╗
-- ║       RANDOM BONUS STATS SYSTEM - Eluna TrinityCore      ║
-- ║    3.3.5 — Affichage via SetEnchantment (DBC custom)     ║
-- ║    v17 — Fix SetEnchantment sur items en sac (IsInWorld) ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- HISTORIQUE DES FIXES :
-- v13 : suppression item:SaveToDB() qui corrompait les items en sac
-- v15 : délai LOGIN_DELAY pour attendre init C++ des items
-- v16 : GetStateMap() → GetPlayerByGUID() ; slots 5/6 → 0/1
-- v17 : CAUSE RACINE TROUVÉE :
--   TrinityCore Item::SetEnchantment() vérifie IsInWorld() en interne.
--   Les items en SAC (backpack, sacs équipés) ne sont PAS "in world" →
--   SetEnchantment() retourne false systématiquement sur eux.
--   Seuls les items ÉQUIPÉS (bag=255, slots 0-18) sont in world.
--
--   Nouvelle logique :
--   - On SAUVEGARDE le bonus en DB pour TOUS les items éligibles (loot/craft).
--   - On APPLIQUE SetEnchantment UNIQUEMENT sur les items équipés (slots 0-18).
--   - Au LOGIN et MAP_CHANGE : on ne ré-applique que sur les slots équipés.
--   - À l'ÉQUIPEMENT (ON_EQUIP) : l'item vient d'être mis in world → on applique.
--   - En sac : les stats sont stockées en DB, visibles dès l'équipement.
--
-- Slots d'équipement WotLK (bag=255, slots 0-18) = IsInWorld() → SetEnchantment OK
-- Slots backpack/sacs (bag=255 slots 23-38, bag=19-22) = NOT IsInWorld() → FAIL

-- ─────────────────────────────────────────────
-- IDs D'ÉVÉNEMENTS
-- ─────────────────────────────────────────────
local PLAYER_EVENT_ON_LOGIN      = 3
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_EQUIP      = 29
local PLAYER_EVENT_ON_LOOT_ITEM  = 32
local PLAYER_EVENT_ON_MAP_CHANGE = 28

-- ─────────────────────────────────────────────
-- CONFIGURATION
-- ─────────────────────────────────────────────
local MIN_QUALITY   = 2
local VALID_CLASSES = { [2] = true, [4] = true }

local ENCHANT_SLOT_1 = 0   -- PERM_ENCHANTMENT_SLOT
local ENCHANT_SLOT_2 = 1   -- TEMP_ENCHANTMENT_SLOT

local CRAFT_DELAY_1  = 400
local CRAFT_DELAY_2  = 2000
local LOGIN_DELAY    = 500

-- ─────────────────────────────────────────────
-- MÉTIERS vérifiés depuis skillline.sql
-- ─────────────────────────────────────────────
local PROFESSION_SKILLS = {
    [164]=true,[165]=true,[171]=true,[182]=true,
    [186]=true,[197]=true,[202]=true,[333]=true,
    [393]=true,[755]=true,[773]=true,[807]=true,
    [129]=true,[185]=true,[356]=true,
}

local function PlayerHasProfession(player)
    for skillId in pairs(PROFESSION_SKILLS) do
        local ok, val = pcall(function() return player:GetSkillValue(skillId) end)
        if not ok then return false end
        if ok and val and val > 0 then return true end
    end
    return false
end

-- ─────────────────────────────────────────────
-- STAT POOL
-- ─────────────────────────────────────────────
local STAT_POOL = {
    { id = 0,  name = "Mana",                 min = 10, max = 80  },
    { id = 1,  name = "Santé",                min = 10, max = 80  },
    { id = 3,  name = "Agilité",              min = 3,  max = 25  },
    { id = 4,  name = "Force",                min = 3,  max = 25  },
    { id = 5,  name = "Intellect",            min = 3,  max = 25  },
    { id = 6,  name = "Endurance",            min = 3,  max = 25  },
    { id = 7,  name = "Esprit",               min = 3,  max = 25  },
    { id = 12, name = "Puissance d'attaque",  min = 5,  max = 40  },
    { id = 13, name = "Puissance des sorts",  min = 5,  max = 40  },
    { id = 14, name = "Soins",                min = 5,  max = 40  },
    { id = 15, name = "Mana/5sec",            min = 2,  max = 15  },
    { id = 16, name = "Armure bonus",         min = 10, max = 100 },
    { id = 17, name = "Résistance Feu",       min = 3,  max = 20  },
    { id = 18, name = "Résistance Nature",    min = 3,  max = 20  },
    { id = 19, name = "Résistance Givre",     min = 3,  max = 20  },
    { id = 20, name = "Résistance Ombre",     min = 3,  max = 20  },
    { id = 21, name = "Résistance Arcane",    min = 3,  max = 20  },
    { id = 31, name = "Critique mêlée",       min = 2,  max = 20  },
    { id = 32, name = "Critique distance",    min = 2,  max = 20  },
    { id = 33, name = "Critique sorts",       min = 2,  max = 20  },
    { id = 35, name = "Toucher mêlée",        min = 2,  max = 20  },
    { id = 36, name = "Toucher distance",     min = 2,  max = 20  },
    { id = 37, name = "Toucher sorts",        min = 2,  max = 20  },
    { id = 38, name = "Hâte mêlée",           min = 2,  max = 20  },
    { id = 39, name = "Hâte distance",        min = 2,  max = 20  },
    { id = 40, name = "Hâte sorts",           min = 2,  max = 20  },
    { id = 44, name = "Esquive",              min = 2,  max = 20  },
    { id = 45, name = "Parade",               min = 2,  max = 20  },
    { id = 46, name = "Blocage",              min = 2,  max = 20  },
    { id = 49, name = "Expertise",            min = 2,  max = 15  },
    { id = 51, name = "Dégâts de Givre",      min = 5,  max = 45  },
    { id = 52, name = "Dégâts de Feu",        min = 5,  max = 45  },
    { id = 53, name = "Dégâts de Nature",     min = 5,  max = 45  },
    { id = 54, name = "Dégâts d'Ombre",       min = 5,  max = 45  },
    { id = 55, name = "Dégâts d'Arcane",      min = 5,  max = 45  },
    { id = 56, name = "Dégâts de Sacré",      min = 5,  max = 45  },
    { id = 57, name = "Dégâts Physiques",     min = 5,  max = 45  },
}

local STAT_MIN   = {}
local STAT_NAMES = {}
for _, s in ipairs(STAT_POOL) do
    STAT_MIN[s.id]   = s.min
    STAT_NAMES[s.id] = s.name
end

-- ─────────────────────────────────────────────
-- CALCUL ID ENCHANT DBC
-- ─────────────────────────────────────────────
local function GetEnchantId(statId, value)
    return 60000 + (statId * 100) + (value - (STAT_MIN[statId] or 1))
end

-- ─────────────────────────────────────────────
-- UTILITAIRES
-- ─────────────────────────────────────────────
local function ShouldGetBonus(item)
    if not item then return false end
    if item:GetQuality() < MIN_QUALITY then return false end
    if not VALID_CLASSES[item:GetClass()] then return false end
    return true
end

local function RollTwoStats()
    local pool = {}
    for _, s in ipairs(STAT_POOL) do pool[#pool + 1] = s end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local s1, s2 = pool[1], pool[2]
    return s1, math.random(s1.min, s1.max), s2, math.random(s2.min, s2.max)
end

-- ─────────────────────────────────────────────
-- HELPER : retrouver un joueur en ligne par son GUIDLow
-- ─────────────────────────────────────────────
local function GetOnlinePlayer(playerLow)
    local ok, p = pcall(function() return GetPlayerByGUID(playerLow) end)
    if not ok or not p then return nil end
    return p
end

-- ─────────────────────────────────────────────
-- HELPER : vérifier si un item est dans un slot d'équipement
-- (bag=255, slots 0-18 = IsInWorld() → SetEnchantment() fonctionne)
-- ─────────────────────────────────────────────
local function IsEquipped(player, item)
    for slot = 0, 18 do
        local equipped = player:GetItemByPos(255, slot)
        if equipped and equipped:GetGUIDLow() == item:GetGUIDLow() then
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────
-- PERSISTANCE SQL
-- ─────────────────────────────────────────────
local function SaveBonus(itemGuid, ownerGuid, s1, v1, s2, v2)
    CharDBExecute(string.format(
        "REPLACE INTO `item_bonus_stats` " ..
        "(`item_guid`,`owner_guid`,`stat1_type`,`stat1_val`,`stat2_type`,`stat2_val`) " ..
        "VALUES (%d,%d,%d,%d,%d,%d)",
        itemGuid, ownerGuid, s1.id, v1, s2.id, v2
    ))
end

local function LoadBonus(itemGuid)
    local q = CharDBQuery(string.format(
        "SELECT `stat1_type`,`stat1_val`,`stat2_type`,`stat2_val` " ..
        "FROM `item_bonus_stats` WHERE `item_guid`=%d LIMIT 1",
        itemGuid
    ))
    if not q then return nil end
    return {
        stat1_type = q:GetUInt32(0),
        stat1_val  = q:GetInt32(1),
        stat2_type = q:GetUInt32(2),
        stat2_val  = q:GetInt32(3),
    }
end

-- ─────────────────────────────────────────────
-- APPLICATION DES ENCHANTS
-- Appelé UNIQUEMENT sur items équipés (IsInWorld = true).
-- Sur items en sac : on sauvegarde en DB, SetEnchantment sera appelé à l'équipement.
-- ─────────────────────────────────────────────
local function ApplyEnchantToEquippedItem(item, s1id, v1, s2id, v2)
    local enchId1 = GetEnchantId(s1id, v1)
    local enchId2 = GetEnchantId(s2id, v2)
    item:SetEnchantment(enchId1, ENCHANT_SLOT_1)
    item:SetEnchantment(enchId2, ENCHANT_SLOT_2)
end

local function NotifyPlayer(player, item, s1name, v1, s2name, v2)
    player:SendBroadcastMessage(string.format(
        "|cff00ff00[Bonus Stats]|r |cffffd700%s|r a reçu des bonus :",
        item:GetName()))
    player:SendBroadcastMessage(string.format("  |cff1eff00+ %d %s|r", v1, s1name))
    player:SendBroadcastMessage(string.format("  |cff1eff00+ %d %s|r", v2, s2name))
end

-- ─────────────────────────────────────────────
-- LOGIQUE PRINCIPALE
-- ─────────────────────────────────────────────

-- Appelé lors d'un loot ou craft : on sauvegarde le bonus en DB.
-- SetEnchantment sera appliqué à l'équipement.
local function AssignBonusToItem(player, item)
    if not item then return end
    if not ShouldGetBonus(item) then return end
    local itemGuid  = item:GetGUIDLow()
    local ownerGuid = player:GetGUIDLow()

    -- Déjà un bonus assigné ? Ne pas ré-assigner.
    local existing = LoadBonus(itemGuid)
    if existing then return end

    local s1, v1, s2, v2 = RollTwoStats()
    SaveBonus(itemGuid, ownerGuid, s1, v1, s2, v2)
    NotifyPlayer(player, item, s1.name, v1, s2.name, v2)
end

-- Appelé UNIQUEMENT sur un item équipé (IsInWorld) : applique l'enchant visuel.
local function ApplyBonusToEquippedItem(player, item)
    if not item then return end
    local data = LoadBonus(item:GetGUIDLow())
    if not data then return end
    ApplyEnchantToEquippedItem(item,
        data.stat1_type, data.stat1_val,
        data.stat2_type, data.stat2_val)
end

-- ─────────────────────────────────────────────
-- ITÉRATEURS
-- ─────────────────────────────────────────────

-- Itère uniquement sur les slots d'équipement (IsInWorld = true)
local function ForEachEquippedItem(player, callback)
    for slot = 0, 18 do
        local item = player:GetItemByPos(255, slot)
        if item then callback(item) end
    end
end

-- Itère sur TOUT l'inventaire (équipement + sacs)
local function ForEachInventoryItem(player, callback)
    for slot = 0, 38 do
        local item = player:GetItemByPos(255, slot)
        if item then callback(item) end
    end
    for bag = 19, 22 do
        for slot = 0, 35 do
            local item = player:GetItemByPos(bag, slot)
            if item then callback(item) end
        end
    end
end

-- ─────────────────────────────────────────────
-- SNAPSHOT ET DÉTECTION CRAFT
-- ─────────────────────────────────────────────
local CRAFT_SNAPSHOT = {}

local function SnapshotInventory(player)
    local snap = {}
    ForEachInventoryItem(player, function(item)
        snap[item:GetGUIDLow()] = true
    end)
    return snap
end

local function CheckNewItems(player, snap)
    local found = false
    ForEachInventoryItem(player, function(item)
        if not snap[item:GetGUIDLow()] then
            AssignBonusToItem(player, item)
            found = true
        end
    end)
    return found
end

-- ─────────────────────────────────────────────
-- HOOKS
-- ─────────────────────────────────────────────

-- 1) LOOT : assigne le bonus en DB (pas d'enchant, item en sac)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOOT_ITEM, function(event, player, item, count)
    AssignBonusToItem(player, item)
end)

-- 2) CRAFT : snapshot avant, détecte les nouveaux items après
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, function(event, player, spell, skipCheck)
    local ok, playerLow = pcall(function() return player:GetGUIDLow() end)
    if not ok or not playerLow then return end

    if not PlayerHasProfession(player) then return end

    local snapOk, snap = pcall(SnapshotInventory, player)
    if not snapOk or not snap then return end
    CRAFT_SNAPSHOT[playerLow] = snap

    CreateLuaEvent(function()
        local s = CRAFT_SNAPSHOT[playerLow]
        if not s then return end
        local p = GetOnlinePlayer(playerLow)
        if p then
            if CheckNewItems(p, s) then
                CRAFT_SNAPSHOT[playerLow] = nil
            end
        end
    end, CRAFT_DELAY_1, 1)

    CreateLuaEvent(function()
        local s = CRAFT_SNAPSHOT[playerLow]
        if not s then return end
        local p = GetOnlinePlayer(playerLow)
        if p then CheckNewItems(p, s) end
        CRAFT_SNAPSHOT[playerLow] = nil
    end, CRAFT_DELAY_2, 1)
end)

-- 3) ÉQUIPEMENT : l'item vient d'être mis in world → appliquer l'enchant maintenant
RegisterPlayerEvent(PLAYER_EVENT_ON_EQUIP, function(event, player, item, bag, slot)
    -- D'abord assigner un bonus si l'item n'en a pas encore
    AssignBonusToItem(player, item)
    -- Puis appliquer l'enchant (item est maintenant in world)
    ApplyBonusToEquippedItem(player, item)
end)

-- 4) MAP CHANGE : ré-appliquer les enchants sur les items équipés uniquement
RegisterPlayerEvent(PLAYER_EVENT_ON_MAP_CHANGE, function(event, player)
    CRAFT_SNAPSHOT[player:GetGUIDLow()] = nil
    ForEachEquippedItem(player, function(item)
        ApplyBonusToEquippedItem(player, item)
    end)
end)

-- 5) LOGIN : délai puis ré-application sur items équipés uniquement
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, function(event, player)
    local playerLow = player:GetGUIDLow()
    CreateLuaEvent(function()
        local p = GetOnlinePlayer(playerLow)
        if not p then return end
        ForEachEquippedItem(p, function(item)
            ApplyBonusToEquippedItem(p, item)
        end)
    end, LOGIN_DELAY, 1)
end)
