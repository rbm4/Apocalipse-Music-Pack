require "ApocalipseBRRadio/ABRRadioFramework"

-- Shared by the authority and listeners. IDs are short, stable catalog codes,
-- never array indices: adding a pack must not change another pack's wire IDs.
ApocalipseMusic = ApocalipseMusic or { stations = {}, content = {} }
local M = ApocalipseMusic
M.PREFIX = "AMP1|"
M.HEARTBEAT = 2
M.TIMEOUT = 8
M.DEFAULT_LYRIC_DURATION = 4

local function validId(id)
    return type(id) == "string" and #id > 0 and #id <= 24
        and id:match("^[%w_%-]+$") ~= nil
end

function M.registerStation(config)
    assert(validId(config.id), "Invalid music station ID")
    assert(not M.stations[config.id], "Duplicate music station ID")
    assert(type(config.frequency) == "number" and config.frequency > 0
        and config.frequency == math.floor(config.frequency), "Station needs an integer frequency")
    assert(config.isTV ~= true, "Music stations must be radio channels")
    assert(not ABRRadio.getChannelIdByFrequency(config.frequency), "Radio frequency already registered")
    config.color = config.color or { r = 0.8, g = 0.65, b = 0.25 }
    config.signalStrength = config.signalStrength or -1
    config.talkChance = config.talkChance or 35
    assert(config.talkChance >= 0 and config.talkChance <= 100, "Talk probability must be 0-100")
    assert(ABRRadio.registerChannel(config), "Radio registration failed")
    config.songs, config.talks = {}, {}
    M.stations[config.id] = config
end

local function register(config, kind)
    assert(validId(config.id), "Invalid content ID")
    assert(not M.content[config.id], "Duplicate content ID: " .. config.id)
    local station = assert(M.stations[config.station], "Unknown music station")
    assert(type(config.duration) == "number" and config.duration > 0, "Duration must be real seconds")
    config.weight = config.weight or 10
    assert(config.weight > 0 and config.weight == math.floor(config.weight), "Weight must be a positive integer")
    local previous = -1
    for _, line in ipairs(config.lyrics or config.lines or {}) do
        assert(type(line.at) == "number" and line.at >= 0 and line.at < config.duration
            and line.at > previous, "Text timestamps must increase and fall within duration")
        assert(line.text, "Timed text requires text")
        if line.untilTime then
            assert(line.untilTime > line.at and line.untilTime <= config.duration, "Invalid text end time")
        end
        previous = line.at
    end
    if kind == "song" then
        config.lyricDuration = config.lyricDuration or M.DEFAULT_LYRIC_DURATION
        assert(type(config.lyricDuration) == "number" and config.lyricDuration > 0,
            "Default lyric display duration must be positive seconds")
        if config.chunks and #config.chunks == 0 then config.chunks = nil end
        assert(type(config.sound) == "string" or #(config.chunks or {}) > 0, "Song needs sound or chunks")
        previous = -1
        for i, chunk in ipairs(config.chunks or {}) do
            assert(type(chunk.at) == "number" and chunk.at >= 0 and chunk.at < config.duration
                and chunk.at > previous and type(chunk.sound) == "string", "Invalid audio chunk")
            assert(i ~= 1 or chunk.at == 0, "First audio chunk must start at zero")
            previous = chunk.at
        end
    end
    config.kind = kind
    M.content[config.id] = config
    table.insert(kind == "song" and station.songs or station.talks, config)
end

function M.registerSong(config) register(config, "song") end
function M.registerTalk(config) register(config, "talk") end

function M.pick(pool, previousId)
    local total = 0
    for _, entry in ipairs(pool) do
        if #pool == 1 or entry.id ~= previousId then total = total + entry.weight end
    end
    if total == 0 then return nil end
    local roll = ZombRand(total)
    for _, entry in ipairs(pool) do
        if #pool == 1 or entry.id ~= previousId then
            roll = roll - entry.weight
            if roll < 0 then return entry end
        end
    end
end

-- Position implies lyric index and audio chunk; neither text nor paths go on wire.
function M.encode(id, sequence, elapsed)
    return M.PREFIX .. id .. "|" .. string.format("%.0f", sequence) .. "|" .. math.floor(elapsed * 10)
end

function M.decode(codes)
    if type(codes) ~= "string" or #codes > 100 then return nil end
    local id, sequence, position = codes:match("^AMP1|([%w_%-]+)|(%d+)|(%d+)$")
    if not id then return nil end
    return id, tonumber(sequence), tonumber(position) / 10
end

function M.textIndex(entry, elapsed)
    local lines = entry.lyrics or entry.lines or {}
    for i = #lines, 1, -1 do
        local line = lines[i]
        if elapsed >= line.at then
            -- Sparse song cues expire even without an explicit end. Talk lines
            -- retain their separate until-next-line behavior. No blank cues are
            -- needed to keep playback commands flowing through instrumental gaps.
            local nextAt = (lines[i + 1] and lines[i + 1].at) or entry.duration
            local ending = line.untilTime or (entry.kind == "song"
                and (line.at + (entry.lyricDuration or M.DEFAULT_LYRIC_DURATION))) or nextAt
            ending = math.min(ending, nextAt, entry.duration)
            if elapsed < ending then return i end
            return 0
        end
    end
    return 0
end

function M.chunkIndex(entry, elapsed)
    local chunks = entry.chunks or {}
    for i = #chunks, 1, -1 do
        if elapsed >= chunks[i].at then return i end
    end
    return 0
end
