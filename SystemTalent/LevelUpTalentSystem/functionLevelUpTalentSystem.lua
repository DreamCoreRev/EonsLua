local function GrantTalentPointsOnLevelUp(event, player, oldLevel)
    local level = oldLevel + 1  -- FIX : GetLevel() retourne l'ancien niveau au moment de l'event

    local pointsToGrant = 0

    -- Points de talent dès le niveau 10
    if level >= 10 and level <= 80 then
        local talentLevels = {
			10, 11, 13, 15, 17, 18, 19,
			20, 22, 24, 26, 28, 30, 32, 34, 36, 38,
			40, 42, 44, 46, 48, 50, 52, 54, 56, 58,
			60, 63, 66, 69, 72, 75, 78, 80
		}

        if table.contains(talentLevels, level) then
            pointsToGrant = 1
        end
    end

    -- Si des points doivent être accordés
    if pointsToGrant > 0 then
        for i = 1, pointsToGrant do
            player:AddItem(338404, 1)
        end
        player:SendAreaTriggerMessage("|cff00ff00Vous avez gagné " .. pointsToGrant .. " point" .. (pointsToGrant > 1 and "s" or "") .. " de talent pour avoir atteint le niveau " .. level .. "!|r")
    end
end

-- Fonction pour vérifier si un tableau contient un élément
function table.contains(tbl, val)
    for i = 1, #tbl do
        if tbl[i] == val then
            return true
        end
    end
    return false
end

RegisterPlayerEvent(13, GrantTalentPointsOnLevelUp)
