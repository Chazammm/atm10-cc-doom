-- Optimised 32vid player for CC:Tweaked / ATM10.
-- Targets combined-stream ANS 32vid files and prioritises smooth video/audio.
-- Based on MCJack123/sanjuuni's 32vid-player-mini format/decoder.

local bit_band, bit_lshift, bit_rshift = bit32.band, bit32.lshift, bit32.rshift
local math_frexp = math.frexp
local function log2(n) local _, r = math_frexp(n) return r - 1 end

local path, endMode = ...
if not path then error("Usage: 32vid-player-fast <file-or-url> [keep]") end

local function wrapSpeaker(name)
    if type(name) ~= "string" then return nil end
    local ok, wrapped = pcall(peripheral.wrap, name)
    if not ok or not wrapped then return nil end
    local types = { peripheral.getType(name) }
    for _, t in ipairs(types) do
        if t == "speaker" then return wrapped end
    end
    return nil
end

local speaker = peripheral.find("speaker")
local speakerName = speaker and peripheral.getName(speaker) or nil

-- V3 can contain optional stereo audio chunks:
--   type 1 = mono fallback
--   type 2 = left channel
--   type 3 = right channel
-- Stereo is enabled only after running /stereosetup.lua, so old media and
-- installations with one speaker keep behaving exactly as before.
local leftName = settings.get("musicvideo.left_speaker")
local rightName = settings.get("musicvideo.right_speaker")
local leftSpeaker = wrapSpeaker(leftName)
local rightSpeaker = wrapSpeaker(rightName)
local stereoActive = leftSpeaker and rightSpeaker and leftName ~= rightName

local dfpwm = require("cc.audio.dfpwm")
local normalDecoder = dfpwm.make_decoder()
local leftNormalDecoder = dfpwm.make_decoder()
local rightNormalDecoder = dfpwm.make_decoder()
local audioMode = settings.get("musicvideo.audio_mode") or "passthrough"
local volume = tonumber(settings.get("musicvideo.volume")) or 1.0
local leftVolume = tonumber(settings.get("musicvideo.left_volume")) or volume
local rightVolume = tonumber(settings.get("musicvideo.right_volume")) or volume
local dropLate = settings.get("musicvideo.drop_late_frames")
if dropLate == nil then dropLate = true end
local dropFactor = tonumber(settings.get("musicvideo.drop_factor")) or 1.0
local diffRows = settings.get("musicvideo.diff_rows")
if diffRows == nil then diffRows = true end
local showStats = settings.get("musicvideo.stats") == true
local fpsOverride = tonumber(settings.get("musicvideo.fps_override"))
local muteAudio = settings.get("musicvideo.mute") == true

-- A playlist can keep one media clock across multiple HTTP files. This makes
-- part boundaries behave as one continuous movie instead of re-syncing A/V.
local sessionActive = settings.get("musicvideo.session_active") == true
local sessionStart = sessionActive and tonumber(settings.get("musicvideo.session_start")) or nil
local frameOffset = sessionActive and (tonumber(settings.get("musicvideo.session_frame")) or 0) or 0

local stats = {
    frames = 0,
    dropped = 0,
    rows = 0,
    backpressure = 0,
    decodeMs = 0,
    renderMs = 0,
    started = os.epoch("utc"),
}

local function openSource(source)
    if source:match("^https?://") then
        local h, err = http.get(source, nil, true)
        if not h then error(err or ("Could not open " .. source)) end
        return h
    end
    local h = fs.open(shell.resolve(source), "rb")
    if not h then error("Could not open " .. source) end
    return h
end

local file = openSource(path)
if file.read(4) ~= "32VD" then file.close() error("Not a 32vid file") end

