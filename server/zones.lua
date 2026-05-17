local LWUtils = exports['lw-shared']:GetUtils()

-- Client sends only the new district hash. State is derived server-side
-- rather than trusting the client, and previous values come from the
-- session cache rather than the client report.
-- NOTE: Sessions must match the internal sessions table name in lw-core's
-- main server script.
RegisterNetEvent('lw-core:zoneChanged')
AddEventHandler('lw-core:zoneChanged', function(district)
    local src     = source
    local session = LWCore.Sessions[src]
    if not session then return end

    -- Validate district against known values and derive state.
    -- Unknown hashes are silently dropped — malformed or spoofed events.
    local state = LWUtils.Enums.DistrictToState[district]
    if not state then return end

    local previousDistrict = session.district
    local previousState    = session.state

    session.district = district
    session.state    = state

    TriggerEvent('lw-core:playerDistrictChanged', src, district, state, previousDistrict, previousState)
end)

---@param  source  integer
---@return         integer|nil
local function GetPlayerDistrict(source)
    local session = LWCore.Sessions[source]
    if not session then return nil end
    return session.district
end

---@param  source  integer
---@return         integer|nil
local function GetPlayerState(source)
    local session = LWCore.Sessions[source]
    if not session then return nil end
    return session.state
end

exports('GetPlayerDistrict', GetPlayerDistrict)
exports('GetPlayerState',    GetPlayerState)