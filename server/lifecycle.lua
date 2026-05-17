

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- Owns playerConnecting, client-ready handshake, and playerDropped.
-- All other lifecycle concerns (character selection, logout) are triggered
-- by consuming resources via exports.
-- ---------------------------------------------------------------------------

-- In-progress connection locks keyed by license2.
-- Prevents a duplicate connection from racing through while a previous
-- session's cleanup is still running.
local _connectingLocks = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function getLicense2(source)
    local raw = GetPlayerIdentifierByType(source, 'license2')
    if not raw then return nil end
    -- Strip the 'license2:' prefix — we store the bare identifier
    return (raw:gsub('^license2:', ''))
end

-- ---------------------------------------------------------------------------
-- playerConnecting
-- Validates license2 and rejects duplicate connections.
-- The deferrals pattern holds the connection open while we check.
-- ---------------------------------------------------------------------------
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source

    deferrals.defer()
    Wait(0)  -- yield to allow the source to stabilise

    deferrals.update('Verifying your account...')

    local license2 = getLicense2(source)

    if not license2 then
        deferrals.done('Connection rejected: no license2 identifier found.')
        return
    end

    deferrals.update('Checking for existing sessions...')

    -- Reject if this license2 is already mid-connect
    if _connectingLocks[license2] then
        deferrals.done('Connection rejected: this account is already connecting.')
        return
    end

    -- Reject if this license2 is already in an active session
    for _, session in pairs(LWCore.Sessions) do
        if session.license2 == license2 then
            deferrals.done('Connection rejected: this account is already connected.')
            return
        end
    end

    _connectingLocks[license2] = true

    deferrals.update('Welcome to Lockwood RP. Loading...')
    Wait(0)

    deferrals.done()
end)

-- ---------------------------------------------------------------------------
-- Client-ready handshake
-- The client fires this once it has fully loaded and is ready to receive data.
-- This is distinct from playerConnecting — the client is in-world and stable.
-- We create the session here rather than in playerConnecting because we need
-- a stable source ID and GetPlayerName to be reliable.
-- ---------------------------------------------------------------------------
RegisterNetEvent('lw-core:client:ready')
AddEventHandler('lw-core:client:ready', function()
    local source  = source
    local license2 = getLicense2(source)

    if not license2 then
        DropPlayer(source, 'Session error: license2 not found at ready stage.')
        return
    end

    _connectingLocks[license2] = nil

    Citizen.CreateThread(function()
        local session = LWCore.CreateSession(source, license2)
        LWCore.RegisterSelectionBucket(source)
        LWCore.AssignGroupPrincipal(source)
        TriggerEvent('lw-core:playerConnected', source, session)
        TriggerClientEvent('lw-core:client:sessionReady', source, {
            license2 = session.license2,
            name     = session.name,
            group    = session.group,
        })
    end)
end)

-- ---------------------------------------------------------------------------
-- playerDropped
-- Saves the session, revokes ACE principals, fires the dropped event, then
-- destroys the in-memory session. Order matters — consuming resources that
-- listen to lw-core:playerDropped still have access to the session during
-- their handler via GetPlayer(source).
-- ---------------------------------------------------------------------------
AddEventHandler('playerDropped', function(reason)
    local source  = source
    local session = LWCore.Sessions[source]

    if not session then return end

    -- Release the connecting lock in case they dropped during handshake
    _connectingLocks[session.license2] = nil

    Citizen.CreateThread(function()
        -- If they had an active character, unload it first so resources
        -- can save character-level data before the session is destroyed
        if session.stateId then
            LWCore.ClearActiveCharacter(source)
        end

        LWCore.SaveSession(source)
        LWCore.RevokeGroupPrincipal(source)
        LWCore.DeregisterSelectionBucket(source)

        TriggerEvent('lw-core:playerDropped', source, session, reason)

        LWCore.DestroySession(source)
    end)
end)