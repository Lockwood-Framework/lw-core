-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- Identifier utilities
-- Provides a clean wrapper around FiveM's GetPlayerIdentifierByType so no
-- other resource needs to handle the raw identifier string format or write
-- their own stripping logic.
--
-- Supported types (passed as the type string):
--   'license'   — Rockstar license (license:xxxx)
--   'license2'  — Rockstar license v2 (license2:xxxx)
--   'steam'     — Steam ID (steam:xxxx)
--   'discord'   — Discord ID (discord:xxxx)
--   'ip'        — IP address (ip:xxxx)
--
-- Returns the bare value with the type prefix stripped, or nil if not found.
-- ---------------------------------------------------------------------------

local _prefixes = {
    license  = 'license:',
    license2 = 'license2:',
    steam    = 'steam:',
    discord  = 'discord:',
    ip       = 'ip:',
}

local function getIdentifier(source, identType)
    local prefix = _prefixes[identType]
    if not prefix then
        print('[lw-core] GetIdentifier: unknown identifier type "' .. tostring(identType) .. '"')
        return nil
    end

    local raw = GetPlayerIdentifierByType(source, identType)
    if not raw then return nil end

    return (raw:gsub('^' .. prefix, ''))
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('GetIdentifier', function(source, identType)
    return getIdentifier(source, identType)
end)

exports('GetAllIdentifiers', function(source)
    local result = {}
    for identType in pairs(_prefixes) do
        result[identType] = getIdentifier(source, identType)
    end
    return result
end)