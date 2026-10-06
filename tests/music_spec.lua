-- Behavioral simulation; Java/FM0D interop still needs an in-game smoke test.
local frameworkRoot = os.getenv("ABR_RADIO_MOD") or
    "C:/Users/ricar/Zomboid/Workshop/ApocalipseBRRadio/Contents/mods/ApocalipseBRRadio"
package.path = "Apocalipse-Music-Pack/common/media/lua/shared/?.lua;"
    .. frameworkRoot .. "/common/media/lua/shared/?.lua;"
    .. frameworkRoot .. "/common/media/lua/client/?.lua;"
    .. frameworkRoot .. "/common/media/lua/server/?.lua;" .. package.path
local function event()
    local handlers = {}
    return { Add = function(fn) table.insert(handlers, fn) end,
        fire = function(...) for _, fn in ipairs(handlers) do fn(...) end end }
end
Events = { OnTick = event(), OnLoadRadioScripts = event(), OnDeviceText = event(),
    EveryOneMinute = event(), OnClientCommand = event() }
local sent, radio, delta, frame = {}, {}, 0.1, 0
function getZomboidRadio() return radio end
function radio:addChannelName() end
function radio:getDaysSinceStart() return 0 end
function ZombRand(min, max) return max and min or 0 end
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
    table.insert(sent, { codes = codes, frame = frame, text = text, frequency = freq })
    Events.OnDeviceText.fire(guid, codes, x, y, 0, text, device)
