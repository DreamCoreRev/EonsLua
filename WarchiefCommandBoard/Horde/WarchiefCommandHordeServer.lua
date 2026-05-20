-- WarchiefCommandHordeServer.lua

if not AIO then return end
if not AIO.IsServer() then return end

-- AIO.AddHandlers et les handlers uniquement sur le main state (map: -1)
-- Sur les autres map states, AIO est nil/incomplet -> erreur si on appelle AddHandlers
if AIO.IsMainState() then

    local WarchiefCommandHordeHandlers = AIO.AddHandlers("WarchiefCommandHordeHandler", {})

    local availableQuests = {
        { id = 27726, title = "Uldum : L'appel du chef de guerre" },
        { id = 27721, title = "Hyjal : Aux portes de la guerre" },
        { id = 27722, title = "Maelström : Contre les forces du chaos" },
    }

    local teleportData = {
        [27726] = { mapId = 829,  x = -11018.59, y = -1263.54,  z = 13.52,    o = 4.85,    message = "Vous avez été téléporté à Uldum !" },
        [27721] = { mapId = 1,    x = 5534.08,   y = -3624.69,  z = 1567.04,  o = 5.39048, message = "Vous avez été téléporté au Mont Hyjal !" },
        [27722] = { mapId = 852,  x = 854.924,   y = 1080.96,   z = -12.5196, o = 4.54772, message = "Vous avez été téléporté au Maelström !" },
    }

    function WarchiefCommandHordeHandlers.AcceptQuest(player, questId)
        if not player or not player:IsInWorld() then return end

        local quest = nil
        for _, q in ipairs(availableQuests) do
            if q.id == questId then
                quest = q
                break
            end
        end

        if not quest then
            player:SendBroadcastMessage("Erreur : cette quête n'existe pas dans la liste disponible.")
            return
        end

        if not player:HasQuest(questId) then
            player:AddQuest(questId)
            player:SendBroadcastMessage("Vous avez accepté la quête : " .. quest.title)
        else
            player:SendBroadcastMessage("Vous avez déjà cette quête : " .. quest.title)
        end

        local data = teleportData[questId]
        if data then
            player:Teleport(data.mapId, data.x, data.y, data.z, data.o)
            player:SendBroadcastMessage(data.message)
        else
            player:SendBroadcastMessage("Erreur : impossible de trouver les données de téléportation.")
        end
    end

end -- fin du bloc AIO.IsMainState()

-- Le gossip event s'enregistre sur TOUS les states (sans guard)
-- comme dans DestinyPandaServer.lua
local function OnGossipHello(event, player, gameObject)
    if not player or not player:IsInWorld() then return end
    player:GossipClearMenu()
    AIO.Handle(player, "WarchiefCommandHordeHandler", "OpenInterface")
    player:GossipComplete()
end

-- Remplacez 206109 par l'ID de votre GameObject Horde.
RegisterGameObjectGossipEvent(206109, 1, OnGossipHello)
