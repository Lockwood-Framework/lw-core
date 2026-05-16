-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- Server-side callback system
-- Provides a request/response pattern between client and server.
-- RedM has no native equivalent — events are fire-and-forget. This system
-- layers a callback mechanism on top of events using a shared request ID.
--
-- Flow:
--   1. Client calls TriggerServerCallback(name, cb, ...) via client/main.lua
--   2. Server receives 'lw-core:server:triggerCallback' with a requestId
--   3. Server finds the registered handler, runs it, sends the result back
--   4. Client receives 'lw-core:client:callbackResponse' and fires the cb
--
-- Handlers are registered per resource name so they are cleaned up
-- automatically when a resource stops.
-- ---------------------------------------------------------------------------

-- Callback registry
-- { [name] = { handler = fn, owner = resourceName } }
local _callbacks = {}

-- ---------------------------------------------------------------------------
-- LWCore.RegisterCallback
-- Registers a named server-side callback handler.
-- handler signature: function(source, resolve, ...)
--   resolve is a function the handler calls with its return values.
--   Supports both sync handlers (call resolve immediately) and async handlers
--   (call resolve inside a Citizen.CreateThread or after a DB call).
-- ---------------------------------------------------------------------------
function LWCore.RegisterCallback(name, resourceName, handler)
    if _callbacks[name] then
        print(string.format(
            '[lw-core] WARNING: callback "%s" already registered by "%s", overwriting with "%s"',
            name, _callbacks[name].owner, resourceName
        ))
    end
    _callbacks[name] = { handler = handler, owner = resourceName }
end

-- ---------------------------------------------------------------------------
-- Incoming callback trigger from client
-- ---------------------------------------------------------------------------
RegisterNetEvent('lw-core:server:triggerCallback')
AddEventHandler('lw-core:server:triggerCallback', function(name, requestId, ...)
    local source = source
    local args   = { ... }

    -- Reject requests from clients with no valid session.
    -- Prevents pre-handshake or spoofed callback triggers.
    if not LWCore.Sessions[source] then
        TriggerClientEvent('lw-core:client:callbackResponse', source, requestId, nil)
        return
    end

    local entry = _callbacks[name]
    if not entry then
        print(string.format(
            '[lw-core] WARNING: callback "%s" triggered by source %d but has no registered handler',
            name, source
        ))
        -- Respond with nil so the client is not left waiting forever
        TriggerClientEvent('lw-core:client:callbackResponse', source, requestId, nil)
        return
    end

    -- resolve sends the result back to the requesting client
    local function resolve(...)
        TriggerClientEvent('lw-core:client:callbackResponse', source, requestId, ...)
    end

    -- Run inside a thread so handlers can safely use sync DB calls
    Citizen.CreateThread(function()
        entry.handler(source, resolve, table.unpack(args))
    end)
end)

-- ---------------------------------------------------------------------------
-- Auto-cleanup on resource stop
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    for name, entry in pairs(_callbacks) do
        if entry.owner == resourceName then
            _callbacks[name] = nil
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------
exports('RegisterCallback', function(name, handler)
    -- GetInvokingResource() identifies which resource is registering so
    -- cleanup on resource stop is automatic and accurate.
    local owner = GetInvokingResource() or 'unknown'
    LWCore.RegisterCallback(name, owner, handler)
end)