-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- Session store
-- Keyed by source (integer). Each entry is the in-memory session for one
-- connected player. Nil stateId means the player has no active character.
--
-- Schema:
--   source    : integer  — current FiveM source ID
--   license2  : string   — immutable for the lifetime of the session
--   name      : string   — GetPlayerName value at connect, may differ from DB
--   group     : string   — server group, synced from config on connect
--   stateId   : string?  — active character state ID, nil until set
-- ---------------------------------------------------------------------------
LWCore.Sessions = {}

local DB = exports['lw-db'].DB()

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Resolves a player's group from config. Falls back to DefaultGroup if the
-- license2 is not listed in PlayerGroups.
local function resolveGroup(license2)
    return Config.PlayerGroups[license2] or Config.DefaultGroup
end

-- ---------------------------------------------------------------------------
-- LWCore.CreateSession
-- Called by lifecycle.lua once a connecting player has been validated.
-- Upserts the lw_players row and builds the in-memory session.
-- Must be called inside a Citizen.CreateThread.
-- ---------------------------------------------------------------------------
function LWCore.CreateSession(source, license2)
    local name  = GetPlayerName(source)
    local group = resolveGroup(license2)

    -- Upsert: insert on first ever connection, update name/group on return.
    DB.update(
        [[INSERT INTO `lw_players` (`license2`, `name`, `group`)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE
            `name`      = IF(`name` <> VALUES(`name`), VALUES(`name`), `name`),
            `group`     = VALUES(`group`),
            `last_seen` = CURRENT_TIMESTAMP]],
        { license2, name, group }
    )

    local session = {
        source   = source,
        license2 = license2,
        name     = name,
        group    = group,
        stateId  = nil,
    }

    LWCore.Sessions[source] = session
    return session
end

-- ---------------------------------------------------------------------------
-- LWCore.DestroySession
-- Removes the session from the store. Does not save — callers are responsible
-- for flushing last_seen before calling this (save.lua handles that).
-- ---------------------------------------------------------------------------
function LWCore.DestroySession(source)
    LWCore.Sessions[source] = nil
end

-- ---------------------------------------------------------------------------
-- LWCore.SetActiveCharacter
-- Attaches a stateId to an existing session. Fires lw-core:characterSelected.
-- Returns false if no session exists for the source.
-- ---------------------------------------------------------------------------
function LWCore.SetActiveCharacter(source, stateId)
    local session = LWCore.Sessions[source]
    if not session then return false end

    session.stateId = stateId
    TriggerEvent('lw-core:characterSelected', source, stateId)
    return true
end

-- ---------------------------------------------------------------------------
-- LWCore.ClearActiveCharacter
-- Removes the stateId from a session, returning the player to a character-
-- less state. Fires lw-core:characterUnloaded.
-- Returns false if no session exists for the source.
-- ---------------------------------------------------------------------------
function LWCore.ClearActiveCharacter(source)
    local session = LWCore.Sessions[source]
    if not session then return false end

    local prev = session.stateId
    session.stateId = nil
    TriggerEvent('lw-core:characterUnloaded', source, prev)
    return true
end

-- ---------------------------------------------------------------------------
-- LWCore.Logout
-- Keeps the session alive but clears the active character, then reassigns
-- the player to their private routing bucket so character selection can
-- restart. Distinct from a full disconnect — lw_players row is untouched.
--
-- Event order:
--   1. lw-core:characterUnloaded  — resources save and clean up character state
--   2. lw-core:playerLogout       — resources that specifically care about the
--                                   logout flow (vs disconnect) act here
-- ---------------------------------------------------------------------------
function LWCore.Logout(source)
    local session = LWCore.Sessions[source]
    if not session then return false end

    LWCore.ClearActiveCharacter(source)           -- fires lw-core:characterUnloaded
    TriggerEvent('lw-core:playerLogout', source) -- logout-specific cleanup
    LWCore.AssignPlayer(source, source)           -- private bucket keyed by source
    TriggerClientEvent('lw-core:client:enterCharacterSelection', source)
    return true
end

-- ---------------------------------------------------------------------------
-- LWCore.SyncPlayerGroups
-- Called once on boot from main.lua. Updates the group column for every row
-- in lw_players to match the current config. Rows whose license2 is not in
-- Config.PlayerGroups receive Config.DefaultGroup.
-- Must be called inside a Citizen.CreateThread (boot sequence satisfies this).
-- ---------------------------------------------------------------------------
function LWCore.SyncPlayerGroups()
    local rows = DB.query('SELECT `license2` FROM `lw_players`', {})
    if not rows or #rows == 0 then return end

    local queries = {}
    for _, row in ipairs(rows) do
        local group = resolveGroup(row.license2)
        queries[#queries + 1] = {
            query  = 'UPDATE `lw_players` SET `group` = ? WHERE `license2` = ?',
            values = { group, row.license2 },
        }
    end

    local ok = DB.transaction(queries, {})
    if ok then
        print('[lw-core] player groups synced (' .. #rows .. ' row(s))')
    else
        print('[lw-core] ERROR: player group sync failed — check DB logs')
    end
end

-- ---------------------------------------------------------------------------
-- Read exports
-- ---------------------------------------------------------------------------

exports('GetPlayer', function(source)
    return LWCore.Sessions[source]
end)

exports('GetPlayerByLicense2', function(license2)
    for _, session in pairs(LWCore.Sessions) do
        if session.license2 == license2 then
            return session
        end
    end
    return nil
end)

exports('GetAllPlayers', function()
    return LWCore.Sessions
end)

exports('GetPlayerCount', function()
    local count = 0
    for _ in pairs(LWCore.Sessions) do
        count = count + 1
    end
    return count
end)

exports('GetOfflinePlayer', function(license2)
    local results = DB.query('SELECT `license2`, `name`, `group`, `created_at`, `last_seen` FROM `lw_players` WHERE `license2` = ? LIMIT 1', { license2 })
    local row = results and results[1]
    
    return row or nil
end)

-- ---------------------------------------------------------------------------
-- Write exports
-- ---------------------------------------------------------------------------

exports('SetActiveCharacter', function(source, stateId)
    return LWCore.SetActiveCharacter(source, stateId)
end)

exports('ClearActiveCharacter', function(source)
    return LWCore.ClearActiveCharacter(source)
end)

exports('Logout', function(source)
    return LWCore.Logout(source)
end)