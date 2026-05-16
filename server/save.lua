-- Copyright 2026 Morgrhim. All rights reserved.

local DB = exports['lw-db'].DB()

-- ---------------------------------------------------------------------------
-- Session persistence
-- Owns two concerns:
--   1. Periodic last_seen flush for all active sessions
--   2. Full save (last_seen + name) on playerDropped
--
-- lw-core only owns the lw_players columns it defined. Nothing else is saved
-- here — character data, inventory, needs, etc. are saved by their respective
-- resources in response to lw-core:playerDropped.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- LWCore.SaveSession
-- Writes name (in case it changed mid-session) and last_seen for one player.
-- Must be called inside a Citizen.CreateThread.
-- ---------------------------------------------------------------------------
function LWCore.SaveSession(source)
    local session = LWCore.Sessions[source]
    if not session then return end

    DB.update(
        [[UPDATE `lw_players`
          SET `name` = ?, `last_seen` = CURRENT_TIMESTAMP
          WHERE `license2` = ?]],
        { session.name, session.license2 }
    )
end

-- ---------------------------------------------------------------------------
-- LWCore.HeartbeatSessions
-- Writes last_seen for every active session in a single transaction.
-- Called on the periodic save loop. Name is not updated here — it is only
-- written on connect (if changed) and on playerDropped.
-- Must be called inside a Citizen.CreateThread.
-- ---------------------------------------------------------------------------
function LWCore.HeartbeatSessions()
    local queries = {}

    for _, session in pairs(LWCore.Sessions) do
        queries[#queries + 1] = {
            query  = 'UPDATE `lw_players` SET `last_seen` = CURRENT_TIMESTAMP WHERE `license2` = ?',
            values = { session.license2 },
        }
    end

    if #queries == 0 then return end

    local ok = DB.transaction(queries, {})
    if not ok then
        print('[lw-core] WARNING: periodic last_seen flush failed — check DB logs')
    end
end

-- ---------------------------------------------------------------------------
-- LWCore.StartSaveLoop
-- Spawns the periodic flush thread. Called once from main.lua on boot.
-- Interval is Config.SaveInterval (minutes), converted to milliseconds.
-- ---------------------------------------------------------------------------
function LWCore.StartSaveLoop()
    local intervalMs = Config.SaveInterval * 60 * 1000

    Citizen.CreateThread(function()
        while true do
            Wait(intervalMs)
            LWCore.HeartbeatSessions()
        end
    end)
end