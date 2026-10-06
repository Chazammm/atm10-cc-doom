-- Optimised 32vid player for CC:Tweaked / ATM10.
-- Targets combined-stream ANS 32vid files and prioritises smooth video/audio.
-- Based on MCJack123/sanjuuni's 32vid-player-mini format/decoder.

local bit_band, bit_lshift, bit_rshift = bit32.band, bit32.lshift, bit32.rshift
local math_frexp = math.frexp
local function log2(n) local _, r = math_frexp(n) return r - 1 end

local path, endMode, skipArg, baseArg, totalArg = ...
if not path then error("Usage: 32vid-player-fast <file-or-url> [keep] [skipFrames] [baseFrame] [totalFrames]") end
local skipFrames = math.max(0, tonumber(skipArg) or 0)
local explicitBaseFrame = tonumber(baseArg)
local totalFrames = tonumber(totalArg) or tonumber(settings.get("musicvideo.total_frames"))
local resumeKey = settings.get("musicvideo.resume_key") or "agartha.v3.resume_frame"

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

-- Embedded CC:Tweaked-compatible DFPWM decoder.
-- Do not depend on require(): this file is also executed as a loaded chunk by
-- the V3 controller, where shell package globals are not guaranteed to exist.
local function makeDfpwmDecoder()
    local floor, byte = math.floor, string.byte
    local PREC = 10
    local PREC_POW = 2 ^ PREC
    local PREC_POW_HALF = 2 ^ (PREC - 1)
    local STRENGTH_MIN = 2 ^ (PREC - 8 + 1)

    local charge, strength, predictorPreviousBit = 0, 0, false
    local lowPassCharge = 0
    local previousCharge, previousBit = 0, false

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
        local output, outputN = {}, 0
        for i = 1, #input do
            local inputByte = byte(input, i)
            for _ = 1, 8 do
                local currentBit = bit_band(inputByte, 1) ~= 0
                local currentCharge = predictor(currentBit)

                local antijerk = currentCharge
                if currentBit ~= previousBit then
                    antijerk = floor((currentCharge + previousCharge + 1) / 2)
                end

                previousCharge, previousBit = currentCharge, currentBit
                lowPassCharge = lowPassCharge + floor(((antijerk - lowPassCharge) * 140 + 0x80) / 256)

                outputN = outputN + 1
                output[outputN] = lowPassCharge
                inputByte = bit_rshift(inputByte, 1)
            end
        end
        return output
    end
end

local normalDecoder = makeDfpwmDecoder()
local leftNormalDecoder = makeDfpwmDecoder()
local rightNormalDecoder = makeDfpwmDecoder()
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
local touchEnabled = settings.get("musicvideo.touch_controls")
if touchEnabled == nil then touchEnabled = true end
local adaptiveEnabled = settings.get("musicvideo.adaptive_fps")
if adaptiveEnabled == nil then adaptiveEnabled = true end
local fpsOverride = tonumber(settings.get("musicvideo.fps_override"))
local muteAudio = settings.get("musicvideo.mute") == true

-- A playlist can keep one media clock across multiple HTTP files. This makes
-- part boundaries behave as one continuous movie instead of re-syncing A/V.
local sessionActive = settings.get("musicvideo.session_active") == true
local sessionStart = sessionActive and tonumber(settings.get("musicvideo.session_start")) or nil
local sessionFrame = sessionActive and (tonumber(settings.get("musicvideo.session_frame")) or 0) or 0
local frameOffset = explicitBaseFrame or sessionFrame

local stats = {
    frames = 0,
    dropped = 0,
    rows = 0,
    backpressure = 0,
    adaptiveSkipped = 0,
    adaptiveBursts = 0,
    decodeMs = 0,
    renderMs = 0,
    started = os.epoch("utc"),
}

local function openSource(source)
    if type(source) == "table" and type(source.read) == "function" then return source end
    if type(source) ~= "string" then error("Invalid 32vid source") end
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
local videoCompression = bit_band(flags, 3)
local directCells = videoCompression == 3 and bit32.btest(flags, 0x4000)
if videoCompression ~= 1 and not directCells then
    file.close()
    error("Fast player requires ANS video or CCV4 direct-cell video")
