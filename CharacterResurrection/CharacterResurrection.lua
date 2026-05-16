local SPELL_ID = 51916 -- Sort qui invoque le PNJ pour ressusciter
local MAX_RESS = 3 -- Nombre maximum de résurrections
local RESS_TIMER = 2100 -- 35 minutes (en secondes) avant de récupérer les résurrections

local playerRessData = {} -- Stocke les résurrections des joueurs

function OnPlayerLogin(event, player)
    local guid = player:GetGUIDLow()

    -- Initialise les données si le joueur n'a pas encore de suivi
    if not playerRessData[guid] then
        playerRessData[guid] = {count = MAX_RESS, lastReset = os.time()}
    end

    -- Vérifie si le timer des 35 minutes est écoulé pour réinitialiser les résurrections
    if os.time() - playerRessData[guid].lastReset >= RESS_TIMER then
        playerRessData[guid].count = MAX_RESS
        playerRessData[guid].lastReset = os.time()
        player:SendBroadcastMessage("|cff00ff00Vos résurrections ont été réinitialisées !|r")
    end
end

function OnKilledByCreature(event, killer, player)
    local guid = player:GetGUIDLow()

    -- Initialise ici aussi car MAP state et WORLD state
    -- ne partagent pas la même table Lua sous Eluna multistate
    if not playerRessData[guid] then
        playerRessData[guid] = {count = MAX_RESS, lastReset = os.time()}
    end

    -- Vérifie si le timer des 35 minutes est écoulé pour réinitialiser les résurrections
    if os.time() - playerRessData[guid].lastReset >= RESS_TIMER then
        playerRessData[guid].count = MAX_RESS
        playerRessData[guid].lastReset = os.time()
    end

    -- Vérifie si le joueur est en champ de bataille ou en arène
    if player:InBattleground() or player:InArena() then
        player:SendBroadcastMessage("|cffff0000Les résurrections ne sont pas disponibles en champ de bataille ou en arène.|r")
        return
    end

    -- Vérifie si le joueur a encore des résurrections disponibles
    if playerRessData[guid] and playerRessData[guid].count > 0 then
        playerRessData[guid].count = playerRessData[guid].count - 1
        player:SendBroadcastMessage("|cffff0000Un ange vient vous sauver... Il vous reste " .. playerRessData[guid].count .. " résurrections.|r")

        -- Sauvegarde en DB pour que la commande .ange puisse lire le vrai état
        CharDBExecute("REPLACE INTO character_resurrection (guid, rez_count, last_reset) VALUES ("
            .. guid .. ", " .. playerRessData[guid].count .. ", " .. playerRessData[guid].lastReset .. ")")

        -- Laisse le PNJ faire l'animation et ressusciter le joueur
        player:CastSpell(player, SPELL_ID, true)
    else
        player:SendBroadcastMessage("|cffff0000Vous avez utilisé toutes vos résurrections ! Libérez votre esprit.|r\nVos résurrections seront réinitialisées après 35 minutes. Une fois ce délai écoulé, déconnectez-vous puis reconnectez votre personnage.|r")
        -- Le joueur va au cimetière normalement
    end
end

function OnAngeCommand(event, player, command)
    if command ~= "ange" then
        return true -- laisse passer les autres commandes
    end

    local guid = player:GetGUIDLow()

    -- Lit l'état réel depuis la DB (seul moyen fiable entre MAP et WORLD state)
    local result = CharDBQuery("SELECT rez_count, last_reset FROM character_resurrection WHERE guid = " .. guid)

    local count, lastReset
    if result then
        count     = result:GetUInt8(0)
        lastReset = result:GetUInt32(1)
    else
        -- Jamais mort depuis le lancement du serveur : charges pleines
        count     = MAX_RESS
        lastReset = os.time()
    end

    local elapsed = os.time() - lastReset

    -- Cas 1 : timer écoulé, charges rechargées
    if elapsed >= RESS_TIMER then
        player:SendBroadcastMessage("|cff00ff00[Ange Gardien]|r Vos résurrections sont rechargées ! Vous disposez de |cffffd700" .. MAX_RESS .. "/" .. MAX_RESS .. "|r charges.")

    -- Cas 2 : il reste des charges, timer en cours
    elseif count > 0 then
        local restant  = RESS_TIMER - elapsed
        local minutes  = math.floor(restant / 60)
        local secondes = restant % 60
        player:SendBroadcastMessage("|cff00ff00[Ange Gardien]|r Il vous reste |cffffd700" .. count .. "/" .. MAX_RESS .. "|r résurrection(s). Le stock sera rechargé dans |cffffd700" .. minutes .. " min " .. secondes .. " sec|r.")

    -- Cas 3 : plus de charge, timer en cours
    else
        local restant  = RESS_TIMER - elapsed
        local minutes  = math.floor(restant / 60)
        local secondes = restant % 60
        player:SendBroadcastMessage("|cffff4444[Ange Gardien]|r Vous avez utilisé toutes vos résurrections. Rechargement dans |cffffd700" .. minutes .. " min " .. secondes .. " sec|r.")
    end

    return false -- bloque la commande pour qu'elle ne remonte pas au serveur
end

RegisterPlayerEvent(3, OnPlayerLogin)  -- Déclencheur à la connexion du joueur
RegisterPlayerEvent(8, OnKilledByCreature) -- Déclencheur à la mort du joueur par une créature
RegisterPlayerEvent(42, OnAngeCommand) -- Déclencheur sur commande joueur (PLAYER_EVENT_ON_COMMAND)
