-- CC-Music Player for CC:Tweaked / ATM10 8.2
-- Designed for large Advanced Monitor walls and SQSH1/SQSH2 (DFPWM) audio files.
-- Repository default: https://github.com/Di33le/CC-Music

local VERSION = "3.5.0"
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
defineSetting("ccmusic.chunk_bytes", 0, "number", "DFPWM bytes per chunk; 0 = automatic maximum safe size")
defineSetting("ccmusic.hq_resampler", true, "boolean", "Use higher-quality 24 kHz -> 48 kHz interpolation")
defineSetting("ccmusic.legacy_resampler", "sinc8", "string", "24 kHz upsampler: sinc8, cubic, or linear")
defineSetting("ccmusic.ui_fps", 12, "number", "Maximum UI refresh rate")
defineSetting("ccmusic.viz_slice_bytes", 512, "number", "DFPWM bytes per visualizer/audio scheduling slice at 48 kHz")
defineSetting("ccmusic.viz_mode", "classic", "string", "Visualizer: classic, mirror, or meter")
defineSetting("ccmusic.start_track", "Sundress", "string", "Preferred title substring to play first")
defineSetting("ccmusic.library_repo", "Chazammm/atm10-cc-doom", "string", "Repository containing the CC-Music release library")
defineSetting("ccmusic.library_tag", "cc-music-library-v1", "string", "GitHub release tag containing library.json and SQSH assets")
defineSetting("ccmusic.resume_enabled", true, "boolean", "Resume the last track and position after restart")
defineSetting("ccmusic.resume_track", "", "string", "Last played logical track name")
defineSetting("ccmusic.resume_position", 0, "number", "Last played position in seconds")
defineSetting("ccmusic.audio_mode", "auto", "string", "Audio routing: auto, stereo, or mono")
defineSetting("ccmusic.left_speaker", "", "string", "Peripheral name for the left stereo speaker")
defineSetting("ccmusic.right_speaker", "", "string", "Peripheral name for the right stereo speaker")
defineSetting("ccmusic.balance", 0.0, "number", "Stereo balance from -1.0 (left) to +1.0 (right)")
defineSetting("ccmusic.passthrough_48k", true, "boolean", "Preserve native 48 kHz DFPWM bitstream when possible")
defineSetting("ccmusic.stereo_chunk_bytes", 8192, "number", "SQSH2 DFPWM bytes per channel block")

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
    chunkBytes = math.floor(tonumber(getSetting("ccmusic.chunk_bytes", 0)) or 0),
    hqResampler = getSetting("ccmusic.hq_resampler", true) ~= false,
    legacyResampler = tostring(getSetting("ccmusic.legacy_resampler", "sinc8")):lower(),
    uiFps = tonumber(getSetting("ccmusic.ui_fps", 12)) or 12,
    vizSliceBytes = math.floor(tonumber(getSetting("ccmusic.viz_slice_bytes", 512)) or 512),
    vizMode = tostring(getSetting("ccmusic.viz_mode", "classic")):lower(),
    startTrack = tostring(getSetting("ccmusic.start_track", "Sundress")),
    libraryRepo = tostring(getSetting("ccmusic.library_repo", "Chazammm/atm10-cc-doom")),
    libraryTag = tostring(getSetting("ccmusic.library_tag", "cc-music-library-v1")),
    resumeEnabled = getSetting("ccmusic.resume_enabled", true) ~= false,
    audioMode = tostring(getSetting("ccmusic.audio_mode", "auto")):lower(),
    leftSpeaker = tostring(getSetting("ccmusic.left_speaker", "")),
    rightSpeaker = tostring(getSetting("ccmusic.right_speaker", "")),
    balance = tonumber(getSetting("ccmusic.balance", 0.0)) or 0.0,
    passthrough48k = getSetting("ccmusic.passthrough_48k", true) ~= false,
    stereoChunkBytes = math.floor(tonumber(getSetting("ccmusic.stereo_chunk_bytes", 8192)) or 8192),
}
if CONFIG.chunkBytes ~= 0 then CONFIG.chunkBytes = math.max(256, math.min(16384, CONFIG.chunkBytes)) end
CONFIG.uiFps = math.max(2, math.min(16, CONFIG.uiFps))
CONFIG.vizSliceBytes = math.max(256, math.min(2048, CONFIG.vizSliceBytes))
if CONFIG.vizMode ~= "classic" and CONFIG.vizMode ~= "mirror" and CONFIG.vizMode ~= "meter" then CONFIG.vizMode = "classic" end
if CONFIG.textScale < 0.5 then CONFIG.textScale = 0.5 end
if CONFIG.textScale > 5 then CONFIG.textScale = 5 end
if CONFIG.legacyResampler ~= "sinc8" and CONFIG.legacyResampler ~= "cubic" and CONFIG.legacyResampler ~= "linear" then CONFIG.legacyResampler = "sinc8" end
if CONFIG.audioMode ~= "auto" and CONFIG.audioMode ~= "stereo" and CONFIG.audioMode ~= "mono" then CONFIG.audioMode = "auto" end
CONFIG.balance = math.max(-1, math.min(1, CONFIG.balance))
CONFIG.stereoChunkBytes = math.max(1024, math.min(16384, CONFIG.stereoChunkBytes))

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