end
-- The framework runtime can load without any music pack or station dependency.
require "ApocalipseBRRadio/ABRRadioMusicClient"
require "ApocalipseBRRadio/ABRRadioMusicServer"
assert(next(ABRRadio.music.stations) == nil, "framework runtime registered pack-specific stations")
Events.OnTick.fire()
assert(#sent == 0, "empty framework runtime broadcast music")
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
require "ApocalipseBRRadio/ABRRadioMusicClient"
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
assert(ABRRadioMusicClient.devices[device].sequence == 10, "stale sequence accepted")
frequency = 91600; advance(0.1)
assert(ABRRadioMusicClient.devices[device] == nil and stopped == 1 and returned == 1, "retune cleanup")
frequency = 94200
heartbeat(3, 11); advance(0.1)
assert(#played == 1, "late join restarted chunk from beginning")
advance(1.9)
assert(#played == 2 and played[2] == "c2", "late join did not catch next boundary")
heartbeat(5, 11); advance(0.1)
assert(#played == 2, "position correction repeated chunk")
deviceVolume = 0; advance(0.1)
assert(ABRRadioMusicClient.devices[device] == nil, "mute cleanup")
deviceVolume = 1
heartbeat(2, 12, "test_s2"); advance(0.1)
assert(#played == 2, "late join to whole file started wrong position")
on = false; advance(0.1)
assert(ABRRadioMusicClient.devices[device] == nil, "power off cleanup")
on = true; distance = 100
heartbeat(0, 13)
assert(ABRRadioMusicClient.devices[device] == nil, "out-of-range listener played music")
distance = 0; deaf = true; heartbeat(0, 13)
assert(ABRRadioMusicClient.devices[device] == nil, "deaf listener played music")
deaf = false
device.getPlayer = function() return player end
heartbeat(0, 13)
assert(ABRRadioMusicClient.devices[device] == nil, "unequipped inventory radio played music")
equipped = device; headphones = 0; heartbeat(0, 13); advance(0.1)
assert(ABRRadioMusicClient.devices[device] ~= nil, "equipped headphone radio did not play")
equipped = nil; advance(0.1)
assert(ABRRadioMusicClient.devices[device] == nil, "unequipping did not stop music")
device.getPlayer = nil; headphones = -1
M.registerSong({ id = "timeout", station = "amp_music", duration = 30, sound = "long" })
heartbeat(0, 14, "timeout"); advance(8.2)
assert(ABRRadioMusicClient.devices[device] == nil, "missing heartbeats did not stop playback")

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
require "ApocalipseBRRadio/ABRRadioMusicServer"
local station = M.stations.amp_music
station.songs = { track, M.content.test_s2 }; station.talkChance = 100
Events.OnLoadRadioScripts.fire()
advance(0.1)
assert(ABRRadioMusicServer.states.amp_music.entry.id == track.id)
local firstSequence = ABRRadioMusicServer.states.amp_music.sequence
advance(9.8)
assert(ABRRadioMusicServer.states.amp_music.sequence == firstSequence, "song interrupted early")
advance(0.5)
assert(ABRRadioMusicServer.states.amp_music.entry.kind == "talk", "missing between-song talk")
local talkDuration = ABRRadioMusicServer.states.amp_music.entry.duration
advance(talkDuration + 0.3)
assert(ABRRadioMusicServer.states.amp_music.entry.id == "test_s2", "talk chaining or immediate song repeat")
assert(#sent < 20, "per-frame network flood")
ABRRadio.channels.amp_music.enabled = false; advance(0.1)
assert(ABRRadioMusicServer.states.amp_music.entry == nil, "disabled station kept scheduling")
ABRRadio.channels.amp_music.enabled = true; station.songs = {}
local before = #sent
advance(2)
assert(#sent == before, "empty template catalog broadcast talk without music")

-- The authority broadcasts positions throughout a long lyric-free interval.
station.songs = { sparse }; station.talkChance = 0
advance(0.1)
local sparseSequence = ABRRadioMusicServer.states.amp_music.sequence
before = #sent
advance(22)
assert(#sent - before >= 10, "instrumental gap stopped playback commands")
assert(ABRRadioMusicServer.states.amp_music.sequence == sparseSequence, "sparse lyrics shortened song")
assert(ABRRadioMusicClient.devices[device] and ABRRadioMusicClient.devices[device].sequence == sparseSequence,
    "lyric-free interval caused listener timeout")
beforeCaptions = #captions
advance(1)
assert(#captions == beforeCaptions, "instrumental interval emitted lyric text")
ABRRadio.channels.amp_music.enabled = false; advance(8.2)
ABRRadio.channels.amp_music.enabled = true; station.songs = { M.content.empty_lyrics }
advance(0.1); before = #sent; beforeCaptions = #captions
advance(6)
assert(#sent - before >= 2 and #captions == beforeCaptions,
    "fully instrumental song requires lyric entries")

-- Actual framework scheduler integration: music owns one channel, queues retain
-- every line, and unrelated frequencies remain independent.
ABRRadio.registerChannel({ id = "other", name = "Other radio", frequency = 95000 })
ABRRadio.registerTransmission("amp_music", { lines = { "scheduled between songs" } })
ABRRadio.triggerImmediate("amp_music", { "queued A1", "queued A2" })
ABRRadio.triggerImmediate("amp_music", { "queued B" })
ABRRadio.triggerImmediate("other", { "other channel" })
local lockedSequence = ABRRadioMusicServer.states.amp_music.sequence
local function countText(text)
    local count = 0
    for _, packet in ipairs(sent) do if packet.text == text then count = count + 1 end end
    return count
end
Events.EveryOneMinute.fire()
assert(ABRRadioServer.channelOwners.amp_music == "music" and #ABRRadio.immediateQueue == 2,
    "immediate messages interrupted music or disappeared")
assert(countText("other channel") == 1 and countText("queued A1") == 0,
    "channel ownership blocked other frequencies or leaked queued text")
assert(countText("scheduled between songs") == 0, "regular scheduled text interrupted music")
assert(not ABRRadioServer.releaseChannel("amp_music", "wrong owner"), "wrong owner released channel")
advance(4.5)
assert(ABRRadioMusicServer.states.amp_music.sequence == lockedSequence
    and ABRRadioMusicServer.states.amp_music.entry == nil, "music restarted ahead of pending text")
Events.EveryOneMinute.fire() -- A1
advance(0.1)
assert(ABRRadioMusicServer.states.amp_music.entry == nil, "music interrupted an active text transmission")
Events.EveryOneMinute.fire() -- A2, B remains queued
assert(countText("queued A1") == 1 and countText("queued A2") == 1
    and countText("queued B") == 0, "deferred messages overwrote one another")
Events.EveryOneMinute.fire() -- completes A
Events.EveryOneMinute.fire() -- B
Events.EveryOneMinute.fire() -- completes B
assert(countText("queued B") == 1 and #ABRRadio.immediateQueue == 0, "queue did not drain")
ABRRadioServer.cooldowns.amp_music = 0
advance(0.1)
assert(ABRRadioMusicServer.states.amp_music.entry == nil, "music starved due scheduled transmission")
Events.EveryOneMinute.fire()
assert(countText("scheduled between songs") == 1, "scheduled transmission did not get its turn")
Events.EveryOneMinute.fire()
advance(0.1)
assert(ABRRadioMusicServer.states.amp_music.entry and ABRRadioServer.channelOwners.amp_music == "music",
    "music did not resume after queued and scheduled text")
assert(countText("queued A1") == 1 and countText("queued A2") == 1 and countText("queued B") == 1,
    "queued message repeated")
print("PASS: framework channel ownership, deferred FIFO, scheduled text fairness, independent frequencies, sparse lyrics, late tuning, cleanup, and music scheduling")
