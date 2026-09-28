if not LoadResourceFile(cache.resource, 'web/build/index.html') then
    error(
    'Unable to load UI. Build ox_doorlock or download the latest release.\n	^3https://github.com/overextended/ox_doorlock/releases/latest/download/ox_doorlock.zip^0')
end

if not lib.checkDependency('ox_lib', '3.30.4', true) then return end

local function createDoor(door)
    local double = door.doors
    door.zone = GetLabelText(GetNameOfZone(door.coords.x, door.coords.y, door.coords.z))

    if double then
        for i = 1, 2 do
            AddDoorToSystem(double[i].hash, double[i].model, double[i].coords.x, double[i].coords.y, double[i].coords.z,
                false, false, false)
            DoorSystemSetDoorState(double[i].hash, 4, false, false)
            DoorSystemSetDoorState(double[i].hash, door.state, false, false)

            if door.doorRate or not door.auto then
                DoorSystemSetAutomaticRate(double[i].hash, door.doorRate or 10.0, false, false)
            end
        end
    else
        AddDoorToSystem(door.hash, door.model, door.coords.x, door.coords.y, door.coords.z, false, false, false)
        DoorSystemSetDoorState(door.hash, 4, false, false)
        DoorSystemSetDoorState(door.hash, door.state, false, false)

        if door.doorRate or not door.auto then
            DoorSystemSetAutomaticRate(door.hash, door.doorRate or 10.0, false, false)
        end
    end
end

local nearbyDoors = {}
local Entity = Entity

