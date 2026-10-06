-- Behavioral simulation; Java/FM0D interop still needs an in-game smoke test.
package.path = "Apocalipse-Music-Pack/common/media/lua/shared/?.lua;" .. package.path
local function event()
    local handlers = {}
    return { Add = function(fn) table.insert(handlers, fn) end,
        fire = function(...) for _, fn in ipairs(handlers) do fn(...) end end }
end
Events = { OnTick = event(), OnLoadRadioScripts = event(), OnDeviceText = event() }
local sent, radio, delta, frame = {}, {}, 0.1, 0
local channels, frequencies = {}, {}
ABRRadio = {
    getChannelIdByFrequency = function(freq) return frequencies[freq] end,
    registerChannel = function(config) channels[config.id] = config; frequencies[config.frequency] = config.id; return true end,
    isChannelEnabled = function(id) return channels[id].enabled ~= false end,
    getRadio = function() return radio end,
    resolveText = function(value) return type(value) == "table" and value.EN or value or "" end,
}
package.preload["ApocalipseBRRadio/ABRRadioFramework"] = function() return ABRRadio end
function ZombRand(max) return 0 end
function isClient() return false end
function isServer() return false end
function getTimestampMs() return 1790000000000 end
function getGameTime() return { getRealworldSecondsSinceLastUpdate = function() return delta end } end
CharacterTrait = { DEAF = "deaf" }
local deaf, equipped, headphones = false, nil, -1
local player = { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
    isDead = function() return false end, hasTrait = function() return deaf end,
    getEquipedRadio = function() return equipped end }
function getNumActivePlayers() return 1 end
function getSpecificPlayer() return player end
local on, frequency, deviceVolume, distance = true, 94200, 1, 0
local data = { getIsTurnedOn = function() return on end, getDeviceVolume = function() return deviceVolume end,
    isPlayingMedia = function() return false end, isNoTransmit = function() return false end,
    getChannel = function() return frequency end, getDeviceSoundVolumeRange = function() return 20 end,
    getHeadphoneType = function() return headphones end }
local captions, played, stopped, returned = {}, {}, 0, 0
local device = { getDeviceData = function() return data end,
    getX = function() return distance end, getY = function() return 0 end, getZ = function() return 0 end,
    AddDeviceText = function(self, text) table.insert(captions, text) end }
local emitter = { playSound = function(self, sound) table.insert(played, sound); return #played end,
    stopSoundLocal = function() stopped = stopped + 1 end, stopAll = function() end,
    set3D = function() end, setPos = function() end, setVolume = function() end, tick = function() end }
local world = { getFreeEmitter = function() return emitter end, takeOwnershipOfEmitter = function() end,
    returnOwnershipOfEmitter = function() returned = returned + 1 end }
function getWorld() return world end
function radio:SendTransmission(x, y, freq, text, guid, codes)
    table.insert(sent, { codes = codes, frame = frame })
    Events.OnDeviceText.fire(guid, codes, x, y, 0, text, device)
end
require "ApocalipseMusic/AMPStation"
local M = ApocalipseMusic
local track = { id = "test_s1", station = "amp_music", title = "Test song", artist = "Test artist", duration = 10,
    chunks = { { at = 0, sound = "c1" }, { at = 5, sound = "c2" } },
    lyrics = { { at = 1, untilTime = 2, text = "lyric1" }, { at = 6, untilTime = 7, text = "lyric2" } } }
M.registerSong(track)
M.registerSong({ id = "test_s2", station = "amp_music", duration = 5, sound = "whole" })
local sparse = { id = "sparse", station = "amp_music", duration = 30,
    chunks = { { at = 0, sound = "sparse0" }, { at = 5, sound = "sparse5" }, { at = 20, sound = "sparse20" } },
    lyrics = { { at = 1, text = "sparse lyric" }, { at = 25, untilTime = 26, text = "last lyric" } } }
