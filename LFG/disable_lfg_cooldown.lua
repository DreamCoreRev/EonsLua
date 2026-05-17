-- disable_lfg_cooldown.lua
-- Supprime les auras de cooldown LFG (71328 / 71041) dès que le joueur
-- entre dans une instance ou change de zone/map.
-- Utilise pcall() sur chaque appel Eluna susceptible de recevoir un
-- pointeur invalidé, ce qui évite l'erreur :
--   "calling 'IsInWorld' on bad self ... (invalidated) object"

local AURA_LFG_COOLDOWN_1 = 71328
local AURA_LFG_COOLDOWN_2 = 71041

-- Tente de retirer les deux auras ; retourne false si le pointeur est mort.
local function TryRemoveAuras(player)
    local ok, err = pcall(function()
        player:RemoveAura(AURA_LFG_COOLDOWN_1)
        player:RemoveAura(AURA_LFG_COOLDOWN_2)
    end)
    if not ok then
        -- Pointeur invalidé : on ignore silencieusement.
        -- Décommenter la ligne suivante pour déboguer :
        -- print("[LFG] TryRemoveAuras ignoré : " .. tostring(err))
    end
end

-- Vérifie que le joueur est valide ET en monde via pcall,
-- puis retire les auras.
local function RemoveLFGCooldownAura(player)
    if not player then return end

    local inWorld = false
    local ok = pcall(function()
        inWorld = player:IsInWorld()
    end)

    if ok and inWorld then
        TryRemoveAuras(player)
    end
end

-- ── Événements ───────────────────────────────────────────────────────────────

-- Login : le joueur vient d'arriver, pointeur toujours valide.
local function OnPlayerLogin(event, player)
    RemoveLFGCooldownAura(player)
end

-- Changement de zone (PLAYER_EVENT_ON_UPDATE_ZONE).
-- On ne retire les auras que si le joueur est dans une instance.
local function OnPlayerZoneChange(event, player, newZone, newArea)
    if not player then return end

    local instanceId
    local ok = pcall(function()
        if player:IsInWorld() then
            instanceId = player:GetInstanceId()
        end
    end)

    if ok and instanceId and instanceId ~= 0 then
        TryRemoveAuras(player)
    end
end

-- Changement de map (PLAYER_EVENT_ON_MAP_CHANGE).
local function OnPlayerMapChange(event, player, oldMap, newMap)
    if not player then return end

    local instanceId
    local ok = pcall(function()
        if player:IsInWorld() then
            instanceId = player:GetInstanceId()
        end
    end)

    if ok and instanceId and instanceId ~= 0 then
        TryRemoveAuras(player)
    end
end

-- ── Enregistrement ───────────────────────────────────────────────────────────
-- OnPlayerLogout et OnPlayerBindToInstance sont volontairement retirés :
--   • Au logout le pointeur est déjà partiellement invalidé côté C++.
--   • OnBindToInstance se déclenche avant que le joueur soit réellement
--     placé en instance ; le cooldown est de toute façon retiré par
--     OnZoneChange / OnMapChange juste après.

RegisterPlayerEvent(3,  OnPlayerLogin)      -- PLAYER_EVENT_ON_LOGIN
RegisterPlayerEvent(27, OnPlayerZoneChange) -- PLAYER_EVENT_ON_UPDATE_ZONE
RegisterPlayerEvent(28, OnPlayerMapChange)  -- PLAYER_EVENT_ON_MAP_CHANGE
