fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'lw-core'
description 'Lockwood RP — Core session, lifecycle, routing bucket management, and permissions API'
version     '1.0.0'
author      'Morgrhim'

server_scripts {
    'server/config.lua',

    'server/main.lua',       -- bootstrap, LWCore global, lw-db ready listener, db migration
    'server/stateid.lua',    -- stateId generation and prefix migration
    'server/session.lua',    -- in-memory session store and all session exports
    'server/buckets.lua',    -- routing bucket register/assign/remove/deregister
    'server/permissions.lua',-- ACE wrapper, permission registry, contributor system
    'server/callbacks.lua',  -- server-side callback registration and dispatch
    'server/save.lua',       -- periodic last_seen flush and playerDropped save
    'server/lifecycle.lua',  -- playerConnecting, playerDropped, client-ready handler
    'server/zones.lua',
}

client_scripts {
    'client/config.lua',
    'client/main.lua',       -- client-ready handshake and client-side callback triggers
    'client/zones.lua',
}

dependencies {
    'lw-db',
    'lw-shared'
}