M.registerSong(sparse)
assert(M.textIndex(sparse, 0) == 0 and M.textIndex(sparse, 1) == 1, "sparse lyric onset")
assert(M.textIndex(sparse, 5) == 0 and M.textIndex(sparse, 24) == 0, "untimed cue leaked into instrumental gap")
assert(M.textIndex(sparse, 25) == 2 and M.textIndex(sparse, 26) == 0, "explicit lyric window")
assert(M.textIndex(M.content.test_s2, 2) == 0, "instrumental song invented lyrics")
M.registerSong({ id = "empty_lyrics", station = "amp_music", duration = 10, sound = "empty", lyrics = {} })
assert(M.textIndex(M.content.empty_lyrics, 2) == 0, "empty lyric array invented lyrics")
M.registerSong({ id = "custom_window", station = "amp_music", duration = 10, sound = "custom",
    lyricDuration = 1, lyrics = { { at = 1, text = "brief" } } })
assert(M.textIndex(M.content.custom_window, 1.9) == 1 and M.textIndex(M.content.custom_window, 2) == 0,
    "custom lyric display duration ignored")
assert(not pcall(M.registerSong, track), "duplicate ID accepted")
assert(not pcall(M.registerSong, { id = "bad", station = "amp_music", duration = 5, sound = "bad",
    lyrics = { { at = 2, text = "x" }, { at = 1, text = "y" } } }), "unordered lyrics accepted")
local id, sequence, elapsed = M.decode(M.encode(track.id, getTimestampMs(), 3.45))
assert(id == track.id and sequence == getTimestampMs() and elapsed == 3.4, "wire roundtrip")
assert(M.decode("AMP1|x|bad|0") == nil and M.decode("AMP2|x|1|0") == nil, "malformed protocol accepted")
assert(M.textIndex(track, 2.5) == 0 and M.textIndex(track, 6.5) == 2, "lyric gaps")
dofile("Apocalipse-Music-Pack/common/media/lua/client/ApocalipseMusic/AMPClient.lua")
local function heartbeat(at, seq, entryId)
    Events.OnDeviceText.fire("", M.encode(entryId or track.id, seq or 10, at), 0, 0, 0, "", device)
end
local function advance(seconds)
    for _ = 1, math.floor(seconds / delta + 0.5) do frame = frame + 1; Events.OnTick.fire() end
