--[[
    Paragon Hook System

    Manages all server-side event hooks and client-server communication for the
    paragon system. Handles player login/logout, experience gains, and statistic
    updates through event handlers and addon communication.

    Responsibilities:
    - Player login/logout lifecycle management
    - Experience gain distribution from various sources
    - Statistic point allocation and reallocation
    - Client-server addon communication
    - Event registration for ALE/Eluna

    Architecture:
    - Event-driven design with Mediator pattern
    - Server events trigger paragon state updates
    - Client packets processed through addon functions
    - Statistics applied/removed atomically

    Fixes applied:
    1. Removed RegisterPlayerEvent(62) — event ID 62 does not exist in Eluna TrinityWotlk.
    2. Removed GetPlayersInWorld() calls in OnLuaStateOpen/Close — not available in
       per-map Lua states (state 0, 1, 530, 571...).
    3. HandleStatFlatModifier → Unit:AddFlatStatModifier — HandleStatFlatModifier is an
       internal C++ method not exposed in the Eluna API for TrinityWotlk.
    4. ApplyRatingMod → Unit:AddFlatStatModifier — ApplyRatingMod is also not exposed
       in the Eluna API. COMBAT_RATING stats are applied as flat modifiers on the
       appropriate stat type using UnitModifierFlatType = 0 (BASE_VALUE).
    5. FIX ASYNC TIMING — Added PendingExperience queue per player GUID.
       When OnPlayerKillCreature fires before the async DB load completes,
       the kill entry is stored in the queue. Once OnPlayerStatLoad fires
       (DB load done, SetData called), the queue is flushed automatically.
    6. FIX EVENT ID — RegisterPlayerEvent(5) → (7): event 5 = on_spell_cast,
       event 7 = on_kill_creature.
    7. FIX CACHE ROOT CAUSE — player:SetData / GetData stocke l'objet Lua sur
       le pointeur C++ du joueur. Au logout, ce pointeur est en cours de
       destruction : GetData retourne nil → Save() n'est jamais appelé →
       la progression n'est jamais écrite en DB.
       SOLUTION : ParagonCache et PendingQueue sont désormais des tables Lua
       locales (module-level) indexées par guid_low. Elles survivent au logout
       et sont explicitement vidées (CacheClear) après sauvegarde.
    8. FIX SAVE PERIODIC — Ajout de Hook.OnPlayerSave (event 26) : sauvegarde
       périodique pendant la session, indépendante du logout.
    9. FIX CACHE SYNC — CacheSet() dans OnPlayerLogout après retour Mediator.
    11. FIX STAT ALLOCATION STALE CACHE — OnParagonClientSendStatistics ne doit PAS
        se fier uniquement à CacheGet(). Dans Eluna multi-state (cross-map), le cache
        peut contenir un objet stale (ex: level=11) alors que la DB a level=12 après
        un gain de niveau survenu sur une map différente. Ce décalage provoque
        "UpdateParagonPoints: points insuffisants" (available=0) et un SaveSync qui
        écrase la DB avec les valeurs de l'objet stale. Fix : OnParagonClientSendStatistics
        recharge toujours depuis la DB (comme UpdatePlayerExperience) avant de traiter
        l'allocation de points.
    10. FIX LOGOUT STALE CACHE — OnPlayerLogout ne doit PAS passer par
        LoadParagonSync() car _G.ParagonCache peut contenir un objet stale
        (level=1) venant d'un Lua state différent (cross-map).
        La DB est la seule source de vérité partagée entre tous les states.
        OnPlayerLogout charge directement depuis la DB via LoadParagonFromDB()
        sans consulter le cache.
    13. FIX CREATURE POINTER INVALIDATION — creature:GetEntry() à la ligne 1002 levait
        "calling 'GetEntry' on bad self (Creature expected, got pointer to nonexisting
        (invalidated) object)". Le pointeur C++ de la créature peut être détruit par
        TrinityCore (despawn immédiat) avant l'exécution du hook Lua. Fix : pcall autour
        de creature:GetEntry() dans Hook.OnPlayerKillCreature. Si le pointeur est invalide,
        la fonction retourne silencieusement sans appeler UpdatePlayerExperience.

    12. FIX QUEST EVENT — on_quest_status_changed (event 54) : cet event se declenche
        a chaque changement de statut de quete (acceptation, abandon, completion...).
        Le parametre `status` vaut 1 (QUEST_STATUS_COMPLETE) uniquement a la completion.
        Fix : guard `if status ~= 1 then return end` dans Hook.OnPlayerQuestComplete
        pour ne declencher XP Paragon qua la vraie completion de quete.

    Eluna API reference for stat modifiers:
      Unit:AddFlatStatModifier(statType, unitModType, value)
        - statType    : integer from Stats enum (0=Strength, 1=Agility, etc.)
        - unitModType : 0 = BASE_VALUE, 1 = BASE_PCT, 2 = TOTAL_VALUE, 3 = TOTAL_PCT
        - value       : positive to add, negative to remove
      Unit:AddPctStatModifier(statType, unitModType, value)
        - same params, but value is a percentage

    @module paragon_hook
    @author iThorgrim
    @license AGL v3
]]

local Paragon = require("paragon_class")
local Config = require("paragon_config")
local Repository = require("paragon_repository")
local Constant = require("paragon_constant")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local Hook = {
    Addon = {
        Prefix = "ParagonAnniversary",
        Functions = {
            [1] = "OnParagonClientLoadRequest",
            [2] = "OnParagonClientSendStatistics"
        }
    }
}

-- Experience source type enumeration
local EXPERIENCE_SOURCE = {
    CREATURE = 1,
    ACHIEVEMENT = 2,
    SKILL = 3,
    QUEST = 4
}