end
local _, nframes, ctype = ("<IIB"):unpack(file.read(9))
if ctype ~= 0x0C then file.close() error("Fast player requires a combined stream") end

-- V3 marks combined files which actually contain AudioLeft/AudioRight chunks
-- with a private high flag. Without this flag, configured stereo speakers must
-- not disable ordinary mono V1/V2 audio.
local hasStereoAudio = bit32.btest(flags, 0x8000)

-- Early full-V4 media was written with the custom-video + stereo private flags
-- (0xC003) but accidentally omitted the standard DFPWM-audio bit (0x0004).
-- Those release assets are otherwise valid and already uploaded. Treat this
-- specific direct-cell/stereo format as DFPWM so we do not need to re-upload
-- ~2.1 GiB of media just to flip one header bit.
local audioIsDfpwm = bit32.btest(flags, 0x0004) or (directCells and hasStereoAudio)

if bit32.btest(flags, 0x20) then file.close() error("Fast player expects one connected monitor surface, not 32vid multi-monitor mode") end

local tw, th = term.getSize()

-- Legacy media may have been encoded for a different monitor shape. Do not
-- fall back to the old mini player in that case: it blindly starts at 1,1,
-- which is what caused the grey strip and one-sided crop on the 164x67 wall.
-- Instead crop oversized media symmetrically and centre undersized media.
local visibleWidth = math.min(width, tw)
local visibleHeight = math.min(height, th)
local cropX = math.floor((width - visibleWidth) / 2)
local cropY = math.floor((height - visibleHeight) / 2)
local xOffset = math.floor((tw - visibleWidth) / 2) + 1
local yOffset = math.floor((th - visibleHeight) / 2) + 1
local leftPad = xOffset - 1
local rightPad = tw - (xOffset + visibleWidth - 1)
local topPad = yOffset - 1
local bottomPad = th - (yOffset + visibleHeight - 1)
local leftSpaces = leftPad > 0 and string.rep(" ", leftPad) or nil
local rightSpaces = rightPad > 0 and string.rep(" ", rightPad) or nil
local fullSpaces = string.rep(" ", tw)

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

-- Keep independent PCM tables per channel. Reusing one table for L and R means
-- decoding the right block mutates the samples which the left speaker still uses.
local function makePassthroughDecoder()
    local buffer, oldLength = {}, 0
    return function(data)
        local n, outAt = #data * 8, 1
        for i = 1, #data do
            table.move(bitSamples[data:byte(i)], 1, 8, outAt, buffer)
            outAt = outAt + 8
        end
        if oldLength > n then
            for i = n + 1, oldLength do buffer[i] = nil end
        end
        oldLength = n
        return buffer
    end
end

local function makePCMDecoder()
    local buffer, oldLength = {}, 0
    return function(data)
        local n = #data
        for i = 1, n do buffer[i] = data:byte(i) - 128 end
        if oldLength > n then
            for i = n + 1, oldLength do buffer[i] = nil end
        end
        oldLength = n
        return buffer
    end
end

local monoPassthrough, leftPassthrough, rightPassthrough =
    makePassthroughDecoder(), makePassthroughDecoder(), makePassthroughDecoder()
local monoPCM, leftPCM, rightPCM = makePCMDecoder(), makePCMDecoder(), makePCMDecoder()

local mediaStart = sessionStart
local currentGlobalFrame = frameOffset + skipFrames
local controlAction, controlTarget
local paused, pauseStarted = false, nil
local osdVisible, osdUntil = false, 0
local osdDark, osdLight = 0, 15
local forceRedraw = false

local function stopSpeakers()
    local seen = {}
    local function stopOne(s, name)
        local key = name or tostring(s)
        if s and not seen[key] then
            seen[key] = true
            pcall(s.stop)
        end
    end
    stopOne(speaker, speakerName)
    stopOne(leftSpeaker, leftName)
    stopOne(rightSpeaker, rightName)
end