local width, height, fps, nstreams, flags = ("<HHBBH"):unpack(file.read(8))
if nstreams ~= 1 then file.close() error("Fast player requires combined-stream 32vid") end
if bit_band(flags, 3) ~= 1 then file.close() error("Fast player currently requires ANS video compression") end
local _, nframes, ctype = ("<IIB"):unpack(file.read(9))
if ctype ~= 0x0C then file.close() error("Fast player requires a combined stream") end
if bit32.btest(flags, 0x20) then file.close() error("Fast player expects one connected monitor surface, not 32vid multi-monitor mode") end

local tw, th = term.getSize()
if width > tw or height > th then
    file.close()
    error(("Video is %dx%d cells, terminal is only %dx%d"):format(width, height, tw, th))
end

if fpsOverride and fpsOverride > 0 then fps = fpsOverride end

local cellCount = width * height
local frameMs = 1000 / fps
local blitColors = {[0]="0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
local glyph = {}
for i = 0, 31 do glyph[i] = string.char(128 + i) end

-- DFPWM passthrough trick:
-- CC:Tweaked re-encodes playAudio PCM to DFPWM server-side. Feeding -128 for a
-- zero bit and +127 for a one bit makes that encoder reproduce the original
-- DFPWM bitstream exactly, avoiding a Lua decode + server re-encode cycle.
local bitSamples = {}
for b = 0, 255 do
    local t = {}
    for j = 0, 7 do
        t[j + 1] = bit_band(bit_rshift(b, j), 1) ~= 0 and 127 or -128
    end
    bitSamples[b] = t
end
local audioBuffer = {}
local audioBufferLength = 0

local function passthroughDecode(data)
    local n = #data * 8
    local outAt = 1
    for i = 1, #data do
        table.move(bitSamples[data:byte(i)], 1, 8, outAt, audioBuffer)
        outAt = outAt + 8
    end
    if audioBufferLength > n then
        for i = n + 1, audioBufferLength do audioBuffer[i] = nil end
    end
    audioBufferLength = n
    return audioBuffer
end

local function pcmDecode(data)
    local n = #data
    for i = 1, n do audioBuffer[i] = data:byte(i) - 128 end
    if audioBufferLength > n then
        for i = n + 1, audioBufferLength do audioBuffer[i] = nil end
    end
    audioBufferLength = n
    return audioBuffer
end

local function playSamplesOn(target, targetName, samples, targetVolume)
    if not target or not samples or #samples == 0 then return end
    while not target.playAudio(samples, targetVolume) do
        stats.backpressure = stats.backpressure + 1
        repeat
            local _, name = os.pullEvent("speaker_audio_empty")
        until not targetName or name == targetName
    end
end

local function decodeAudio(audio, decoder)
    if bit_band(flags, 12) == 0 then
        return pcmDecode(audio)
    elseif audioMode == "passthrough" then
        return passthroughDecode(audio)
    else
        return decoder(audio)
    end
end

local function waitUntil(deadline)
    local remaining = deadline - os.epoch("utc")
    if remaining <= 0 then return end
    local timer = os.startTimer(remaining / 1000)
    while true do
        local event, id = os.pullEvent()
        if event == "timer" and id == timer then return end
    end
end

local function byteReader(data)
    local p = 1
    return function()
        local b = data:byte(p)
        if not b then error("Corrupt/truncated ANS frame") end
        p = p + 1
        return b
    end
end

local function readDict(nextByte, size)
    local retval = {}
    for i = 0, size - 1, 2 do
        local b = nextByte()
        retval[i] = bit_rshift(b, 4)
        retval[i + 1] = bit_band(b, 15)
    end
    return retval
end

local function makeANSReader(nextByte, isColor)
    local R = nextByte()
    local L = 2 ^ R
    local dictSize = isColor and 24 or 32
    local Ls = readDict(nextByte, dictSize)

    if R == 0 then
        local constant = nextByte()
        return function(nsym)
            local out = {}
            for i = 1, nsym do out[i] = constant end
            return out
        end
    end

    local total = 0
    for i = 0, dictSize - 1 do
        local v = Ls[i]
        v = v == 0 and 0 or 2 ^ (v - 1)
        Ls[i] = v
        total = total + v
    end
    assert(total == L, "Invalid ANS dictionary")

    local decodingTable = {R = R}
    local x, step, nextState, symbol = 0, 0.625 * L + 3, {}, {}
    for i = 0, dictSize - 1 do
        nextState[i] = Ls[i]
        for _ = 1, Ls[i] do
            while symbol[x] do x = (x + 1) % L end
            symbol[x] = i
            x = (x + step) % L
        end
    end
    for state = 0, L - 1 do
        local s = symbol[state]
        local n = R - log2(nextState[s])
        local entry = {s = s, n = n}
        entry.X = bit_lshift(nextState[s], n) - L
        decodingTable[state] = entry
        nextState[s] = nextState[s] + 1
    end

    local partial, bits = 0, 0
    local function readBits(n)
        if n == 0 then return 0 end
        while bits < n do
            partial = bit_lshift(partial, 8) + nextByte()
            bits = bits + 8
        end
        local value = bit_band(bit_rshift(partial, bits - n), 2 ^ n - 1)
        bits = bits - n
        return value
    end

    local X = readBits(R)
    return function(nsym)
        local out, i, last = {}, 1, 0
        while i <= nsym do
            local t = decodingTable[X]
            if isColor and t.s >= 16 then
                local count = 2 ^ (t.s - 15)
                for n = 0, count - 1 do out[i + n] = last end
                i = i + count
            else
                out[i] = t.s
                last = t.s
                i = i + 1
            end
            X = t.X + readBits(t.n)
        end
        return out
    end
end

local previousText, previousFg, previousBg = {}, {}, {}
local previousPalette = {}
local rowText, rowFg, rowBg = {}, {}, {}

local function decodeFrame(payload)
    local t0 = os.epoch("utc")
    local nextByte = byteReader(payload)

    local readScreen = makeANSReader(nextByte, false)
    local screen = readScreen(cellCount)
    local readColors = makeANSReader(nextByte, true)
    -- Sanjuuni's ANS color stream decodes background first, then foreground.
    local bg = readColors(cellCount)
    local fg = readColors(cellCount)

    local palette = {}
    for i = 0, 15 do
        palette[i] = {nextByte(), nextByte(), nextByte()}
    end
    stats.decodeMs = stats.decodeMs + (os.epoch("utc") - t0)
    return screen, fg, bg, palette
end

local function drawFrame(screen, fg, bg, palette)
    local r0 = os.epoch("utc")

    -- Palette changes recolour already-present monitor cells, so unchanged rows
    -- do not need to be re-blitted just because RGB palette values changed.
    for i = 0, 15 do
        local p = palette[i]
        local old = previousPalette[i]
        if not old or old[1] ~= p[1] or old[2] ~= p[2] or old[3] ~= p[3] then
            term.setPaletteColor(2 ^ i, p[1] / 255, p[2] / 255, p[3] / 255)
            previousPalette[i] = p
        end
    end

    for y = 0, height - 1 do
        local base = y * width
        for x = 1, width do
            local index = base + x
            rowText[x] = glyph[screen[index]]
            rowFg[x] = blitColors[fg[index]]
            rowBg[x] = blitColors[bg[index]]
        end
        local text = table.concat(rowText, "", 1, width)
        local fgs = table.concat(rowFg, "", 1, width)
        local bgs = table.concat(rowBg, "", 1, width)
        local yy = y + 1

        if not diffRows or previousText[yy] ~= text or previousFg[yy] ~= fgs or previousBg[yy] ~= bgs then
            term.setCursorPos(1, yy)
            term.blit(text, fgs, bgs)
            previousText[yy], previousFg[yy], previousBg[yy] = text, fgs, bgs
            stats.rows = stats.rows + 1
        end
    end

    stats.renderMs = stats.renderMs + (os.epoch("utc") - r0)
end

term.setBackgroundColor(colors.black)
term.clear()

local mediaStart = sessionStart
local videoFrame = 0
local subtitles = {}

for _ = 1, nframes do
    local header = file.read(5)
    if not header or #header < 5 then break end
    local size, frameType = ("<IB"):unpack(header)

    if frameType == 1 then
        -- Standard mono audio. V3 keeps this as a fallback when stereo has not
        -- been configured, so the file still works with one ordinary speaker.
        local audio = file.read(size)
        if speaker and not muteAudio and not stereoActive then
            local samples = decodeAudio(audio, normalDecoder)
            playSamplesOn(speaker, speakerName, samples, volume)
            if not mediaStart then
                mediaStart = os.epoch("utc")
                if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
            end
        end

    elseif frameType == 2 then
        -- V3 left-channel DFPWM chunk.
        local audio = file.read(size)
        if stereoActive and not muteAudio then
            local samples = decodeAudio(audio, leftNormalDecoder)
            playSamplesOn(leftSpeaker, leftName, samples, leftVolume)
            if not mediaStart then
                mediaStart = os.epoch("utc")
                if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
            end
        end

    elseif frameType == 3 then
        -- V3 right-channel DFPWM chunk.
        local audio = file.read(size)
        if stereoActive and not muteAudio then
            local samples = decodeAudio(audio, rightNormalDecoder)
            playSamplesOn(rightSpeaker, rightName, samples, rightVolume)
            if not mediaStart then
                mediaStart = os.epoch("utc")
                if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
            end
        end

    elseif frameType == 0 then
        local deadline = (mediaStart or os.epoch("utc")) + (frameOffset + videoFrame) * frameMs
        if not mediaStart then
            mediaStart = deadline
            if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
        end
        local now = os.epoch("utc")

        if dropLate and videoFrame > 0 and now - deadline > frameMs * dropFactor then
            file.read(size) -- consume compressed frame without decoding it
            stats.dropped = stats.dropped + 1
        else
            local payload = file.read(size)
            -- Decode ahead of the presentation deadline. This uses otherwise-idle time
            -- and avoids starting an expensive ANS decode at the exact frame deadline.
            local screen, fg, bg, palette = decodeFrame(payload)
            local afterDecode = os.epoch("utc")
            if dropLate and videoFrame > 0 and afterDecode - deadline > frameMs * dropFactor then
                stats.dropped = stats.dropped + 1
            else
                waitUntil(deadline)
                drawFrame(screen, fg, bg, palette)
                stats.frames = stats.frames + 1
            end
        end
        videoFrame = videoFrame + 1

    elseif frameType == 8 then
        -- Consume subtitles for compatibility. The current Agartha files do not use them.
        local data = file.read(size)
        subtitles[#subtitles + 1] = data
    else
        -- Unknown combined-stream event: skip it rather than desynchronising the file.
        file.read(size)
    end
end

file.close()

if sessionActive then
    settings.set("musicvideo.session_frame", frameOffset + videoFrame)
end

if endMode ~= "keep" then
    for i = 0, 15 do term.setPaletteColor(2 ^ i, term.nativePaletteColor(2 ^ i)) end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clear()
end

if showStats then
    local native = term.native()
    local old = term.redirect(native)
    local elapsed = math.max(1, os.epoch("utc") - stats.started)
    print(("video: %d shown, %d dropped (%.1f%%)"):format(
        stats.frames, stats.dropped, 100 * stats.dropped / math.max(1, stats.frames + stats.dropped)))
    print(("rows blitted: %d | speaker waits: %d"):format(stats.rows, stats.backpressure))
    print(("decode %.1f ms/frame | render %.1f ms/frame"):format(
        stats.decodeMs / math.max(1, stats.frames), stats.renderMs / math.max(1, stats.frames)))
    print(("elapsed %.1fs"):format(elapsed / 1000))
    term.redirect(old)
end