-- ============================================================================
-- PARAGON CACHE — table _G GLOBALE partagée entre tous les Lua states
--
-- PROBLÈME RACINE : Eluna TrinityWotlk crée un état Lua par map-thread.
-- Une table `local` n'existe que dans le Lua state qui l'a créée.
-- OnPlayerLogin (map 0) et OnPlayerKillCreature (map 1, 530, 571...)
-- s'exécutent dans des états Lua DIFFÉRENTS avec chacun leur propre
-- ParagonCache local → ils ne voient jamais les données de l'autre.
--
-- SetData/GetData ne sérialise pas les tables Lua entre états.
--
-- SOLUTION : _G.ParagonCache — la table _G est l'environnement global Lua.
-- Dans Eluna, tous les Lua states per-map PARTAGENT le même _G.
-- Une valeur écrite dans _G depuis map 0 est visible depuis map 571.
--
-- IMPORTANT LOGOUT : _G.ParagonCache peut contenir un objet stale si le
-- joueur a gagné des niveaux sur une autre map. Au logout, on lit toujours
-- depuis la DB (source de vérité unique, synchronisée à chaque SaveSync).
-- ============================================================================

_G.ParagonCache = _G.ParagonCache or {}

local function CacheSet(player, paragon)
    local guid_low = player:GetGUIDLow()
    -- print("[Paragon CACHE] CacheSet | guid_low=" .. tostring(guid_low) .. " | level=" .. tostring(paragon and paragon:GetLevel()))
    _G.ParagonCache[guid_low] = paragon
end

local function CacheGet(player)
    -- FIX : player peut être un pointeur C++ invalidé (objet détruit au logout/déco).
    -- On protège l'appel GetGUIDLow() avec pcall pour éviter le crash Eluna.
    local ok, guid_low = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid_low then
        -- print("[Paragon CACHE] CacheGet | player invalidé — guid_low introuvable")
        return nil
    end
    local result = _G.ParagonCache[guid_low]
    -- print("[Paragon CACHE] CacheGet | guid_low=" .. tostring(guid_low) .. " | found=" .. tostring(result ~= nil) .. (result and (" | level=" .. tostring(result:GetLevel())) or ""))
    return result
end

local function CacheClear(guid_low)
    -- print("[Paragon CACHE] CacheClear | guid_low=" .. tostring(guid_low))
    _G.ParagonCache[guid_low] = nil
end

-- ============================================================================
-- PENDING EXPERIENCE QUEUE
-- Stockée dans une table Lua globale indexée par guid_low.
-- Même raison que ParagonCache : SetData sur l'objet C++ est instable
-- au moment du login async.
-- ============================================================================

local PendingQueue = {}

