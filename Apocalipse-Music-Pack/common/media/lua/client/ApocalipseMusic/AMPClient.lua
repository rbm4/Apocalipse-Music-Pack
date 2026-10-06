if isServer() then return end
require "ApocalipseMusic/AMPStation"

AMPMusicClient = { devices = {}, clock = 0 }
local C, M = AMPMusicClient, ApocalipseMusic

local function stop(state)
    if state.handle then state.emitter:stopSoundLocal(state.handle) end
    if state.emitter then
        -- We own this emitter, never the device's static/VOIP emitter.
        state.emitter:stopAll()
        getWorld():returnOwnershipOfEmitter(state.emitter)
    end
    state.emitter, state.handle = nil, nil
end

local function position(device)
    if device.getPlayer then
        local owner = device:getPlayer()
        if not owner or owner:getEquipedRadio() ~= device then return nil end
        return owner:getX(), owner:getY(), owner:getZ(), owner
    end
    return device:getX(), device:getY(), device:getZ(), nil
end

local function audible(device, data)
    if not data:getIsTurnedOn() or data:getDeviceVolume() <= 0
        or data:isPlayingMedia() or data:isNoTransmit() then return false end
    local x, y, z, owner = position(device)
    if not x then return false end
    local range = data:getDeviceSoundVolumeRange()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() and not player:hasTrait(CharacterTrait.DEAF) then
            if owner and data:getHeadphoneType() >= 0 then
                if player == owner then return true end
            elseif math.abs(player:getZ() - z) < 1
                and (player:getX() - x)^2 + (player:getY() - y)^2 <= range^2 then
                return true
            end
        end
    end
    return false
end

local function onDeviceText(guid, codes, x, y, z, text, device)
    local id, sequence, elapsed = M.decode(codes)
    if not id or not device or not device.getDeviceData then return end
    local entry = M.content[id]
    if not entry or elapsed >= entry.duration then return end
    local data = device:getDeviceData()
    local station = M.stations[entry.station]
    if not data or data:getChannel() ~= station.frequency or not audible(device, data) then return end
    local state = C.devices[device]
    if state and sequence < state.sequence then return end
    if state and sequence == state.sequence and (state.entry.id ~= id or elapsed < state.lastPosition) then return end
    if not state or state.sequence ~= sequence then
        if state then stop(state) end
        state = { entry = entry, sequence = sequence, chunk = 0, textIndex = 0 }
        C.devices[device] = state
    end
    -- Heartbeats refresh position without restarting music or repeating lyrics.
    state.elapsed, state.lastPosition = elapsed, elapsed
    state.receivedAt = C.clock
end

local function display(device, state, elapsed)
    if state.entry.kind == "song" and not state.captionShown then
        state.captionShown = true
        local title = ABRRadio.resolveText(state.entry.title)
        local artist = ABRRadio.resolveText(state.entry.artist)
        local caption = title .. (artist ~= "" and (" - " .. artist) or "")
        local color = M.stations[state.entry.station].color
        if caption ~= "" then device:AddDeviceText(caption, color.r, color.g, color.b, "", nil, -1) end
    end
    local index = M.textIndex(state.entry, elapsed)
    if index == 0 or index <= state.textIndex then return end
    state.textIndex = index
    local line = (state.entry.lyrics or state.entry.lines)[index]
    local text = ABRRadio.resolveText(line.text)
    if text == "" then return end
    local color = M.stations[state.entry.station].color
    -- No protocol codes: this local caption cannot recursively trigger playback.
    device:AddDeviceText(text, color.r, color.g, color.b, "", nil, -1)
end

local function play(device, state, elapsed)
    if state.entry.kind ~= "song" then return end
    local entry = state.entry
    local index = entry.chunks and M.chunkIndex(entry, elapsed) or 1
    if index == 0 or index <= state.chunk then return end
    local at = entry.chunks and entry.chunks[index].at or 0
    -- File sounds cannot seek. Joining mid-chunk waits for the next boundary;
    -- starting a full file mid-song would put this listener out of sync.
    state.chunk = index
    if state.handle then
        state.emitter:stopSoundLocal(state.handle)
        state.handle = nil
    end
    if elapsed - at > 0.25 then return end
    if not state.emitter then
        local x, y, z = position(device)
        state.emitter = getWorld():getFreeEmitter(x, y, z)
        getWorld():takeOwnershipOfEmitter(state.emitter)
    end
    local sound = entry.chunks and entry.chunks[index].sound or entry.sound
    state.handle = state.emitter:playSound(sound)
    state.emitter:set3D(state.handle, false) -- distance/volume controlled below
end

local function volume(device, data)
    local x, y, z, owner = position(device)
    if owner and data:getHeadphoneType() >= 0 then return data:getDeviceVolume() end
    local range, gain = data:getDeviceSoundVolumeRange(), 0
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() and not player:hasTrait(CharacterTrait.DEAF)
            and math.abs(player:getZ() - z) < 1 then
            local distance = math.sqrt((player:getX() - x)^2 + (player:getY() - y)^2)
            gain = math.max(gain, math.max(0, 1 - distance / range))
        end
    end
    return data:getDeviceVolume() * gain
end

local function tick()
    C.clock = C.clock + getGameTime():getRealworldSecondsSinceLastUpdate()
    for device, state in pairs(C.devices) do
        local data = device:getDeviceData()
        local age = C.clock - state.receivedAt
        local elapsed = state.elapsed + age
        if not data or age > M.TIMEOUT or elapsed >= state.entry.duration
            or data:getChannel() ~= M.stations[state.entry.station].frequency
            or not audible(device, data) then
            stop(state)
            C.devices[device] = nil
        else
            display(device, state, elapsed)
            play(device, state, elapsed)
            if state.emitter then
                local x, y, z = position(device)
                state.emitter:setPos(x, y, z)
                if state.handle then state.emitter:setVolume(state.handle, volume(device, data)) end
                state.emitter:tick()
            end
        end
    end
end

Events.OnDeviceText.Add(onDeviceText)
Events.OnTick.Add(tick)
