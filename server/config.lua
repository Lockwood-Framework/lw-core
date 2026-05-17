-- Copyright 2026 Morgrhim. All rights reserved.

Config = {}

-- ---------------------------------------------------------------------------
-- State ID
-- ---------------------------------------------------------------------------
-- Prefix for all generated state IDs. Must be 2–4 uppercase letters.
-- If this changes between server restarts, lw-core will automatically
-- update every existing state ID in the database and cascade the change.
Config.StateIdPrefix = 'LW'

-- Characters used when generating the random portion of a state ID.
-- Do not modify unless you have a very good reason. All uppercase alphanumeric.
Config.StateIdCharset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

-- Length of the random portion appended after the prefix.
Config.StateIdRandomLength = 13

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------
-- The group assigned to any player whose license2 is not in PlayerGroups.
Config.DefaultGroup = 'lw-user'

-- All valid server groups. Used for validation and ACE principal assignment.
-- Hierarchy is defined in the server ACE config, not here.
Config.Groups = {
    'lw-user',
    'lw-mod',
    'lw-admin',
    'lw-dev',
    'lw-superadmin',
}

-- Map a player's license2 identifier to a specific group.
-- Players not listed here receive Config.DefaultGroup.
-- Format: ['license2:XXXX'] = 'lw.superadmin'
Config.PlayerGroups = {
    ['license2:dd39ad26cf8b67f1a2cabed316bb59f7aafd7e33'] = 'lw-superadmin'
}

-- ---------------------------------------------------------------------------
-- Session save
-- ---------------------------------------------------------------------------
-- How often (in minutes) lw-core flushes last_seen for all active sessions.
-- Also flushed on playerDropped regardless of this interval.
Config.SaveInterval = 5

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
-- How long (in milliseconds) lw-core waits for all registered permission
-- contributors to call DoneContributing before applying whatever has arrived.
-- Fires lw-core:permissionsApplied with a 'timeout' reason so you can diagnose
-- which contributor stalled. Set high enough that a cold DB lookup won't trip it.
Config.PermissionTimeout = 5000