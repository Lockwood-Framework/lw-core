-- ---------------------------------------------------------------------------
-- Permissions API
-- Wraps the CFX ACE system into a centralized, resource-aware API.
--
-- Three concerns are handled here:
--   1. Group assignment   — applies a player's server group principal on connect
--   2. Permission registry — resources declare which roles unlock which perms
--   3. Character permissions — contributors push roles on character selection,
--                              core resolves and applies ACE grants, fires done
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Permission registry
-- Keyed by resource name. Each entry is a table of { [permString] = { conditions } }
-- where each condition is a table with at minimum a `type` string field.
-- Cleared automatically when a resource stops.
-- ---------------------------------------------------------------------------
local _registry = {}

-- ---------------------------------------------------------------------------
-- Contributor registry
-- Keyed by resource name. Value is true while the resource is registered.
-- Tracks which resources will push roles when a character is selected.
-- ---------------------------------------------------------------------------
local _contributors = {}

-- ---------------------------------------------------------------------------
-- Per-source contributor state
-- Tracks pending permission contributions for each player during character selection.
-- Keyed by source. Each entry:
--   roles     : table  — accumulated permission name strings from all contributors
--   pending   : table  — set of contributor resource names not yet done
--   timer     : number — Citizen.SetTimeout handle for the fallback timeout
-- ---------------------------------------------------------------------------
local _pending = {}

-- ---------------------------------------------------------------------------
-- Internal: apply ACE grants for a resolved set of permissions.
-- Contributors now evaluate conditions themselves and pass permission name
-- strings directly via GrantRoles — no role→perm mapping needed here.
-- ---------------------------------------------------------------------------
local function applyPermissions(source, permissions)
    local session = LWCore.Sessions[source]
    if not session then return end

    local granted = {}

    for _, perm in ipairs(permissions) do
        if not granted[perm] then
            granted[perm] = true
            ExecuteCommand(string.format(
                'add_ace identifier.license2:%s %s allow',
                session.license2, perm
            ))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Internal: resolve and apply all accumulated roles for a source, then fire
