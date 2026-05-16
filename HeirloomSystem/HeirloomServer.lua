if not AIO then return end
if not AIO.IsServer() then return end  -- ← CRUCIAL, ignore les states non-main
if not AIO.IsMainState() then return end  -- ← CRUCIAL
local HerosHandlers = AIO.AddHandlers("HeirloomClient", {})

local CURRENCY_ITEM_ID = 43228  -- Item requis pour acheter un héritage
local CURRENCY_COST = 50        -- Coût en Eclats du gardien par héritage

-- Fonction pour ajouter un item dans les sacs du joueur
function HerosHandlers.AddHeirloomItem(player, itemID)
    -- Vérifier si le joueur possède au moins 50 Eclats
    local itemCount = player:GetItemCount(CURRENCY_ITEM_ID)
    if itemCount < CURRENCY_COST then
        AIO.Handle(player, "HeirloomClient", "ShowError", "no_currency")
        return
    end

    -- Retirer 50 Eclats
    player:RemoveItem(CURRENCY_ITEM_ID, CURRENCY_COST)

    -- Ajouter l'item héritage
    local itemAdded = player:AddItem(itemID, 1)
    if itemAdded then
        player:SendBroadcastMessage("|cff00ff00Item ajouté dans vos sacs :|r " .. GetItemLink(itemID))
    else
        -- Rembourser les Eclats si l'ajout échoue (sac plein)
        player:AddItem(CURRENCY_ITEM_ID, CURRENCY_COST)
        AIO.Handle(player, "HeirloomClient", "ShowError", "bag_full")
    end
end
