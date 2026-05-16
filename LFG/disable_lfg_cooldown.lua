local function RemoveLFGCooldownAura(player)
    if not player or not player:IsInWorld() then
        return
    end
    player:RemoveAura(71328)
    player:RemoveAura(71041)
end

local function OnPlayerLogin(event, player)
    RemoveLFGCooldownAura(player)
end

local function OnPlayerLogout(event, player)
    -- Le joueur peut déjà être invalide au logout, on ignore silencieusement
    if not player or not player:IsInWorld() then
        return
    end
    RemoveLFGCooldownAura(player)
end

local function OnPlayerZoneChange(event, player, newZone, newArea)
    if not player or not player:IsInWorld() then
        return
    end
    local instanceId = player:GetInstanceId()
    if instanceId and instanceId ~= 0 then
        RemoveLFGCooldownAura(player)
    end
end

local function OnPlayerMapChange(event, player, oldMap, newMap)
    if not player or not player:IsInWorld() then
        return
    end
    local instanceId = player:GetInstanceId()
    if instanceId and instanceId ~= 0 then
        RemoveLFGCooldownAura(player)
    end
end

local function OnPlayerBindToInstance(event, player, difficulty, mapId, permanent)
    if not player or not player:IsInWorld() then
        return
    end
    local instanceId = player:GetInstanceId()
    if instanceId and instanceId ~= 0 then
        RemoveLFGCooldownAura(player)
    end
end

RegisterPlayerEvent(3,  OnPlayerLogin)          -- PLAYER_EVENT_ON_LOGIN
RegisterPlayerEvent(4,  OnPlayerLogout)         -- PLAYER_EVENT_ON_LOGOUT
RegisterPlayerEvent(27, OnPlayerZoneChange)     -- PLAYER_EVENT_ON_UPDATE_ZONE
RegisterPlayerEvent(28, OnPlayerMapChange)      -- PLAYER_EVENT_ON_MAP_CHANGE
RegisterPlayerEvent(26, OnPlayerBindToInstance) -- PLAYER_EVENT_ON_BIND_TO_INSTANCE