-- the done event and clean up pending state.
-- ---------------------------------------------------------------------------
local function commitPermissions(source, reason)
    local state = _pending[source]
    if not state then return end

    -- Cancel the fallback timer if we are committing early
    if state.timer then
        Citizen.ClearTimeout(state.timer)
    end

    if reason == 'timeout' then
        local remaining = {}
        for name in pairs(state.pending) do
            remaining[#remaining + 1] = name
        end
        print(string.format(
            '[lw-core] permission timeout for source %d — stalled contributor(s): %s',
            source, table.concat(remaining, ', ')
        ))
    end

    applyPermissions(source, state.roles)
    _pending[source] = nil

    TriggerEvent('lw-core:permissionsApplied', source, reason)
end

-- ---------------------------------------------------------------------------
-- LWCore.AssignGroupPrincipal
-- Adds the player's group as an ACE principal so the static hierarchy in the
-- ACE config takes effect. Called on session creation.
-- ---------------------------------------------------------------------------
function LWCore.AssignGroupPrincipal(source)
    local session = LWCore.Sessions[source]
    if not session then return end

    ExecuteCommand(string.format(
        'add_principal identifier.license2:%s group.%s',
        session.license2, session.group
    ))
end

-- ---------------------------------------------------------------------------
-- LWCore.RevokeGroupPrincipal
-- Removes the group principal on disconnect.
-- ---------------------------------------------------------------------------
function LWCore.RevokeGroupPrincipal(source)
    local session = LWCore.Sessions[source]
    if not session then return end

    ExecuteCommand(string.format(
        'remove_principal identifier.license2:%s group.%s',
        session.license2, session.group
    ))
end

-- ---------------------------------------------------------------------------
-- LWCore.RevokeCharacterPermissions
-- Removes all ACE grants that were applied for a character. Called when
-- lw-core:characterUnloaded fires (logout or disconnect).
-- ---------------------------------------------------------------------------
function LWCore.RevokeCharacterPermissions(source)
    local session = LWCore.Sessions[source]
    if not session then return end

    local revoked = {}

    for _, perms in pairs(_registry) do
        for permName in pairs(perms) do
            if not revoked[permName] then
                revoked[permName] = true
                ExecuteCommand(string.format(
                    'remove_ace identifier.license2:%s %s allow',
                    session.license2, permName
                ))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- LWCore.BeginPermissionCollection
-- Called internally when lw-core:characterSelected fires. Initialises pending
-- state for this source and starts the fallback timeout.
-- ---------------------------------------------------------------------------
function LWCore.BeginPermissionCollection(source)
    -- If a previous collection is still open (shouldn't happen, but be safe)
    if _pending[source] then
        Citizen.ClearTimeout(_pending[source].timer)
    end

    local pending = {}
    for name in pairs(_contributors) do
        pending[name] = true
    end

    -- If no contributors are registered, apply immediately with no roles
    if not next(pending) then
        TriggerEvent('lw-core:permissionsApplied', source, 'immediate')
        return
    end

    _pending[source] = {
        roles   = {},
        pending = pending,
        timer   = Citizen.SetTimeout(Config.PermissionTimeout, function()
            commitPermissions(source, 'timeout')
        end),
    }
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

-- RegisterPermissions
-- Called by a resource on start to declare its permission domain.
--
-- perms format: { ['resource.permname'] = { conditions } }
-- Each condition is a table with at minimum a `type` string field and a `value` field.
-- Multiple conditions on one permission use OR logic — any passing condition
-- grants the permission. Evaluation is performed by contributor resources via
-- GetConditionsForType, not by lw-core itself.
--
-- Example:
--   exports['lw-core']:RegisterPermissions('lw-medicine', {
--       ['medicine.licensed'] = {
--           { type = 'org_role', value = 'doctor'      },
--           { type = 'org_role', value = 'field_medic' },
--       },
--   })
exports('RegisterPermissions', function(resourceName, perms)
    if type(perms) ~= 'table' then
        print('[lw-core] RegisterPermissions: invalid perms table from "' .. tostring(resourceName) .. '"')
        return
    end

    local validated = {}

    for permName, conditions in pairs(perms) do
        if type(permName) ~= 'string' then
            print(string.format('[lw-core] RegisterPermissions: permission name must be a string (resource: %s)', resourceName))
        elseif type(conditions) ~= 'table' then
            print(string.format('[lw-core] RegisterPermissions: conditions for "%s" must be a table (resource: %s)', permName, resourceName))
        else
            local valid = true
            for i, condition in ipairs(conditions) do
                if type(condition) ~= 'table' or type(condition.type) ~= 'string' then
                    print(string.format(
                        '[lw-core] RegisterPermissions: condition %d for "%s" must be a table with a string `type` field (resource: %s)',
                        i, permName, resourceName
                    ))
                    valid = false
                    break
                end
            end
            if valid then
                validated[permName] = conditions
            end
        end
    end

    _registry[resourceName] = validated
end)

-- RegisterPermissionContributor
-- Called by a resource on start to declare it will push roles on character
-- selection. Resources that only declare permissions but never push roles
-- (e.g. a resource whose perms are always granted via group hierarchy)
-- should NOT register as contributors.
exports('RegisterPermissionContributor', function(resourceName)
    _contributors[resourceName] = true
end)

-- GrantRoles
-- Called by a contributor when it has resolved the character's roles.
-- Roles are accumulated immediately. ACE grants are NOT applied per-call —
-- they are applied once all contributors have called DoneContributing or
-- the timeout fires, to avoid partial-grant states during resolution.
exports('GrantRoles', function(source, roles)
    local state = _pending[source]
    if not state then
        print(string.format(
            '[lw-core] GrantRoles called for source %d with no active collection — ignored',
            source
        ))
        return
    end

    for _, role in ipairs(roles) do
        state.roles[#state.roles + 1] = role
    end
end)

-- DoneContributing
-- Called by a contributor once it has finished pushing all roles for a source.
-- When all registered contributors have called this, permissions are applied.
exports('DoneContributing', function(source, resourceName)
    local state = _pending[source]
    if not state then return end

    state.pending[resourceName] = nil

    if not next(state.pending) then
        commitPermissions(source, 'complete')
    end
end)

-- HasAcePermission
exports('HasAcePermission', function(source, permission)
    return IsPlayerAceAllowed(source, permission)
end)

-- IsPlayerAdmin
exports('IsPlayerAdmin', function(source)
    return IsPlayerAceAllowed(source, 'lw-core.admin')
end)

-- GetConditionsForType
-- Returns all registered permissions that have at least one condition of the
-- given type, along with only the matching conditions for that type.
--
-- Contributor resources call this on lw-core:characterSelected to know which
-- permissions fall within their domain to evaluate. Each contributor only
-- handles condition types it owns — lw-organizations-api handles 'org_role'
-- and 'rank', other resources handle their own types.
--
-- Returns an array of:
--   { permission = string, resource = string, conditions = table[] }
--
-- Example:
--   local entries = exports['lw-core']:GetConditionsForType('org_role')
--   for _, entry in ipairs(entries) do
--       -- entry.permission = 'medicine.licensed'
--       -- entry.conditions = { { type = 'org_role', value = 'doctor' }, ... }
--   end
exports('GetConditionsForType', function(conditionType)
    local results = {}

    for resourceName, perms in pairs(_registry) do
        for permName, conditions in pairs(perms) do
            local matching = {}
            for _, condition in ipairs(conditions) do
                if condition.type == conditionType then
                    matching[#matching + 1] = condition
                end
            end
            if #matching > 0 then
                results[#results + 1] = {
                    permission = permName,
                    resource   = resourceName,
                    conditions = matching,
                }
            end
        end
    end

    return results
end)

-- ---------------------------------------------------------------------------
-- Auto-cleanup on resource stop
-- Removes the stopped resource from the registry and contributor table.
-- Any permissions it registered remain in effect until the player disconnects
-- or selects a new character — they are not retroactively revoked, which would
-- require re-running the full permission resolution for every online player.
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    _registry[resourceName]     = nil
    _contributors[resourceName] = nil
end)

-- ---------------------------------------------------------------------------
-- Begin collection when a character is selected
-- ---------------------------------------------------------------------------
AddEventHandler('lw-core:characterSelected', function(source)
    LWCore.BeginPermissionCollection(source)
end)

-- ---------------------------------------------------------------------------
-- Revoke character permissions when a character is unloaded
-- ---------------------------------------------------------------------------
AddEventHandler('lw-core:characterUnloaded', function(source)
    LWCore.RevokeCharacterPermissions(source)
end)