local function QueuePendingExperience(player, source_type, entry)
    local guid_low = player:GetGUIDLow()
    PendingQueue[guid_low] = PendingQueue[guid_low] or {}
    table.insert(PendingQueue[guid_low], { source_type = source_type, entry = entry })
    -- print("[Paragon DEBUG] QueuePendingExperience | guid_low=" .. tostring(guid_low) .. " | entry=" .. tostring(entry) .. " | qsize=" .. #PendingQueue[guid_low])
end

local function FlushPendingExperience(player, paragon)
    local guid_low = player:GetGUIDLow()
    local queue = PendingQueue[guid_low]

    -- print("[Paragon DEBUG] FlushPendingExperience | player=" .. player:GetName()
        -- .. " | queue=" .. tostring(queue)
        -- .. " | size=" .. (queue and #queue or "nil"))

    if not queue or #queue == 0 then
        -- print("[Paragon DEBUG] Flush: queue vide ou nil")
        return
    end

    -- print("[Paragon] Flushing " .. #queue .. " pending XP entries for " .. player:GetName())
    for i, pending in ipairs(queue) do
        -- print("[Paragon DEBUG] Flush entry " .. i .. " | source_type=" .. tostring(pending.source_type) .. " | entry=" .. tostring(pending.entry))
        Hook._UpdatePlayerExperience(player, paragon, pending.source_type, pending.entry)
    end

    -- Vider la queue après flush
    PendingQueue[guid_low] = nil
end

-- ============================================================================
-- PRIVATE FUNCTIONS
-- ============================================================================

---
--- Retrieves a player object from their GUID low value.
---
--- @param guid_low The low part of the player's GUID
--- @return The player object, or false if not found
---
local function GetPlayerIfExist(guid_low)
    local guid = GetPlayerGUID(guid_low)
    if not guid then
        return false
    end

    local player = GetPlayerByGUID(guid)
    if not player then
        return false
    end

    return player
end

---
--- Synchronously loads a Paragon instance for a player using blocking DB queries.
--- Used in kill/quest/achievement handlers when async load hasn't completed yet.
--- Populates the cache immediately so subsequent kills don't reload from DB.
---
--- NOTE : Cette fonction vérifie _G.ParagonCache en premier et retourne l'objet
--- existant si présent. Ne PAS utiliser au logout — voir LoadParagonFromDB().
---
--- @param player The player object
--- @return The loaded Paragon instance, or nil on failure
---
local function LoadParagonSync(player)
    local guid_low = player:GetGUIDLow()
    local account_id = player:GetAccountId()

    -- FIX CRITIQUE : si ParagonCache contient déjà un objet pour ce joueur,
    -- on le retourne IMMÉDIATEMENT sans recharger depuis la DB.
    -- Recharger depuis la DB ici écraserait les levels gagnés en session
    -- (la DB contient toujours l'ancienne valeur tant que SaveSync n'a pas tourné).
    if _G.ParagonCache[guid_low] then
        -- print("[Paragon DEBUG] LoadParagonSync | player=" .. player:GetName() .. " | cache HIT — retour objet existant level=" .. tostring(_G.ParagonCache[guid_low]:GetLevel()))
        return _G.ParagonCache[guid_low]
    end

    -- print("[Paragon DEBUG] LoadParagonSync | player=" .. player:GetName() .. " | guid_low=" .. tostring(guid_low))

    local paragon = Paragon(guid_low, account_id)

    -- Load level/experience synchronously
    local data = Repository:GetParagonByCharacterSync(guid_low)
    if data and data.level then
        paragon.level = data.level
        paragon.exp.current = data.current_experience or 0
        local base_max_exp = tonumber(Config:GetByField("BASE_MAX_EXPERIENCE")) or 1000
        paragon.exp.max = base_max_exp * paragon.level
    end

    -- Load statistics synchronously
    local stats = Repository:GetParagonStatByCharacterSync(guid_low)
    if stats then
        paragon.statistics = stats
    end

    -- Recalculate points
    local used_points = 0
    for _, v in pairs(paragon.statistics) do used_points = used_points + v end
    local points_per_level = tonumber(Config:GetByField("POINTS_PER_LEVEL")) or 1
    paragon.points = (paragon.level * points_per_level) - used_points

    -- Store in cache for subsequent calls
    CacheSet(player, paragon)
    -- print("[Paragon DEBUG] LoadParagonSync done | level=" .. tostring(paragon.level) .. " | exp=" .. tostring(paragon.exp.current))

    return paragon
end

---
--- Loads a Paragon instance DIRECTLY from the database, bypassing the cache.
---
--- USAGE LOGOUT UNIQUEMENT : Au logout, _G.ParagonCache peut contenir un objet
--- stale issu d'un Lua state différent (ex: map 0 login vs map 571 kills).
--- La DB est la seule source de vérité synchronisée entre tous les Lua states
--- car UpdatePlayerExperience appelle SaveSync (CharDBQuery synchrone) à chaque
--- gain d'XP. Ce chargement garantit la valeur correcte au moment du logout.
---
--- @param player The player object
--- @return The loaded Paragon instance, or nil on failure
---
local function LoadParagonFromDB(player)
    local guid_low = player:GetGUIDLow()
    local account_id = player:GetAccountId()

    -- print("[Paragon DEBUG] LoadParagonFromDB | player=" .. player:GetName() .. " | guid_low=" .. tostring(guid_low) .. " | BYPASS CACHE — lecture DB directe")

    local paragon = Paragon(guid_low, account_id)

    -- Load level/experience synchronously from DB (ignores cache)
    local data = Repository:GetParagonByCharacterSync(guid_low)
    if data and data.level then
        paragon.level = data.level
        paragon.exp.current = data.current_experience or 0
        local base_max_exp = tonumber(Config:GetByField("BASE_MAX_EXPERIENCE")) or 1000
        paragon.exp.max = base_max_exp * paragon.level
    end

    -- Load statistics synchronously
    local stats = Repository:GetParagonStatByCharacterSync(guid_low)
    if stats then
        paragon.statistics = stats
    end

    -- Recalculate points
    local used_points = 0
    for _, v in pairs(paragon.statistics) do used_points = used_points + v end
    local points_per_level = tonumber(Config:GetByField("POINTS_PER_LEVEL")) or 1
    paragon.points = (paragon.level * points_per_level) - used_points

    -- print("[Paragon DEBUG] LoadParagonFromDB done | level=" .. tostring(paragon.level) .. " | exp=" .. tostring(paragon.exp.current))

    return paragon
end

---
--- Applies or removes all paragon statistic modifiers to a player.
---
--- Uses Eluna's Unit:AddFlatStatModifier and Unit:AddPctStatModifier.
--- HandleStatFlatModifier and ApplyRatingMod are C++ internal methods not
--- exposed in the Eluna TrinityWotlk Lua API — they cause nil method errors.
---
--- Stat type mapping (paragon_config stat_data.type):
---   "UNIT_MODS"     → Unit:AddFlatStatModifier(statType, unitModType, value)
---   "COMBAT_RATING" → Unit:AddFlatStatModifier(statType, unitModType, value)
---   "AURA"          → Unit:AddAura / Unit:RemoveAura
---
--- The `apply` boolean controls sign: positive value when applying, negative when removing.
--- stat_data.application maps to unitModType: 0=BASE_VALUE, 2=TOTAL_VALUE (see Constant).
---
--- Mediator Events:
--- - OnBeforeUpdatePlayerStatistics: (player, paragon, apply)
--- - OnAfterUpdatePlayerStatistics: (player, paragon, apply)
---
--- @param player The player object to update
--- @param paragon The paragon instance containing stat data
--- @param apply Boolean indicating whether to apply (true) or remove (false) the bonuses
---
local function UpdatePlayerStatistics(player, paragon, apply)
    if not apply then
        apply = false
    end

    -- Allow modules to hook before statistics are applied/removed
    player, paragon, apply = Mediator.On("OnBeforeUpdatePlayerStatistics", {
        arguments = { player, paragon, apply },
        defaults = { player, paragon, apply },
    })

    local statistics = paragon:GetStatistics()
    if not statistics then
        return
    end

    for stat_id, stat_value in pairs(statistics) do
        if not stat_value or stat_value <= 0 then
            goto continue
        end

        local stat_data = Config:GetByStatId(stat_id)
        if not stat_data then
            goto continue
        end

        local constant_stat_type = Constant.STATISTICS[stat_data.type]
        if not constant_stat_type then
            goto continue
        end

        -- Value is positive when applying, negative when removing
        local effective_value = apply and stat_value or -stat_value

        -- Apply bonus based on statistic type
        -- Unit:AddFlatStatModifier(statType, unitModType, value) — Eluna TrinityWotlk API
        -- Unit:AddPctStatModifier(statType, unitModType, value)  — Eluna TrinityWotlk API
        if stat_data.type == "UNIT_MODS" then
            player:AddFlatStatModifier(
                constant_stat_type[stat_data.value],
                stat_data.application,
                effective_value
            )

        elseif stat_data.type == "COMBAT_RATING" then
            player:AddFlatStatModifier(
                constant_stat_type[stat_data.value],
                stat_data.application or 2,
                effective_value
            )

        elseif stat_data.type == "AURA" then
            if apply then
                for _ = 1, stat_value do
                    player:AddAura(constant_stat_type[stat_data.value], player)
                end
            else
                player:RemoveAura(constant_stat_type[stat_data.value])
            end
        end

        ::continue::
    end

    -- Allow modules to hook after statistics are applied/removed
    Mediator.On("OnAfterUpdatePlayerStatistics", {
        arguments = { player, paragon, apply },
    })
end

-- ============================================================================
-- PLAYER EXPERIENCE MANAGEMENT
-- ============================================================================

---
--- Updates player paragon experience based on activity source.
---
--- @param player The player object
--- @param paragon The paragon instance to update
--- @param source_type The source type (EXPERIENCE_SOURCE enum)
--- @param entry The source entry ID
--- @return boolean True if experience was awarded, false otherwise
---
local function UpdatePlayerExperience(player, paragon, source_type, entry)
    if not player or not source_type or not entry then
        return false
    end

    local min_level = tonumber(Config:GetByField("MINIMUM_LEVEL_FOR_PARAGON_XP")) or 0
    if player:GetLevel() < min_level then
        return false
    end

    -- FIX CROSS-MAP : _G.ParagonCache n'est PAS partagé entre les Lua states
    -- de maps différentes dans Eluna TrinityWotlk. Chaque map-thread a son propre
    -- état Lua isolé. Un CacheSet fait sur map 0 (login) n'est pas visible sur
    -- map 1 (Elwynn Forest). En conséquence :
    --   - Le cache local peut contenir un objet "stale" (level=7 alors que la DB a level=8)
    --   - Deux kills simultanés sur deux maps différentes peuvent se marcher dessus
    --
    -- SOLUTION : on recharge TOUJOURS depuis la DB au début de UpdatePlayerExperience.
    -- La DB est la seule source de vérité partagée entre tous les Lua states.
    -- La DB est garantie à jour car SaveSync (CharDBQuery synchrone) est appelé
    -- à la fin de chaque UpdatePlayerExperience.
    local guid_low = player:GetGUIDLow()
    local account_id = player:GetAccountId()
    local fresh_paragon = Paragon(guid_low, account_id)

    local data = Repository:GetParagonByCharacterSync(guid_low)
    if data and data.level then
        fresh_paragon.level = data.level
        fresh_paragon.exp.current = data.current_experience or 0
        local base_max_exp = tonumber(Config:GetByField("BASE_MAX_EXPERIENCE")) or 1000
        fresh_paragon.exp.max = base_max_exp * fresh_paragon.level
    end

    local stats = Repository:GetParagonStatByCharacterSync(guid_low)
    if stats then
        fresh_paragon.statistics = stats
    end

    -- Recalculate points from DB data
    local used_points = 0
    for _, v in pairs(fresh_paragon.statistics) do used_points = used_points + v end
    local points_per_level = tonumber(Config:GetByField("POINTS_PER_LEVEL")) or 1
    fresh_paragon.points = (fresh_paragon.level * points_per_level) - used_points

    -- Use the freshly loaded paragon from DB
    paragon = fresh_paragon

    -- print("[Paragon DEBUG] UpdatePlayerExperience | DB reload | guid=" .. tostring(guid_low)
        -- .. " | level=" .. tostring(paragon.level)
        -- .. " | exp=" .. tostring(paragon.exp.current)
        -- .. " | points=" .. tostring(paragon.points))

    -- Inject player reference so paragon_class.lua:SetLevel can fire OnParagonLevelChanged
    paragon._player = player

    paragon, source_type, entry = Mediator.On("OnBeforeUpdatePlayerExperience", {
        arguments = { player, paragon, source_type, entry },
        defaults = { paragon, source_type, entry },
    })

    local source_config_map = {
        [EXPERIENCE_SOURCE.CREATURE]    = "UNIVERSAL_CREATURE_EXPERIENCE",
        [EXPERIENCE_SOURCE.ACHIEVEMENT] = "UNIVERSAL_ACHIEVEVEMENT_EXPERIENCE",
        [EXPERIENCE_SOURCE.SKILL]       = "UNIVERSAL_SKILL_EXPERIENCE",
        [EXPERIENCE_SOURCE.QUEST]       = "UNIVERSAL_QUEST_EXPERIENCE"
    }

    local config_key = source_config_map[source_type] or "UNIVERSAL_CREATURE_EXPERIENCE"
    local universal_value = tonumber(Config:GetByField(config_key)) or 0

    if universal_value <= 0 then
        return false
    end

    local source_experience_map = {
        ["UNIVERSAL_CREATURE_EXPERIENCE"]       = Config:GetCreatureExperience(entry),
        ["UNIVERSAL_ACHIEVEVEMENT_EXPERIENCE"]  = Config:GetAchievementExperience(entry),
        ["UNIVERSAL_SKILL_EXPERIENCE"]          = Config:GetSkillExperience(entry),
        ["UNIVERSAL_QUEST_EXPERIENCE"]          = Config:GetQuestExperience(entry)
    }

    local specific_experience = source_experience_map[config_key] or universal_value

    if not specific_experience or specific_experience <= 0 then
        return false
    end

    specific_experience = Mediator.On("OnExperienceCalculated", {
        arguments = { player, paragon, source_type, specific_experience },
        defaults = { specific_experience },
    })

    paragon = Mediator.On("OnUpdatePlayerExperience", {
        arguments = { player, paragon, specific_experience },
        defaults = { paragon }
    })

    Mediator.On("OnParagonStateSync", {
        arguments = { player, paragon },
    })

    -- Update client with new paragon state
    player:SendServerResponse(Hook.Addon.Prefix, 1, paragon:GetLevel())
    player:SendServerResponse(Hook.Addon.Prefix, 4, paragon:GetPoints())
    player:SendServerResponse(Hook.Addon.Prefix, 2, paragon:GetExperience(), paragon:GetExperienceForNextLevel())

    -- Mettre à jour le cache avec l'objet frais après traitement
    CacheSet(player, paragon)

    -- SAVE IMMEDIAT (CharDBQuery synchrone) : garantit que la DB est à jour
    -- avant le prochain appel à UpdatePlayerExperience (qui relit la DB).
    paragon:SaveSync()

    Mediator.On("OnAfterUpdatePlayerExperience", {
        arguments = { player, paragon },
    })

    return true
end

-- Expose UpdatePlayerExperience via Hook so FlushPendingExperience can call it
-- (local functions cannot be forward-referenced in Lua)
Hook._UpdatePlayerExperience = UpdatePlayerExperience
Hook.CacheGet = CacheGet
Hook.CacheSet = CacheSet

-- ============================================================================
-- PLAYER POINTS MANAGEMENT
-- ============================================================================

---
--- Updates a character's paragon statistic investment and available points.
---
--- @param player The player object
--- @param paragon The paragon instance to update
--- @param stat_id The statistic ID to modify
--- @param stat_value The new value to set for the statistic
--- @return boolean True if points were updated, false otherwise
---
local function UpdateParagonPoints(player, paragon, stat_id, stat_value)
    if not player or not paragon or not stat_id or not stat_value then
        return false
    end

    paragon, stat_id, stat_value = Mediator.On("OnBeforeUpdateParagonPoints", {
        arguments = { player, paragon, stat_id, stat_value },
        defaults = { paragon, stat_id, stat_value },
    })

    -- Snapshot de la valeur actuelle AVANT modification
    local old_stat_value = paragon:GetStatValue(stat_id)
    local available_points = paragon:GetPoints()

    -- Calcul du delta : positif = depense de points, negatif = remboursement
    local delta = stat_value - old_stat_value
    available_points = available_points - delta

    -- FIX: le Mediator recoit (stat_id, stat_value, available_points) :
    -- la NOUVELLE valeur cible et les points recalcules.
    -- L'ancienne signature passait old_stat_value en 4e arg ce qui pouvait
    -- confondre les listeners et provoquer un mauvais recalcul.
    paragon, stat_id, stat_value, available_points = Mediator.On("OnUpdateParagonPoints", {
        arguments = { player, paragon, stat_id, stat_value, available_points },
        defaults = { paragon, stat_id, stat_value, available_points },
    })

    -- Points insuffisants : on annule sans recursion (evite stack overflow)
    if available_points < 0 then
        -- print("[Paragon DEBUG] UpdateParagonPoints: points insuffisants | stat_id=" .. tostring(stat_id)
            -- .. " | old=" .. tostring(old_stat_value)
            -- .. " | requested=" .. tostring(stat_value)
            -- .. " | available=" .. tostring(paragon:GetPoints()))
        return false
    end

    -- Apply the stat change
    paragon:SetPoints(available_points)
    paragon:SetStatValue(stat_id, stat_value)

    -- print("[Paragon DEBUG] UpdateParagonPoints | stat_id=" .. tostring(stat_id)
        -- .. " | old=" .. tostring(old_stat_value)
        -- .. " | new=" .. tostring(stat_value)
        -- .. " | points_remaining=" .. tostring(available_points))

    -- Send updated stat to client
    player:SendServerResponse(Hook.Addon.Prefix, 5, {
        id = stat_id,
        value = stat_value,
        category = Config:GetCategoryByStatId(stat_id)
    })

    Mediator.On("OnAfterUpdateParagonPoints", {
        arguments = { player, paragon, stat_id, stat_value }
    })

    return true
end

-- ============================================================================
-- ADDON COMMAND HANDLERS
-- ============================================================================

---
--- Handles client request to load and display all paragon data.
---
--- @param player The player object making the request
--- @param _ Unused parameter
---
function OnParagonClientLoadRequest(player, _)
    if not player then
        return false
    end

    local paragon = CacheGet(player)
    if not paragon then
        -- NE PAS appeler Hook.OnPlayerLogin ici — il contient CacheClear qui efface
        -- _G.ParagonCache, puis recharge la DB (level non sauvé = vieilles données).
        -- LoadParagonSync est sûr : il vérifie _G.ParagonCache avant de toucher la DB.
        paragon = LoadParagonSync(player)
        if not paragon then return false end
    end

    paragon = Mediator.On("OnBeforeClientLoadRequest", {
        arguments = { player, paragon },
        defaults = { paragon },
    })

    local categories = Config:GetCategories()
    if not categories then
        return false
    end

    for _, category_data in pairs(categories) do
        local statistics = category_data.statistics
        if statistics then
            for stat_id, stat_data in pairs(statistics) do
                stat_data.assigned = paragon:GetStatValue(stat_id)
            end
        end
    end

    categories = Mediator.On("OnAfterClientLoadRequest", {
        arguments = { player, paragon, categories },
        defaults = { categories },
    })

    player:SendServerResponse(Hook.Addon.Prefix, 1, paragon:GetLevel())
    player:SendServerResponse(Hook.Addon.Prefix, 2, paragon:GetExperience(), paragon:GetExperienceForNextLevel())
    player:SendServerResponse(Hook.Addon.Prefix, 3, categories)
    player:SendServerResponse(Hook.Addon.Prefix, 4, paragon:GetPoints())

    return true
end

---
--- Handles client request to update paragon statistics.
---
--- @param player The player object making the request
--- @param arg_table Table containing statistics update data
--- @return boolean True if all updates succeeded, false if validation failed
---
function OnParagonClientSendStatistics(player, arg_table)
    if not player or not arg_table then
        return false
    end

    local data = arg_table[1]
    if not data then
        player:SendNotification("ERROR.")
        return false
    end

    -- FIX SYNC : On recharge TOUJOURS depuis la DB ici, comme UpdatePlayerExperience.
    -- Le cache (_G.ParagonCache) peut être stale dans Eluna multi-state (cross-map) :
    -- un CacheSet fait depuis map X n'est pas visible depuis map Y dans certains builds.
    -- La DB est la seule source de vérité fiable (mise à jour via SaveSync synchrone
    -- à chaque kill / gain d'XP). Sans ce rechargement, le paragon récupéré depuis
    -- le cache peut avoir level=11 alors que la DB et le prochain kill voient level=12,
    -- ce qui provoque "points insuffisants" et un SaveSync(level=11) qui écrase la DB.
    local guid_low = player:GetGUIDLow()
    local account_id = player:GetAccountId()
    local paragon = Paragon(guid_low, account_id)

    local db_data = Repository:GetParagonByCharacterSync(guid_low)
    if db_data and db_data.level then
        paragon.level = db_data.level
        paragon.exp.current = db_data.current_experience or 0
        local base_max_exp = tonumber(Config:GetByField("BASE_MAX_EXPERIENCE")) or 1000
        paragon.exp.max = base_max_exp * paragon.level
    end

    local db_stats = Repository:GetParagonStatByCharacterSync(guid_low)
    if db_stats then
        paragon.statistics = db_stats
    end

    local used_points = 0
    for _, v in pairs(paragon.statistics) do used_points = used_points + v end
    local points_per_level = tonumber(Config:GetByField("POINTS_PER_LEVEL")) or 1
    paragon.points = (paragon.level * points_per_level) - used_points

    -- print("[Paragon DEBUG] OnParagonClientSendStatistics | DB reload | guid=" .. tostring(guid_low)
        -- .. " | level=" .. tostring(paragon.level)
        -- .. " | exp=" .. tostring(paragon.exp.current)
        -- .. " | points=" .. tostring(paragon.points))

    paragon, data = Mediator.On("OnBeforeClientStatisticsUpdate", {
        arguments = { player, paragon, data },
        defaults = { paragon, data },
    })

    -- Temporarily remove all stat bonuses during processing
    UpdatePlayerStatistics(player, paragon, false)

    -- Process each statistic update
    for _, updated_data in pairs(data) do
        local category_id = updated_data.categoryId
        if not category_id then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        local categories = Config:GetCategories()
        local category_data = categories[category_id]
        if not category_data then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        local statistic_id = updated_data.statId
        if not statistic_id then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        local statistic_data = category_data.statistics[statistic_id]
        if not statistic_data then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        local statistic_value = updated_data.value
        if not statistic_value or statistic_value < 0 then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        if statistic_data.limit > 0 and statistic_value > statistic_data.limit then
            UpdatePlayerStatistics(player, paragon, true)
            return false
        end

        paragon, statistic_id, statistic_value = Mediator.On("OnBeforeStatisticChange", {
            arguments = { player, paragon, statistic_id, statistic_value },
            defaults = { paragon, statistic_id, statistic_value },
        })

        UpdateParagonPoints(player, paragon, statistic_id, statistic_value)

        Mediator.On("OnAfterStatisticChange", {
            arguments = { player, paragon, statistic_id, statistic_value },
        })
    end

    CacheSet(player, paragon)

    -- Reapply all stat bonuses after processing
    UpdatePlayerStatistics(player, paragon, true)
    player:SendServerResponse(Hook.Addon.Prefix, 4, paragon:GetPoints())

    -- SAVE IMMEDIAT des stats en DB (synchrone via CharDBQuery).
    -- Sans ce SaveSync, les stats sont uniquement dans le cache Lua.
    -- Au logout, LoadParagonFromDB recharge depuis la DB => les nouvelles
    -- allocations seraient perdues si elles n'ont pas ete ecrites ici.
    paragon:SaveSync()

    Mediator.On("OnAfterClientStatisticsUpdate", {
        arguments = { player, paragon },
    })

    return true
end

-- ============================================================================
-- PLAYER LIFECYCLE MANAGEMENT
-- ============================================================================

---
--- Callback executed after paragon data has been loaded from the database.
--- This is the moment SetData("Paragon") is called — safe to flush the queue.
---
--- @param guid_low The low part of the player's GUID
--- @param paragon The loaded paragon instance
--- @return boolean True if successful, false if player not found
---
function Hook.OnPlayerStatLoad(guid_low, paragon)
    -- DESACTIVE : OnPlayerLogin utilise LoadParagonSync() directement.
    -- Cette fonction ne fait plus rien pour ne pas écraser le cache.
    -- print("[Paragon DEBUG] OnPlayerStatLoad (désactivé) | guid_low=" .. tostring(guid_low))
    return false
end

---
--- Handles player login event.
---
--- @param event The event ID (3 = PLAYER_EVENT_ON_LOGIN)
--- @param player The player object that logged in
---
function Hook.OnPlayerLogin(event, player)
    if not player then
        return
    end

    local system_enabled = tonumber(Config:GetByField("ENABLE_PARAGON_SYSTEM")) or 1
    if system_enabled == 0 then
        return
    end

    local character_guid = player:GetGUIDLow()

    -- Au login, on vide TOUJOURS le cache pour forcer un rechargement DB propre.
    -- Cela garantit que si un reload eluna s'est produit ou que des données
    -- obsolètes traînent dans _G.ParagonCache, elles ne polluent pas la session.
    CacheClear(character_guid)

    local paragon = LoadParagonSync(player)
    if not paragon then
        -- print("[Paragon ERROR] OnPlayerLogin: LoadParagonSync a échoué pour guid_low=" .. tostring(character_guid))
        return
    end

    -- print("[Paragon DEBUG] OnPlayerLogin: paragon chargé en sync | player=" .. player:GetName()
        -- .. " | level=" .. tostring(paragon:GetLevel())
        -- .. " | exp=" .. tostring(paragon:GetExperience()))

    Mediator.On("OnPlayerStatLoad", {
        arguments = { player, paragon },
        defaults = { paragon }
    })

    UpdatePlayerStatistics(player, paragon, true)
    OnParagonClientLoadRequest(player)

    Mediator.On("OnAfterPlayerStatLoad", {
        arguments = { player, paragon },
    })
end

---
--- Handles player logout event.
---
--- FIX CRITIQUE : On ne passe PLUS par LoadParagonSync() ni par _G.ParagonCache.
--- Raison : dans Eluna multi-state, chaque map a son propre Lua state.
--- _G.ParagonCache[guid_low] du state de logout peut contenir l'objet level=1
--- issu du state de login (map 0), alors que les kills ont eu lieu sur map 571
--- avec un state différent ayant CacheSet level=3/4 dans SON propre _G.
--- Les deux "partagent" _G en théorie mais Eluna per-map crée des états
--- indépendants — l'isolation n'est pas garantie.
---
--- La DB est la seule source de vérité fiable : UpdatePlayerExperience appelle
--- paragon:SaveSync() (CharDBQuery synchrone) à chaque gain d'XP.
--- Au logout, on recharge DIRECTEMENT depuis la DB via LoadParagonFromDB().
---
--- @param event The event ID (4 = PLAYER_EVENT_ON_LOGOUT)
--- @param player The player object that logged out
---
function Hook.OnPlayerLogout(event, player)
    if not player then
        return
    end

    local guid_low = player:GetGUIDLow()

    -- BYPASS CACHE : charger directement depuis la DB pour obtenir le niveau
    -- réellement sauvegardé (mis à jour à chaque SaveSync dans UpdatePlayerExperience).
    local paragon = LoadParagonFromDB(player)
    if not paragon then
        -- print("[Paragon DEBUG] OnPlayerLogout: LoadParagonFromDB échoué — abandon")
        return
    end

    -- print("[Paragon DEBUG] OnPlayerLogout | player=" .. player:GetName()
        -- .. " | guid_low=" .. tostring(guid_low)
        -- .. " | level=" .. tostring(paragon:GetLevel())
        -- .. " | exp=" .. tostring(paragon:GetExperience()))

    paragon = Mediator.On("OnBeforePlayerStatSave", {
        arguments = { player, paragon },
        defaults = { paragon }
    })

    UpdatePlayerStatistics(player, paragon, false)

    paragon:SaveSync()

    -- print("[Paragon DEBUG] OnPlayerLogout: SaveSync() terminé | level=" .. tostring(paragon:GetLevel())
        -- .. " | exp=" .. tostring(paragon:GetExperience()))

    Mediator.On("OnAfterPlayerStatSave", {
        arguments = { player, paragon },
    })

    -- Libérer le cache après sauvegarde
    CacheClear(guid_low)
end


---
--- Handles player save event (26 = PLAYER_EVENT_ON_SAVE).
---
--- TrinityCore déclenche cet event périodiquement pendant la session
--- ET juste avant le logout, garantissant une sauvegarde régulière.
---
--- @param event The event ID (26 = PLAYER_EVENT_ON_SAVE)
--- @param player The player object being saved
---
function Hook.OnPlayerSave(event, player)
    if not player then
        return
    end

    local paragon = CacheGet(player)
    if not paragon then
        return
    end

    -- print("[Paragon DEBUG] OnPlayerSave | player=" .. player:GetName()
        -- .. " | level=" .. tostring(paragon:GetLevel())
        -- .. " | exp=" .. tostring(paragon:GetExperience()))

    paragon:SaveSync()
end

---
--- Handles character deletion event.
---
--- @param event The event ID (2 = PLAYER_EVENT_ON_CHARACTER_DELETE)
--- @param player_guid The GUID of the character being deleted
---
function Hook.OnCharacterDelete(event, player_guid)
    if player_guid then
        Repository:DeleteParagonData(player_guid)
    end
end

-- ============================================================================
-- PLAYER EXPERIENCE EVENTS
-- ============================================================================

---
--- Handles creature kill event (7 = PLAYER_EVENT_ON_KILL_CREATURE).
---
--- If paragon data is not yet loaded (async DB load still in flight),
--- the kill is queued and will be processed once OnPlayerStatLoad fires.
---
function Hook.OnPlayerKillCreature(event, player, creature)
    if not player or not creature then
        return
    end

    -- NOTE: creature:IsDead() retiré — non exposé dans l'API Eluna TrinityWotlk.
    -- PLAYER_EVENT_ON_KILL_CREATURE (event 5) garantit implicitement que la
    -- créature est morte. L'objet creature peut aussi être expiré selon le build.
    --
    -- FIX POINTER INVALIDATION (ligne 1002) : le pointeur C++ de la créature peut
    -- être détruit par TrinityCore avant que ce hook Lua s'exécute (ex: despawn
    -- immédiat sur certains builds ou maps). On protège GetEntry() avec pcall.
    -- Si le pointeur est invalide, on abandonne silencieusement.
    local ok, creature_entry = pcall(function() return creature:GetEntry() end)
    if not ok or not creature_entry then
        -- print("[Paragon DEBUG] OnPlayerKillCreature | creature invalidée — abandon")
        return
    end

    -- FIX CROSS-MAP : UpdatePlayerExperience recharge maintenant toujours depuis
    -- la DB. On passe nil comme paragon — il sera ignoré et rechargé depuis la DB.
    -- On garde CacheGet uniquement pour le Mediator OnBeforeCreatureExperience.
    local paragon_for_mediator = CacheGet(player)
    if not paragon_for_mediator then
        paragon_for_mediator = LoadParagonSync(player)
    end

    if paragon_for_mediator then
        Mediator.On("OnBeforeCreatureExperience", {
            arguments = { player, creature, paragon_for_mediator },
            defaults = { paragon_for_mediator },
        })
    end

    UpdatePlayerExperience(player, nil, EXPERIENCE_SOURCE.CREATURE, creature_entry)
end

---
--- Handles achievement complete event (45 = PLAYER_EVENT_ON_ACHIEVEMENT_COMPLETE).
---
function Hook.OnPlayerAchievementComplete(event, player, achievement)
    if not player or not achievement then
        return
    end

    -- FIX : dans Eluna TrinityWotlk (event 45), le paramètre `achievement` est
    -- directement l'ID entier du succès, PAS un objet avec méthode :GetId().
    local achievement_id = (type(achievement) == "number") and achievement or achievement:GetId()

    local paragon_for_mediator = CacheGet(player)
    if not paragon_for_mediator then
        paragon_for_mediator = LoadParagonSync(player)
    end

    if paragon_for_mediator then
        Mediator.On("OnBeforeAchievementExperience", {
            arguments = { player, achievement, paragon_for_mediator },
            defaults = { paragon_for_mediator },
        })
    end

    UpdatePlayerExperience(player, nil, EXPERIENCE_SOURCE.ACHIEVEMENT, achievement_id)
end

---
--- Handles quest status changed event (54 = on_quest_status_changed).
--- Se déclenche à chaque changement de statut (acceptation, abandon, complétion...).
--- On filtre sur status == 1 (QUEST_STATUS_COMPLETE) pour ne donner l'XP Paragon
--- qu'à la complétion réelle de la quête.
---
--- QuestStatus TrinityCore :
---   0 = QUEST_STATUS_NONE
---   1 = QUEST_STATUS_COMPLETE  <- seul cas qui doit déclencher l'XP
---   2 = QUEST_STATUS_UNAVAILABLE
---   3 = QUEST_STATUS_INCOMPLETE
---   4 = QUEST_STATUS_AVAILABLE
---   5 = QUEST_STATUS_FAILED
---
function Hook.OnPlayerQuestComplete(event, player, quest, status)
    if not player or not quest then
        return
    end

    -- Guard : n'accorder l'XP Paragon que si la quete est reellement completee
    if status ~= 6 then
        return
    end

    -- Le parametre `quest` est l'ID entier de la quete dans cet event Eluna.
    local quest_id = (type(quest) == "number") and quest or quest:GetId()

    local paragon_for_mediator = CacheGet(player)
    if not paragon_for_mediator then
        paragon_for_mediator = LoadParagonSync(player)
    end

    if paragon_for_mediator then
        Mediator.On("OnBeforeQuestExperience", {
            arguments = { player, quest_id, paragon_for_mediator },
            defaults = { paragon_for_mediator },
        })
    end

    UpdatePlayerExperience(player, nil, EXPERIENCE_SOURCE.QUEST, quest_id)
end

-- NOTE: Hook.OnPlayerSkillUpdate (event 62) removed — does not exist in Eluna TrinityWotlk.

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

---
--- Handles Lua state open event (33 = SERVER_EVENT_ON_LUA_STATE_OPEN).
--- GetPlayersInWorld() not available in per-map states — players reload on next login.
---
function Hook.OnLuaStateOpen(event)
    -- no-op: GetPlayersInWorld() unavailable in per-map Lua states
end

---
--- Handles Lua state close event (16 = SERVER_EVENT_ON_LUA_STATE_CLOSE).
--- Player data saved automatically via PLAYER_EVENT_ON_LOGOUT.
---
function Hook.OnLuaStateClose(event)
    -- no-op: GetPlayersInWorld() unavailable in per-map Lua states
end

---
--- Handles player command event (42 = PLAYER_EVENT_ON_COMMAND).
---
function Hook.OnPlayerCommand(event, player, command)
    if not player or not command then
        return
    end

    if command == "test" then
        local paragon = CacheGet(player)
        if not paragon then
            return false
        end

        UpdatePlayerStatistics(player, paragon, false)
        paragon:AddStatValue(1, 150)
        CacheSet(player, paragon)
        UpdatePlayerStatistics(player, paragon, true)

        return false
    end
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

-- Player Events
RegisterPlayerEvent(2, Hook.OnCharacterDelete)
RegisterPlayerEvent(3, Hook.OnPlayerLogin)
RegisterPlayerEvent(4, Hook.OnPlayerLogout)
RegisterPlayerEvent(7, Hook.OnPlayerKillCreature)
RegisterPlayerEvent(26, Hook.OnPlayerSave)     -- on_save : sauvegarde périodique + pré-logout
RegisterPlayerEvent(42, Hook.OnPlayerCommand)
RegisterPlayerEvent(45, Hook.OnPlayerAchievementComplete)
RegisterPlayerEvent(54, Hook.OnPlayerQuestComplete)  -- on_quest_status_changed : filtre sur status == 1 (COMPLETE)
-- RegisterPlayerEvent(62, Hook.OnPlayerSkillUpdate) -- REMOVED: event 62 n'existe pas dans Eluna TrinityWotlk

-- Server Events
RegisterServerEvent(16, Hook.OnLuaStateClose)
RegisterServerEvent(33, Hook.OnLuaStateOpen)

-- Addon Communication Events
RegisterClientRequests(Hook.Addon)

return Hook
