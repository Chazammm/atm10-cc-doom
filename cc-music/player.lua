-- CC-Music Player for CC:Tweaked / ATM10 8.2
-- Designed for large Advanced Monitor walls and SQSH1 (DFPWM) audio files.
-- Repository default: https://github.com/Di33le/CC-Music

local VERSION = "2.0.0"
local PROTOCOL = "ccmusic.v2"
local INDEX_CACHE = "/.ccmusic-index.json"

local okDfpwm, dfpwm = pcall(require, "cc.audio.dfpwm")
if not okDfpwm then
    error("CC:Tweaked DFPWM library not found: " .. tostring(dfpwm), 0)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function defineSetting(name, default, kind, description)
    if settings and settings.define then
        pcall(settings.define, name, {
            default = default,
            type = kind,
            description = description,
        })
    end
end

defineSetting("ccmusic.repo", "Di33le/CC-Music", "string", "GitHub owner/repository containing SQSH tracks")
defineSetting("ccmusic.branch", "main", "string", "GitHub branch to read")
defineSetting("ccmusic.volume", 1.0, "number", "Playback volume from 0.0 to 1.0")
defineSetting("ccmusic.shuffle", true, "boolean", "Shuffle playlist")
defineSetting("ccmusic.loop", "all", "string", "Loop mode: all, one, off")
defineSetting("ccmusic.text_scale", 0.5, "number", "Advanced Monitor text scale")
defineSetting("ccmusic.chunk_bytes", 1024, "number", "SQSH/DFPWM bytes decoded per audio chunk")
defineSetting("ccmusic.ui_fps", 6, "number", "Maximum UI refresh rate")
defineSetting("ccmusic.start_track", "Sundress", "string", "Preferred title substring to play first")

if settings and settings.load then pcall(settings.load) end

local function getSetting(name, fallback)
    if settings and settings.get then
        local ok, value = pcall(settings.get, name)
        if ok and value ~= nil then return value end
    end
    return fallback
end

local CONFIG = {
    repo = tostring(getSetting("ccmusic.repo", "Di33le/CC-Music")),
    branch = tostring(getSetting("ccmusic.branch", "main")),
    textScale = tonumber(getSetting("ccmusic.text_scale", 0.5)) or 0.5,
    chunkBytes = math.floor(tonumber(getSetting("ccmusic.chunk_bytes", 1024)) or 1024),
    uiFps = tonumber(getSetting("ccmusic.ui_fps", 6)) or 6,
    startTrack = tostring(getSetting("ccmusic.start_track", "Sundress")),
}
CONFIG.chunkBytes = math.max(256, math.min(4096, CONFIG.chunkBytes))
CONFIG.uiFps = math.max(2, math.min(12, CONFIG.uiFps))
if CONFIG.textScale < 0.5 then CONFIG.textScale = 0.5 end
if CONFIG.textScale > 5 then CONFIG.textScale = 5 end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function saveSetting(name, value)
    if settings and settings.set then pcall(settings.set, name, value) end
    if settings and settings.save then pcall(settings.save) end
end

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------

local function nowMs()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

local function waitSeconds(seconds)
    local timer = os.startTimer(math.max(0, seconds))
    while true do
        local ev, id = os.pullEventRaw()
        if ev == "timer" and id == timer then return true end
        if ev == "ccmusic_shutdown" or not _G.__ccmusic_running then return false end
    end
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function asciiSafe(s)
    s = tostring(s or "")
    -- Common UTF-8 punctuation in YouTube-derived filenames.
    s = s:gsub("\226\128\147", "-") -- en dash
         :gsub("\226\128\148", "-") -- em dash
         :gsub("\226\128\152", "'")
         :gsub("\226\128\153", "'")
         :gsub("\226\128\156", '"')
         :gsub("\226\128\157", '"')
         :gsub("\195\151", "x")
    return (s:gsub("[\128-\255]", "?"))
end