local function formatTime(frame)
    local seconds = math.max(0, math.floor((frame or 0) / fps + 0.5))
    return ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function fitLine(s)
    if #s > tw then return s:sub(1, tw) end
    return s .. string.rep(" ", tw - #s)
end

local function drawOSD()
    if not osdVisible and not paused then return end
    local total = totalFrames or math.max(currentGlobalFrame + 1, 1)
    local ratio = math.max(0, math.min(1, currentGlobalFrame / math.max(1, total - 1)))
    local barWidth = math.max(10, tw - 73)
    local filled = math.floor(barWidth * ratio + 0.5)
    local bar = string.rep("=", filled) .. string.rep("-", barWidth - filled)
    local mode = stereoActive and hasStereoAudio and "ST" or "MO"
    local line1 = fitLine(("%s/%s [%s] %s %3d%% drop:%d adapt:%d"):format(
        formatTime(currentGlobalFrame), formatTime(total), bar, mode,
        math.floor(volume * 100 + 0.5), stats.dropped, stats.adaptiveSkipped))
    local playLabel = paused and "PLAY" or "PAUSE"
    local labels = {"<10s", playLabel, "+10s", "VOL-", "VOL+", "INFO", "STOP"}
    local pieces = {}
    for i = 1, 7 do
        local first = math.floor((i - 1) * tw / 7) + 1
        local last = math.floor(i * tw / 7)
        local sw = last - first + 1
        local label = "[" .. labels[i] .. "]"
        local lp = math.max(0, math.floor((sw - #label) / 2))
        local rp = math.max(0, sw - lp - #label)
        pieces[i] = string.rep(" ", lp) .. label:sub(1, sw) .. string.rep(" ", rp)
    end
    local line2 = fitLine(table.concat(pieces))
    local fg, bg = blitColors[osdLight], blitColors[osdDark]
    term.setCursorPos(1, math.max(1, th - 1))
    term.blit(line1, string.rep(fg, tw), string.rep(bg, tw))
    term.setCursorPos(1, th)
    term.blit(line2, string.rep(fg, tw), string.rep(bg, tw))
end

local function showOSD()
    osdVisible = true
    osdUntil = os.epoch("utc") + 5000
    drawOSD()
end

local function hideOSD()
    if osdVisible and not paused then
        osdVisible = false
        forceRedraw = true
    end
end

local function requestSeek(deltaFrames)
    local target = math.max(0, currentGlobalFrame + deltaFrames)
    if totalFrames then target = math.min(totalFrames - 1, target) end
    controlAction, controlTarget = "seek", target
    stopSpeakers()
end

local function togglePause()
    local now = os.epoch("utc")
    if paused then
        paused = false
        if pauseStarted and mediaStart then
            mediaStart = mediaStart + now - pauseStarted
            if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
        end
        pauseStarted = nil
        osdUntil = now + 5000
        forceRedraw = true
    else
        paused = true
        pauseStarted = now
        stopSpeakers()
        osdVisible = true
        drawOSD()
    end
end

local function handleTouch(_, x, y)
    if not touchEnabled then return end
    if not x or not y then return end
    if not osdVisible and not paused then showOSD() return end
    osdUntil = os.epoch("utc") + 5000
    if y < th then
        if not paused then hideOSD() end
        return
    end
    local section = math.floor((x - 1) * 7 / math.max(1, tw)) + 1
    if section == 1 then requestSeek(-10 * fps)
    elseif section == 2 then togglePause()
    elseif section == 3 then requestSeek(10 * fps)
    elseif section == 4 then
        volume = math.max(0, volume - 0.1)
        leftVolume, rightVolume = volume, volume
        settings.set("musicvideo.volume", volume)
        showOSD()
    elseif section == 5 then
        volume = math.min(3, volume + 0.1)
        leftVolume, rightVolume = volume, volume
        settings.set("musicvideo.volume", volume)
        showOSD()
    elseif section == 6 then
        showStats = not showStats
        showOSD()
    else
        controlAction = "stop"
        stopSpeakers()
    end
end

local function waitPaused()
    while paused and not controlAction do
        drawOSD()
        local ev, a, b, d = os.pullEvent()
        if ev == "monitor_touch" then handleTouch(a, b, d) end
    end
end

local function playSamplesOn(target, targetName, samples, targetVolume, allowControls)
    if not target or not samples or #samples == 0 or muteAudio then return end
    while not controlAction and not target.playAudio(samples, targetVolume) do
        stats.backpressure = stats.backpressure + 1
        local ready = false
        while not ready and not controlAction do
            local ev, a, b, d = os.pullEvent()
            if ev == "speaker_audio_empty" and (not targetName or a == targetName) then
                ready = true
            elseif ev == "monitor_touch" and allowControls then
                handleTouch(a, b, d)
            end
            if paused then waitPaused() end
        end
    end
end

local function playStereo(leftSamples, rightSamples)
    if not stereoActive or muteAudio then return end
    parallel.waitForAll(
        function() playSamplesOn(leftSpeaker, leftName, leftSamples, leftVolume, true) end,
        function() playSamplesOn(rightSpeaker, rightName, rightSamples, rightVolume, false) end
    )
end

local function decodeAudio(audio, decoder, passthrough, pcm)
    if not audioIsDfpwm then
        return pcm(audio)
    elseif audioMode == "passthrough" then
        return passthrough(audio)
    else
        return decoder(audio)
    end
end

local function waitUntilFrame(globalFrame)
    while not controlAction do
        if paused then waitPaused() end
        if controlAction then return false end
        local deadline = (mediaStart or os.epoch("utc")) + globalFrame * frameMs
        local now = os.epoch("utc")
        if osdVisible and not paused and now >= osdUntil then hideOSD() end
        local remaining = deadline - now
        if remaining <= 0 then return true end
        local wake = remaining
        if osdVisible and not paused then wake = math.min(wake, math.max(1, osdUntil - now)) end
        local timer = os.startTimer(wake / 1000)
        while true do
            local ev, a, b, d = os.pullEvent()
            if ev == "timer" and a == timer then break
            elseif ev == "monitor_touch" then handleTouch(a, b, d) end
            if controlAction then return false end
            if paused then break end
        end
    end
    return false
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

    if directCells then
        -- CCV4 direct-cell frame:
        --   48 bytes RGB palette
        --   cellCount bytes 5-bit semigraphics character masks
        --   cellCount bytes packed bg<<4 | fg
        -- This is intentionally trivial to decode: the expensive optimisation
        -- happened offline against the original RGB pixels.
        local expected = 48 + cellCount * 2
        if #payload ~= expected then
            error(("Invalid CCV4 frame: expected %d bytes, got %d"):format(expected, #payload))
        end
        local palette, screen, fg, bg = {}, {}, {}, {}
        local p = 1
        for i = 0, 15 do
            palette[i] = {payload:byte(p), payload:byte(p + 1), payload:byte(p + 2)}
            p = p + 3
        end
        for i = 1, cellCount do
            screen[i] = payload:byte(p)
            p = p + 1
        end
        for i = 1, cellCount do
            local packed = payload:byte(p)
            p = p + 1
            fg[i] = bit_band(packed, 15)
            bg[i] = bit_rshift(packed, 4)
        end
        stats.decodeMs = stats.decodeMs + (os.epoch("utc") - t0)
        return screen, fg, bg, palette
    end

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
    if forceRedraw then
        previousText, previousFg, previousBg = {}, {}, {}
        forceRedraw = false
    end

    -- Palette changes recolour already-present monitor cells, so unchanged rows
    -- do not need to be re-blitted just because RGB palette values changed.
    -- At the same time find the darkest current palette slot for letterbox/
    -- padding cells. A terminal "black" cell is only an index: if that palette
    -- index is later changed to grey, untouched padding turns grey too.
    local darkestIndex, darkestValue = 0, math.huge
    local lightestIndex, lightestValue = 15, -1
    for i = 0, 15 do
        local p = palette[i]
        local old = previousPalette[i]
        if not old or old[1] ~= p[1] or old[2] ~= p[2] or old[3] ~= p[3] then
            term.setPaletteColor(2 ^ i, p[1] / 255, p[2] / 255, p[3] / 255)
            previousPalette[i] = p
        end
        -- Weighted luma is a better "blackest" test than RGB sum.
        local luma = p[1] * 2126 + p[2] * 7152 + p[3] * 722
        if luma < darkestValue then
            darkestValue = luma
            darkestIndex = i
        end
        if luma > lightestValue then
            lightestValue = luma
            lightestIndex = i
        end
    end
    osdDark, osdLight = darkestIndex, lightestIndex

    -- Repaint all out-of-video cells after the palette update. This fixes the
    -- grey/right strip seen when old 143x81 media is shown on the 164x67 wall.
    if leftPad > 0 or rightPad > 0 or topPad > 0 or bottomPad > 0 then
        term.setBackgroundColor(2 ^ darkestIndex)
        if topPad > 0 then
            for yy = 1, topPad do
                term.setCursorPos(1, yy)
                term.write(fullSpaces)
            end
        end
        if bottomPad > 0 then
            for yy = th - bottomPad + 1, th do
                term.setCursorPos(1, yy)
                term.write(fullSpaces)
            end
        end
        if leftPad > 0 or rightPad > 0 then
            for yy = yOffset, yOffset + visibleHeight - 1 do
                if leftSpaces then
                    term.setCursorPos(1, yy)
                    term.write(leftSpaces)
                end
                if rightSpaces then
                    term.setCursorPos(xOffset + visibleWidth, yy)
                    term.write(rightSpaces)
                end
            end
        end
    end

    for outY = 0, visibleHeight - 1 do
        local sourceY = cropY + outY
        local base = sourceY * width + cropX
        for x = 1, visibleWidth do
            local index = base + x
            rowText[x] = glyph[screen[index]]
            rowFg[x] = blitColors[fg[index]]
            rowBg[x] = blitColors[bg[index]]
        end
        local text = table.concat(rowText, "", 1, visibleWidth)
        local fgs = table.concat(rowFg, "", 1, visibleWidth)
        local bgs = table.concat(rowBg, "", 1, visibleWidth)
        local yy = outY + 1

        if not diffRows or previousText[yy] ~= text or previousFg[yy] ~= fgs or previousBg[yy] ~= bgs then
            term.setCursorPos(xOffset, yOffset + outY)
            term.blit(text, fgs, bgs)
            previousText[yy], previousFg[yy], previousBg[yy] = text, fgs, bgs
            stats.rows = stats.rows + 1
        end
    end

    if osdVisible or paused then drawOSD() end
    stats.renderMs = stats.renderMs + (os.epoch("utc") - r0)
end

if endMode ~= "keep" then
    term.setBackgroundColor(colors.black)
    term.clear()
end

local videoFrame = 0
local subtitles = {}
local pendingLeft, pendingRight
local pendingLeftFrame, pendingRightFrame
local lateScore, adaptiveUntil = 0, -1
local lastResumeSave = frameOffset + skipFrames

local function maybeSaveResume(globalFrame, force)
    if not totalFrames then return end
    if force or globalFrame - lastResumeSave >= 600 then
        settings.set(resumeKey, math.max(0, math.min(totalFrames - 1, globalFrame)))
        settings.save()
        lastResumeSave = globalFrame
    end
end

for _ = 1, nframes do
    if controlAction then break end
    local header = file.read(5)
    if not header or #header < 5 then break end
    local size, frameType = ("<IB"):unpack(header)
    local skipping = videoFrame < skipFrames

    if frameType == 1 then
        local audio = file.read(size)
        if not skipping and speaker and not muteAudio and (not hasStereoAudio or not stereoActive) then
            local samples = decodeAudio(audio, normalDecoder, monoPassthrough, monoPCM)
            if stereoActive and not hasStereoAudio then
                -- Legacy mono mirrored to both speakers in the same scheduler slice.
                parallel.waitForAll(
                    function() playSamplesOn(leftSpeaker, leftName, samples, leftVolume) end,
                    function() playSamplesOn(rightSpeaker, rightName, samples, rightVolume) end
                )
            else
                playSamplesOn(speaker, speakerName, samples, volume)
            end
            if not mediaStart then
                mediaStart = os.epoch("utc")
                if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
            end
        end

    elseif frameType == 2 then
        local audio = file.read(size)
        if not skipping and hasStereoAudio and stereoActive and not muteAudio then
            pendingLeft = decodeAudio(audio, leftNormalDecoder, leftPassthrough, leftPCM)
            pendingLeftFrame = videoFrame
        end

    elseif frameType == 3 then
        local audio = file.read(size)
        if not skipping and hasStereoAudio and stereoActive and not muteAudio then
            pendingRight = decodeAudio(audio, rightNormalDecoder, rightPassthrough, rightPCM)
            pendingRightFrame = videoFrame
            if pendingLeft and pendingLeftFrame == pendingRightFrame then
                playStereo(pendingLeft, pendingRight)
                pendingLeft, pendingRight = nil, nil
                if not mediaStart then
                    mediaStart = os.epoch("utc")
                    if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
                end
            end
        end

    elseif frameType == 0 then
        local globalFrame = frameOffset + videoFrame
        currentGlobalFrame = globalFrame

        if videoFrame < skipFrames then
            file.read(size)
            videoFrame = videoFrame + 1
        else
            if not mediaStart then
                mediaStart = os.epoch("utc") - globalFrame * frameMs
                if sessionActive then settings.set("musicvideo.session_start", mediaStart) end
            end

            local now = os.epoch("utc")
            local deadline = mediaStart + globalFrame * frameMs
            local lateness = now - deadline
            if lateness > frameMs * 0.65 then lateScore = lateScore + 2
            else lateScore = math.max(0, lateScore - 0.25) end

            if adaptiveEnabled and fps >= 18 and lateScore >= 4 and globalFrame >= adaptiveUntil then
                adaptiveUntil = globalFrame + math.floor(fps * 2)
                lateScore = 0
                stats.adaptiveBursts = stats.adaptiveBursts + 1
            end

            if globalFrame < adaptiveUntil and globalFrame % 2 == 1 then
                file.read(size)
                stats.adaptiveSkipped = stats.adaptiveSkipped + 1
            elseif dropLate and videoFrame > skipFrames and lateness > frameMs * dropFactor then
                file.read(size)
                stats.dropped = stats.dropped + 1
            else
                local payload = file.read(size)
                local screen, fg, bg, palette = decodeFrame(payload)
                if dropLate and videoFrame > skipFrames and os.epoch("utc") - deadline > frameMs * dropFactor then
                    stats.dropped = stats.dropped + 1
                elseif waitUntilFrame(globalFrame) and not controlAction then
                    drawFrame(screen, fg, bg, palette)
                    stats.frames = stats.frames + 1
                end
            end

            videoFrame = videoFrame + 1
            currentGlobalFrame = frameOffset + videoFrame
            maybeSaveResume(currentGlobalFrame, false)
        end

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

if controlAction or endMode ~= "keep" then stopSpeakers() end

if sessionActive then
    settings.set("musicvideo.session_frame", frameOffset + videoFrame)
end
maybeSaveResume(currentGlobalFrame, controlAction ~= nil)
settings.set("musicvideo.volume", volume)
settings.set("musicvideo.left_volume", volume)
settings.set("musicvideo.right_volume", volume)
settings.save()

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
    print(("video: %d shown, %d late-drop, %d adaptive-skip"):format(stats.frames, stats.dropped, stats.adaptiveSkipped))
    print(("adaptive bursts: %d | rows: %d | speaker waits: %d"):format(stats.adaptiveBursts, stats.rows, stats.backpressure))
    print(("decode %.1f ms/frame | render %.1f ms/frame | elapsed %.1fs"):format(
        stats.decodeMs / math.max(1, stats.frames), stats.renderMs / math.max(1, stats.frames), elapsed / 1000))
    term.redirect(old)
end

return {
    control = controlAction,
    target = controlTarget,
    current_frame = currentGlobalFrame,
    video_frames_consumed = videoFrame,
    stats = stats,
}
