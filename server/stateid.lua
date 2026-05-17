

local DB = exports['lw-db'].DB()

-- ---------------------------------------------------------------------------
-- State ID generation and prefix migration
-- ---------------------------------------------------------------------------

-- Seed the PRNG once on module load using Lua 5.4's system entropy source.
-- Avoids the deterministic sequence that results from a fixed or time-only seed.
math.randomseed()

-- Monotonic nonce. Advances the PRNG state by a small bounded amount each call
-- to ensure divergence when RequestStateId is called in rapid succession.
local _nonce = 0

-- ---------------------------------------------------------------------------
-- generateStateId (private)
-- Builds a raw state ID string from config. No DB interaction.
-- ---------------------------------------------------------------------------
local function generateStateId()
    _nonce = _nonce + 1

    -- Advance PRNG state by a bounded nonce-derived amount.
    -- Keeps calls cheap (1–7 iterations) while guaranteeing state divergence
    -- on rapid successive calls within the same scheduler tick.
    for _ = 1, (_nonce % 7) + 1 do
        math.random()
    end

    local charset    <const> = Config.StateIdCharset
    local charsetLen         = #charset
    local randomLen  <const> = Config.StateIdRandomLength
    local prefix     <const> = Config.StateIdPrefix

    local chars = {}
    for i = 1, randomLen do
        local idx = math.random(1, charsetLen)
        chars[i]  = charset:sub(idx, idx)
    end

    return prefix .. table.concat(chars)
end

-- ---------------------------------------------------------------------------
-- LWCore.RequestStateId (export)
-- The public API for state ID generation. Generates a candidate, checks
-- lw_characters for a collision, and loops until a unique value is found.
-- Returns the unique state ID to the caller, who is responsible for inserting
-- it into lw_characters. Does not write to the DB itself.
--
-- Only called at the end of character creation — lw_characters is guaranteed
-- to exist by this point.
-- Must be called inside a Citizen.CreateThread.
-- ---------------------------------------------------------------------------
function LWCore.RequestStateId()
    local stateId
    local existing

    repeat
        if stateId then
            print('[lw-core] state ID collision on "' .. stateId .. '", regenerating')
        end
        stateId  = generateStateId()
        existing = DB.scalar(
            'SELECT `state_id` FROM `lw_characters` WHERE `state_id` = ? LIMIT 1',
            { stateId }
        )
    until not existing

    return stateId
end

-- ---------------------------------------------------------------------------
-- LWCore.MigrateStateIdPrefix
-- Called once on boot from main.lua after migrations have run.
-- lw_characters is owned by lw-characters-api and may not exist on a fresh
-- install — we guard for that and return early if so.
-- Detects a prefix change and swaps the prefix on every state ID in a single
-- transaction. The FK cascade on lw_characters.state_id propagates to all
-- dependent tables automatically.
-- Must be called inside a Citizen.CreateThread (boot sequence satisfies this).
-- ---------------------------------------------------------------------------
function LWCore.MigrateStateIdPrefix()
    local tableExists = DB.scalar(
        [[SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = DATABASE()
          AND table_name = 'lw_characters']],
        {}
    )
    if not tableExists or tableExists == 0 then return end

    local rows = DB.query('SELECT `state_id` FROM `lw_characters`', {})
    if not rows or #rows == 0 then return end

    local randomLen       = Config.StateIdRandomLength
    local newPrefix       = Config.StateIdPrefix
    local firstId         = rows[1].state_id

    if #firstId <= randomLen then
        print('[lw-core] WARNING: state IDs in lw_characters appear malformed, skipping prefix migration')
        return
    end

    local storedPrefixLen = #firstId - randomLen
    local storedPrefix    = firstId:sub(1, storedPrefixLen)

    if storedPrefix == newPrefix then return end

    print(string.format(
        '[lw-core] state ID prefix changed "%s" → "%s", migrating %d character(s)',
        storedPrefix, newPrefix, #rows
    ))

    local queries = {}
    for _, row in ipairs(rows) do
        local oldId  = row.state_id
        local random = oldId:sub(storedPrefixLen + 1)
        local newId  = newPrefix .. random

        queries[#queries + 1] = {
            query  = 'UPDATE `lw_characters` SET `state_id` = ? WHERE `state_id` = ?',
            values = { newId, oldId },
        }
    end

    local ok = DB.transaction(queries, {})
    if ok then
        print('[lw-core] state ID prefix migration complete')
    else
        print('[lw-core] ERROR: state ID prefix migration failed — check DB logs')
    end
end

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------
exports('RequestStateId', function()
    return LWCore.RequestStateId()
end)