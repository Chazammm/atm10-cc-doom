-- by Firecaster for CC Version 1.75
 
-- msg store
local STORE = {}
local lastBackup = os.clock()
local backupTimer = 60 * 10 -- every 10 Minutes
local backupFile = "backup"
local graphGroupSize = 10 -- adjust to improve graph readability
local maxStoreCount = 2000
 
-- peripherals
local modem = peripheral.wrap("back")
local monitor = peripheral.wrap("right")
 
-- color converter
local function colorToPaint(color)
    local base2Color = math.log(color) / math.log(2)
    return string.format("%x", base2Color)
end
 
-- colors
local mBack = colors.black
local mFore = colors.white
local mBackPaint = colorToPaint(mBack) 
local mForePaint = colorToPaint(mFore)
 
-- functions
 
local function backupStore()    
    local timestamp = os.clock()
    local timeSince = timestamp - lastBackup
    if timeSince > backupTimer then
        lastBackup = timestamp
        local storeStr = textutils.serialise(STORE)
        local file = fs.open(backupFile, "w")
        file.write(storeStr)
        file.close()
    end
end
 
local function initStore()
    local file = fs.open(backupFile, "r")
    if file ~= nil then
        local data = file.readAll() 
        file.close()
        if data ~= nil and string.len(data) > 0 then
            STORE = textutils.unserialise(data)
        end
    end
end
 
local function clearMonitor()
    -- Setup Monitor
    monitor.setCursorBlink(false)
    monitor.setBackgroundColor(mBack)
    monitor.clear()
end
 
local function createWindow(x, y, w, h, label, borderColor, labelColor)
    local frame = window.create(monitor, x, y, w, h, false)
    -- border color
    if borderColor == nil then
        borderColor = colors.lightGray
    end 
    local borderPaint = colorToPaint(borderColor)
    -- label color
    if labelColor == nil then
        labelColor = colors.white
    end
    local labelPaint = colorToPaint(labelColor)
    -- frame size
    local frameW = w - 2
    local frameH = h - 2
    -- label dimensions
    local labelLen = string.len(label)
    local prefixLen = math.floor((frameW - (labelLen + 2)) / 2)
    if prefixLen < 1 then
        error("Window "..label.." is too small!")
    end
    local suffixLen = frameW - prefixLen - labelLen - 2
    -- Draw frameTop
    local frameTop = string.rep(" ", prefixLen).." "..label.." "..string.rep(" ", suffixLen)
    local labelBack = string.rep(borderPaint, prefixLen)..string.rep(mBackPaint, labelLen + 2)..string.rep(borderPaint, suffixLen)
    local labelFore = string.rep(labelPaint, string.len(labelBack))
    frame.setCursorPos(2, 2)
    frame.blit(frameTop, labelFore, labelBack)
    -- Draw the rest of the frame   
    local borderFore = string.rep(labelPaint, frameW)
    local windowLine = string.rep(" ", frameW)
    local sideBorderPaint = borderPaint..string.rep(mBackPaint, frameW - 2)..borderPaint
    frame.setCursorPos(2, h - 1)
    frame.blit(windowLine, borderFore, string.rep(borderPaint, frameW)) 
    for i = 3, h - 2 do
        frame.setCursorPos(2, i)
        frame.blit(windowLine, borderFore, sideBorderPaint)
    end
    -- Create inner window
    local innerFrame = window.create(frame, 3, 3, frameW - 2, frameH - 2)
    --
    local result = {}
    result.main = frame
    result.inner = innerFrame   
    return result
end
 
local function drawWindows()
    clearMonitor()
    local w, h = monitor.getSize()
    local rfFrameW = 11
    local rfFrame = createWindow(w - rfFrameW + 1, 1, rfFrameW, h, "RF", colors.red, colors.lime)
    local graphFrameH = 14
    local graphFrame = createWindow(1, h - graphFrameH + 1, w - rfFrameW + 1, graphFrameH, "Power Level Graph")
    local statsFrame = createWindow(1, 1, w - rfFrameW + 1, h - graphFrameH + 1, "Power Stats")
    local frames = {}
    frames.rf = rfFrame
    frames.graph = graphFrame
    frames.stats = statsFrame
    frames.setVisible = function (self, isVisible)
        self.rf.main.setVisible(isVisible)
        self.graph.main.setVisible(isVisible)
        self.stats.main.setVisible(isVisible)
    end
    return frames
end
 
local function isEmpty(msg)
  return msg == nil or msg[2] == nil or type(msg[2]) ~= "number"
end
 
local function removeOldMsgs()
    local msgCount = table.getn(STORE)
    if msgCount > maxStoreCount then
        for i = 1, 500 do -- remove oldest 500 msgs. This way this function doesn't have to run often
            table.remove(STORE, 1)
        end
    end
end
 
local function drawRfStorageBar(frame)
    local w, h = frame.getSize()
    local lastMsgN = table.getn(STORE)
    if lastMsgN > 0 then
        local lastMsg = STORE[lastMsgN]
        local energyStored = lastMsg[2]
        local maxEnergy = lastMsg[3]
        local percentage = math.floor((energyStored / maxEnergy) * 100)
        local barHeight = math.floor((h * percentage) / 100)    
        local barYPos = h - barHeight + 1
        local percString = string.format("%d%%", percentage)
        local middlePos = math.floor((h - 1) / 2) + 1
        local centerPos = math.floor((w - string.len(percString)) / 2) + 1  
        local labelBack = mBack
        local labelFore = mFore
        if barYPos <= middlePos then
            labelBack = colors.lime
            labelFore = colors.black
        end
        -- draw
        local bar = window.create(frame, 1, barYPos, w, barHeight)
        frame.setBackgroundColor(mBack)
        frame.clear()
        bar.setBackgroundColor(colors.lime)
        bar.clear()
        frame.setCursorPos(centerPos, middlePos)
        frame.setBackgroundColor(labelBack)     
        frame.setTextColor(labelFore)
        frame.write(percString)
    end
