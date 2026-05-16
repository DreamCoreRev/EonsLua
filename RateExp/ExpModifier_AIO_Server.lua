--[[ 

    MOD_EXP - ExpModifier AIO Server
    TrinityCore 3.3.5 + Eluna + AIO

    ANALYSE DU SOURCE C++ :
    OnGiveXP lit bien lua_isnumber(L, r) et fait amount = CHECKVAL<uint32>(r).
    Le return fonctionne. Le problème était ailleurs.

    CAUSE RÉELLE IDENTIFIÉE :
    Eluna TrinityCore WotLK crée une instance Eluna séparée par map (MAP state).
    Les tables Lua (m_exp, m_pending) ne sont PAS partagées entre instances.
    - onConnect s'exécute en WORLD state → charge m_exp[pGuid] dans l'instance WORLD
    - onGiveXP s'exécute en MAP state → m_exp[pGuid] est NIL dans cette instance
    - ensureLoaded fait un CharDBQuery → retourne la bonne valeur depuis la BDD
    
    MAIS : le return depuis onGiveXP fonctionne, il faut juste s'assurer que
    ensureLoaded est appelé et retourne bien le bon modificateur.
    On ajoute des prints de debug pour confirmer le comportement.

]]--

    local m_config = {
        elunaDB = 'eons_chars',
    };

    local m_exp = {}

--[[ AIO REQUIREMENT ]]--
    local AIO = AIO or require("AIO");
    if not AIO then return end


--[[
    HELPER : charge le modificateur depuis la BDD si pas en mémoire
    Fonctionne dans toutes les instances Eluna (WORLD et MAP)
]]--
local function ensureLoaded(pGuid)
    if not m_exp[pGuid] then
        m_exp[pGuid] = { mod_exp = 1 }
        local res = CharDBQuery(
            'SELECT mod_exp FROM '..m_config.elunaDB..
            '.characters_exp_rates WHERE guid = '..pGuid..';'
        )
        if res ~= nil then
            m_exp[pGuid].mod_exp = res:GetUInt32(0)
        end
        -- Debug : confirmer ce qui est chargé depuis la BDD
        -- print('[ExpMod] ensureLoaded guid='..pGuid..' mod_exp='..m_exp[pGuid].mod_exp)
    end
end


--[[
    on_give_xp (event 12) - State : MAP
    On lit directement depuis la BDD à chaque gain d'XP.
    m_exp n'est PAS partagé entre instances Eluna (MAP vs WORLD),
    donc on ne cache pas ici — la BDD est la source de vérité.
]]--
function m_exp.onGiveXP(event, player, amount, victim)
    local pGuid = player:GetGUIDLow()

    -- Lecture directe BDD (pas de cache côté MAP state)
    local modifier = 1
    local res = CharDBQuery(
        'SELECT mod_exp FROM '..m_config.elunaDB..
        '.characters_exp_rates WHERE guid = '..pGuid..';'
    )
    if res ~= nil then
        modifier = res:GetUInt32(0)
    end

    -- print('[ExpMod] onGiveXP guid='..pGuid..' amount='..amount..' modifier='..modifier)

    if modifier <= 1 then
        return
    end

    local newAmount = amount * modifier
    -- print('[ExpMod] onGiveXP → new amount='..newAmount)
    return newAmount
end
RegisterPlayerEvent(12, m_exp.onGiveXP)


--[[
    Le reste du code AIO est en WORLD/MainState uniquement
]]--
    if not AIO.IsServer() then return end
    if not AIO.IsMainState() then return end

    local h_expmodifier = AIO.AddHandlers("h_expmodifier", {})

    function h_expmodifier.getRateModifier(msg, player)
        local pGuid = player:GetGUIDLow()
        ensureLoaded(pGuid)
        return msg:Add("h_expmodifier", "setMyRate", m_exp[pGuid].mod_exp)
    end
    AIO.AddOnInit(h_expmodifier.getRateModifier)

    function h_expmodifier.update(player)
        h_expmodifier.getRateModifier(AIO.Msg(), player):Send(player)
    end

--[[ DON'T TOUCH THIS ]]--
    CharDBQuery('CREATE DATABASE IF NOT EXISTS `'..m_config.elunaDB..'`;')
    CharDBQuery(
        'CREATE TABLE IF NOT EXISTS `'..m_config.elunaDB..'`.'..
        '`characters_exp_rates` ('..
        '`guid` int(10) NOT NULL, '..
        '`mod_exp` INT(2) NOT NULL DEFAULT 1, '..
        'PRIMARY KEY (`guid`)'..
        ') ENGINE=InnoDB DEFAULT CHARSET=latin1;'
    )

function m_exp.onConnect(event, player)
    local pGuid = player:GetGUIDLow()
    m_exp[pGuid] = { mod_exp = 1 }
    local res = CharDBQuery(
        'SELECT mod_exp FROM '..m_config.elunaDB..
        '.characters_exp_rates WHERE guid = '..pGuid..';'
    )
    if res ~= nil then
        m_exp[pGuid].mod_exp = res:GetUInt32(0)
    else
        CharDBQuery(
            'INSERT INTO '..m_config.elunaDB..
            '.characters_exp_rates (guid, mod_exp) VALUES ('..pGuid..', 1);'
        )
        m_exp[pGuid].mod_exp = 1
    end
    -- print('[ExpMod] onConnect guid='..pGuid..' mod_exp='..m_exp[pGuid].mod_exp)
    h_expmodifier.update(player)
end
RegisterPlayerEvent(3, m_exp.onConnect)

function m_exp.onDisconnect(event, player)
    local pGuid = player:GetGUIDLow()
    ensureLoaded(pGuid)
    CharDBQuery(
        'UPDATE '..m_config.elunaDB..
        '.characters_exp_rates SET mod_exp = '..m_exp[pGuid].mod_exp..
        ' WHERE guid = '..pGuid..';'
    )
    m_exp[pGuid] = nil
end
RegisterPlayerEvent(4, m_exp.onDisconnect)

function m_exp.getAllPlayerExp(event)
    for _, player in ipairs(GetPlayersInWorld()) do
        m_exp.onConnect(event, player)
    end
end
RegisterServerEvent(33, m_exp.getAllPlayerExp)

function m_exp.saveAllPlayerExp(event)
    for _, player in ipairs(GetPlayersInWorld()) do
        m_exp.onDisconnect(event, player)
    end
end
RegisterServerEvent(16, m_exp.saveAllPlayerExp)

function h_expmodifier.setRateModifier(player, modifier)
    local pGuid = player:GetGUIDLow()
    ensureLoaded(pGuid)

    local mod = tonumber(modifier)
    if not mod or mod < 1 or mod > 3 then mod = 1 end
    mod = math.floor(mod)

    m_exp[pGuid].mod_exp = mod
    -- Sauvegarder immédiatement en BDD pour que les instances MAP voient la valeur
    CharDBQuery(
        'UPDATE '..m_config.elunaDB..
        '.characters_exp_rates SET mod_exp = '..mod..
        ' WHERE guid = '..pGuid..';'
    )
    -- print('[ExpMod] setRateModifier guid='..pGuid..' mod='..mod)
    player:SendNotification(
        'Votre multiplicateur d\'expérience est maintenant en x'..mod..'!'
    )
    h_expmodifier.update(player)
end
