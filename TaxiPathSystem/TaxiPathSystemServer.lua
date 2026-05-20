-- TaxiPathSystemServer.lua
-- Compatibilité Eluna Multistate (dernière révision ElunaTrinityWotlk 3.3.5)

if not AIO then return end
if not AIO.IsServer() then return end

local TAXI_GAMEOBJECT_ID = 1660056  -- ID du GameObject

-- ─────────────────────────────────────────────────────────────────────────────
-- AIO.AddHandlers n'est disponible QUE sur le main state (map -1).
-- On l'enregistre uniquement là, comme dans DestinyPandaServer.lua.
-- ─────────────────────────────────────────────────────────────────────────────
if AIO.IsMainState() then
    local TxiPathHandlers = AIO.AddHandlers("TxiPathSystemServer", {})

    -- Téléportation du joueur (appelée depuis le client via AIO.Handle)
    function TxiPathHandlers.TeleportPlayer(player, mapId, x, y, z, orientation)
        if not player or not player:IsInWorld() then return end
        player:Teleport(mapId, x, y, z, orientation)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Gossip GameObject : doit s'enregistrer sur TOUS les states
-- (le joueur et le GO se trouvent sur un map state, pas le main state)
-- AIO.Handle fonctionne depuis n'importe quel state pour envoyer au client.
-- ─────────────────────────────────────────────────────────────────────────────
local function OnGossipHello(event, player, gameObject)
    if not player or not player:IsInWorld() then return end
    AIO.Handle(player, "TxiPathSystemClient", "ShowMainFrame")
end

RegisterGameObjectGossipEvent(TAXI_GAMEOBJECT_ID, 1, OnGossipHello)
