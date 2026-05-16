--[[
    Paragon Repository

    Data access layer for paragon system. Manages all interactions with the
    database including schema migrations, configuration queries, and character
    paragon data persistence.

    @class Repository
    @author iThorgrim
    @license AGL v3
]]

local Constants = require("paragon_constant")

local Repository = Object:extend()
local Instance = nil

local sf = string.format

-- ============================================================================
-- CONSTRUCTOR & MIGRATIONS
-- ============================================================================

function Repository:new()
    self:VerifyDatabaseSchema()
end

function Repository:VerifyDatabaseSchema()
    local required_tables = {
        "paragon_config_category",
        "paragon_config_statistic",
        "paragon_config",
        "paragon_config_experience_creature",
        "paragon_config_experience_achievement",
        "paragon_config_experience_skill",
        "paragon_config_experience_quest",
        "character_paragon",
        "account_paragon",
        "character_paragon_stats"
    }

    local missing_tables = {}

    local db_exists = CharDBQuery(sf("SHOW DATABASES LIKE '%s';", Constants.DB_NAME))
    if not db_exists then
        print("=================================================================")
        print("[PARAGON SYSTEM ERROR] Database not found!")
        print("=================================================================")
        error("[Paragon System] Database does not exist. Please install SQL migrations.")
    end

    for _, table_name in ipairs(required_tables) do
        local result = CharDBQuery(sf(
            "SELECT 1 FROM information_schema.tables WHERE table_schema = '%s' AND table_name = '%s' LIMIT 1;",
            Constants.DB_NAME,
            table_name
        ))

        if not result then
            table.insert(missing_tables, table_name)
        end
    end

    if #missing_tables > 0 then
        print("=================================================================")
        print("[PARAGON SYSTEM ERROR] Database schema incomplete!")
        print("=================================================================")
        for _, table_name in ipairs(missing_tables) do
            print("  - " .. table_name)
        end
        error("[Paragon System] Database schema verification failed.")
    end

    -- print("[Paragon System] Database schema verified successfully.")

    MediatorTimerAdapter.Publish("OnAfterMigrationExecute", {
        arguments = { self },
        deferred = true,
        flushDelay = 250
    })
end

-- ============================================================================
-- CONFIGURATION QUERIES
-- ============================================================================

function Repository:GetConfigCategories()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_CAT, Constants.DB_NAME))
    if not results then
        return false
    end

    local categories = {}
    repeat
        local cat_id = results:GetUInt32(0)
        local cat_name = results:GetString(1)
        categories[cat_id] = cat_name
    until not results:NextRow()

    return categories
end

function Repository:GetConfigStatistics()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_STAT, Constants.DB_NAME))
    if not results then
        return false
    end

    local statistics = {}
    repeat
        local stat_id       = results:GetUInt32(0)
        local stat_cat      = results:GetUInt32(1)
        local stat_type     = results:GetString(2)
        local stat_value    = results:GetString(3)
        local stat_icon     = results:GetString(4)
        local stat_factor   = results:GetUInt32(5)
        local stat_limit    = results:GetUInt32(6)
        local stat_application = results:GetUInt32(7)

        statistics[stat_cat] = statistics[stat_cat] or {}
        statistics[stat_cat][stat_id] = {
            type        = stat_type,
            value       = stat_value,
            icon        = stat_icon,
            factor      = stat_factor,
            limit       = stat_limit,
            application = stat_application
        }
    until not results:NextRow()

    return statistics
end

function Repository:GetConfig()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG, Constants.DB_NAME))
    if not results then
        return false
    end

    local config = {}
    repeat
        local conf_field = results:GetString(0)
        local conf_value = results:GetString(1)
        config[conf_field] = conf_value
    until not results:NextRow()

    return config
end

-- ============================================================================
-- EXPERIENCE REWARDS QUERIES
-- ============================================================================

local function ProcessExperienceResults(results)
    if not results then
        return {}
    end

    local data = {}
    repeat
        local entry      = results:GetUInt32(0)
        local experience = results:GetUInt32(1)
        data[entry] = experience
    until not results:NextRow()

    return data
end

function Repository:GetConfigCreatureExperience()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_EXP_CREATURE, Constants.DB_NAME))
    return ProcessExperienceResults(results)
end

function Repository:GetConfigAchievementExperience()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_EXP_ACHIEVEMENT, Constants.DB_NAME))
    return ProcessExperienceResults(results)
end

function Repository:GetConfigSkillExperience()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_EXP_SKILL, Constants.DB_NAME))
    return ProcessExperienceResults(results)
end

function Repository:GetConfigQuestExperience()
    local results = CharDBQuery(sf(Constants.QUERY.SEL_CONFIG_EXP_QUEST, Constants.DB_NAME))
    return ProcessExperienceResults(results)
end

-- ============================================================================
-- CHARACTER PARAGON DATA
-- ============================================================================

function Repository:GetParagonByCharacter(guid, callback)
    if not guid or not callback then
        return
    end

    CharDBQueryAsync(sf(Constants.QUERY.SEL_PARA_CHARACTER, Constants.DB_NAME, guid), function(results)
        local data = {}
        if results then
            repeat
                data.level = results:GetUInt32(0)
                data.current_experience = results:GetUInt32(1)
            until not results:NextRow()
        end
        callback(data)
    end)
