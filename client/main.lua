-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- Client-side core
-- Owns two concerns:
--   1. Client-ready handshake — signals the server the client is stable
--   2. Client-side callback system — allows client scripts to trigger server
--      callbacks and receive responses via a requestId correlation pattern
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Session data
-- Populated once the server confirms the session is ready.
-- Accessible to other client scripts via the GetSessionData export.
-- ---------------------------------------------------------------------------
local _session = nil

-- ---------------------------------------------------------------------------
-- Callback system
-- Pending callbacks keyed by requestId. Each entry is a function waiting
-- for its response from the server.
-- ---------------------------------------------------------------------------
local _pendingCallbacks = {}
local _requestIdCounter = 0

local function nextRequestId()
    _requestIdCounter = _requestIdCounter + 1
    return _requestIdCounter
end

-- ---------------------------------------------------------------------------
-- Client-ready handshake
-- Fires once the client has fully loaded. The server creates the session and
-- responds with lw-core:client:sessionReady when it is done.
-- ---------------------------------------------------------------------------
AddEventHandler('onClientGameTypeStart', function()
    TriggerServerEvent('lw-core:client:ready')
end)

-- ---------------------------------------------------------------------------
-- Session ready response from server
-- ---------------------------------------------------------------------------
RegisterNetEvent('lw-core:client:sessionReady')
AddEventHandler('lw-core:client:sessionReady', function(sessionData)
    _session = sessionData
    TriggerEvent('lw-core:sessionReady', sessionData)
end)

-- ---------------------------------------------------------------------------
-- Character selection trigger from server (logout flow)
-- ---------------------------------------------------------------------------
RegisterNetEvent('lw-core:client:enterCharacterSelection')
AddEventHandler('lw-core:client:enterCharacterSelection', function()
    TriggerEvent('lw-core:enterCharacterSelection')
end)

-- ---------------------------------------------------------------------------
-- Callback response handler
-- Receives the server's response and fires the stored callback function.
-- ---------------------------------------------------------------------------
RegisterNetEvent('lw-core:client:callbackResponse')
AddEventHandler('lw-core:client:callbackResponse', function(requestId, ...)
    local cb = _pendingCallbacks[requestId]
    if not cb then return end

    _pendingCallbacks[requestId] = nil
    cb(...)
end)

-- ---------------------------------------------------------------------------
-- TriggerServerCallback
-- Client-facing API. Triggers a named server callback and fires cb when the
-- response arrives. Additional arguments are forwarded to the server handler.
-- ---------------------------------------------------------------------------
local function triggerServerCallback(name, cb, ...)
    local requestId = nextRequestId()
    _pendingCallbacks[requestId] = cb
    TriggerServerEvent('lw-core:server:triggerCallback', name, requestId, ...)
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('TriggerServerCallback', function(name, cb, ...)
    triggerServerCallback(name, cb, ...)
end)

exports('GetSessionData', function()
    return _session
end)