end
 
-- powers levels
local TRI = 10^12
local BIL = 10^9
local MIL = 10^6
local KILO = 10^3
 
local function formatRF(rf)
    local div = 1
    local symbol = "RF"
    local absRF = math.abs(rf)
    if absRF > TRI then
        div = TRI
        symbol = "TRF"
    elseif absRF > BIL then
        div = BIL
        symbol = "BRF"
    elseif absRF > MIL then
        div = MIL
        symbol = "MRF"
    elseif absRF > KILO then
        div = KILO
        symbol = "KRF"
    end
    rf = math.floor((rf / div) * 100) / 100
    return string.format("%f %s", rf, symbol)
end
 
local function formatRate(rate, isPerTick)
    local timeSym = "sec"
    if isPerTick then
        rate = rate / 20
        timeSym = "tick"
    end
    return string.format("%s/%s", formatRF(rate), timeSym)
end
 
local function drawStatistics(frame)
    local w, h = frame.getSize()
    local lastMsgN = table.getn(STORE)
    if lastMsgN > 1 then
        local msg1 = STORE[lastMsgN - 1]
        local msg2 = STORE[lastMsgN]
        local timeDelta = msg2[1] - msg1[1]
        local energyDelta = msg2[2] - msg1[2]
        local rate = energyDelta / timeDelta
        local energyStored = msg2[2]    
        local energyMax = msg2[3]
        local ratePSec = formatRate(rate, false)
        local ratePTick = formatRate(rate, true)
        local energyStoredStr = formatRF(energyStored)
        local energyMaxLabel = "Max Energy Storage: "
        local energyMaxFormat = formatRF(energyMax)
        local energyMaxStr = string.format("(%s%s)", energyMaxLabel, energyMaxFormat)
        local energyMaxFore = string.rep(mForePaint, string.len(energyMaxLabel) + 1)..string.rep(colorToPaint(colors.cyan), string.len(energyMaxFormat))..mForePaint
        local valueColor = colors.lime
        if rate < 0 and energyStored < energyMax then
            valueColor = colors.red
        end
        frame.setBackgroundColor(mBack)
        frame.clear()
        frame.setTextColor(mFore)
        frame.setCursorPos(2, 2)
        frame.write("Excess power")
        frame.setCursorPos(2, 6)
        frame.write("Power Stored")
        frame.setTextColor(valueColor)
        frame.setCursorPos(w - string.len(ratePTick), 2)
        frame.write(ratePTick)
        frame.setCursorPos(w - string.len(ratePSec), 4)
        frame.write(ratePSec)
        frame.setCursorPos(w - string.len(energyStoredStr), 6)
        frame.write(energyStoredStr)
        frame.setCursorPos(w - string.len(energyMaxStr), 8)
        frame.blit(energyMaxStr, energyMaxFore, string.rep(mBackPaint, string.len(energyMaxStr)))
    end
end
 
local function drawGraph(frame)
    local w, h = frame.getSize()
    local msgCount = table.getn(STORE)
    if msgCount > graphGroupSize then
        local dataPoints = {}
        local dataPointsN = math.floor((msgCount - 1) / graphGroupSize)
        if dataPointsN > w then
            dataPointsN = w
        end
        -- Get graphGroupSize msgs and get the max/min value
        local maxEnergy = 0
        local minEnergy = 0
		local index = msgCount - (dataPointsN * graphGroupSize)
		while index <= msgCount do
			local msg = STORE[index]
			local energy = msg[2]
			table.insert(dataPoints, energy)
			if energy > maxEnergy then
				maxEnergy = energy
			end
			if minEnergy == 0 or energy < minEnergy then
				minEnergy = energy
			end
			index = index + graphGroupSize			
		end
        -- let's do some deceptive bar chart practices to emphasize the graph
        local minMaxDelta = maxEnergy - minEnergy;
        local unitSize = (minMaxDelta / h) * 2
        minEnergy = minEnergy - unitSize
        maxEnergy = maxEnergy - minEnergy       
        maxEnergy = maxEnergy + unitSize
        -- draw the graph
        frame.setBackgroundColor(mBack)
        frame.clear()
		local pointsN = table.getn(dataPoints)
        for i = 1, pointsN do
            local point = dataPoints[i] - minEnergy
            local height = math.floor((point / maxEnergy) * h)
            local bar = window.create(frame, i, h - height + 1, 1, height)
            bar.setBackgroundColor(colors.cyan)
            bar.clear()
        end
    end
end
 
local function listen()
    -- init STORE from backup if present
    initStore()
    -- open connection
    modem.open(69)
    -- draw windows
    local frames = drawWindows()
    frames:setVisible(true)
    -- start loop
    print("PowerMonitor is listening for flying molemen to get data...")
    while true do
        local e,s,f,re,msg,d = os.pullEvent("modem_message")
        
        if not isEmpty(msg) then  
            -- update store
            table.insert(STORE, msg)
            removeOldMsgs() -- don't want STORE getting too big
            backupStore()
            -- update windows
            frames:setVisible(false)
            drawRfStorageBar(frames.rf.inner)
            drawStatistics(frames.stats.inner)
            drawGraph(frames.graph.inner)
            frames:setVisible(true)
        end
    end
end
 
-- end of functions
 
listen() -- start listening for data packets