end

function Repository:GetParagonByAccountId(account_id, callback)
    if not account_id or not callback then
        return
    end

    CharDBQueryAsync(sf(Constants.QUERY.SEL_PARA_ACCOUNT, Constants.DB_NAME, account_id), function(results)
        local data = {}
        if results then
            repeat
                data.level = results:GetUInt32(0)
                data.current_experience = results:GetUInt32(1)
            until not results:NextRow()
        end
        callback(data)
    end)
end

function Repository:GetParagonStatByCharacter(guid, callback)
    if not guid or not callback then
        return
    end

    CharDBQueryAsync(sf(Constants.QUERY.SEL_PARA_STAT, Constants.DB_NAME, guid), function(results)
        local data = {}
        if results then
            repeat
                local stat_id    = results:GetUInt32(0)
                local stat_value = results:GetUInt32(1)
                data[stat_id] = stat_value
            until not results:NextRow()
        end
        callback(data)
    end)
end

function Repository:SaveParagonCharacterStat(guid, statistics)
    if not guid or not statistics then
        return
    end

    -- FIX : CharDBExecute est asynchrone (fire-and-forget). Au logout, la requete
    -- peut etre annulee avant execution si la session se ferme trop vite.
    -- CharDBQuery est synchrone/bloquant : l'ecriture est garantie avant retour.
    for stat_id, stat_value in pairs(statistics) do
        local query = sf(Constants.QUERY.INS_PARA_STAT, Constants.DB_NAME, guid, stat_id, stat_value)
        -- print("[Paragon SAVE] SaveParagonCharacterStat QUERY = " .. query)
        CharDBQuery(query)
    end
end

-- ============================================================================
-- SYNCHRONOUS QUERIES
-- ============================================================================

function Repository:GetParagonByCharacterSync(guid)
    if not guid then return {} end
    local results = CharDBQuery(sf(Constants.QUERY.SEL_PARA_CHARACTER, Constants.DB_NAME, guid))
    if not results then return {} end
    return {
        level = results:GetUInt32(0),
        current_experience = results:GetUInt32(1)
    }
end

function Repository:GetParagonStatByCharacterSync(guid)
    if not guid then return {} end
    local results = CharDBQuery(sf(Constants.QUERY.SEL_PARA_STAT, Constants.DB_NAME, guid))
    local data = {}
    if results then
        repeat
            local stat_id    = results:GetUInt32(0)
            local stat_value = results:GetUInt32(1)
            data[stat_id] = stat_value
        until not results:NextRow()
    end
    return data
end

-- ============================================================================
-- SAVE — CHARACTER
-- ============================================================================

function Repository:SaveParagonByCharacter(guid, level, experience)
    if not guid or not level then
        -- print("[Paragon SAVE ERROR] SaveParagonByCharacter: guid ou level nil !")
        return
    end

    -- CharDBQuery est SYNCHRONE et bloquant : il attend que le write soit
    -- committed avant de retourner. CharDBExecute est async (fire-and-forget) :
    -- la requête est mise en queue et exécutée plus tard, ce qui causait le bug
    -- où OnPlayerLogout écrasait la progression avec l'ancienne valeur DB.
    -- On utilise INSERT ... ON DUPLICATE KEY UPDATE comme avant, mais via
    -- CharDBQuery pour garantir l'écriture immédiate et synchrone.
    local query = sf(Constants.QUERY.INS_PARA_CHARACTER, Constants.DB_NAME, guid, level, experience or 0)
    -- print("[Paragon SAVE] SaveParagonByCharacter QUERY = " .. query)
    CharDBQuery(query)
end

function Repository:SaveParagonByCharacterSync(guid, level, experience)
    self:SaveParagonByCharacter(guid, level, experience)
end

-- ============================================================================
-- SAVE — ACCOUNT
-- ============================================================================

function Repository:SaveParagonByAccount(account_id, level, experience)
    if not account_id or not level then
        -- print("[Paragon SAVE ERROR] SaveParagonByAccount: account_id ou level nil !")
        return
    end

    local query = sf(Constants.QUERY.INS_PARA_ACCOUNT, Constants.DB_NAME, account_id, level, experience or 0)
    -- print("[Paragon SAVE] SaveParagonByAccount QUERY = " .. query)
    CharDBQuery(query)
end

function Repository:SaveParagonByAccountSync(account_id, level, experience)
    self:SaveParagonByAccount(account_id, level, experience)
end

-- ============================================================================
-- DELETE
-- ============================================================================

function Repository:DeleteParagonData(guid)
    if not guid then
        return
    end

    CharDBExecute(sf(Constants.QUERY.DEL_PARA_CHARACTER, Constants.DB_NAME, guid))
    CharDBExecute(sf(Constants.QUERY.DEL_PARA_STAT, Constants.DB_NAME, guid))
end

-- ============================================================================
-- SINGLETON MANAGEMENT
-- ============================================================================

function Repository:GetInstance()
    if not Instance then
        Instance = Repository()
    end

    return Instance
end

return Repository:GetInstance()
