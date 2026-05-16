--[[
    Paragon Target Level Module

    Displays the Paragon level of the player's current target in the UI.
    Only works when targeting another player character.

    Features:
    - Server-side hook to retrieve target's Paragon level
    - Client-side UI display near target frame
    - Automatic updates when target changes

    Fix:
    - Replaced target:IsPlayer() with target:GetTypeId() == 4 (TYPEID_PLAYER).
      IsPlayer() is NOT exposed in the Eluna TrinityWotlk Lua API — it is a C++
      internal method on Unit. The equivalent in Eluna is GetTypeId(), which returns:
        0 = TYPEID_OBJECT
        1 = TYPEID_ITEM
        2 = TYPEID_CONTAINER
        3 = TYPEID_UNIT (Creature/NPC)
        4 = TYPEID_PLAYER
        5 = TYPEID_GAMEOBJECT
        6 = TYPEID_DYNAMICOBJECT
        7 = TYPEID_CORPSE
    - Added nil guard on target:GetTypeId() in case GetSelection() returns an
      already-expired/invalid object reference.

    @module paragon_target_level
    @author Paragon Team
]]

-- TYPEID constants (TrinityCore TypeID enum)
local TYPEID_PLAYER = 4

-- ============================================================================
-- MODULE CONFIGURATION
-- ============================================================================

local ParagonHook = require("paragon_hook")
ParagonHook.Addon.Functions[6] = "OnParagonClientRequestTargetLevel"

RegisterClientRequests(ParagonHook.Addon, true)

-- ============================================================================
-- SERVER HOOK HANDLERS
-- ============================================================================

---
--- Handles client request to get the Paragon level of their current target.
---
--- Validates that the target exists and is a player, then retrieves their
--- Paragon data and sends the level back to the requesting client.
---
--- Uses target:GetTypeId() == TYPEID_PLAYER (4) instead of IsPlayer(), which
--- is not exposed in the Eluna TrinityWotlk Lua API.
---
--- @param player The player object making the request
--- @param _ Unused parameter (always nil for addon requests)
--- @return boolean True if target level was sent, false otherwise
---
function OnParagonClientRequestTargetLevel(player, _)
    if not player then
        return false
    end

    -- Get the player's current target
    local target = player:GetSelection()
    if not target then
        -- No target selected, send level 0 to hide UI
        player:SendServerResponse(ParagonHook.Addon.Prefix, 6, 0)
        return false
    end

    -- Check if target is a player using GetTypeId()
    -- IsPlayer() is not exposed in Eluna TrinityWotlk — use GetTypeId() == 4
    local type_id = target:GetTypeId()
    if not type_id or type_id ~= TYPEID_PLAYER then
        -- Target is not a player, send level 0 to hide UI
        player:SendServerResponse(ParagonHook.Addon.Prefix, 6, 0)
        return false
    end

    -- Cast to Player to access player-specific data
    -- ToPlayer() returns nil if the unit is not actually a player
    local target_player = target:ToPlayer()
    if not target_player then
        player:SendServerResponse(ParagonHook.Addon.Prefix, 6, 0)
        return false
    end

    -- Get target's Paragon data
    local target_paragon = ParagonHook.CacheGet(target_player)
    if not target_paragon then
        -- Target has no Paragon data (shouldn't happen but handle gracefully)
        player:SendServerResponse(ParagonHook.Addon.Prefix, 6, 0)
        return false
    end

    -- Send target's Paragon level to the client
    local target_level = target_paragon:GetLevel()
    player:SendServerResponse(ParagonHook.Addon.Prefix, 6, target_level or 0)

    return true
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

-- print("[Paragon] Paragon Anniversary Target Level module loaded")
