local cordenadas = {823, 13329.1, 12957.5, 496.738, 5.63043}
local players
local function Update(evento, unidad, diferencia)

	players = unidad:GetPlayersInRange( 5, 0, 1 )
	
	for i = 1, #players do
		local map, x, y, z, o = table.unpack(cordenadas)
		players[i]:Teleport(map, x, y, z, o)
	end
end

RegisterGameObjectEvent(300512, 1, Update)