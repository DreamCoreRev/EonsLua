local NpcId = 12016
local MenuId = 12016

local pathTable = {}

table.insert(pathTable, {860, 910.778, 3612.88, 253.835})
table.insert(pathTable, {860, 915.773, 3623.44, 254.681})
table.insert(pathTable, {860, 922.559, 3637.8, 255.754})
table.insert(pathTable, {860, 918.383, 3643.92, 260.234})
table.insert(pathTable, {860, 906.1, 3663.59, 280.163})
table.insert(pathTable, {860, 880.057, 3749, 281.402})
table.insert(pathTable, {860, 872.987, 3863.43, 277.985})
table.insert(pathTable, {860, 871.136, 4035, 254.998})
table.insert(pathTable, {860, 907.686, 4106.53, 241.287})
table.insert(pathTable, {860, 967.076, 4136.26, 238.841})
table.insert(pathTable, {860, 1051.4, 4173.36, 234.442})
table.insert(pathTable, {860, 1115.54, 4169.37, 195.787})

local WanderingIslefourPath = AddTaxiPath(pathTable, 142225, 142225)

local function OnGossipHello(event, player, object)
	local questID = 29775

    -- Vérifie si l'objet player est valide
    if not player or not player:IsInWorld() then
        return
    end

    -- Vérifie si la quête 29775 a été complétée (récompense reçue)
    if not player:HasReceivedQuestReward(questID) then
        player:SendBroadcastMessage("|cff00ff98Vous devez d'abord terminer la quête : (L’esprit et le corps de Shen Zin Su) avant de pouvoir voyager.|r")
		player:SendNotification('|cff00ff98Vous devez d\'abord terminer la quête : (L’esprit et le corps de Shen Zin Su) avant de pouvoir voyager.|r')
        return
    end

	player:GossipClearMenu()
	player:GossipSetText('Bonjour '..player:GetName()..'!\n\nJe propose un voyage à Brise-du-Matin.\n\nVoulez-vous y aller ?');
	player:GossipMenuAddItem(2, "Oui ! Allez à Brise-du-Matin !", 1, 1)
	player:GossipMenuAddItem(7, 'Pas maintenant... Au revoir !', 1, 2);
	player:GossipSendMenu(0x7FFFFFFF, object)
    end
	
	local function OnGossipSelect(event, player, object, sender, intid, code, menuid)
	if (intid == 1) then
		player:StartTaxi(WanderingIslefourPath)
        player:GossipComplete();
		end
		
		if(intid == 2) then
		player:SendNotification('|cffff0000Reviens me voir si tu veux voyager.|r');
		player:GossipComplete();
	end
end
		
RegisterCreatureGossipEvent(NpcId, 1, OnGossipHello)
RegisterCreatureGossipEvent(NpcId, 2, OnGossipSelect)
RegisterPlayerGossipEvent(MenuId, 2, OnGossipSelect)