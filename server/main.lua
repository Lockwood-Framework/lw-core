-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- LWCore global
-- All submodules attach themselves to this table. Consumers use exports, not
-- this global directly — it is internal to lw-core's own server scripts.
-- ---------------------------------------------------------------------------
LWCore = {}

-- ---------------------------------------------------------------------------
-- Database migration
-- ---------------------------------------------------------------------------
exports['lw-db']:RegisterMigration(
    'lw-core',
    '001_create_players',
    [[
        CREATE TABLE IF NOT EXISTS `lw_players` (
            `license2`   VARCHAR(60)  NOT NULL,
            `name`       VARCHAR(255) NOT NULL,
            `group`      VARCHAR(64)  NOT NULL DEFAULT 'lw.user',
            `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `last_seen`  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`license2`),
            KEY `idx_group` (`group`)
        )
    ]]
)

AddEventHandler('lw-db:ready', function()
    CreateThread(function()
        LWCore.OnDBReady()
    end)
end)

-- ---------------------------------------------------------------------------
-- Boot sequence — called once lw-db confirms migrations have run
-- ---------------------------------------------------------------------------
function LWCore.OnDBReady()
    -- Validate config before touching the DB
    LWCore.ValidateConfig()

    -- Run startup routines that depend on the DB being live
    LWCore.MigrateStateIdPrefix()  -- server/stateid.lua
    LWCore.SyncPlayerGroups()      -- server/session.lua
    LWCore.StartSaveLoop()         -- server/save.lua

    TriggerEvent('lw-core:ready')
    print('[lw-core] Ready.')
end

-- ---------------------------------------------------------------------------
-- Config validation
-- Catches bad config values early so errors surface at startup, not mid-session.
-- ---------------------------------------------------------------------------
function LWCore.ValidateConfig()
    local prefix = Config.StateIdPrefix
    assert(
        type(prefix) == 'string'
        and #prefix >= 2
        and #prefix <= 4
        and (prefix:match('^[A-Z]+$') ~= nil),
        '[lw-core] Config.StateIdPrefix must be 2–4 uppercase letters. Got: ' .. tostring(prefix)
    )

    assert(
        type(Config.DefaultGroup) == 'string' and #Config.DefaultGroup > 0,
        '[lw-core] Config.DefaultGroup must be a non-empty string.'
    )

    local groupSet = {}
    for _, g in ipairs(Config.Groups) do
        groupSet[g] = true
    end

    assert(
        groupSet[Config.DefaultGroup],
        '[lw-core] Config.DefaultGroup "' .. Config.DefaultGroup .. '" is not listed in Config.Groups.'
    )

    for license2, group in pairs(Config.PlayerGroups) do
        assert(
            groupSet[group],
            '[lw-core] Config.PlayerGroups entry for "' .. license2 .. '" references unknown group "' .. group .. '".'
        )
    end

    assert(
        type(Config.SaveInterval) == 'number' and Config.SaveInterval > 0,
        '[lw-core] Config.SaveInterval must be a positive number (minutes).'
    )

    assert(
        type(Config.PermissionTimeout) == 'number' and Config.PermissionTimeout > 0,
        '[lw-core] Config.PermissionTimeout must be a positive number (milliseconds).'
    )

    assert(
        type(Config.StateIdRandomLength) == 'number' and Config.StateIdRandomLength > 0,
        '[lw-core] Config.StateIdRandomLength must be a positive number.'
    )

    assert(
        type(Config.StateIdCharset) == 'string' and #Config.StateIdCharset >= 10,
        '[lw-core] Config.StateIdCharset must be a string with at least 10 characters.'
    )
end