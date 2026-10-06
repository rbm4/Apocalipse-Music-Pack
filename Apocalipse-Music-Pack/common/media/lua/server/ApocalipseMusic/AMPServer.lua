if isClient() then return end
require "ApocalipseMusic/AMPStation"

-- Independent of ABR's game-minute scheduler: audio runs in real seconds.
AMPMusicServer = { states = {}, sequence = getTimestampMs(), ready = false }
local S, M = AMPMusicServer, ApocalipseMusic

local function broadcast(station, state)
    local radio = ABRRadio.getRadio()
    if not radio then return end
    local color = station.color
    radio:SendTransmission(0, 0, station.frequency, "", "",
        M.encode(state.entry.id, state.sequence, state.elapsed),
        color.r, color.g, color.b, station.signalStrength, false)
    state.sinceBroadcast = 0
end

local function start(station, state, entry)
    S.sequence = S.sequence + 1
    state.entry, state.sequence, state.elapsed = entry, S.sequence, 0
    state.sinceBroadcast = 0
    if entry.kind == "song" then state.previousSong = entry.id end
    if entry.kind == "talk" then state.previousTalk = entry.id end
    broadcast(station, state)
end

local function tick()
    if not S.ready then return end
    local delta = getGameTime():getRealworldSecondsSinceLastUpdate()
    for id, station in pairs(M.stations) do
        local state = S.states[id]
        if not state then state = {}; S.states[id] = state end
        if ABRRadio.isChannelEnabled(id) then
            if not state.entry then
                -- With an empty template catalog, stay silent until songs exist.
                local entry = M.pick(station.songs, state.previousSong)
                if entry then start(station, state, entry) end
            else
                state.elapsed = state.elapsed + delta
                state.sinceBroadcast = state.sinceBroadcast + delta
                if state.elapsed >= state.entry.duration then
                    local entry
                    if state.entry.kind == "song" and ZombRand(100) < (station.talkChance or 0) then
                        entry = M.pick(station.talks, state.previousTalk)
                    end
                    entry = entry or M.pick(station.songs, state.previousSong)
                    if entry then start(station, state, entry) else state.entry = nil end
                elseif state.sinceBroadcast >= M.HEARTBEAT then
                    broadcast(station, state)
                end
            end
        else
            state.entry = nil -- listeners expire when heartbeats stop
        end
    end
end

Events.OnLoadRadioScripts.Add(function() S.ready = true end)
Events.OnTick.Add(tick)