lib.callback('ox_doorlock:getDoors', false, function(data)
    doors = data

    for _, door in pairs(data) do
        createDoor(door)
    end

    while true do
        table.wipe(nearbyDoors)
        local coords = GetEntityCoords(cache.ped)

        for _, door in pairs(doors) do
            local double = door.doors
            door.distance = #(coords - door.coords)

            if double then
                if door.distance < 80 then
                    for i = 1, 2 do
                        if not double[i].entity and IsModelValid(double[i].model) then
                            local entity = GetClosestObjectOfType(double[i].coords.x, double[i].coords.y,
                                double[i].coords.z, 1.0, double[i].model, false, false, false)

                            if entity ~= 0 then
                                double[i].entity = entity
                                Entity(entity).state.doorId = door.id
                            end
                        end
                    end

                    if door.distance < 20 then
                        nearbyDoors[#nearbyDoors + 1] = door
                    end
                else
                    for i = 1, 2 do
                        double[i].entity = nil
                    end
                end
            elseif door.distance < 80 then
                if not door.entity and IsModelValid(door.model) then
                    local entity = GetClosestObjectOfType(door.coords.x, door.coords.y, door.coords.z, 1.0, door.model,
                        false, false, false)

                    if entity ~= 0 then
                        local min, max = GetModelDimensions(door.model)
                        local points = {
                            GetOffsetFromEntityInWorldCoords(entity, min.x, min.y, min.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, min.x, min.y, max.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, min.x, max.y, max.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, min.x, max.y, min.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, max.x, min.y, min.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, max.x, min.y, max.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, max.x, max.y, max.z).xy,
                            GetOffsetFromEntityInWorldCoords(entity, max.x, max.y, min.z).xy
                        }

                        local centroid = vec2(0, 0)

                        for i = 1, 8 do
                            centroid += points[i]
                        end

                        centroid = centroid / 8
                        door.coords = vec3(centroid.x, centroid.y, door.coords.z)
                        door.entity = entity
                        Entity(entity).state.doorId = door.id
                    end
                end

                if door.distance < 20 then
                    nearbyDoors[#nearbyDoors + 1] = door
                end
            elseif door.entity then
                door.entity = nil
            end
        end

        Wait(500)
    end
end)

RegisterNetEvent('ox_doorlock:setState', function(id, state, source, data)
    if not doors then return end

    if data then
        doors[id] = data
        createDoor(data)

        if NuiHasLoaded then
            SendNuiMessage(json.encode({
                action = 'updateDoorData',
                data = data
            }))
        end
    end

    if Config.Notify and source == cache.serverId then
        if state == 0 then
            lib.notify({
                type = 'success',
                icon = 'unlock',
                description = locale('unlocked_door')
            })
        else
            lib.notify({
                type = 'success',
                icon = 'lock',
                description = locale('locked_door')
            })
        end
    end

    local door = data or doors[id]
    local double = door.doors
    door.state = state

    if double then
        DoorSystemSetDoorState(double[1].hash, door.state, false, false)
        DoorSystemSetDoorState(double[2].hash, door.state, false, false)

        if door.holdOpen then
            DoorSystemSetHoldOpen(double[1].hash, door.state == 0)
            DoorSystemSetHoldOpen(double[2].hash, door.state == 0)
        end

        while door.state == 1 and (not IsDoorClosed(double[1].hash) or not IsDoorClosed(double[2].hash)) do Wait(0) end
    else
        DoorSystemSetDoorState(door.hash, door.state, false, false)

        if door.holdOpen then DoorSystemSetHoldOpen(door.hash, door.state == 0) end
        while door.state == 1 and not IsDoorClosed(door.hash) do Wait(0) end
    end

    if door.state == state and door.distance and door.distance < 20 then
        if Config.NativeAudio then
            RequestScriptAudioBank('dlc_oxdoorlock/oxdoorlock', false)
            local sound = state == 0 and door.unlockSound or door.lockSound or 'door_bolt'
            local soundId = GetSoundId()

            PlaySoundFromCoord(soundId, sound, door.coords.x, door.coords.y, door.coords.z, 'DLC_OXDOORLOCK_SET', false,
                0, false)
            ReleaseSoundId(soundId)
            ReleaseNamedScriptAudioBank('dlc_oxdoorlock/oxdoorlock')
        else
            local volume = (0.01 * GetProfileSetting(300)) / (door.distance / 2)
            if volume > 1 then volume = 1 end
            local sound = state == 0 and door.unlockSound or door.lockSound or 'door-bolt-4'

            SendNUIMessage({
                action = 'playSound',
                data = {
                    sound = sound,
                    volume = volume
                }
            })
        end
    end
end)

RegisterNetEvent('ox_doorlock:editDoorlock', function(id, data)
    if source == '' then return end

    local door = doors[id]
    local double = door.doors
    local doorState = data and data.state or 0

    if data then
        data.zone = door.zone or GetLabelText(GetNameOfZone(door.coords.x, door.coords.y, door.coords.z))

        -- hacky method to resolve a bug with "closest door" by forcing a distance recalculation
        if door.distance < 20 then door.distance = 80 end
    elseif ClosestDoor?.id == id then
        ClosestDoor = nil
    end

    if double then
        for i = 1, 2 do
            local doorHash = double[i].hash

            if data then
                if data.doorRate or door.doorRate or not data.auto then
                    DoorSystemSetAutomaticRate(doorHash, data.doorRate or door.doorRate and 0.0 or 10.0, false, false)
                end

                DoorSystemSetDoorState(doorHash, doorState, false, false)

                if data.holdOpen then DoorSystemSetHoldOpen(doorHash, doorState == 0) end
            else
                DoorSystemSetDoorState(doorHash, 4, false, false)
                DoorSystemSetDoorState(doorHash, 0, false, false)

                if double[i].entity then
                    Entity(double[i].entity).state.doorId = nil
                end
            end
        end
    else
        if data then
            if data.doorRate or door.doorRate or not data.auto then
                DoorSystemSetAutomaticRate(door.hash, data.doorRate or door.doorRate and 0.0 or 10.0, false, false)
            end

            DoorSystemSetDoorState(door.hash, doorState, false, false)

            if data.holdOpen then DoorSystemSetHoldOpen(door.hash, doorState == 0) end
        else
            DoorSystemSetDoorState(door.hash, 4, false, false)
            DoorSystemSetDoorState(door.hash, 0, false, false)

            if door.entity then
                Entity(door.entity).state.doorId = nil
            end
        end
    end

    doors[id] = data

    if NuiHasLoaded then
        SendNuiMessage(json.encode({
            action = 'updateDoorData',
            data = data or id
        }))
    end
end)

ClosestDoor = nil

lib.callback.register('ox_doorlock:inputPassCode', function()
    return ClosestDoor?.passcode and lib.inputDialog(locale('door_lock'), {
        {
            type = 'input',
            label = locale('passcode'),
            password = true,
            icon = 'lock'
        },
    })?[1]
end)

local lastTriggered = 0

-- door.coords is the door's PIVOT, which for most props sits near the base/
-- hinge, not the visual middle of the door face -- a flat guessed Z offset
-- (what this used to be) only happens to look right on doors that are close
-- to a standard residential height, and looks off-centre on anything taller/
-- shorter (e.g. the Mission Row PD double doors). Using the model's own
-- bounding box instead gets the true vertical centre of whatever door prop
-- is actually there, single or double leaf.
local modelDimensionsCache = {}

local function getModelCenterZ(model)
    if not model or not IsModelValid(model) then return 0.9 end

    local cached = modelDimensionsCache[model]

    if not cached then
        local min, max = GetModelDimensions(model)
        cached = (min.z + max.z) / 2
        modelDimensionsCache[model] = cached
    end

    return cached
end

local function getDoorPromptCoords(door)
    local model = door.doors and door.doors[1].model or door.model
    return vec3(door.coords.x, door.coords.y, door.coords.z + getModelCenterZ(model))
end

-- Pinned to a 3D world position (the door itself), unlike lib.showTextUI
-- which is a fixed screen-corner NUI element with no world anchoring --
-- this is what makes the prompt appear "on" the door and follow it as the
-- camera moves. Rendered by ox_doorlock's own bundled NUI pill (see
-- web/src/components/DoorPrompt.tsx) rather than a separate resource or
-- native DrawRect, since the NUI is always guaranteed to be loaded here.
local function showDoorPrompt(coords, text, locked)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)

    if not onScreen then
        SendNUIMessage({ action = 'hideDoorPrompt' })
        return
    end

    SendNUIMessage({
        action = 'showDoorPrompt',
        data = {
            x = x,
            y = y,
            text = text:gsub('^%[E%] ', ''),
            icon = locked and 'lock' or 'lock-open'
        }
    })
