-- DestinyPandaServer.lua
-- Compatibilité Eluna Multistate (défaut depuis ~2023)
-- Les RegisterXxxEvent s'exécutent sur tous les states (world + map states)
-- AIO.Handle nécessite le main state pour communiquer avec le client

if not AIO then return end
if not AIO.IsServer() then return end

local WEAPON_UPGRADE_GAMEOBJECT_ID = 5400427  -- ID du GameObject

-- ─────────────────────────────────────────────────────────────────────────────
-- Event 42 : commandes chat player (.teleport_panda ...)
-- Cet event ne tourne que sur le main state, le guard IsMainState est justifié
-- ─────────────────────────────────────────────────────────────────────────────
local function TeleportPlayer(event, player, command)
    if not AIO.IsMainState() then return end

    local team = player:GetTeam()  -- 0 = Alliance, 1 = Horde

    -- Fermer la frame avant téléportation
    AIO.Handle(player, "DestinyFactionHandler", "CloseDestinyInterface")

    if command == "teleport_panda alliance" then
        if team == 1 then
            player:SendBroadcastMessage("|cff00ff98Vous ne pouvez pas rejoindre l'Alliance en tant que membre de la Horde.|r")
            player:SendNotification("|cff00ff98Vous ne pouvez pas rejoindre l'Alliance en tant que membre de la Horde.|r")
            return false
        end
        player:Teleport(0, -8905, 560, 94, 0.62)
        return false

    elseif command == "teleport_panda horde" then
        if team == 0 then
            player:SendBroadcastMessage("|cff00ff98Vous ne pouvez pas rejoindre la Horde en tant que membre de l'Alliance.|r")
            player:SendNotification("|cff00ff98Vous ne pouvez pas rejoindre la Horde en tant que membre de l'Alliance.|r")
            return false
        end
        player:Teleport(1, 1517.55, -4412.03, 21.7103, 0.243466)
        return false
    end
end

RegisterPlayerEvent(42, TeleportPlayer)

-- ─────────────────────────────────────────────────────────────────────────────
-- Gossip GameObject : doit s'enregistrer sur TOUS les states
-- Ne pas mettre de guard IsMainState ici, sinon l'event ne se déclenche jamais
-- sur les map states (là où le joueur et le gameobject se trouvent)
-- ─────────────────────────────────────────────────────────────────────────────
local function OnGossipHello(event, player, gameObject)
    local questID = 29800
    local requiredLevel = 17

    if not player or not player:IsInWorld() then
        return
    end

    if player:GetLevel() < requiredLevel then
        player:SendBroadcastMessage("|cff00ff98Vous devez être au moins niveau 17 pour aller vers votre destin.|r")
        player:SendNotification("|cff00ff98Vous devez être au moins niveau 17 pour aller vers votre destin.|r")
        return
    end

    if not player:HasReceivedQuestReward(questID) then
        player:SendBroadcastMessage("|cff00ff98Vous devez d'abord terminer la quête : (De nouveaux alliés) pour aller vers votre destin.|r")
        player:SendNotification("|cff00ff98Vous devez d'abord terminer la quête : (De nouveaux alliés) pour aller vers votre destin.|r")
        return
    end

    -- AIO.Handle fonctionne depuis n'importe quel state pour envoyer au client
    AIO.Handle(player, "DestinyFactionHandler", "OpenDestinyInterface")
end

RegisterGameObjectGossipEvent(WEAPON_UPGRADE_GAMEOBJECT_ID, 1, OnGossipHello)
