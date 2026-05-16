-- ============================================================
--  Contributeur - Activation via item gossip
--  TrinityCore 3.3.5 | ElunaTrinityWotlk
--  Base : Characters DB → table premium (AccountId, active)
-- ============================================================

local ITEM_ID    = 132747 -- Item utilisé pour activer le statut
local REWARD_ID  = 9017   -- Item donné lors de l'activation / création de perso

-- ------------------------------------------------------------
--  Utilitaire : vérifie si le joueur a déjà l'item dans ses sacs
-- ------------------------------------------------------------
local function HasRewardItem(player)
    return player:HasItem(REWARD_ID)
end

-- ------------------------------------------------------------
--  Gossip Hello : affiche le menu si pas encore contributeur
-- ------------------------------------------------------------
local function OnGossipHello(event, player, item)
    local accountId = player:GetAccountId()
    local query = string.format(
        "SELECT active FROM premium WHERE AccountId = %d AND active = 1",
        accountId
    )
    local result = CharDBQuery(query)

    if result then
        player:SendBroadcastMessage("Vous êtes déjà contributeur.")
        player:GossipComplete()
        return
    end

    player:GossipSetText(
        "Bonjour " .. player:GetName() .. ",\n\n" ..
        "En activant votre statut de contributeur, vous bénéficierez de nombreux avantages exclusifs.\n\n" ..
        "L'activation est immédiate et ne nécessite aucune déconnexion."
    )
    player:GossipMenuAddItem(0, "Je souhaite activer mon statut de contributeur", 0, 1)
    player:GossipSendMenu(0x7FFFFFFF, item)
end

-- ------------------------------------------------------------
--  Gossip Select : insertion dans premium + don de l'item
-- ------------------------------------------------------------
local function OnGossipSelect(event, player, item, sender, intid, code, menu_id)
    if intid == 1 then
        local accountId = player:GetAccountId()

        local query = string.format(
            "INSERT INTO premium (AccountId, active) VALUES (%d, 1) ON DUPLICATE KEY UPDATE active = 1",
            accountId
        )
        CharDBExecute(query)

        player:AddItem(REWARD_ID, 1)
        player:SendBroadcastMessage("|cff00ff00Votre statut de contributeur a été activé avec succès !|r")
        player:GossipComplete()
    end
end

-- ------------------------------------------------------------
--  Nouveau personnage : don de l'item si compte contributeur
-- ------------------------------------------------------------
local function OnFirstLogin(event, player)
    local accountId = player:GetAccountId()
    local query = string.format(
        "SELECT active FROM premium WHERE AccountId = %d AND active = 1",
        accountId
    )
    local result = CharDBQuery(query)

    if result then
        player:AddItem(REWARD_ID, 1)
        player:SendBroadcastMessage("|cff00ff00Bienvenue ! Votre statut de contributeur vous offre un cadeau de bienvenue.|r")
    end
end

-- ------------------------------------------------------------
--  Connexion : don de l'item si contributeur et item absent des sacs
-- ------------------------------------------------------------
local function OnLogin(event, player)
    local accountId = player:GetAccountId()
    local query = string.format(
        "SELECT active FROM premium WHERE AccountId = %d AND active = 1",
        accountId
    )
    local result = CharDBQuery(query)

    if result and not HasRewardItem(player) then
        player:AddItem(REWARD_ID, 1)
        player:SendBroadcastMessage("|cff00ff00Bienvenue ! Votre statut de contributeur vous offre un cadeau de bienvenue.|r")
    end
end

-- ------------------------------------------------------------
--  Enregistrement des événements
-- ------------------------------------------------------------
RegisterItemGossipEvent(ITEM_ID, 1, OnGossipHello)
RegisterItemGossipEvent(ITEM_ID, 2, OnGossipSelect)
RegisterPlayerEvent(30, OnFirstLogin) -- 30 = PLAYER_EVENT_ON_FIRST_LOGIN
RegisterPlayerEvent(3, OnLogin)       --  3 = PLAYER_EVENT_ON_LOGIN