end

local function useClosestDoor()
    if not ClosestDoor then return false end

    local gameTimer = GetGameTimer()

    if gameTimer - lastTriggered > 500 then
        lastTriggered = gameTimer
        TriggerServerEvent('ox_doorlock:setState', ClosestDoor.id, ClosestDoor.state == 1 and 0 or 1)
    end
end

CreateThread(function()
    local lockDoor = locale('lock_door')
    local unlockDoor = locale('unlock_door')
    local drawSprite = Config.DrawSprite

    if drawSprite then
        local sprite1 = drawSprite[0]?[1]
        local sprite2 = drawSprite[1]?[1]

        if sprite1 then
            RequestStreamedTextureDict(sprite1, true)
        end

        if sprite2 then
            RequestStreamedTextureDict(sprite2, true)
        end
    end

    local SetDrawOrigin = SetDrawOrigin
    local ClearDrawOrigin = ClearDrawOrigin
    local DrawSprite = drawSprite and DrawSprite
    local promptShown = false

    while true do
        local num = #nearbyDoors

        if num > 0 then
            local ratio = drawSprite and GetAspectRatio(true)
            for i = 1, num do
                local door = nearbyDoors[i]

                if door.distance < door.maxDistance then
                    if door.distance < (ClosestDoor?.distance or 10) then
                        ClosestDoor = door
                    end

                    if drawSprite and not door.hideUi then
                        local sprite = drawSprite[door.state]

                        if sprite then
                            SetDrawOrigin(door.coords.x, door.coords.y, door.coords.z)
                            DrawSprite(sprite[1], sprite[2], sprite[3], sprite[4], sprite[5], sprite[6] * ratio,
                                sprite[7], sprite[8], sprite[9], sprite[10], sprite[11])
                            ClearDrawOrigin()
                        end
                    end
                end
            end
        else
            ClosestDoor = nil
        end

        if ClosestDoor and ClosestDoor.distance < ClosestDoor.maxDistance then
            if Config.DrawTextUI and not ClosestDoor.hideUi then
                showDoorPrompt(getDoorPromptCoords(ClosestDoor), ClosestDoor.state == 0 and lockDoor or unlockDoor,
                    ClosestDoor.state == 1)
                promptShown = true
            end

            if not PickingLock and IsDisabledControlJustReleased(0, 38) then
                useClosestDoor()
            end
        elseif promptShown then
            SendNUIMessage({ action = 'hideDoorPrompt' })
            promptShown = false
        end

        Wait(num > 0 and 0 or 500)
    end
end)

exports('useClosestDoor', useClosestDoor)
exports('getClosestDoor', function() return ClosestDoor end)
