local LWUtils = exports['lw-shared']:GetUtils()

local currentDistrict = nil
local polling         = false

AddEventHandler('lw-core:characterReady', function()
    if polling then return end
    polling = true

    Citizen.CreateThread(function()
        while polling do
            Wait(Config.ZonePollInterval)

            local ped = PlayerPedId()
            if ped ~= 0 then
                local coords   = GetEntityCoords(ped)
                local district = LWUtils.Utils.Zones.GetZoneAtCoords(coords.x, coords.y, coords.z, LWUtils.Enums.ZoneType.District)

                -- If the native returns nil we hold last known value silently.
                if district and district ~= currentDistrict then
                    currentDistrict = district
                    TriggerServerEvent('lw-core:zoneChanged', district)
                end
            end
        end
    end)
end)

AddEventHandler('lw-core:enterCharacterSelection', function()
    polling         = false
    currentDistrict = nil
end)