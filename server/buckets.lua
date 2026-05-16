-- Copyright 2026 Morgrhim. All rights reserved.

-- ---------------------------------------------------------------------------
-- Routing bucket API
-- lw-core does not know what buckets are for. It only manages their lifecycle
-- and player assignment. Consumers register a bucket, put players in it, take
-- players out, and deregister when done.
--
-- Private selection buckets are keyed by source ID so concurrent connecting
-- players never share a bucket.
--
-- Bucket store schema:
--   key      : any   — the identifier the registering resource uses
--   owner    : string — resource name that registered it
--   bucketId : integer — the actual routing bucket ID passed to natives
-- ---------------------------------------------------------------------------
LWCore.Buckets = {}

-- ---------------------------------------------------------------------------
-- Internal: next available bucket ID
-- Bucket 0 is the default world bucket — never assign it here.
-- We start at 1 and increment. IDs are never reused within a server session.
-- ---------------------------------------------------------------------------
local _nextBucketId = 1

local function nextBucketId()
    local id = _nextBucketId
    _nextBucketId = _nextBucketId + 1
    return id
end

-- ---------------------------------------------------------------------------
-- LWCore.RegisterBucket
-- Allocates a new routing bucket and associates it with a key and owner.
-- Returns the numeric bucket ID on success, nil if the key is already taken.
-- ---------------------------------------------------------------------------
function LWCore.RegisterBucket(key, owner)
    if LWCore.Buckets[key] then
        print(string.format(
            '[lw-core] WARNING: bucket key "%s" already registered by "%s", ignoring request from "%s"',
            tostring(key), LWCore.Buckets[key].owner, tostring(owner)
        ))
        return nil
    end

    local bucketId = nextBucketId()
    LWCore.Buckets[key] = { owner = owner, bucketId = bucketId }
    return bucketId
end

-- ---------------------------------------------------------------------------
-- LWCore.DeregisterBucket
-- Removes a bucket registration. Any players still in the bucket are moved
-- to bucket 0 (default world) before deregistration so no one is stranded.
-- Only the registering owner may deregister a bucket.
-- ---------------------------------------------------------------------------
function LWCore.DeregisterBucket(key, owner)
    local bucket = LWCore.Buckets[key]
    if not bucket then return false end

    if bucket.owner ~= owner then
        print(string.format(
            '[lw-core] WARNING: "%s" attempted to deregister bucket "%s" owned by "%s"',
            tostring(owner), tostring(key), bucket.owner
        ))
        return false
    end

    -- Evict any players still in this bucket back to the world
    for _, session in pairs(LWCore.Sessions) do
        if session.bucket == key then
            SetPlayerRoutingBucket(session.source, 0)
            session.bucket = nil
        end
    end

    LWCore.Buckets[key] = nil
    return true
end

-- ---------------------------------------------------------------------------
-- LWCore.AssignPlayer
-- Moves a player into a registered bucket. Stores the bucket key on the
-- session so DeregisterBucket can evict stranded players.
-- Returns false if the bucket key is not registered or the session is missing.
-- ---------------------------------------------------------------------------
function LWCore.AssignPlayer(source, key)
    local session = LWCore.Sessions[source]
    if not session then return false end

    local bucket = LWCore.Buckets[key]
    if not bucket then return false end

    SetPlayerRoutingBucket(source, bucket.bucketId)
    session.bucket = key
    return true
end

-- ---------------------------------------------------------------------------
-- LWCore.RemovePlayer
-- Returns a player to bucket 0 (default world) and clears their bucket key.
-- Returns false if the session is missing.
-- ---------------------------------------------------------------------------
function LWCore.RemovePlayer(source)
    local session = LWCore.Sessions[source]
    if not session then return false end

    SetPlayerRoutingBucket(source, 0)
    session.bucket = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Private selection bucket management
-- Each connecting player gets their own private bucket keyed by source ID.
-- Registered on session creation, deregistered on full disconnect.
-- Logout reassigns the player back to their own selection bucket without
-- deregistering it — the bucket persists for the session lifetime.
-- ---------------------------------------------------------------------------
function LWCore.RegisterSelectionBucket(source)
    local key = source
    local bucketId = LWCore.RegisterBucket(key, 'lw-core')
    if not bucketId then return end
    LWCore.AssignPlayer(source, key)
end

function LWCore.DeregisterSelectionBucket(source)
    LWCore.DeregisterBucket(source, 'lw-core')
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports('RegisterBucket', function(key, owner)
    return LWCore.RegisterBucket(key, owner)
end)

exports('DeregisterBucket', function(key, owner)
    return LWCore.DeregisterBucket(key, owner)
end)

exports('AssignPlayer', function(source, key)
    return LWCore.AssignPlayer(source, key)
end)

exports('RemovePlayer', function(source)
    return LWCore.RemovePlayer(source)
end)