local function marqueeText(text, width)
    text = asciiSafe(text or "")
    width = math.max(1, math.floor(width or #text))
    if #text <= width then return text end
    local gap = "   "
    local cycle = text .. gap
    local offset = math.floor(nowMs() / 320) % #cycle
    local doubled = cycle .. cycle
    return doubled:sub(offset + 1, offset + width)
end

local function urlEncode(s)
    return (tostring(s):gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function releaseBaseUrl()
    return "https://github.com/" .. CONFIG.libraryRepo .. "/releases/download/"
        .. urlEncode(CONFIG.libraryTag) .. "/"
end

local function releaseTagApiUrl()
    return "https://api.github.com/repos/" .. CONFIG.libraryRepo
        .. "/releases/tags/" .. urlEncode(CONFIG.libraryTag)
end

local function releaseAssetsApiUrl(releaseId)
    return "https://api.github.com/repos/" .. CONFIG.libraryRepo
        .. "/releases/" .. tostring(releaseId) .. "/assets?per_page=100&page=1"
end

local function manifestUrl()
    return releaseBaseUrl() .. "library.json"
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
        ["Cache-Control"] = "no-cache",
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
    local slim = {
        version = 2,
        repo = CONFIG.libraryRepo,
        tag = CONFIG.libraryTag,
        tracks = tracks,
    }
    local raw = jsonEncode(slim)
    if not raw then return end
    local h = fs.open(INDEX_CACHE, "w")
    if h then h.write(raw); h.close() end
end

local function canonicalAssetKey(name)
    name = tostring(name or ""):lower()
    name = name:gsub("%.sqsh$", "")
    name = name:gsub("%.part%d%d%d$", "")
    return (name:gsub("[^%w]", ""))
end

local function displayTitleFromAsset(stem)
    local s = tostring(stem or "")
    s = s:gsub("%.-%.", " - ")
    s = s:gsub("%.", " ")
    s = s:gsub("_", " ")
    s = s:gsub("%s+", " ")
    return trim(s)
end

local function fetchJson(url)
    local h, err = httpGet(url, false)
    if not h then return nil, err end
    local body = h.readAll()
    safeClose(h)
    local data = jsonDecode(body)
    if type(data) ~= "table" then return nil, "Invalid JSON from " .. tostring(url) end
    return data
end

local function loadReleaseLibrary()
    -- Manifest supplies human-friendly titles and exact durations. Asset API
    -- supplies the real GitHub-normalized filenames/URLs (GitHub turns spaces
    -- into dots on release assets), so playback never depends on guessed URLs.
    local manifest = nil
    do
        local data = fetchJson(manifestUrl())
        if type(data) == "table" and type(data.tracks) == "table" then manifest = data end
    end

    local release, err = fetchJson(releaseTagApiUrl())
    if not release or not release.id then return nil, err or "Could not resolve music release" end

    local assets, assetsErr = fetchJson(releaseAssetsApiUrl(release.id))
    if not assets then return nil, assetsErr or "Could not list music release assets" end

    local manifestByKey = {}
    if manifest then
        for _, item in ipairs(manifest.tracks) do
            if type(item) == "table" and item.name then
                manifestByKey[canonicalAssetKey(item.name)] = item
            end
        end
    end

    local groups = {}
    for _, asset in ipairs(assets) do
        if type(asset) == "table" and asset.state == "uploaded"
            and type(asset.name) == "string" and asset.name:lower():match("%.sqsh$") then
            local stem, partNo = asset.name:match("^(.*)%.part(%d%d%d)%.sqsh$")
            if not stem then
                stem = asset.name:gsub("%.sqsh$", "")
                partNo = "001"
            end
            local key = canonicalAssetKey(stem)
            local group = groups[key]
            if not group then
                group = { stem = stem, items = {} }
                groups[key] = group
            end
            group.items[#group.items + 1] = {
                name = asset.name,
                size = tonumber(asset.size) or 0,
                url = asset.browser_download_url,
                partNo = tonumber(partNo) or 1,
            }
        end
    end

    local tracks = {}
    for key, group in pairs(groups) do
        table.sort(group.items, function(a, b) return a.partNo < b.partNo end)
        local meta = manifestByKey[key]
        local totalSize = 0
        for _, p in ipairs(group.items) do totalSize = totalSize + (p.size or 0) end

        local track = {
            name = meta and meta.name or (group.stem .. ".sqsh"),
            title = meta and meta.title or displayTitleFromAsset(group.stem),
            size = totalSize,
            rate = tonumber(meta and meta.rate) or 48000,
            channels = tonumber(meta and meta.channels) or 2,
            format = meta and meta.format or "SQSH2",
            duration = tonumber(meta and meta.duration) or 0,
            audioBytes = nil,
            lyricsBytes = nil,
        }

        if track.duration <= 0 and totalSize > 0 then
            local ch = math.max(1, track.channels or 2)
            track.duration = totalSize * 8 / (track.rate * ch)
        end

        if #group.items == 1 then
            track.url = group.items[1].url
        else
            track.segmented = true
            track.parts = {}
            for i, p in ipairs(group.items) do
                track.parts[i] = { name = p.name, size = p.size, url = p.url }
            end
        end

        tracks[#tracks + 1] = track
    end

    table.sort(tracks, function(a, b) return a.title:lower() < b.title:lower() end)
    if #tracks == 0 then return nil, "Music release contains no uploaded SQSH assets" end
    return tracks, nil
end

local function loadLibrary()
    local tracks, warning = loadReleaseLibrary()
    if tracks and #tracks > 0 then
        writeCache(tracks)
        return tracks, warning, false
    end

    local cache = readCache()
    if cache and cache.version == 2 and cache.repo == CONFIG.libraryRepo
        and cache.tag == CONFIG.libraryTag and type(cache.tracks) == "table" and #cache.tracks > 0 then
        return cache.tracks, warning or "Using cached music library", true
    end

    return {}, warning or "Could not load CC-Music release library", false
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
    bandTargets = {},
    bandPeaks = {},
    bandPeakHold = {},
    bandsL = {},
    bandsR = {},
    bandTargetsL = {},
    bandTargetsR = {},
    rms = 0,
    rmsTarget = 0,
    vizBass = 0,
    vizGain = 1,
    vizLastMs = nil,
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
    leftSpeakerName = nil,
    rightSpeakerName = nil,
    leftSpeaker = nil,
    rightSpeaker = nil,
    sourceChannels = 1,
    sourceRate = 0,
    sourceFormat = "SQSH1",
    activeAudioMode = "MONO",
    audioPassthrough = false,
    streamPart = 0,
    streamPartCount = 0,
    requestedSeek = nil,
    manualQueue = {},
    queueAddMode = false,
    favorites = {},
    favoritesOnly = false,
    settingsOpen = false,
    lastResumeSaveMs = 0,
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

    -- Reuse the video player's stereo mapping when CC-Music has not been
    -- configured separately. This makes the existing LEFT/RIGHT setup work
    -- immediately for both projects.
    local leftName = CONFIG.leftSpeaker
    local rightName = CONFIG.rightSpeaker
    if leftName == "" then leftName = tostring(getSetting("musicvideo.left_speaker", "") or "") end
    if rightName == "" then rightName = tostring(getSetting("musicvideo.right_speaker", "") or "") end
    state.leftSpeakerName = leftName ~= "" and leftName or nil
    state.rightSpeakerName = rightName ~= "" and rightName or nil
    state.leftSpeaker = state.leftSpeakerName and speakerMap[state.leftSpeakerName] or nil
    state.rightSpeaker = state.rightSpeakerName and speakerMap[state.rightSpeakerName] or nil

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

local function requestSeek(seconds)
    if not state.current then return end
    local duration = tonumber(state.current.duration) or 0
    if duration <= 0 then return end

    seconds = clamp(tonumber(seconds) or 0, 0, math.max(0, duration - 0.05))
    state.requestedSeek = seconds
    state.playedSamples = math.floor(seconds * 48000 + 0.5)
    state.flight = nil
    state.loading = true
    state.error = nil
    state.paused = false
    state.generation = state.generation + 1
    interruptAudio("seek")
end

local function seekRelative(delta)
    requestSeek(currentPositionSeconds() + (tonumber(delta) or 0))
end

local FAVORITES_FILE = "/ccmusic/favorites.json"

local function loadFavorites()
    if not fs or not fs.exists(FAVORITES_FILE) then return {} end
    local h = fs.open(FAVORITES_FILE, "r")
    if not h then return {} end
    local raw = h.readAll()
    h.close()
    local data = jsonDecode(raw)
    local out = {}
    if type(data) == "table" then
        for _, name in ipairs(data) do
            if type(name) == "string" and name ~= "" then out[name] = true end
        end
    end
    return out
end

local function saveFavorites()
    if not fs then return end
    local list = {}
    for name, enabled in pairs(state.favorites) do
        if enabled then list[#list + 1] = name end
    end
    table.sort(list)
    local raw = jsonEncode(list)
    if not raw then return end
    local h = fs.open(FAVORITES_FILE, "w")
    if h then h.write(raw); h.close() end
end

local function isFavorite(indexOrTrack)
    local tr = type(indexOrTrack) == "table" and indexOrTrack or state.library[indexOrTrack]
    return tr and state.favorites[tr.name] == true or false
end

local function toggleFavorite(index)
    index = index or state.currentIndex
    local tr = index and state.library[index] or nil
    if not tr then return end
    if state.favorites[tr.name] then state.favorites[tr.name] = nil else state.favorites[tr.name] = true end
    saveFavorites()
end

local function favoriteCount()
    local n = 0
    for _, enabled in pairs(state.favorites) do if enabled then n = n + 1 end end
    return n
end

local function saveResume(force)
    if not CONFIG.resumeEnabled or not state.current then return end
    local now = nowMs()
    if not force and now - (state.lastResumeSaveMs or 0) < 5000 then return end
    state.lastResumeSaveMs = now
    saveSetting("ccmusic.resume_track", state.current.name or "")
    saveSetting("ccmusic.resume_position", currentPositionSeconds())
end

local function toggleResume()
    CONFIG.resumeEnabled = not CONFIG.resumeEnabled
    saveSetting("ccmusic.resume_enabled", CONFIG.resumeEnabled)
    if CONFIG.resumeEnabled then saveResume(true) end
end

local function queueTrackNext(index)
    index = tonumber(index)
    if not index or not state.library[index] then return false end
    state.manualQueue[#state.manualQueue + 1] = index
    return true
end

local function popQueuedTrack()
    while #state.manualQueue > 0 do
        local index = table.remove(state.manualQueue, 1)
        if state.library[index] then return index end
    end
    return nil
end

local function toggleQueueAddMode()
    state.queueAddMode = not state.queueAddMode
end

local function toggleFavoritesOnly()
    state.favoritesOnly = not state.favoritesOnly
    state.queueScroll = 0
end

local function toggleSettings()
    state.settingsOpen = not state.settingsOpen
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
    if state.current and state.currentIndex ~= index then saveResume(true) end
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

    local queued = popQueuedTrack()
    if queued then
        requestTrack(queued, true)
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

local function cycleAudioMode()
    if CONFIG.audioMode == "auto" then CONFIG.audioMode = "stereo"
    elseif CONFIG.audioMode == "stereo" then CONFIG.audioMode = "mono"
    else CONFIG.audioMode = "auto" end
    saveSetting("ccmusic.audio_mode", CONFIG.audioMode)
    interruptAudio("audio_mode")
end

local function cycleVizMode()
    if CONFIG.vizMode == "classic" then CONFIG.vizMode = "mirror"
    elseif CONFIG.vizMode == "mirror" then CONFIG.vizMode = "meter"
    else CONFIG.vizMode = "classic" end
    saveSetting("ccmusic.viz_mode", CONFIG.vizMode)
    state._frameInvalid = true
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

    if magic == "SQSH1" then
        local rate = parseHeaderLine(handle.readLine(), "rate")
        local lyricBytes = parseHeaderLine(handle.readLine(), "lyrics")
        local audioBytes = parseHeaderLine(handle.readLine(), "audio")
        handle.readLine() -- blank separator line

        if not rate or rate < 1000 or rate > 48000 then return nil, "Invalid SQSH1 sample rate" end
        if not lyricBytes or lyricBytes < 0 then return nil, "Invalid SQSH1 lyrics size" end
        if not audioBytes or audioBytes < 1 then return nil, "Invalid SQSH1 audio size" end

        local lyricsRaw = ""
        if lyricBytes > 0 then
            lyricsRaw = readExact(handle, lyricBytes)
            if not lyricsRaw then return nil, "Truncated SQSH1 lyrics block" end
        end

        return {
            format = "SQSH1",
            channels = 1,
            rate = rate,
            lyricBytes = lyricBytes,
            audioBytes = audioBytes,
            lyricsRaw = lyricsRaw,
        }
    elseif magic == "SQSH2" then
        -- Streaming stereo format. Audio bytes are per channel and stored as
        -- alternating fixed-size LEFT/RIGHT DFPWM blocks after the lyrics.
        local rate = parseHeaderLine(handle.readLine(), "rate")
        local channels = parseHeaderLine(handle.readLine(), "channels")
        local lyricBytes = parseHeaderLine(handle.readLine(), "lyrics")
        local audioBytes = parseHeaderLine(handle.readLine(), "audio")
        local blockBytes = parseHeaderLine(handle.readLine(), "block")
        handle.readLine() -- blank separator line

        if not rate or rate < 1000 or rate > 48000 then return nil, "Invalid SQSH2 sample rate" end
        if channels ~= 2 then return nil, "SQSH2 currently requires exactly 2 channels" end
        if not lyricBytes or lyricBytes < 0 then return nil, "Invalid SQSH2 lyrics size" end
        if not audioBytes or audioBytes < 1 then return nil, "Invalid SQSH2 audio size" end
        if not blockBytes or blockBytes < 256 or blockBytes > 16384 then return nil, "Invalid SQSH2 block size" end

        local lyricsRaw = ""
        if lyricBytes > 0 then
            lyricsRaw = readExact(handle, lyricBytes)
            if not lyricsRaw then return nil, "Truncated SQSH2 lyrics block" end
        end

        return {
            format = "SQSH2",
            channels = 2,
            rate = rate,
            lyricBytes = lyricBytes,
            audioBytes = audioBytes,
            blockBytes = blockBytes,
            lyricsRaw = lyricsRaw,
        }
    end

    return nil, "Not an SQSH1/SQSH2 file"
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

for i = 1, #VIZ_FREQS do
    state.bands[i] = 0
    state.bandTargets[i] = 0
    state.bandPeaks[i] = 0
    state.bandPeakHold[i] = 0
    state.bandsL[i] = 0
    state.bandsR[i] = 0
    state.bandTargetsL[i] = 0
    state.bandTargetsR[i] = 0
end

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


local function spectrumOf(samples, rate)
    local count = #samples
    if count == 0 then return nil, 0, 0 end
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

    return mags, maxMag, math.sqrt(sumSq / n)
end

local function updateVizGain(maxMag)
    local wanted = 1
    if maxMag > 0.005 then wanted = clamp(0.65 / maxMag, 0.7, 16) end
    if wanted < state.vizGain then
        state.vizGain = state.vizGain * 0.72 + wanted * 0.28
    else
        state.vizGain = state.vizGain * 0.94 + wanted * 0.06
    end
end

local function perceptualBand(mag)
    local v = clamp((mag or 0) * state.vizGain, 0, 1)
    return math.sqrt(v)
end

local function analyzeAudio(samples, rate)
    local mags, maxMag, rms = spectrumOf(samples, rate)
    if not mags then return end
    updateVizGain(maxMag)
    state.rmsTarget = rms

    for i = 1, #mags do
        local v = perceptualBand(mags[i])
        local previousTarget = state.bandTargets[i] or 0
        state.bandTargets[i] = previousTarget * 0.18 + v * 0.82
        state.bandTargetsL[i] = state.bandTargets[i]
        state.bandTargetsR[i] = state.bandTargets[i]
    end
end

local function analyzeStereoAudio(left, right, rate)
    local magsL, maxL, rmsL = spectrumOf(left, rate)
    local magsR, maxR, rmsR = spectrumOf(right, rate)
    if not magsL or not magsR then return end

    updateVizGain(math.max(maxL, maxR))
    state.rmsTarget = math.sqrt((rmsL * rmsL + rmsR * rmsR) * 0.5)

    for i = 1, #magsL do
        local l = perceptualBand(magsL[i])
        local r = perceptualBand(magsR[i])
        state.bandTargetsL[i] = (state.bandTargetsL[i] or 0) * 0.18 + l * 0.82
        state.bandTargetsR[i] = (state.bandTargetsR[i] or 0) * 0.18 + r * 0.82
        local combined = (l + r) * 0.5
        state.bandTargets[i] = (state.bandTargets[i] or 0) * 0.18 + combined * 0.82
    end
end

local function advanceVisualizer()
    local now = nowMs()
    local last = state.vizLastMs or now
    local dt = clamp((now - last) / 1000, 0, 0.25)
    state.vizLastMs = now
    if dt <= 0 then return end

    local active = state.current and not state.paused and not state.loading and not state.error
    local rmsTarget = active and (state.rmsTarget or 0) or 0

    -- Exponential attack/release. Fast attack catches drums; slower release
    -- gives the bars inertia instead of the old frame-to-frame twitch.
    local rmsTau = rmsTarget > (state.rms or 0) and 0.045 or 0.20
    local rmsK = 1 - math.exp(-dt / rmsTau)
    state.rms = (state.rms or 0) + (rmsTarget - (state.rms or 0)) * rmsK

    local bassSum = 0
    for i = 1, #VIZ_FREQS do
        local target = active and (state.bandTargets[i] or 0) or 0
        local shown = state.bands[i] or 0
        local tau = target > shown and 0.050 or 0.24
        local k = 1 - math.exp(-dt / tau)
        shown = shown + (target - shown) * k
        if shown < 0.002 then shown = 0 end
        state.bands[i] = shown

        local targetL = active and (state.bandTargetsL[i] or target) or 0
        local shownL = state.bandsL[i] or 0
        local tauL = targetL > shownL and 0.050 or 0.24
        state.bandsL[i] = shownL + (targetL - shownL) * (1 - math.exp(-dt / tauL))

        local targetR = active and (state.bandTargetsR[i] or target) or 0
        local shownR = state.bandsR[i] or 0
        local tauR = targetR > shownR and 0.050 or 0.24
        state.bandsR[i] = shownR + (targetR - shownR) * (1 - math.exp(-dt / tauR))

        local peak = state.bandPeaks[i] or 0
        if shown >= peak then
            peak = shown
            state.bandPeakHold[i] = now + 180
        elseif now >= (state.bandPeakHold[i] or 0) then
            peak = math.max(shown, peak - dt * 0.62)
        end
        state.bandPeaks[i] = peak

        if i <= 4 then bassSum = bassSum + shown end
    end

    local bassTarget = bassSum / 4
    local bassTau = bassTarget > (state.vizBass or 0) and 0.055 or 0.28
    local bassK = 1 - math.exp(-dt / bassTau)
    state.vizBass = (state.vizBass or 0) + (bassTarget - (state.vizBass or 0)) * bassK
end

local function clampPcm8(v)
    if v > 127 then return 127 end
    if v < -128 then return -128 end
    if v >= 0 then return math.floor(v + 0.5) end
    return math.ceil(v - 0.5)
end

-- For native 48 kHz DFPWM, feeding the original one-bit decisions back into
-- speaker.playAudio as -128/+127 preserves the stored DFPWM stream through
-- CC:Tweaked's server-side encoder. We still decode a copy for the visualizer.
local DFPWM_BITS = {}
for b = 0, 255 do
    local row = {}
    for j = 0, 7 do
        row[j + 1] = bit32.band(bit32.rshift(b, j), 1) ~= 0 and 127 or -128
    end
    DFPWM_BITS[b] = row
end

local function makeDfpwmPassthrough()
    local out, oldLength = {}, 0
    return function(data)
        local n, at = #data * 8, 1
        for i = 1, #data do
            table.move(DFPWM_BITS[data:byte(i)], 1, 8, at, out)
            at = at + 8
        end
        if oldLength > n then
            for i = n + 1, oldLength do out[i] = nil end
        end
        oldLength = n
        return out
    end
end

local function makeDfpwmTailDecoder(tailCount)
    -- CC:Tweaked-compatible predictor, but retain only the last few decoded
    -- samples needed by the visualizer. Native 48 kHz passthrough therefore
    -- avoids allocating a 65k/131k-sample PCM table for every audio block.
    tailCount = math.max(32, math.floor(tailCount or 384))
    local floor, byte = math.floor, string.byte
    local PREC, PREC_POW, PREC_POW_HALF = 10, 1024, 512
    local STRENGTH_MIN = 8
    local charge, strength, predictorPreviousBit = 0, 0, false
    local lowPassCharge, previousCharge, previousBit = 0, 0, false
    local ring, ringAt, seen = {}, 1, 0

    local function predictor(currentBit)
        local target = currentBit and 127 or -128
        local nextCharge = charge + floor((strength * (target - charge) + PREC_POW_HALF) / PREC_POW)
        if nextCharge == charge and nextCharge ~= target then
            nextCharge = nextCharge + (currentBit and 1 or -1)
        end
        local z = currentBit == predictorPreviousBit and PREC_POW - 1 or 0
        local nextStrength = strength
        if nextStrength ~= z then
            nextStrength = nextStrength + (currentBit == predictorPreviousBit and 1 or -1)
        end
        if nextStrength < STRENGTH_MIN then nextStrength = STRENGTH_MIN end
        charge, strength, predictorPreviousBit = nextCharge, nextStrength, currentBit
        return charge
    end

    return function(input)
        for i = 1, #input do
            local inputByte = byte(input, i)
            for _ = 1, 8 do
                local currentBit = bit32.band(inputByte, 1) ~= 0
                local currentCharge = predictor(currentBit)
                local antijerk = currentCharge
                if currentBit ~= previousBit then
                    antijerk = floor((currentCharge + previousCharge + 1) / 2)
                end
                previousCharge, previousBit = currentCharge, currentBit
                lowPassCharge = lowPassCharge + floor(((antijerk - lowPassCharge) * 140 + 0x80) / 256)
                ring[ringAt] = lowPassCharge
                ringAt = ringAt + 1
                if ringAt > tailCount then ringAt = 1 end
                seen = math.min(tailCount, seen + 1)
                inputByte = bit32.rshift(inputByte, 1)
            end
        end

        local out = {}
        if seen < tailCount then
            for i = 1, seen do out[i] = ring[i] end
        else
            local p = ringAt
            for i = 1, tailCount do
                out[i] = ring[p]
                p = p + 1
                if p > tailCount then p = 1 end
            end
        end
        return out
    end
end

local function makeStereoMixer()
    local out, oldLength = {}, 0
    return function(left, right)
        local n = math.min(#left, #right)
        for i = 1, n do out[i] = clampPcm8(((left[i] or 0) + (right[i] or 0)) * 0.5) end
        if oldLength > n then
            for i = n + 1, oldLength do out[i] = nil end
        end
        oldLength = n
        return out
    end
end

local function resample48k(samples, sourceRate, context)
    if sourceRate == 48000 then return samples end
    local n = #samples
    if n == 0 then return samples end

    if sourceRate == 24000 then
        local out = {}
        local k = 1
        local mode = CONFIG.hqResampler and CONFIG.legacyResampler or "linear"

        if mode == "sinc8" then
            -- Blackman-windowed sinc interpolation at the half-sample point.
            -- The 8-tap design has two zero end taps, so the hot path needs six
            -- multiplies. It rejects much more 24 kHz imaging than cubic while
            -- staying cheap enough for real-time CC:Tweaked playback.
            --
            -- Coefficients are symmetric and sum to 1:
            --   +0.01151696, -0.09744225, +0.58592529,
            --   +0.58592529, -0.09744225, +0.01151696
            local prev2 = (context and context.prev2) or samples[1] or 0
            local prev1 = (context and context.prev1) or samples[1] or 0

            for i = 1, n do
                local xm2 = i > 2 and samples[i - 2] or (i == 2 and prev1 or prev2)
                local xm1 = i > 1 and samples[i - 1] or prev1
                local x0 = samples[i] or 0
                local x1 = samples[i + 1] or x0
                local x2 = samples[i + 2] or x1
                local x3 = samples[i + 3] or x2

                out[k] = x0
                out[k + 1] = clampPcm8(
                    0.01151696 * xm2
                    - 0.09744225 * xm1
                    + 0.58592529 * x0
                    + 0.58592529 * x1
                    - 0.09744225 * x2
                    + 0.01151696 * x3
                )
                k = k + 2
            end

            if context then
                context.prev2 = samples[math.max(1, n - 1)] or prev2
                context.prev1 = samples[n] or prev1
            end
        elseif mode == "cubic" then
            local previous = (context and context.previous) or samples[1] or 0
            for i = 1, n do
                local xm1 = i > 1 and samples[i - 1] or previous
                local x0 = samples[i] or 0
                local x1 = samples[i + 1] or x0
                local x2 = samples[i + 2] or x1
                out[k] = x0
                out[k + 1] = clampPcm8((-xm1 + 9 * x0 + 9 * x1 - x2) / 16)
                k = k + 2
            end
            if context then context.previous = samples[n] or previous end
        else
            for i = 1, n do
                local a = samples[i] or 0
                local b = samples[i + 1] or a
                out[k] = a
                out[k + 1] = clampPcm8((a + b) * 0.5)
                k = k + 2
            end
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
            out[i] = clampPcm8(x + (y - x) * frac)
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
            local accepted = {}
            local tasks = {}
            for i = 1, #state.speakers do
                local entry = state.speakers[i]
                tasks[i] = function()
                    local ok, value = pcall(entry.object.playAudio, segment, state.volume)
                    accepted[i] = ok and value == true
                end
            end
            parallel.waitForAll(table.unpack(tasks))

            local allAccepted = true
            local acceptedNames = {}
            for i = 1, #state.speakers do
                if accepted[i] then acceptedNames[#acceptedNames + 1] = state.speakers[i].name
                else allAccepted = false end
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

local function stereoRouteAvailable()
    return state.leftSpeaker and state.rightSpeaker
        and state.leftSpeakerName and state.rightSpeakerName
        and state.leftSpeakerName ~= state.rightSpeakerName
end

local function stereoVolumes()
    local left, right = state.volume, state.volume
    if CONFIG.balance > 0 then left = left * (1 - CONFIG.balance)
    elseif CONFIG.balance < 0 then right = right * (1 + CONFIG.balance) end
    return left, right
end

local function tryStartStereoSegment(leftSegment, rightSegment, generation)
    local n = math.min(#leftSegment, #rightSegment)
    if n == 0 then return {} end

    while state.running and generation == state.generation do
        while state.paused and state.running and generation == state.generation do
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return false end
        end
        if not state.running or generation ~= state.generation then return false end
        if not stereoRouteAvailable() then return false end

        local leftVolume, rightVolume = stereoVolumes()
        local okL, acceptedL, okR, acceptedR
        parallel.waitForAll(
            function() okL, acceptedL = pcall(state.leftSpeaker.playAudio, leftSegment, leftVolume) end,
            function() okR, acceptedR = pcall(state.rightSpeaker.playAudio, rightSegment, rightVolume) end
        )

        if okL and acceptedL and okR and acceptedR then
            state.flight = {
                startedMs = nowMs(),
                length = n,
                interruptMs = nil,
                interruptReason = nil,
            }
            return { state.leftSpeakerName, state.rightSpeakerName }
        end

        -- If one side accepted before the other reported busy, stop both so
        -- the next retry begins on the same sample boundary.
        stopSpeakers()
        local timer = os.startTimer(0.04)
        while state.running and generation == state.generation do
            local ev, id = os.pullEventRaw()
            if ev == "timer" and id == timer then break end
            if ev == "ccmusic_wake" then break end
            if ev == "ccmusic_shutdown" then return false end
        end
    end
    return false
end

local playPcmBlock

local function playStereoPcmBlock(leftPcm, rightPcm, generation)
    local total = math.min(#leftPcm, #rightPcm)
    local offset = 1
    while offset <= total and state.running and generation == state.generation do
        while state.paused and state.running and generation == state.generation do
            local ev = os.pullEventRaw()
            if ev == "ccmusic_shutdown" then return false end
        end
        if generation ~= state.generation or not state.running then return false end

        if not stereoRouteAvailable() then
            -- Hot-unplug recovery: continue the remaining samples as mono on
            -- whatever speakers are still connected instead of restarting the song.
            local leftRemain = offset == 1 and leftPcm or sliceSamples(leftPcm, offset)
            local rightRemain = offset == 1 and rightPcm or sliceSamples(rightPcm, offset)
            local downmix = makeStereoMixer()(leftRemain, rightRemain)
            state.activeAudioMode = "MONO"
            state.audioPassthrough = false
            return playPcmBlock(downmix, generation)
        end

        local leftSegment = offset == 1 and leftPcm or sliceSamples(leftPcm, offset)
        local rightSegment = offset == 1 and rightPcm or sliceSamples(rightPcm, offset)
        local interruptVersion = state.audioInterrupt
        local waitingNames = tryStartStereoSegment(leftSegment, rightSegment, generation)
        if type(waitingNames) ~= "table" then return false end

        state.loading = false
        state.error = nil
        local waiting = {}
        for i = 1, #waitingNames do waiting[waitingNames[i]] = true end
        local naturalDone, interrupted = false, false

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
            local length = math.min(#leftSegment, #rightSegment)
            state.playedSamples = state.playedSamples + length
            state.flight = nil
            offset = total + 1
        elseif interrupted then
            local stopAt = f and (f.interruptMs or nowMs()) or nowMs()
            local consumed = f and clamp(math.floor((stopAt - f.startedMs) * 48), 0, f.length) or 0
            if consumed > 0 then
                state.playedSamples = state.playedSamples + consumed
                offset = offset + consumed
            end
            state.flight = nil
        else
            state.flight = nil
            return false
        end
    end
    return generation == state.generation and state.running
end

playPcmBlock = function(pcm, generation)
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

local function trackSources(track)
    if type(track.parts) == "table" and #track.parts > 0 then
        return track.parts
    end
    if track.url then
        return { { name = track.name, size = track.size, url = track.url } }
    end
    return {}
end

local function openAudioUrl(url)
    local lastErr
    for attempt = 1, 3 do
        if not state.running then return nil, "Stopped" end
        local h, err = httpGet(url, true)
        if h then return h end
        lastErr = err
        state.error = "Stream retry " .. attempt .. "/3: " .. tostring(err)
        waitSeconds(0.7 * attempt)
    end
    return nil, lastErr or "Could not open audio stream"
end

local function chunkBytesForRate(rate)
    -- speaker.playAudio accepts at most 128*1024 PCM samples. One DFPWM byte
    -- decodes to eight source samples. For 24 kHz tracks we double the sample
    -- count during resampling, so 8 KiB is the largest safe DFPWM chunk.
    -- Native 48 kHz tracks can use the full 16 KiB recommended by CC:Tweaked.
    if CONFIG.chunkBytes and CONFIG.chunkBytes > 0 then
        local maxBytes = rate == 24000 and 8192 or 16384
        return math.min(CONFIG.chunkBytes, maxBytes)
    end
    if rate == 24000 then return 8192 end
    if rate == 48000 then return 16384 end

    local ratio = 48000 / rate
    local maxBytes = math.floor((128 * 1024) / (8 * math.max(1, ratio)))
    return math.max(256, math.min(16384, maxBytes))
end

local function vizSliceBytesForRate(rate)
    -- 512 DFPWM bytes at 48 kHz = 4096 samples ~= 85 ms (~11.7 Hz).
    -- Scale at lower source rates so visual response stays around the same
    -- real-time cadence.
    local scaled = math.floor(CONFIG.vizSliceBytes * rate / 48000 + 0.5)
    return math.max(128, math.min(2048, scaled))
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
            local seekSeconds = tonumber(state.requestedSeek) or 0
            state.requestedSeek = nil
            state.playedSamples = math.floor(seekSeconds * 48000 + 0.5)
            state.flight = nil
            state.lyrics = {}
            state.sourceChannels = tonumber(track.channels) or 1
            state.sourceRate = tonumber(track.rate) or 0
            state.sourceFormat = tostring(track.format or "SQSH")
            state.activeAudioMode = "MONO"
            state.audioPassthrough = false
            state.streamPart = 0
            state.streamPartCount = 0
            stopSpeakers()

            local sources = trackSources(track)
            state.streamPartCount = #sources

            if #sources == 0 then
                state.loading = false
                state.error = "Track has no stream URL"
                waitSeconds(1.0)
                if generation == state.generation then
                    os.queueEvent("ccmusic_track_end", generation, true)
                end
            else
                local firstHeader = nil
                local totalAudioBytes = 0
                local seekRemainingBytes = nil
                local skippedAudioBytes = 0

                -- Decoder/resampler state deliberately lives across release
                -- parts. Oversized albums are just one continuous DFPWM stream
                -- split at safe GitHub/HTTP boundaries.
                local stereo = {
                    leftDecoder = dfpwm.make_decoder(),
                    rightDecoder = dfpwm.make_decoder(),
                    leftTail = makeDfpwmTailDecoder(384),
                    rightTail = makeDfpwmTailDecoder(384),
                    leftResample = {},
                    rightResample = {},
                    monoResample = {},
                    leftPassthrough = makeDfpwmPassthrough(),
                    rightPassthrough = makeDfpwmPassthrough(),
                    mix = makeStereoMixer(),
                }
                local mono = {
                    decoder = dfpwm.make_decoder(),
                    tail = makeDfpwmTailDecoder(384),
                    passthrough = makeDfpwmPassthrough(),
                    resample = {},
                }

                for sourceIndex = 1, #sources do
                    if not state.running or generation ~= state.generation or state.error then break end

                    local source = sources[sourceIndex]
                    state.streamPart = sourceIndex
                    if sourceIndex == 1 then state.loading = true end

                    local handle, openErr = openAudioUrl(source.url)
                    if not handle then
                        state.loading = false
                        state.error = "Stream failed: " .. tostring(openErr)
                        break
                    end

                    local okHeader, headerOrErr, headerErr = pcall(readSqshHeader, handle)
                    local header = okHeader and headerOrErr or nil
                    local parseErr = okHeader and headerErr or headerOrErr

                    if not header then
                        safeClose(handle)
                        state.loading = false
                        state.error = "SQSH error: " .. tostring(parseErr)
                        break
                    end

                    if not firstHeader then
                        firstHeader = header
                        track.rate = header.rate
                        track.channels = header.channels
                        track.format = header.format
                        track.lyricsBytes = header.lyricBytes

                        state.sourceChannels = header.channels
                        state.sourceRate = header.rate
                        state.sourceFormat = header.format
                        state.lyrics = parseLyrics(header.lyricsRaw)
                        seekRemainingBytes = math.max(0, math.floor(seekSeconds * header.rate / 8 + 0.5))
                    else
                        if header.rate ~= firstHeader.rate
                            or header.channels ~= firstHeader.channels
                            or header.format ~= firstHeader.format then
                            safeClose(handle)
                            state.error = "Segment format changed mid-track"
                            break
                        end
                    end

                    totalAudioBytes = totalAudioBytes + header.audioBytes
                    local remaining = header.audioBytes

                    -- Seek is performed on DFPWM byte boundaries. For SQSH2 we
                    -- align to a complete interleaved L/R block so the next
                    -- read still starts at a valid LEFT block boundary.
                    if seekRemainingBytes and seekRemainingBytes > 0 then
                        if seekRemainingBytes >= remaining then
                            seekRemainingBytes = seekRemainingBytes - remaining
                            skippedAudioBytes = skippedAudioBytes + remaining
                            remaining = 0
                        else
                            local skipBytes
                            if header.channels == 2 then
                                local block = header.blockBytes or CONFIG.stereoChunkBytes
                                skipBytes = math.floor(seekRemainingBytes / block) * block
                                if skipBytes > 0 then
                                    local discarded = readExact(handle, skipBytes * 2)
                                    if not discarded then
                                        state.error = "Seek failed while skipping SQSH2 data"
                                    end
                                end
                            else
                                skipBytes = math.floor(seekRemainingBytes / 256) * 256
                                if skipBytes > 0 then
                                    local discarded = readExact(handle, skipBytes)
                                    if not discarded then
                                        state.error = "Seek failed while skipping SQSH1 data"
                                    end
                                end
                            end
                            skipBytes = math.min(skipBytes or 0, remaining)
                            seekRemainingBytes = 0
                            skippedAudioBytes = skippedAudioBytes + skipBytes
                            remaining = remaining - skipBytes

                            if firstHeader and firstHeader.rate > 0 then
                                state.playedSamples = math.floor(skippedAudioBytes * 8 * 48000 / firstHeader.rate + 0.5)
                            end
                        end
                    end

                    state.loading = false

                    if remaining <= 0 then
                        -- Entire segment was before the seek target.
                    elseif header.channels == 2 then
                        while state.running and generation == state.generation and remaining > 0 do
                            while state.paused and state.running and generation == state.generation do
                                local ev = os.pullEventRaw()
                                if ev == "ccmusic_shutdown" then break end
                            end
                            if not state.running or generation ~= state.generation then break end

                            local want = math.min(header.blockBytes or CONFIG.stereoChunkBytes, remaining)
                            local leftChunk = readExact(handle, want)
                            local rightChunk = readExact(handle, want)
                            if not leftChunk or not rightChunk then
                                state.error = "Unexpected end of SQSH2 stream"
                                break
                            end
                            remaining = remaining - want

                            local sliceBytes = vizSliceBytesForRate(header.rate)
                            local blockPlaybackOk = true
                            for byteOffset = 1, #leftChunk, sliceBytes do
                                if not state.running or generation ~= state.generation then
                                    blockPlaybackOk = false
                                    break
                                end

                                local lastByte = math.min(#leftChunk, byteOffset + sliceBytes - 1)
                                local leftSlice = leftChunk:sub(byteOffset, lastByte)
                                local rightSlice = rightChunk:sub(byteOffset, lastByte)

                                local wantStereo = CONFIG.audioMode ~= "mono" and stereoRouteAvailable()
                                local directStereo = wantStereo and CONFIG.passthrough48k and header.rate == 48000
                                local decodedL, decodedR

                                if directStereo then
                                    decodedL = stereo.leftTail(leftSlice)
                                    decodedR = stereo.rightTail(rightSlice)
                                else
                                    local okL, valueL = pcall(stereo.leftDecoder, leftSlice)
                                    local okR, valueR = pcall(stereo.rightDecoder, rightSlice)
                                    if not okL or not okR or type(valueL) ~= "table" or type(valueR) ~= "table" then
                                        state.error = "Stereo DFPWM decode failed"
                                        blockPlaybackOk = false
                                        break
                                    end
                                    decodedL, decodedR = valueL, valueR
                                end

                                local analysisMono = stereo.mix(decodedL, decodedR)
                                analyzeStereoAudio(decodedL, decodedR, header.rate)

                                if wantStereo then
                                    local leftPcm, rightPcm
                                    if directStereo then
                                        leftPcm = stereo.leftPassthrough(leftSlice)
                                        rightPcm = stereo.rightPassthrough(rightSlice)
                                        state.audioPassthrough = true
                                    else
                                        leftPcm = resample48k(decodedL, header.rate, stereo.leftResample)
                                        rightPcm = resample48k(decodedR, header.rate, stereo.rightResample)
                                        state.audioPassthrough = false
                                    end

                                    state.activeAudioMode = "STEREO"
                                    if not playStereoPcmBlock(leftPcm, rightPcm, generation) then
                                        blockPlaybackOk = false
                                        break
                                    end
                                else
                                    state.activeAudioMode = "MONO"
                                    state.audioPassthrough = false
                                    local monoPcm = resample48k(analysisMono, header.rate, stereo.monoResample)
                                    if not playPcmBlock(monoPcm, generation) then
                                        blockPlaybackOk = false
                                        break
                                    end
                                end
                            end
                            if not blockPlaybackOk then break end
                        end
                    elseif header.channels == 1 then
                        while state.running and generation == state.generation and remaining > 0 do
                            while state.paused and state.running and generation == state.generation do
                                local ev = os.pullEventRaw()
                                if ev == "ccmusic_shutdown" then break end
                            end
                            if not state.running or generation ~= state.generation then break end

                            local want = math.min(chunkBytesForRate(header.rate), remaining)
                            local chunk = handle.read(want)
                            if not chunk or #chunk == 0 then
                                state.error = "Unexpected end of SQSH1 stream"
                                break
                            end
                            remaining = remaining - #chunk

                            local sliceBytes = vizSliceBytesForRate(header.rate)
                            local blockPlaybackOk = true
                            for byteOffset = 1, #chunk, sliceBytes do
                                if not state.running or generation ~= state.generation then
                                    blockPlaybackOk = false
                                    break
                                end

                                local monoSlice = chunk:sub(byteOffset, math.min(#chunk, byteOffset + sliceBytes - 1))
                                local directMono = CONFIG.passthrough48k and header.rate == 48000
                                local decoded

                                if directMono then
                                    decoded = mono.tail(monoSlice)
                                else
                                    local okDecode, value = pcall(mono.decoder, monoSlice)
                                    if not okDecode or type(value) ~= "table" then
                                        state.error = "DFPWM decode failed"
                                        blockPlaybackOk = false
                                        break
                                    end
                                    decoded = value
                                end

                                analyzeAudio(decoded, header.rate)

                                local pcm
                                if directMono then
                                    pcm = mono.passthrough(monoSlice)
                                    state.audioPassthrough = true
                                else
                                    pcm = resample48k(decoded, header.rate, mono.resample)
                                    state.audioPassthrough = false
                                end

                                state.activeAudioMode = "MONO"
                                if not playPcmBlock(pcm, generation) then
                                    blockPlaybackOk = false
                                    break
                                end
                            end
                            if not blockPlaybackOk then break end
                        end
                    end

                    safeClose(handle)
                    if remaining > 0 and not state.error and generation == state.generation then
                        state.error = "Audio segment ended early"
                        break
                    end
                end

                if firstHeader then
                    track.audioBytes = totalAudioBytes
                    if not track.duration or track.duration <= 0 then
                        track.duration = totalAudioBytes * 8 / firstHeader.rate
                    end
                end

                state.streamPart = 0

                if generation == state.generation and state.running then
                    if not state.error then
                        os.queueEvent("ccmusic_track_end", generation, false)
                    else
                        waitSeconds(1.0)
                        if generation == state.generation then
                            os.queueEvent("ccmusic_track_end", generation, true)
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
}) do
    BLIT[c] = colors.toBlit(c)
end

local function colorBlit(c) return BLIT[c] or colors.toBlit(c) end

local Canvas = {}
Canvas.__index = Canvas

function Canvas.new(w, h)
    local self = setmetatable({ w = w, h = h, rows = {} }, Canvas)
    local fg, bg = colorBlit(colors.white), colorBlit(colors.black)
    for y = 1, h do
        local row = { c = {}, f = {}, b = {} }
        for x = 1, w do row.c[x] = " "; row.f[x] = fg; row.b[x] = bg end
        self.rows[y] = row
    end
    return self
end

function Canvas:clear(fgColor, bgColor)
    local fg = colorBlit(fgColor or colors.white)
    local bg = colorBlit(bgColor or colors.black)
    for y = 1, self.h do
        local row = self.rows[y]
        for x = 1, self.w do
            row.c[x] = " "
            row.f[x] = fg
            row.b[x] = bg
        end
    end
end

function Canvas:cell(x, y, ch, fg, bg)
    x, y = math.floor(x), math.floor(y)
    if x < 1 or y < 1 or x > self.w or y > self.h then return end
    local row = self.rows[y]
    row.c[x] = ch or " "
    if fg then row.f[x] = colorBlit(fg) end
    if bg then row.b[x] = colorBlit(bg) end
end

function Canvas:text(x, y, text, fg, bg, maxLen)
    if y < 1 or y > self.h then return end
    text = asciiSafe(text)
    if maxLen and #text > maxLen then
        if maxLen >= 2 then text = text:sub(1, maxLen - 1) .. ">" else text = text:sub(1, maxLen) end
    end
    for i = 1, #text do self:cell(x + i - 1, y, text:sub(i, i), fg, bg) end
end

function Canvas:center(y, text, x1, x2, fg, bg)
    x1, x2 = x1 or 1, x2 or self.w
    text = asciiSafe(text)
    local room = math.max(0, x2 - x1 + 1)
    if #text > room then text = text:sub(1, room) end
    local x = x1 + math.floor((room - #text) / 2)
    self:text(x, y, text, fg, bg)
end

function Canvas:fill(x1, y1, x2, y2, bg, ch, fg)
    x1, x2 = math.max(1, math.floor(x1)), math.min(self.w, math.floor(x2))
    y1, y2 = math.max(1, math.floor(y1)), math.min(self.h, math.floor(y2))
    if x2 < x1 or y2 < y1 then return end
    ch = ch or " "
    for y = y1, y2 do
        for x = x1, x2 do self:cell(x, y, ch, fg or colors.white, bg) end
    end
end

function Canvas:hline(x1, x2, y, ch, fg, bg)
    for x = x1, x2 do self:cell(x, y, ch or "-", fg or colors.gray, bg or colors.black) end
end

function Canvas:vline(x, y1, y2, ch, fg, bg)
    for y = y1, y2 do self:cell(x, y, ch or "|", fg or colors.gray, bg or colors.black) end
end

local prevFrame = { w = 0, h = 0, text = {}, fg = {}, bg = {}, target = nil }
local canvasCache = nil

local function invalidateFrame()
    prevFrame.w, prevFrame.h, prevFrame.target = 0, 0, nil
    prevFrame.text, prevFrame.fg, prevFrame.bg = {}, {}, {}
end

local function flushCanvas(canvas, target)
    if not target then return end
    if state._frameInvalid or prevFrame.target ~= target or prevFrame.w ~= canvas.w or prevFrame.h ~= canvas.h then
        invalidateFrame()
        prevFrame.target = target
        prevFrame.w, prevFrame.h = canvas.w, canvas.h
        state._frameInvalid = false
        pcall(target.setBackgroundColor, colors.black)
        pcall(target.clear)
    end

    for y = 1, canvas.h do
        local row = canvas.rows[y]
        local t, f, b = table.concat(row.c), table.concat(row.f), table.concat(row.b)
        if t ~= prevFrame.text[y] or f ~= prevFrame.fg[y] or b ~= prevFrame.bg[y] then
            local ok = pcall(function()
                target.setCursorPos(1, y)
                target.blit(t, f, b)
            end)
            if not ok then return end
            prevFrame.text[y], prevFrame.fg[y], prevFrame.bg[y] = t, f, b
        end
    end
end

local function addHitbox(id, x1, y1, x2, y2, data)
    state.hitboxes[#state.hitboxes + 1] = {
        id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2, data = data,
    }
end

local RAINBOW = {
    colors.red, colors.orange, colors.yellow, colors.lime,
    colors.green, colors.cyan, colors.lightBlue, colors.blue,
    colors.purple, colors.magenta, colors.pink, colors.red,
    colors.orange, colors.yellow, colors.lime, colors.cyan,
}


local function drawVisualizer(c, x1, y1, x2, y2)
    if x2 - x1 < 20 or y2 - y1 < 9 then return end

    local cx = math.floor((x1 + x2) / 2)
    local cy = math.floor((y1 + y2) / 2)
    local bands = #state.bands

    if CONFIG.vizMode == "meter" then
        -- Traditional bottom-up equalizer. This uses more of the available
        -- vertical area and is especially readable from farther away.
        local width = x2 - x1 + 1
        local height = y2 - y1 + 1
        local slot = math.max(1, math.floor(width / bands))
        local barW = math.max(1, slot - 1)
        local maxH = math.max(2, height - 2)

        for b = 1, bands do
            local bx = x1 + (b - 1) * slot
            if bx > x2 then break end
            local v = clamp(state.bands[b] or 0, 0, 1)
            local h = math.floor(v * maxH + 0.5)
            local col = RAINBOW[b] or colors.white
            if h > 0 then
                c:fill(bx, y2 - h + 1, math.min(x2, bx + barW - 1), y2, col, " ", col)
            end

            local peak = clamp(state.bandPeaks[b] or 0, 0, 1)
            local py = y2 - math.floor(peak * maxH + 0.5)
            if py >= y1 and py < y2 - h + 1 then
                c:fill(bx, py, math.min(x2, bx + barW - 1), py, colors.white, " ", colors.white)
            end
        end

        c:center(y1, "METER", x1, x2, colors.gray, colors.black)
        return
    end

    if CONFIG.vizMode == "mirror" then
        -- True stereo mode: LEFT grows from the center toward the left and
        -- RIGHT grows toward the right. Each side is analyzed independently.
        local maxWidth = math.max(8, math.floor((x2 - x1 - 4) / 2))
        local maxHalf = math.max(1, math.floor((y2 - y1) * 0.42))
        local spacing = math.max(1, math.floor(maxWidth / bands))

        c:center(y1, "L   STEREO   R", x1, x2, colors.gray, colors.black)

        for b = 1, bands do
            local offset = math.min(maxWidth - 1, (b - 1) * spacing)
            local lx = cx - 2 - offset
            local rx = cx + 2 + offset
            if lx < x1 or rx > x2 then break end

            local lv = clamp(state.bandsL[b] or 0, 0, 1)
            local rv = clamp(state.bandsR[b] or 0, 0, 1)
            local lh = math.floor(lv * maxHalf + 0.5)
            local rh = math.floor(rv * maxHalf + 0.5)
            local col = RAINBOW[b] or colors.white

            if lh > 0 then c:fill(lx, cy - lh, lx, cy + lh, col, " ", col) end
            if rh > 0 then c:fill(rx, cy - rh, rx, cy + rh, col, " ", col) end
        end

        -- Center channel separator pulses gently with bass.
        local pulse = clamp((state.vizBass or 0) * 1.5, 0, 1)
        local centerHalf = 1 + math.floor(pulse * 3 + 0.5)
        c:vline(cx, cy - centerHalf, cy + centerHalf, "|", colors.white, colors.black)
        return
    end

    -- CLASSIC: the original ring/bar look, now with smoothing + peaks.
    local baseRx = math.max(5, math.floor((x2 - x1) * 0.36))
    local baseRy = math.max(3, math.floor((y2 - y1) * 0.40))
    local pulse = clamp((state.vizBass or 0) * 1.35 + (state.rms or 0) * 0.45, 0, 1)
    local rx = math.min(math.floor((x2 - x1) / 2) - 1, baseRx + math.floor(pulse * 3 + 0.5))
    local ry = math.min(math.floor((y2 - y1) / 2) - 1, baseRy + math.floor(pulse * 1.5 + 0.5))

    for deg = 0, 354, 6 do
        local a = deg * math.pi / 180
        local x = math.floor(cx + math.cos(a) * rx + 0.5)
        local y = math.floor(cy + math.sin(a) * ry + 0.5)
        c:cell(x, y, ".", colors.white, colors.black)
    end

    local barSpan = math.max(18, math.min(rx * 2 - 6, bands * 2))
    local startX = cx - math.floor(barSpan / 2)
    local maxHalf = math.max(1, ry - 2)

    for b = 1, bands do
        local x = startX + math.floor((b - 1) * (barSpan - 1) / math.max(1, bands - 1))
        local v = clamp(state.bands[b] or 0, 0, 1)
        local half = math.floor(v * maxHalf + 0.5)
        local col = RAINBOW[b] or colors.white
        if half > 0 then c:fill(x, cy - half, x, cy + half, col, " ", col) end

        local peak = clamp(state.bandPeaks[b] or 0, 0, 1)
        local peakHalf = math.floor(peak * maxHalf + 0.5)
        if peakHalf > half and peakHalf > 0 then
            c:cell(x, cy - peakHalf, ".", colors.white, colors.black)
            c:cell(x, cy + peakHalf, ".", colors.white, colors.black)
        end
    end

    c:cell(cx, cy - 1, " ", colors.white, colors.white)
    c:cell(cx, cy, " ", colors.white, colors.white)
    c:cell(cx, cy + 1, " ", colors.white, colors.white)
    c:cell(cx - 1, cy, " ", colors.white, colors.white)
    c:cell(cx + 1, cy, " ", colors.white, colors.white)

    if pulse > 0.68 then
        c:cell(cx - 2, cy, ".", colors.lightGray, colors.black)
        c:cell(cx + 2, cy, ".", colors.lightGray, colors.black)
        c:cell(cx, cy - 2, ".", colors.lightGray, colors.black)
        c:cell(cx, cy + 2, ".", colors.lightGray, colors.black)
    end
end

local function filteredLibrary()
    if not state.searchMode and not state.favoritesOnly then return nil end
    local q = state.searchMode and state.search:lower() or ""
    local out = {}
    for i = 1, #state.library do
        local tr = state.library[i]
        local matchesSearch = (q == "") or tr.title:lower():find(q, 1, true)
        local matchesFavorite = (not state.favoritesOnly) or isFavorite(tr)
        if matchesSearch and matchesFavorite then out[#out + 1] = i end
    end
    return out
end

local function nextQueueTrackIndex(rowOffset)
    if #state.order == 0 then return nil end
    local p = state.orderPos + rowOffset
    while p > #state.order do p = p - #state.order end
    if p < 1 then p = 1 end
    return state.order[p]
end

local function drawQueue(c, x1, y1, x2, y2)
    if x2 <= x1 then return end
    local width = x2 - x1 + 1
    local searchResults = filteredLibrary()

    local heading
    if state.searchMode then
        heading = "SEARCH: " .. (state.search ~= "" and state.search or "type...")
    elseif state.favoritesOnly then
        heading = "FAVORITES  " .. tostring(favoriteCount())
    else
        heading = "UP NEXT  " .. tostring(#state.library) .. " TRACKS"
        if #state.manualQueue > 0 then heading = heading .. "  Q:" .. tostring(#state.manualQueue) end
    end

    c:text(x1 + 1, y1, heading, state.searchMode and colors.yellow or (state.favoritesOnly and colors.pink or colors.white), colors.black, math.max(1, width - 9))
    c:text(x2 - 6, y1, "[U][D]", colors.lightGray, colors.black)
    addHitbox("scroll_up", x2 - 6, y1, x2 - 4, y1)
    addHitbox("scroll_down", x2 - 2, y1, x2, y1)

    local firstY = y1 + 1
    local rows = math.max(0, y2 - firstY + 1)
    local maxScroll

    if searchResults then
        maxScroll = math.max(0, #searchResults - rows)
    else
        maxScroll = math.max(0, #state.manualQueue + #state.order - 1 - rows)
    end
    state.queueScroll = clamp(state.queueScroll, 0, maxScroll)

    for r = 0, rows - 1 do
        local itemIndex, ordinal, queued
        if searchResults then
            local p = state.queueScroll + r + 1
            itemIndex = searchResults[p]
            ordinal = p
        else
            local off = state.queueScroll + r + 1
            if off <= #state.manualQueue then
                itemIndex = state.manualQueue[off]
                ordinal = off
                queued = true
            else
                local orderOff = off - #state.manualQueue
                itemIndex = nextQueueTrackIndex(orderOff)
                ordinal = orderOff
                if orderOff > #state.order - 1 then itemIndex = nil end
            end
        end

        local y = firstY + r
        if itemIndex and state.library[itemIndex] then
            local tr = state.library[itemIndex]
            local time = fmtTime(tr.duration)
            local fav = isFavorite(tr)
            local marker = queued and "Q" or ((not searchResults and not state.favoritesOnly and r == 0 and #state.manualQueue == 0) and ">" or " ")
            local star = fav and "*" or " "
            local prefix = string.format("%s%s%2d ", marker, star, ordinal)
            local titleRoom = width - #prefix - #time - 2
            if titleRoom < 3 then titleRoom = 3 end
            local title = tr.title
            if #title > titleRoom then title = title:sub(1, titleRoom - 1) .. ">" end

            local selected = itemIndex == state.currentIndex
            local bg = selected and colors.gray or colors.black
            local fg
            if selected then fg = colors.white
            elseif queued then fg = colors.orange
            elseif fav then fg = colors.pink
            elseif marker == ">" then fg = colors.lightBlue
            else fg = colors.lightGray end

            c:fill(x1, y, x2, y, bg)
            c:text(x1, y, prefix .. title, fg, bg, width - #time - 1)
            c:text(x2 - #time + 1, y, time, selected and colors.white or fg, bg)
            addHitbox("track", x1, y, x2, y, itemIndex)
        end
    end
end

local function drawButton(c, x, y, text, active, id)
    local bg = active and colors.lightBlue or colors.gray
    local fg = active and colors.black or colors.white
    local label = " " .. text .. " "
    c:text(x, y, label, fg, bg)
    addHitbox(id, x, y, x + #label - 1, y)
    return x + #label + 1
end

local function drawControls(c, x1, y, x2)
    -- Transport row: deliberately large/frequent actions.
    local x = x1
    x = drawButton(c, x, y, "|<", false, "prev")
    if x + 5 <= x2 then x = drawButton(c, x, y, "-10", false, "back10") end
    x = drawButton(c, x, y, state.paused and "PLAY" or "PAUSE", state.paused, "pause")
    if x + 5 <= x2 then x = drawButton(c, x, y, "+10", false, "forward10") end
    x = drawButton(c, x, y, ">|", false, "next")

    -- Mode row: settings which are touched less frequently.
    x = x1
    if x + 10 <= x2 then x = drawButton(c, x, y + 1, "SHUFFLE", state.shuffle, "shuffle") end
    if x + 9 <= x2 then x = drawButton(c, x, y + 1, "LOOP:" .. state.loopMode:upper(), state.loopMode ~= "off", "loop") end
    if x + 12 <= x2 then x = drawButton(c, x, y + 1, "AUDIO:" .. CONFIG.audioMode:upper(), CONFIG.audioMode ~= "mono", "audio_mode") end
    if x + 13 <= x2 then x = drawButton(c, x, y + 1, "VIZ:" .. CONFIG.vizMode:upper(), true, "viz_mode") end
    if x + 6 <= x2 then x = drawButton(c, x, y + 1, isFavorite(state.currentIndex) and "FAV*" or "FAV", isFavorite(state.currentIndex), "favorite") end
    if x + 7 <= x2 then x = drawButton(c, x, y + 1, "FAVS", state.favoritesOnly, "favorites_only") end
    if x + 5 <= x2 then x = drawButton(c, x, y + 1, "Q+", state.queueAddMode, "queue_add") end
    if x + 6 <= x2 then x = drawButton(c, x, y + 1, "SET", state.settingsOpen, "settings") end
end

local function drawProgress(c, x1, y, x2)
    local cur = currentPositionSeconds()
    local total = state.current and state.current.duration or 0
    local left = fmtTime(cur)
    local right = fmtTime(total)
    c:text(x1, y, left, colors.lightGray, colors.black)
    c:text(x2 - #right + 1, y, right, colors.lightGray, colors.black)

    local barX1 = x1 + #left + 2
    local barX2 = x2 - #right - 2
    if barX2 >= barX1 then
        local width = barX2 - barX1 + 1
        local ratio = total > 0 and clamp(cur / total, 0, 1) or 0
        local playhead = math.floor((width - 1) * ratio + 0.5)

        for i = 0, width - 1 do
            local col = i <= playhead and colors.lightBlue or colors.gray
            c:cell(barX1 + i, y, " ", col, col)
        end
        c:cell(barX1 + playhead, y, " ", colors.white, colors.white)
        addHitbox("seek", barX1, y, barX2, y, { x1 = barX1, x2 = barX2, duration = total })
    end
end

local function drawVolume(c, x1, y, x2)
    local label = "VOL"
    c:text(x1, y, label, colors.lightGray, colors.black)
    local pct = string.format("%3d%%", math.floor(state.volume * 100 + 0.5))
    local barX1 = x1 + #label + 2
    local barX2 = x2 - #pct - 2
    c:text(x2 - #pct + 1, y, pct, colors.white, colors.black)
    if barX2 >= barX1 then
        local width = barX2 - barX1 + 1
        local filled = math.floor(width * state.volume + 0.5)
        for i = 0, width - 1 do
            local col = i < filled and colors.lime or colors.gray
            c:cell(barX1 + i, y, " ", col, col)
        end
        addHitbox("volume", barX1, y, barX2, y, { x1 = barX1, x2 = barX2 })
    end
end

local function drawSettingsPanel(c, x1, y1, x2, y2)
    c:fill(x1, y1, x2, y2, colors.black)
    c:center(y1, "SETTINGS", x1, x2, colors.yellow, colors.black)

    local row = y1 + 2
    local function option(label, value, id, active)
        if row > y2 - 1 then return end
        c:text(x1 + 3, row, label, colors.lightGray, colors.black)
        local text = " " .. tostring(value) .. " "
        local bx = math.max(x1 + 24, x2 - #text - 2)
        c:text(bx, row, text, active == false and colors.lightGray or colors.black, active == false and colors.gray or colors.lightBlue)
        addHitbox(id, x1 + 1, row, x2 - 1, row)
        row = row + 2
    end

    option("VISUALIZER", CONFIG.vizMode:upper(), "viz_mode", true)
    option("AUDIO ROUTING", CONFIG.audioMode:upper(), "audio_mode", true)
    option("SHUFFLE", state.shuffle and "ON" or "OFF", "shuffle", state.shuffle)
    option("LOOP", state.loopMode:upper(), "loop", state.loopMode ~= "off")
    option("RESUME AFTER RESTART", CONFIG.resumeEnabled and "ON" or "OFF", "resume_toggle", CONFIG.resumeEnabled)
    option("FAVORITES VIEW", state.favoritesOnly and "ON" or "OFF", "favorites_only", state.favoritesOnly)

    if row <= y2 then
        c:center(y2, "[ CLOSE SETTINGS ]", x1, x2, colors.white, colors.gray)
        addHitbox("settings", x1, y2, x2, y2)
    end
end

local function activeRemoteCount()
    local now = nowMs()
    local n = 0
    for id, seen in pairs(state.remotes) do
        if now - seen < 10000 then n = n + 1 else state.remotes[id] = nil end
    end
    return n
end

local function renderFrame()
    advanceVisualizer()
    local target = state.target or term.current()
    local ok, w, h = pcall(target.getSize)
    if not ok or not w or not h then return end
    if w < 20 or h < 8 then return end

    local c
    if canvasCache and canvasCache.w == w and canvasCache.h == h then
        c = canvasCache
        c:clear(colors.white, colors.black)
    else
        c = Canvas.new(w, h)
        canvasCache = c
    end
    state.hitboxes = {}

    -- Header
    c:fill(1, 1, w, 1, colors.blue)
    c:text(2, 1, "CC-MUSIC", colors.white, colors.blue)
    local mode = state.shuffle and "SHUFFLE" or "ORDER"
    c:text(math.min(w, 12), 1, mode, state.shuffle and colors.lime or colors.lightGray, colors.blue)

    local rateBadge = state.sourceRate > 0 and (tostring(math.floor(state.sourceRate / 1000 + 0.5)) .. "k") or "--"
    local audioBadge = state.activeAudioMode .. " " .. rateBadge
    if state.audioPassthrough then
        audioBadge = audioBadge .. " DIRECT"
    elseif state.sourceRate == 24000 then
        audioBadge = audioBadge .. " " .. CONFIG.legacyResampler:upper()
    end
    local statusRight = string.format("%s  %d remote  %d spk", audioBadge, activeRemoteCount(), #state.speakers)
    c:text(math.max(1, w - #statusRight), 1, statusRight, colors.white, colors.blue)
    if state.current then
        local rightLimit = math.max(20, w - #statusRight - 2)
        local titleWidth = math.max(8, rightLimit - 26 + 1)
        c:center(1, marqueeText(state.current.title, titleWidth), 26, rightLimit, colors.yellow, colors.blue)
    else
        c:center(1, "CC-Music " .. VERSION, 20, w - #statusRight - 2, colors.yellow, colors.blue)
    end

    local mainW
    if w >= 70 then mainW = math.floor(w * 0.67) else mainW = w end
    local dividerX = mainW + 1
    if mainW < w then c:vline(dividerX, 2, h, "|", colors.gray, colors.black) end

    local leftX1, leftX2 = 2, mainW - 1
    if mainW >= w then leftX2 = w - 1 end

    -- Main visual area
    local controlsY = math.max(6, h - 2)
    local progressY = controlsY - 1
    local lyricY = math.max(5, progressY - 2)
    local statusY = lyricY + 1
    if state.settingsOpen then
        drawSettingsPanel(c, leftX1, 3, leftX2, math.max(8, lyricY - 1))
    else
        drawVisualizer(c, leftX1, 3, leftX2, math.max(5, lyricY - 1))
    end

    if state.current and not state.settingsOpen then
        c:center(lyricY, lyricAt(currentPositionSeconds()), leftX1, leftX2, colors.lightGray, colors.black)
    elseif state.settingsOpen then
        c:center(lyricY, "Touch an option above", leftX1, leftX2, colors.gray, colors.black)
    elseif state.stopped then
        c:center(lyricY, "End of playlist", leftX1, leftX2, colors.lightGray, colors.black)
    else
        c:center(lyricY, "Loading library...", leftX1, leftX2, colors.lightGray, colors.black)
    end

    local playbackStatus
    local playbackColor = colors.white
    if state.error then playbackStatus = "ERROR: " .. state.error; playbackColor = colors.red
    elseif state.loading then playbackStatus = "BUFFERING"; playbackColor = colors.yellow
    elseif state.paused then playbackStatus = "PAUSED"; playbackColor = colors.yellow
    elseif state.queueAddMode then playbackStatus = "ADD NEXT: TAP A TRACK"; playbackColor = colors.orange
    elseif state.current then
        playbackStatus = "PLAYING | " .. state.sourceFormat .. " | " .. state.activeAudioMode
        if state.streamPartCount and state.streamPartCount > 1 and state.streamPart > 0 then
            playbackStatus = playbackStatus .. " | PART " .. state.streamPart .. "/" .. state.streamPartCount
        end
        playbackColor = colors.lime
    else playbackStatus = "STOPPED"; playbackColor = colors.lightGray end
    c:center(statusY, playbackStatus, leftX1, leftX2, playbackColor, colors.black)

    drawProgress(c, leftX1, progressY, leftX2)
    drawControls(c, leftX1, controlsY, leftX2)
    drawVolume(c, leftX1, h, leftX2)

    if h > 10 then
        local subline
        local subColor = colors.gray
        if state.warning then
            subline = state.warning
            subColor = colors.orange
        elseif state.libraryCached then
            subline = "cached library"
            subColor = colors.orange
        elseif state.current then
            subline = string.format("%s / %s  |  %s  |  %s", fmtTime(currentPositionSeconds()), fmtTime(state.current.duration), state.sourceFormat, CONFIG.vizMode:upper())
            subColor = colors.lightGray
        end
        if subline then c:center(2, subline, leftX1, leftX2, subColor, colors.black) end
    end

    if mainW < w then drawQueue(c, dividerX + 1, 2, w, h) end

    flushCanvas(c, target)
end

local function renderLoop()
    local delay = 1 / CONFIG.uiFps
    while state.running do
        local ok, err = pcall(renderFrame)
        if not ok then state.lastUiError = tostring(err) end
        local timer = os.startTimer(delay)
        while state.running do
            local ev, id = os.pullEventRaw()
            if ev == "timer" and id == timer then break end
            if ev == "monitor_resize" or ev == "term_resize" then break end
            if ev == "ccmusic_shutdown" then return end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Input + Rednet
-- ---------------------------------------------------------------------------

local function hitTest(x, y)
    for i = #state.hitboxes, 1, -1 do
        local b = state.hitboxes[i]
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b end
    end
    return nil
end

local function scrollQueue(delta)
    state.queueScroll = math.max(0, state.queueScroll + delta)
end

local function handleAction(id, data, touchX)
    if id == "prev" then choosePrevious()
    elseif id == "back10" then seekRelative(-10)
    elseif id == "pause" then togglePause()
    elseif id == "forward10" then seekRelative(10)
    elseif id == "next" then chooseNext(true)
    elseif id == "shuffle" then toggleShuffle()
    elseif id == "loop" then cycleLoop()
    elseif id == "audio_mode" then cycleAudioMode()
    elseif id == "viz_mode" then cycleVizMode()
    elseif id == "favorite" then toggleFavorite()
    elseif id == "favorites_only" then toggleFavoritesOnly()
    elseif id == "queue_add" then toggleQueueAddMode()
    elseif id == "settings" then toggleSettings()
    elseif id == "resume_toggle" then toggleResume()
    elseif id == "scroll_up" then scrollQueue(-1)
    elseif id == "scroll_down" then scrollQueue(1)
    elseif id == "track" then
        if state.queueAddMode then
            if queueTrackNext(data) then state.queueAddMode = false end
        else
            requestTrack(data, true)
        end
    elseif id == "seek" and type(data) == "table" then
        local width = math.max(1, data.x2 - data.x1)
        local ratio = clamp((touchX - data.x1) / width, 0, 1)
        requestSeek((data.duration or 0) * ratio)
    elseif id == "volume" and type(data) == "table" then
        local width = math.max(1, data.x2 - data.x1)
        local ratio = clamp((touchX - data.x1) / width, 0, 1)
        setVolume(ratio)
    end
end

local function broadcastStatus(targetId)
    if not rednet or not rednet.send then return end
    local msg = {
        op = "status",
        version = VERSION,
        title = state.current and state.current.title or nil,
        playing = state.current ~= nil and not state.paused and not state.loading,
        paused = state.paused,
        loading = state.loading,
        position = currentPositionSeconds(),
        duration = state.current and state.current.duration or 0,
        volume = state.volume,
        shuffle = state.shuffle,
        loop = state.loopMode,
        speakers = #state.speakers,
        audio_mode = state.activeAudioMode,
        routing_mode = CONFIG.audioMode,
        viz_mode = CONFIG.vizMode,
        queue_count = #state.manualQueue,
        favorite = isFavorite(state.currentIndex),
        favorites_count = favoriteCount(),
        resume_enabled = CONFIG.resumeEnabled,
        source_rate = state.sourceRate,
        source_channels = state.sourceChannels,
        source_format = state.sourceFormat,
        passthrough = state.audioPassthrough,
        stereo_ready = stereoRouteAvailable(),
        error = state.error,
    }
    if targetId then
        pcall(rednet.send, targetId, msg, PROTOCOL)
    else
        pcall(rednet.broadcast, msg, PROTOCOL)
    end
end

local function handleRemote(sender, msg)
    if type(msg) ~= "table" then return end
    state.remotes[sender] = nowMs()
    local op = msg.op
    if op == "discover" or op == "status" or op == "ping" then
        broadcastStatus(sender)
    elseif op == "toggle" then togglePause(); broadcastStatus(sender)
    elseif op == "pause" then setPaused(true); broadcastStatus(sender)
    elseif op == "play" then setPaused(false); broadcastStatus(sender)
    elseif op == "next" then chooseNext(true); broadcastStatus(sender)
    elseif op == "prev" then choosePrevious(); broadcastStatus(sender)
    elseif op == "shuffle" then toggleShuffle(); broadcastStatus(sender)
    elseif op == "loop" then cycleLoop(); broadcastStatus(sender)
    elseif op == "audio_mode" then cycleAudioMode(); broadcastStatus(sender)
    elseif op == "viz_mode" then cycleVizMode(); broadcastStatus(sender)
    elseif op == "favorite" then toggleFavorite(); broadcastStatus(sender)
    elseif op == "favorites_only" then toggleFavoritesOnly(); broadcastStatus(sender)
    elseif op == "resume_toggle" then toggleResume(); broadcastStatus(sender)
    elseif op == "seek_rel" then seekRelative(tonumber(msg.value) or 0); broadcastStatus(sender)
    elseif op == "seek" then requestSeek(tonumber(msg.value) or 0); broadcastStatus(sender)
    elseif op == "volume" then setVolume(tonumber(msg.value) or state.volume); broadcastStatus(sender)
    elseif op == "play_index" then requestTrack(tonumber(msg.index), true); broadcastStatus(sender) end
end

local function eventLoop()
    while state.running do
        local ev, a, b, c = os.pullEventRaw()

        if ev == "terminate" then
            state.running = false
            _G.__ccmusic_running = false
            state.generation = state.generation + 1
            stopSpeakers()
            os.queueEvent("ccmusic_shutdown")
            return

        elseif ev == "monitor_touch" then
            if not state.monitorName or a == state.monitorName then
                local hit = hitTest(b, c)
                if hit then handleAction(hit.id, hit.data, b) end
            end

        elseif ev == "mouse_click" and not state.targetIsMonitor then
            local hit = hitTest(b, c)
            if hit then handleAction(hit.id, hit.data, b) end

        elseif ev == "mouse_scroll" and not state.targetIsMonitor then
            scrollQueue(a > 0 and 1 or -1)

        elseif ev == "key" then
            if a == keys.space then togglePause()
            elseif a == keys.left then choosePrevious()
            elseif a == keys.right then chooseNext(true)
            elseif a == keys.up then setVolume(state.volume + 0.05)
            elseif a == keys.down then setVolume(state.volume - 0.05)
            elseif a == keys.s and not state.searchMode then toggleShuffle()
            elseif a == keys.l and not state.searchMode then cycleLoop()
            elseif a == keys.a and not state.searchMode then cycleAudioMode()
            elseif a == keys.v and not state.searchMode then cycleVizMode()
            elseif a == keys.j and not state.searchMode then seekRelative(-10)
            elseif a == keys.k and not state.searchMode then seekRelative(10)
            elseif a == keys.b and not state.searchMode then toggleFavorite()
            elseif a == keys.g and not state.searchMode then toggleFavoritesOnly()
            elseif a == keys.n and not state.searchMode then toggleQueueAddMode()
            elseif a == keys.m and not state.searchMode then toggleSettings()
            elseif a == keys.f and not state.searchMode then state.searchMode = true; state.search = ""; state.queueScroll = 0
            elseif a == keys.escape and state.settingsOpen then state.settingsOpen = false
            elseif a == keys.escape and state.searchMode then state.searchMode = false; state.search = ""; state.queueScroll = 0
            elseif a == keys.enter and state.searchMode then
                local results = filteredLibrary()
                if results and results[1] then requestTrack(results[1], true) end
                state.searchMode = false; state.search = ""; state.queueScroll = 0
            elseif a == keys.backspace and state.searchMode then
                state.search = state.search:sub(1, math.max(0, #state.search - 1)); state.queueScroll = 0
            end

        elseif ev == "char" and state.searchMode then
            local ch = asciiSafe(a)
            if ch:match("[%w%s%-%._@&,'+]" ) then state.search = state.search .. ch; state.queueScroll = 0 end

        elseif ev == "peripheral" or ev == "peripheral_detach" then
            local oldSpeakerCount = #state.speakers
            refreshPeripherals()
            invalidateFrame()
            if oldSpeakerCount ~= #state.speakers then interruptAudio("speaker_change") end

        elseif ev == "monitor_resize" or ev == "term_resize" then
            invalidateFrame()

        elseif ev == "rednet_message" then
            local sender, message, protocol = a, b, c
            if protocol == PROTOCOL then handleRemote(sender, message) end

        elseif ev == "ccmusic_track_end" then
            local generation = a
            if generation == state.generation then chooseNext(false) end
        end
    end
end

local function heartbeatLoop()
    while state.running do
        saveResume(false)
        if rednet and rednet.isOpen and rednet.isOpen() then broadcastStatus(nil) end
        local timer = os.startTimer(2)
        while state.running do
            local ev, id = os.pullEventRaw()
            if ev == "timer" and id == timer then break end
            if ev == "ccmusic_shutdown" then return end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

math.randomseed((os.epoch and os.epoch("utc") or os.clock() * 100000) + (os.getComputerID and os.getComputerID() or 0))

local tracks, libraryErr, cached = loadLibrary()
state.library = tracks
state.favorites = loadFavorites()
state.libraryCached = cached
state.warning = libraryErr
state.loading = false

if #tracks == 0 then
    state.error = libraryErr or "No .sqsh tracks found"
else
    rebuildOrder(false)

    local start = nil
    local resumePosition = 0
    if CONFIG.resumeEnabled then
        local resumeName = tostring(getSetting("ccmusic.resume_track", "") or "")
        resumePosition = tonumber(getSetting("ccmusic.resume_position", 0)) or 0
        if resumeName ~= "" then
            for i = 1, #state.library do
                if state.library[i].name == resumeName then start = i; break end
            end
        end
    end

    if not start then
        start = preferredStartIndex()
        resumePosition = 0
    end

    if start then
        if state.shuffle then
            local p = findOrderPos(start)
            if p then state.order[1], state.order[p] = state.order[p], state.order[1] end
            state.orderPos = 1
        else
            state.orderPos = findOrderPos(start) or 1
        end
        requestTrack(start, false)
        if CONFIG.resumeEnabled and resumePosition > 1 then
            state.requestedSeek = math.min(resumePosition, math.max(0, (state.library[start].duration or 0) - 0.25))
            state.playedSamples = math.floor((state.requestedSeek or 0) * 48000 + 0.5)
        end
    end
end

local ok, err = pcall(function()
    parallel.waitForAll(audioLoop, eventLoop, renderLoop, heartbeatLoop)
end)

saveResume(true)
state.running = false
_G.__ccmusic_running = false
stopSpeakers()
if state.target then
    pcall(state.target.setBackgroundColor, colors.black)
    pcall(state.target.setTextColor, colors.white)
    pcall(state.target.clear)
    pcall(state.target.setCursorPos, 1, 1)
end

if not ok and tostring(err) ~= "Terminated" then
    printError("CC-Music crashed: " .. tostring(err))
end