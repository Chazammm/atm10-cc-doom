-- Agartha V3.1 controller: seamless part prefetch, seeking/resume and touch OSD.
local base, startMode = ...
if not base then error("Usage: agartha-v3-player <base-url> [start|resume]") end
if base:sub(-1) ~= "/" then base = base .. "/" end

local index = dofile("/video-lib/v3-index.lua")
local fast = assert(loadfile("/video-lib/32vid-player-fast.lua"))
local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found.") end
local speaker = peripheral.find("speaker")
if not speaker then error("No speaker found.") end

monitor.setTextScale(0.5)
local w, h = monitor.getSize()
if w ~= 164 or h ~= 67 then error(("V3 requires 164x67 cells, got %dx%d"):format(w,h)) end

local function urlFor(part)
    return base .. "agartha-v3-part" .. ("%02d"):format(part) .. ".32vid"
end

local function locate(frame)
    frame = math.max(0, math.min(index.total_frames - 1, math.floor(frame)))
    for i = #index.frames, 1, -1 do
        if frame >= index.starts[i] then return i, frame - index.starts[i] end
    end
    return 1, frame
end

local function requestHandle(url)
    local ok, err = http.request({url = url, binary = true, redirect = true})
    if not ok then return nil, err end
    while true do
        local ev, u, a, b = os.pullEvent()
        if ev == "http_success" then
            return a
        elseif ev == "http_failure" then
            if type(b) == "table" and b.close then pcall(b.close) end
            return nil, tostring(a)
        end
    end
end

local function closeHandle(h)
    if h and h.close then pcall(h.close) end
end

local saved = tonumber(settings.get("agartha.v3.resume_frame")) or 0
local currentFrame = (startMode == "resume") and math.max(0, math.min(index.total_frames - 1, saved)) or 0

settings.set("musicvideo.session_active", true)
settings.set("musicvideo.total_frames", index.total_frames)
settings.set("musicvideo.session_frame", currentFrame)
settings.set("musicvideo.session_start", os.epoch("utc") - currentFrame * (1000 / index.fps))
settings.save()

local native = term.current()
term.redirect(monitor)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

local currentHandle, currentHandlePart
local finished = false

local function cleanup()
    closeHandle(currentHandle)
    settings.unset("musicvideo.session_active")
    settings.unset("musicvideo.total_frames")
    settings.unset("musicvideo.segment_base_frame")
    settings.save()
    for i = 0, 15 do monitor.setPaletteColor(2 ^ i, term.nativePaletteColor(2 ^ i)) end
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    term.redirect(native)
end

local ok, err = xpcall(function()
    while currentFrame < index.total_frames and not finished do
        local part, localSkip = locate(currentFrame)
        local partStart = index.starts[part]
        local currentUrl = urlFor(part)
        local nextPart = part < #index.frames and part + 1 or nil
        local nextUrl = nextPart and urlFor(nextPart) or nil

        if currentHandlePart ~= part then
            closeHandle(currentHandle)
            currentHandle, currentHandlePart = nil, nil
        end

        if not currentHandle then
            local hnd, why = requestHandle(currentUrl)
            if not hnd then error("Could not download part " .. part .. ": " .. tostring(why)) end
            currentHandle, currentHandlePart = hnd, part
        end

        settings.set("musicvideo.session_frame", currentFrame)
        settings.set("musicvideo.segment_base_frame", partStart)

        local result, nextHandle, nextError
        local playbackError
        local function playTask()
            local okPlay, value = xpcall(function()
                return fast(currentHandle, "keep", tostring(localSkip), tostring(partStart), tostring(index.total_frames))
            end, debug.traceback)
            currentHandle, currentHandlePart = nil, nil
            if okPlay then result = value else playbackError = value end
        end

        local function prefetchTask()
            if nextUrl then nextHandle, nextError = requestHandle(nextUrl) end
        end

        if nextUrl then parallel.waitForAll(playTask, prefetchTask) else playTask() end
        if playbackError then closeHandle(nextHandle); error(playbackError) end

        result = type(result) == "table" and result or {}
        local control = result.control
        local reported = tonumber(result.current_frame) or currentFrame

        if control == "seek" then
            closeHandle(nextHandle)
            local target = tonumber(result.target) or reported
            currentFrame = math.max(0, math.min(index.total_frames - 1, target))
            settings.set("agartha.v3.resume_frame", currentFrame)
            settings.set("musicvideo.session_frame", currentFrame)
            settings.set("musicvideo.session_start", os.epoch("utc") - currentFrame * (1000 / index.fps))
            settings.save()
        elseif control == "stop" then
            closeHandle(nextHandle)
            currentFrame = math.max(0, math.min(index.total_frames - 1, reported))
            settings.set("agartha.v3.resume_frame", currentFrame)
            settings.save()
            finished = true
        else
            currentFrame = partStart + index.frames[part]
            settings.set("musicvideo.session_frame", currentFrame)
            settings.set("agartha.v3.resume_frame", math.min(index.total_frames - 1, currentFrame))
            settings.save()
            if nextPart then
                if nextHandle then
                    currentHandle, currentHandlePart = nextHandle, nextPart
                elseif nextError then
                    currentHandle, currentHandlePart = nil, nil
                end
            end
        end
    end

    if currentFrame >= index.total_frames then
        settings.set("agartha.v3.resume_frame", 0)
        settings.save()
    end
end, debug.traceback)

cleanup()
if not ok then error(err, 0) end
