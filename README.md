# lw-core

Core session, lifecycle, routing bucket management, and permissions API for Lockwood RP.

## Dependencies

- `lw-db` — database access and migration engine

## What it does

Manages the player session lifecycle from connection to disconnect, owns routing bucket allocation, wraps the CFX ACE permissions system, and provides a server-side callback system for client/server request-response flows.

## Configuration

All configuration lives in `config/server/config.lua`.

| Key | Type | Description |
|---|---|---|
| `StateIdPrefix` | string | 2–4 uppercase letters prepended to every generated state ID |
| `StateIdCharset` | string | Characters used for the random portion of state IDs |
| `StateIdRandomLength` | number | Length of the random portion (default 13) |
| `DefaultGroup` | string | ACE group assigned to players not listed in `PlayerGroups` |
| `Groups` | table | All valid server groups — must include `DefaultGroup` |
| `PlayerGroups` | table | Maps `license2:xxxx` identifiers to a specific group |
| `SaveInterval` | number | How often (minutes) `last_seen` is flushed for all sessions |
| `PermissionTimeout` | number | Milliseconds before permission collection falls back |

## ACE setup

Create a config file loaded before lw-core in `server.cfg` that defines the group hierarchy and grants lw-core permission to manage ACE at runtime:

```
add_principal group.lw.mod        group.lw.user
add_principal group.lw.admin      group.lw.mod
add_principal group.lw.dev        group.lw.admin
add_principal group.lw.superadmin group.lw.dev

add_ace resource.lw-core command.add_ace        allow
add_ace resource.lw-core command.remove_ace     allow
add_ace resource.lw-core command.add_principal  allow
add_ace resource.lw-core command.remove_principal allow
```

## Database

Creates one table on first run: `lw_players` (`license2`, `name`, `group`, `created_at`, `last_seen`).

State IDs live in `lw_characters`, owned by lw-characters-api. On restart, lw-core detects prefix changes and migrates existing state IDs automatically.

## Server exports

### Session reads
```lua
exports['lw-core']:GetPlayer(source)               -- session table or nil
exports['lw-core']:GetPlayerByLicense2(license2)   -- session table or nil
exports['lw-core']:GetAllPlayers()                 -- all active sessions keyed by source
exports['lw-core']:GetPlayerCount()                -- number of active sessions
exports['lw-core']:GetOfflinePlayer(license2)      -- lw_players row or nil (sync, requires thread)
```

### Session writes
```lua
exports['lw-core']:SetActiveCharacter(source, stateId)  -- attach character to session
exports['lw-core']:ClearActiveCharacter(source)         -- detach character from session
exports['lw-core']:Logout(source)                       -- return player to character selection
```

### State IDs
```lua
exports['lw-core']:RequestStateId()  -- generate a unique state ID (sync, requires thread)
```

### Routing buckets
```lua
exports['lw-core']:RegisterBucket(key, owner)    -- allocate a bucket, returns bucketId or nil
exports['lw-core']:DeregisterBucket(key, owner)  -- release a bucket, evicts players to bucket 0
exports['lw-core']:AssignPlayer(source, key)     -- move player into a registered bucket
exports['lw-core']:RemovePlayer(source)          -- return player to bucket 0
```

### Permissions
```lua
exports['lw-core']:RegisterPermissions(resourceName, perms)
-- perms: { ['perm.name'] = { 'role1', 'role2' } }

exports['lw-core']:RegisterPermissionContributor(resourceName)
exports['lw-core']:GrantRoles(source, roles)
exports['lw-core']:DoneContributing(source, resourceName)

exports['lw-core']:HasAcePermission(source, permission)  -- boolean
exports['lw-core']:IsPlayerAdmin(source)                 -- boolean
```

### Identifiers
```lua
exports['lw-core']:GetIdentifier(source, type)   -- bare identifier string or nil
exports['lw-core']:GetAllIdentifiers(source)     -- table of all available identifiers
-- types: 'license', 'license2', 'steam', 'discord', 'ip'
```

### Callbacks
```lua
-- Server: register a handler
exports['lw-core']:RegisterCallback('myresource:getName', function(source, resolve, ...)
    resolve('some value')
end)

-- Client: trigger and receive response
exports['lw-core']:TriggerServerCallback('myresource:getName', function(result)
    print(result)
end)
```

## Client exports

```lua
exports['lw-core']:TriggerServerCallback(name, cb, ...)  -- trigger a server callback
exports['lw-core']:GetSessionData()                      -- { license2, name, group } or nil
```

## Events fired (server)

| Event | Args | When |
|---|---|---|
| `lw-core:ready` | — | Boot complete, DB live |
| `lw-core:playerConnected` | `source, session` | Session created, no character yet |
| `lw-core:characterSelected` | `source, stateId` | Character attached to session |
| `lw-core:characterUnloaded` | `source, prevStateId` | Character detached (logout or disconnect) |
| `lw-core:playerLogout` | `source` | Player returned to character selection (not a disconnect) |
| `lw-core:playerDropped` | `source, session, reason` | Player disconnected, session still readable |
| `lw-core:permissionsApplied` | `source, reason` | All contributors done (`'complete'`, `'timeout'`, `'immediate'`) |

## Events fired (client)

| Event | Args | When |
|---|---|---|
| `lw-core:sessionReady` | `sessionData` | Server confirmed session, client can proceed |
| `lw-core:enterCharacterSelection` | — | Server triggered logout flow |

## Copyright

Copyright 2026 Morgrhim. All rights reserved.