local function cleanTitle(name)
    local s = asciiSafe(name)
    s = s:gsub("%.sqsh$", "")
    s = s:gsub("%s*%([Oo]fficial [Mm]usic [Vv]ideo%)%s*$", "")
    s = s:gsub("%s*%([Oo]fficial [Vv]ideo%)%s*$", "")
    s = s:gsub("%s*%([Oo]fficial [Aa]udio%)%s*$", "")
    s = s:gsub("%s*%([Oo]fficial [Ll]yric [Vv]ideo%)%s*$", "")
    s = s:gsub("%s*%([Ll]yrics%)%s*$", "")
    s = s:gsub("%s*%([Vv]isualizer%)%s*$", "")
    s = s:gsub("%s*%-%s*%(320 Kbps%)%s*$", "")
    s = s:gsub("%s*%[[Oo]fficial [Aa]udio%]%s*$", "")
    s = s:gsub("%s*%[[%w_%-]+%]%s*$", "")
    s = s:gsub("_", " ")
    s = s:gsub("%s+", " ")
    return trim(s)
end

local function fmtTime(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function urlEncode(s)
    return (tostring(s):gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function rawUrl(filename)
    local owner, repo = CONFIG.repo:match("^([^/]+)/(.+)$")
    if not owner then return nil end
    return "https://raw.githubusercontent.com/" .. urlEncode(owner) .. "/" .. urlEncode(repo)
        .. "/" .. urlEncode(CONFIG.branch) .. "/" .. urlEncode(filename)
end

local function apiContentsUrl()
    local owner, repo = CONFIG.repo:match("^([^/]+)/(.+)$")
    if not owner then return nil end
    return "https://api.github.com/repos/" .. urlEncode(owner) .. "/" .. urlEncode(repo)
        .. "/contents/?ref=" .. urlEncode(CONFIG.branch)
end

local function safeClose(handle)
    if handle and handle.close then pcall(handle.close) end
end

local function jsonDecode(s)
    if not textutils or not textutils.unserializeJSON then return nil end
    local ok, data = pcall(textutils.unserializeJSON, s)
    if ok then return data end
    return nil
end

local function jsonEncode(v)
    if not textutils or not textutils.serializeJSON then return nil end
    local ok, data = pcall(textutils.serializeJSON, v)
    if ok then return data end
    return nil
end

local function httpGet(url, binary)
    if not http or not http.get then return nil, "HTTP API disabled" end
    local headers = {
        ["User-Agent"] = "CC-Music/" .. VERSION,
        ["Accept"] = "application/vnd.github+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
    }
    local ok, handle, err = pcall(http.get, url, headers, binary == true)
    if not ok then return nil, tostring(handle) end
    if not handle then return nil, tostring(err or "HTTP request failed") end
    return handle
end

local function readCache()
    if not fs or not fs.exists or not fs.exists(INDEX_CACHE) then return nil end
    local h = fs.open(INDEX_CACHE, "r")
    if not h then return nil end
    local raw = h.readAll()
    h.close()
    local data = jsonDecode(raw)
    if type(data) ~= "table" then return nil end
    return data
end

local function writeCache(tracks)
    if not fs then return end
    local slim = { version = 1, repo = CONFIG.repo, branch = CONFIG.branch, tracks = {} }
    for i = 1, #tracks do
        slim.tracks[#slim.tracks + 1] = { name = tracks[i].name, size = tracks[i].size }
    end
    local raw = jsonEncode(slim)
    if not raw then return end
    local h = fs.open(INDEX_CACHE, "w")
    if h then h.write(raw); h.close() end
end

local function normalizeTracks(entries)
    local tracks = {}
    if type(entries) ~= "table" then return tracks end
    for _, item in ipairs(entries) do
        local name = item.name
        if type(name) == "string" and name:lower():match("%.sqsh$") then
            local size = tonumber(item.size) or 0
            local track = {
                name = name,
                title = cleanTitle(name),
                size = size,
                url = rawUrl(name),
                rate = 24000,
                audioBytes = nil,
                lyricsBytes = nil,
            }
            -- Excellent estimate before the exact SQSH header has been read.
            track.duration = size > 0 and (size * 8 / 24000) or 0
            tracks[#tracks + 1] = track
        end
    end
    table.sort(tracks, function(a, b)
        return a.title:lower() < b.title:lower()
    end)
    return tracks
end

local function loadLibrary()
    local url = apiContentsUrl()
    if url then
        local h, err = httpGet(url, false)
        if h then
            local body = h.readAll()
            safeClose(h)
            local data = jsonDecode(body)
            if type(data) == "table" then
                local tracks = normalizeTracks(data)
                if #tracks > 0 then
                    writeCache(tracks)
                    return tracks, nil, false
                end
            end
            err = "GitHub returned an invalid/empty track index"
        end

        local cache = readCache()
        if cache and cache.repo == CONFIG.repo and cache.branch == CONFIG.branch then
            local tracks = normalizeTracks(cache.tracks)
            if #tracks > 0 then return tracks, err or "Using cached library", true end
        end
        return {}, err or "Could not load GitHub library", false
    end
    return {}, "Invalid ccmusic.repo (expected owner/repository)", false
end

-- ---------------------------------------------------------------------------
-- State and peripherals
-- ---------------------------------------------------------------------------

local state = {
    running = true,
    library = {},
    order = {},
    orderPos = 1,
    currentIndex = nil,
    current = nil,
    generation = 0,
    audioInterrupt = 0,
    paused = false,
    loading = true,
    stopped = false,
    error = nil,
    warning = nil,
    volume = clamp(tonumber(getSetting("ccmusic.volume", 1.0)) or 1.0, 0, 1),
    shuffle = getSetting("ccmusic.shuffle", true) == true,
    loopMode = tostring(getSetting("ccmusic.loop", "all")),
    history = {},
    playedSamples = 0,
    flight = nil,
    lyrics = {},
    bands = {},
    rms = 0,
    vizGain = 1,
    searchMode = false,
    search = "",
    queueScroll = 0,
    hitboxes = {},
    monitor = nil,
    monitorName = nil,
    target = term.current(),
    targetIsMonitor = false,
    speakers = {},
    speakerMap = {},
    remotes = {},
    lastRemoteStatus = 0,
    lastUiError = nil,
    libraryCached = false,
}

if state.loopMode ~= "all" and state.loopMode ~= "one" and state.loopMode ~= "off" then
    state.loopMode = "all"
end

_G.__ccmusic_running = true

local function stopSpeakers()
    for i = 1, #state.speakers do
        local sp = state.speakers[i].object
        if sp and sp.stop then pcall(sp.stop) end
    end
end

local function refreshPeripherals()
    local oldMonitorName = state.monitorName
    local names = peripheral.getNames and peripheral.getNames() or {}
    local monitor, monitorName
    local speakers, speakerMap = {}, {}

    for _, name in ipairs(names) do
        local ty = peripheral.getType(name)
        if ty == "monitor" and not monitor then
            local obj = peripheral.wrap(name)
            if obj then monitor, monitorName = obj, name end
        elseif ty == "speaker" then
            local obj = peripheral.wrap(name)
            if obj then
                speakers[#speakers + 1] = { name = name, object = obj }
                speakerMap[name] = obj
            end
        elseif ty == "modem" then
            if rednet and rednet.open and not rednet.isOpen(name) then pcall(rednet.open, name) end
        end
    end

    table.sort(speakers, function(a, b) return a.name < b.name end)
    state.speakers = speakers
    state.speakerMap = speakerMap
    state.monitor = monitor
    state.monitorName = monitorName

    if monitor then
        pcall(monitor.setTextScale, CONFIG.textScale)
        state.target = monitor
        state.targetIsMonitor = true
    else
        state.target = term.current()
        state.targetIsMonitor = false
    end

    if oldMonitorName ~= state.monitorName then state._frameInvalid = true end
end

refreshPeripherals()

local function interruptAudio(reason)
    state.audioInterrupt = state.audioInterrupt + 1
    if state.flight and not state.flight.interruptMs then
        state.flight.interruptMs = nowMs()
        state.flight.interruptReason = reason
    end
    stopSpeakers()
    os.queueEvent("ccmusic_wake", reason or "interrupt")
end

local function setVolume(v)
    v = clamp(v, 0, 1)
    if math.abs(v - state.volume) < 0.001 then return end
    state.volume = v
    saveSetting("ccmusic.volume", state.volume)
    interruptAudio("volume")
end

local function setPaused(v)
    v = v == true
    if state.paused == v then return end
    state.paused = v
    if v then
        interruptAudio("pause")
    else
        os.queueEvent("ccmusic_wake", "resume")
    end
end

local function togglePause()
    if state.current then setPaused(not state.paused) end
end

-- ---------------------------------------------------------------------------
-- Playlist / queue
-- ---------------------------------------------------------------------------

local function shuffleArray(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function findOrderPos(trackIndex)
    for i = 1, #state.order do
        if state.order[i] == trackIndex then return i end
    end
    return nil
end

local function rebuildOrder(keepCurrent)
    local current = keepCurrent and state.currentIndex or nil
    state.order = {}
    for i = 1, #state.library do state.order[i] = i end
    if state.shuffle then shuffleArray(state.order) end

    if current then
        local pos = findOrderPos(current)
        if pos then
            state.orderPos = pos
        else
            state.orderPos = 1
        end
    else
        state.orderPos = 1
    end
    state.queueScroll = 0
end

local function preferredStartIndex()
    local needle = CONFIG.startTrack:lower()
    if needle ~= "" then
        for i = 1, #state.library do
            if state.library[i].title:lower():find(needle, 1, true) then return i end
        end
    end
    return #state.library > 0 and 1 or nil
end

local function requestTrack(index, addHistory)
    if not index or not state.library[index] then return end
    if addHistory and state.currentIndex and state.currentIndex ~= index then
        state.history[#state.history + 1] = state.currentIndex
        if #state.history > 100 then table.remove(state.history, 1) end
    end

    state.currentIndex = index
    state.current = state.library[index]
    local pos = findOrderPos(index)
    if pos then state.orderPos = pos end
    state.generation = state.generation + 1
    state.playedSamples = 0
    state.flight = nil
    state.lyrics = {}
    state.loading = true
    state.stopped = false
    state.error = nil
    state.paused = false
    state.queueScroll = 0
    interruptAudio("track")
end

local function restartCurrent()
    if state.currentIndex then requestTrack(state.currentIndex, false) end
end

local function chooseNext(manual)
    if #state.order == 0 then return end
    if not manual and state.loopMode == "one" then
        restartCurrent()
        return
    end

    local nextPos = state.orderPos + 1
    if nextPos > #state.order then
        if state.loopMode == "off" and not manual then
            state.stopped = true
            state.loading = false
            state.paused = false
            state.current = nil
            state.currentIndex = nil
            state.generation = state.generation + 1
            interruptAudio("stop")
            return
        end
        nextPos = 1
        if state.shuffle then shuffleArray(state.order) end
    end
    state.orderPos = nextPos
    requestTrack(state.order[nextPos], true)
end

local function choosePrevious()
    if not state.current then return end
    local posSeconds = 0
    if state.flight then
        local t = state.flight.interruptMs or nowMs()
        local elapsed = clamp(math.floor((t - state.flight.startedMs) * 48), 0, state.flight.length)
        posSeconds = (state.playedSamples + elapsed) / 48000
    else
        posSeconds = state.playedSamples / 48000
    end
    if posSeconds > 3 then
        restartCurrent()
        return
    end

    local hist = table.remove(state.history)
    if hist and state.library[hist] then
        requestTrack(hist, false)
        return
    end

    local p = state.orderPos - 1
    if p < 1 then p = #state.order end
    state.orderPos = p
    requestTrack(state.order[p], false)
end

local function toggleShuffle()
    state.shuffle = not state.shuffle
    saveSetting("ccmusic.shuffle", state.shuffle)
    rebuildOrder(true)
end

local function cycleLoop()
    if state.loopMode == "all" then state.loopMode = "one"
    elseif state.loopMode == "one" then state.loopMode = "off"
    else state.loopMode = "all" end
    saveSetting("ccmusic.loop", state.loopMode)
end

-- ---------------------------------------------------------------------------
-- SQSH + lyrics
-- ---------------------------------------------------------------------------

local function parseHeaderLine(line, key)
    if type(line) ~= "string" then return nil end
    line = line:gsub("\r$", "")
    return tonumber(line:match("^" .. key .. "=(%d+)$"))
end

local function readExact(handle, count)
    if count <= 0 then return "" end
    local parts, got = {}, 0
    while got < count do
        local piece = handle.read(count - got)
        if not piece or #piece == 0 then return nil end
        parts[#parts + 1] = piece
        got = got + #piece
    end
    return table.concat(parts)
end

local function readSqshHeader(handle)
    local magic = handle.readLine()
    if magic then magic = magic:gsub("\r$", "") end
    if magic ~= "SQSH1" then return nil, "Not an SQSH1 file" end

    local rate = parseHeaderLine(handle.readLine(), "rate")
    local lyricBytes = parseHeaderLine(handle.readLine(), "lyrics")
    local audioBytes = parseHeaderLine(handle.readLine(), "audio")
    handle.readLine() -- blank separator line

    if not rate or rate < 1000 or rate > 48000 then return nil, "Invalid SQSH sample rate" end
    if not lyricBytes or lyricBytes < 0 then return nil, "Invalid SQSH lyrics size" end
    if not audioBytes or audioBytes < 1 then return nil, "Invalid SQSH audio size" end

    local lyricsRaw = ""
    if lyricBytes > 0 then
        lyricsRaw = readExact(handle, lyricBytes)
        if not lyricsRaw then return nil, "Truncated SQSH lyrics block" end
    end

    return {
        rate = rate,
        lyricBytes = lyricBytes,
        audioBytes = audioBytes,
        lyricsRaw = lyricsRaw,
    }
end

local function parseLyrics(raw)
    local out = {}
    if type(raw) ~= "string" or raw == "" then return out end
    raw = raw:gsub("\0", "")

    for line in raw:gmatch("[^\r\n]+") do
        local text = line:gsub("%[[^%]]+%]", "")
        text = trim(asciiSafe(text))
        local foundFractional = false
        for min, sec, frac in line:gmatch("%[(%d+):(%d+)[%.:](%d+)%]") do
            foundFractional = true
            local m, s = tonumber(min), tonumber(sec)
            local f = tonumber(frac) or 0
            local scale = 10 ^ #frac
            if m and s then
                out[#out + 1] = { time = m * 60 + s + f / scale, text = text }
            end
        end
        -- Also accept [mm:ss] timestamps without a fractional part.
        if not foundFractional then
            for min, sec in line:gmatch("%[(%d+):(%d+)%]") do
                local m, s = tonumber(min), tonumber(sec)
                if m and s then out[#out + 1] = { time = m * 60 + s, text = text } end
            end
        end
    end

    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

local function lyricAt(seconds)
    local lyrics = state.lyrics
    if #lyrics == 0 then return "(no synced lyrics)" end
    local lo, hi, best = 1, #lyrics, nil
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if lyrics[mid].time <= seconds + 0.06 then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    if not best or lyrics[best].text == "" then return "..." end
    return lyrics[best].text
end

-- ---------------------------------------------------------------------------
-- Audio analysis and resampling
-- ---------------------------------------------------------------------------

local VIZ_FREQS = { 70, 100, 145, 205, 290, 410, 580, 820, 1160, 1640, 2320, 3280, 4640, 6560, 8500, 10800 }
local vizCoeffCache = {}

for i = 1, #VIZ_FREQS do state.bands[i] = 0 end

local function getVizCoefficients(rate)
    local cache = vizCoeffCache[rate]
    if cache then return cache end
    cache = {}
    for i = 1, #VIZ_FREQS do
        local f = math.min(VIZ_FREQS[i], rate * 0.45)
        cache[i] = 2 * math.cos(2 * math.pi * f / rate)
    end
    vizCoeffCache[rate] = cache
    return cache
end

local function analyzeAudio(samples, rate)
    local count = #samples
    if count == 0 then return end
    local n = math.min(384, count)
    local start = count - n + 1
    local coeffs = getVizCoefficients(rate)
    local mags = {}
    local maxMag = 0
    local sumSq = 0

    for j = start, count do
        local v = (samples[j] or 0) / 128
        sumSq = sumSq + v * v
    end
    local rms = math.sqrt(sumSq / n)
    state.rms = state.rms * 0.72 + rms * 0.28

    for b = 1, #VIZ_FREQS do
        local coeff = coeffs[b]
        local q1, q2 = 0, 0
        for j = start, count do
            local x = (samples[j] or 0) / 128
            local q0 = coeff * q1 - q2 + x
            q2, q1 = q1, q0
        end
        local p = q1 * q1 + q2 * q2 - coeff * q1 * q2
        if p < 0 then p = 0 end
        local mag = math.sqrt(p) / n
        mags[b] = mag
        if mag > maxMag then maxMag = mag end
    end

    local wanted = 1
    if maxMag > 0.005 then wanted = clamp(0.65 / maxMag, 0.7, 16) end
    if wanted < state.vizGain then
        state.vizGain = state.vizGain * 0.55 + wanted * 0.45
    else
        state.vizGain = state.vizGain * 0.90 + wanted * 0.10
    end

    for i = 1, #mags do
        local v = clamp(mags[i] * state.vizGain, 0, 1)
        v = math.sqrt(v)
        local old = state.bands[i] or 0
        if v > old then
            state.bands[i] = old * 0.25 + v * 0.75
        else
            state.bands[i] = old * 0.78 + v * 0.22
        end
    end
end

local function resample48k(samples, sourceRate)
    if sourceRate == 48000 then return samples end
    local n = #samples
    if sourceRate == 24000 then
        -- 2x linear interpolation sounds noticeably smoother than simply duplicating
        -- every 24 kHz sample, while keeping the exact 48 kHz output length.
        local out = {}
        local k = 1
        for i = 1, n do
            local a = samples[i] or 0
            local b = samples[i + 1] or a
            out[k] = a
            out[k + 1] = math.floor((a + b) * 0.5 + (a + b >= 0 and 0.5 or -0.5))
            k = k + 2
        end
        return out
    end

    local out = {}
    local outCount = math.max(1, math.floor(n * 48000 / sourceRate + 0.5))
    for i = 1, outCount do
        local src = 1 + (i - 1) * sourceRate / 48000
        local a = math.floor(src)
        local frac = src - a
        if a < 1 then a = 1 end
        if a >= n then
            out[i] = samples[n] or 0
        else
            local x, y = samples[a] or 0, samples[a + 1] or 0
            out[i] = math.floor(x + (y - x) * frac + 0.5)
        end
    end
    return out
end

local function sliceSamples(samples, first)
    local out = {}
    local k = 1
    for i = first, #samples do out[k] = samples[i]; k = k + 1 end
    return out
end

local function currentPositionSamples()
    local base = state.playedSamples
    local f = state.flight
    if f then
        local t
        if f.interruptMs then t = f.interruptMs
        elseif state.paused and f.pauseMs then t = f.pauseMs
        else t = nowMs() end
        local consumed = clamp(math.floor((t - f.startedMs) * 48), 0, f.length)
        base = base + consumed
    end
    return base
end

local function currentPositionSeconds()
    return currentPositionSamples() / 48000
end

-- ---------------------------------------------------------------------------
-- Speaker scheduling
-- ---------------------------------------------------------------------------

local function speakersAvailable()
    return #state.speakers > 0
end

local function tryStartSegment(segment, generation)
    if #segment == 0 then return true end
    while state.running and generation == state.generation do
        while state.paused and state.running and generation == state.generation do
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return false end
        end
        if not state.running or generation ~= state.generation then return false end

        if not speakersAvailable() then
            state.loading = false
            state.error = "No speaker found"
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return false end
        else
            local allAccepted = true
            local acceptedNames = {}
            for i = 1, #state.speakers do
                local entry = state.speakers[i]
                local ok, accepted = pcall(entry.object.playAudio, segment, state.volume)
                if ok and accepted then
                    acceptedNames[#acceptedNames + 1] = entry.name
                else
                    allAccepted = false
                    break
                end
            end

            if allAccepted then
                local started = nowMs()
                state.flight = {
                    startedMs = started,
                    length = #segment,
                    interruptMs = nil,
                    interruptReason = nil,
                }
                return acceptedNames
            end

            -- Avoid starting one speaker early if another was still busy.
            stopSpeakers()
            local timer = os.startTimer(0.05)
            while state.running and generation == state.generation do
                local ev, id = os.pullEventRaw()
                if ev == "timer" and id == timer then break end
                if ev == "ccmusic_wake" then break end
                if ev == "ccmusic_shutdown" then return false end
            end
        end
    end
    return false
end

local function playPcmBlock(pcm, generation)
    local offset = 1
    while offset <= #pcm and state.running and generation == state.generation do
        while state.paused and state.running and generation == state.generation do
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return false end
        end
        if generation ~= state.generation or not state.running then return false end

        local segment
        if offset == 1 then segment = pcm else segment = sliceSamples(pcm, offset) end
        local interruptVersion = state.audioInterrupt
        local waitingNames = tryStartSegment(segment, generation)
        if type(waitingNames) ~= "table" then return false end

        state.loading = false
        state.error = nil
        local waiting = {}
        for i = 1, #waitingNames do waiting[waitingNames[i]] = true end
        local naturalDone = false
        local interrupted = false

        while state.running and generation == state.generation do
            if next(waiting) == nil then naturalDone = true; break end
            if state.audioInterrupt ~= interruptVersion or state.paused then interrupted = true; break end

            local ev, a = os.pullEventRaw()
            if ev == "speaker_audio_empty" then
                waiting[a] = nil
            elseif ev == "peripheral_detach" then
                waiting[a] = nil
            elseif ev == "ccmusic_wake" then
                if state.audioInterrupt ~= interruptVersion or state.paused then interrupted = true; break end
            elseif ev == "ccmusic_shutdown" then
                return false
            end
        end

        if generation ~= state.generation or not state.running then
            state.flight = nil
            return false
        end

        local f = state.flight
        if naturalDone then
            state.playedSamples = state.playedSamples + #segment
            state.flight = nil
            offset = #pcm + 1
        elseif interrupted then
            local stopAt = f and (f.interruptMs or nowMs()) or nowMs()
            local consumed = f and clamp(math.floor((stopAt - f.startedMs) * 48), 0, #segment) or 0
            if consumed > 0 then
                state.playedSamples = state.playedSamples + consumed
                offset = offset + consumed
            end
            state.flight = nil
            -- If this was only a volume change, resume immediately from the remaining PCM.
            -- If paused, the top of the loop blocks until resume.
        else
            state.flight = nil
            return false
        end
    end
    return generation == state.generation and state.running
end

local function openTrack(track)
    local lastErr
    for attempt = 1, 3 do
        if not state.running then return nil, "Stopped" end
        local h, err = httpGet(track.url, true)
        if h then return h end
        lastErr = err
        state.error = "Stream retry " .. attempt .. "/3: " .. tostring(err)
        waitSeconds(0.7 * attempt)
    end
    return nil, lastErr or "Could not open audio stream"
end

local function audioLoop()
    while state.running do
        local generation = state.generation
        local track = state.current
        if not track then
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return end
        else
            state.loading = true
            state.error = nil
            state.playedSamples = 0
            state.flight = nil
            state.lyrics = {}
            stopSpeakers()

            local handle, err = openTrack(track)
            if not handle then
                if generation == state.generation then
                    state.loading = false
                    state.error = "Stream failed: " .. tostring(err)
                    waitSeconds(1.5)
                    if generation == state.generation then os.queueEvent("ccmusic_track_end", generation, true) end
                end
            else
                local ok, headerOrErr, headerErr = pcall(readSqshHeader, handle)
                local header = ok and headerOrErr or nil
                local parseErr = ok and headerErr or headerOrErr
                if not header then
                    safeClose(handle)
                    if generation == state.generation then
                        state.loading = false
                        state.error = "SQSH error: " .. tostring(parseErr)
                        waitSeconds(1.2)
                        if generation == state.generation then os.queueEvent("ccmusic_track_end", generation, true) end
                    end
                else
                    track.rate = header.rate
                    track.audioBytes = header.audioBytes
                    track.lyricsBytes = header.lyricBytes
                    track.duration = header.audioBytes * 8 / header.rate
                    state.lyrics = parseLyrics(header.lyricsRaw)
                    local decoder = dfpwm.make_decoder()
                    local remaining = header.audioBytes
                    state.loading = false

                    while state.running and generation == state.generation and remaining > 0 do
                        while state.paused and state.running and generation == state.generation do
                            local ev = os.pullEventRaw()
                            if ev == "ccmusic_shutdown" then break end
                        end
                        if not state.running or generation ~= state.generation then break end

                        local want = math.min(CONFIG.chunkBytes, remaining)
                        local chunk = handle.read(want)
                        if not chunk or #chunk == 0 then
                            state.error = "Unexpected end of SQSH stream"
                            break
                        end
                        remaining = remaining - #chunk

                        local okDecode, decoded = pcall(decoder, chunk)
                        if not okDecode or type(decoded) ~= "table" then
                            state.error = "DFPWM decode failed"
                            break
                        end

                        analyzeAudio(decoded, header.rate)
                        local pcm = resample48k(decoded, header.rate)
                        if not playPcmBlock(pcm, generation) then break end
                    end

                    safeClose(handle)
                    if generation == state.generation and state.running then
                        if remaining <= 0 and not state.error then
                            os.queueEvent("ccmusic_track_end", generation, false)
                        elseif state.error then
                            waitSeconds(1.0)
                            if generation == state.generation then os.queueEvent("ccmusic_track_end", generation, true) end
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- UI framebuffer
-- ---------------------------------------------------------------------------

local BLIT = {}
for _, c in ipairs({
    colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray,
    colors.lightGray, colors.cyan, colors.purple, colors.blue,
    colors.brown, colors.green, colors.red, colors.black,