end
heartbeat(0)
advance(1.1)
assert(#played == 1 and played[1] == "c1", "start music")
assert(captions[1] == "Test song - Test artist" and captions[2] == "lyric1", "labels and lyrics")
heartbeat(1.1); heartbeat(1.1)
advance(0.3)
assert(#played == 1 and #captions == 2, "duplicate heartbeat restarted music/text")
heartbeat(3, 9)
assert(AMPMusicClient.devices[device].sequence == 10, "stale sequence accepted")
frequency = 91600; advance(0.1)
assert(AMPMusicClient.devices[device] == nil and stopped == 1 and returned == 1, "retune cleanup")
frequency = 94200
heartbeat(3, 11); advance(0.1)
assert(#played == 1, "late join restarted chunk from beginning")
advance(1.9)
assert(#played == 2 and played[2] == "c2", "late join did not catch next boundary")
heartbeat(5, 11); advance(0.1)
assert(#played == 2, "position correction repeated chunk")
deviceVolume = 0; advance(0.1)
assert(AMPMusicClient.devices[device] == nil, "mute cleanup")
deviceVolume = 1
heartbeat(2, 12, "test_s2"); advance(0.1)
assert(#played == 2, "late join to whole file started wrong position")
on = false; advance(0.1)
assert(AMPMusicClient.devices[device] == nil, "power off cleanup")
on = true; distance = 100
heartbeat(0, 13)
assert(AMPMusicClient.devices[device] == nil, "out-of-range listener played music")
distance = 0; deaf = true; heartbeat(0, 13)
assert(AMPMusicClient.devices[device] == nil, "deaf listener played music")
deaf = false
device.getPlayer = function() return player end
heartbeat(0, 13)
assert(AMPMusicClient.devices[device] == nil, "unequipped inventory radio played music")
equipped = device; headphones = 0; heartbeat(0, 13); advance(0.1)
assert(AMPMusicClient.devices[device] ~= nil, "equipped headphone radio did not play")
equipped = nil; advance(0.1)
assert(AMPMusicClient.devices[device] == nil, "unequipping did not stop music")
device.getPlayer = nil; headphones = -1
M.registerSong({ id = "timeout", station = "amp_music", duration = 30, sound = "long" })
heartbeat(0, 14, "timeout"); advance(8.2)
assert(AMPMusicClient.devices[device] == nil, "missing heartbeats did not stop playback")

-- A late listener in an instrumental gap gets no stale lyric, but still joins
-- a subsequent audio chunk and stays synchronized through regular commands.
local beforeCaptions, beforePlayed = #captions, #played
heartbeat(10, 15, "sparse"); advance(0.1)
assert(#captions == beforeCaptions and #played == beforePlayed, "late gap listener received stale content")
for at = 12, 20, 2 do heartbeat(at, 15, "sparse"); advance(0.1) end
assert(#captions == beforeCaptions and played[#played] == "sparse20",
    "missing lyric blocked audio synchronization")
on = false; advance(0.1); on = true

-- Authority timing: no next entry until duration expires; one talk at most.
dofile("Apocalipse-Music-Pack/common/media/lua/server/ApocalipseMusic/AMPServer.lua")
local station = M.stations.amp_music
station.songs = { track, M.content.test_s2 }; station.talkChance = 100
Events.OnLoadRadioScripts.fire()
advance(0.1)
assert(AMPMusicServer.states.amp_music.entry.id == track.id)
local firstSequence = AMPMusicServer.states.amp_music.sequence
advance(9.8)
assert(AMPMusicServer.states.amp_music.sequence == firstSequence, "song interrupted early")
advance(0.3)
assert(AMPMusicServer.states.amp_music.entry.kind == "talk", "missing between-song talk")
local talkDuration = AMPMusicServer.states.amp_music.entry.duration
advance(talkDuration + 0.1)
assert(AMPMusicServer.states.amp_music.entry.id == "test_s2", "talk chaining or immediate song repeat")
assert(#sent < 20, "per-frame network flood")
station.enabled = false; advance(0.1)
assert(AMPMusicServer.states.amp_music.entry == nil, "disabled station kept scheduling")
station.enabled = true; station.songs = {}
local before = #sent
advance(2)
assert(#sent == before, "empty template catalog broadcast talk without music")

-- The authority broadcasts positions throughout a long lyric-free interval.
station.songs = { sparse }; station.talkChance = 0
advance(0.1)
local sparseSequence = AMPMusicServer.states.amp_music.sequence
before = #sent
advance(22)
assert(#sent - before >= 10, "instrumental gap stopped playback commands")
assert(AMPMusicServer.states.amp_music.sequence == sparseSequence, "sparse lyrics shortened song")
assert(AMPMusicClient.devices[device] and AMPMusicClient.devices[device].sequence == sparseSequence,
    "lyric-free interval caused listener timeout")
beforeCaptions = #captions
advance(1)
assert(#captions == beforeCaptions, "instrumental interval emitted lyric text")
station.enabled = false; advance(8.2)
station.enabled = true; station.songs = { M.content.empty_lyrics }
advance(0.1); before = #sent; beforeCaptions = #captions
advance(6)
assert(#sent - before >= 2 and #captions == beforeCaptions,
    "fully instrumental song requires lyric entries")
print("PASS: sparse/absent lyrics, bounded lyric windows, uninterrupted instrumental commands/audio, registry, protocol, late tuning, cleanup, and scheduling")
