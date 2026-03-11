local loop = require("taskmaster")()

local common = require("common")
local api = require("vault_relay_api")(loop)

-- ################################################### --
-- State
-- ################################################### --

local log = nil

---@class Config
---@field hostname string
---@field controllerHostname string
---@field inventorySide string
---@field redstoneSide string | string[]
---@field maxSignalCount number
---@field lastSignalDelay number
---@field pingInterval number
---@field pongTimeout number
---@field reconnectInterval number
---@field connectTimeout number
local cfg = {}

local controllerId = nil
local connectQueue = loop:createQueue()
local lastPulseTimerTask = nil
local pulse_count = 0
local inv = nil
local max_count_cache = {}

-- ################################################### --
-- Main logic
-- ################################################### --

local function warmingUpCache()
    log:info("warming up cache...")
    local items = inv.list()
    for slot, item in pairs(items) do
        if not max_count_cache[item.name] then
            log:debug("item limit cache miss")
            local detail = inv.getItemDetail(slot)
            max_count_cache[item.name] = detail.maxCount
        end
    end
end

local function scheduleConnect()
    connectQueue:push({})
end

local function nextConnect()
    local _ = connectQueue:pop()
end

local function getRedstoneInput()
    if type(cfg.redstoneSide) == "string" then
        return redstone.getInput(cfg.redstoneSide)
    elseif type(cfg.redstoneSide) == "table" then
        for _, side in ipairs(cfg.redstoneSide) do
            local state = redstone.getInput(side)
            log:debug(("redstone input %s = %s"):format(side, tostring(state)))
            if state then
                log:info("redstone pulse detected on", side, "side")
                return true
            end
        end

        return false
    end
end

local function resetPulseCount()
    pulse_count = 0
end

local function cancelDelayedAnnounce()
    if lastPulseTimerTask then
        lastPulseTimerTask:remove()
        lastPulseTimerTask = nil
    end
end

local function getCurrentState()
    local items = inv.list()
    for slot, item in pairs(items) do
        if not max_count_cache[item.name] then
            --log:debug("item limit cache miss")
            local detail = inv.getItemDetail(slot)
            max_count_cache[item.name] = detail.maxCount
        end

        item.maxCount = max_count_cache[item.name]
    end

    return {
        items = items,
        totalSlots = inv.size(),
    }
end

local function announceState()
    local controllerId = controllerId
    if controllerId then
        log:info("announcing state to controller...")
        local state = getCurrentState()
        api.client.announceState(controllerId, state.items, state.totalSlots)
    end
end

local function scheduleDelayedAnnounce()
    lastPulseTimerTask = loop:addTimer(cfg.lastSignalDelay, function()
        lastPulseTimerTask = nil
        announceState()
        return 0
    end)
end

local function onPing(sender)
    log:debug(("received ping from %d"):format(sender))
end

local function onGetState()
    local state = getCurrentState()
    return state
end

local function onRedstone()
    if not getRedstoneInput() then return end
    log:info("redstone signal received")
    pulse_count = pulse_count + 1

    if pulse_count >= cfg.maxSignalCount then
        cancelDelayedAnnounce()
        resetPulseCount()
        announceState()
    else
        cancelDelayedAnnounce()
        scheduleDelayedAnnounce()
    end
end

local function connectTask(task)
    while true do
        nextConnect()

        local id = api.client.lookup(cfg.controllerHostname)
        if id then
            log:info(("controller hostname %s resolve to %d"):format(cfg.controllerHostname, id))

            api.client.connect({ id = id, timeout = cfg.connectTimeout }, cfg.hostname)
                :next(function(_)
                    controllerId = id
                    log:info("connected to controller")
                    announceState()
                end)
                :catch(function(err)
                    log:error(("failed to connect to controller: %s"):format(err))
                    loop:timer(cfg.reconnectInterval, function()
                        scheduleConnect()
                        return 0
                    end)
                end)
        else
            loop:timer(cfg.reconnectInterval, function()
                scheduleConnect()
                return 0
            end)
        end
    end
end

local function pingTask()
    if not controllerId then return nil end

    log:debug("sendig ping to controller...")
    api.client.ping({ id = controllerId, timeout = cfg.pongTimeout })
        :next(function(_) 
            log:debug("received pong from controller")
        end)
        :catch(function (err)
            log:error(("failed to receive pong from controller %s"):format(err))
            controllerId = nil
            scheduleConnect()
        end)

    return nil
end

local function initInventory()
    return peripheral.wrap(cfg.inventorySide)
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
        logFile = "logs/entrypoint.log",
        config = "config.json",
    }
    
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--verbose" or a == "-v" then
            options.verbose = true
        elseif a == "--log" or a == "-l" then
            i = i + 1
            if arg[i] then options.logFile = arg[i] end
        elseif a == "--config" or a == "-c" then
            i = i + 1
            if arg[i] then options.config = arg[i] end
        end
        i = i + 1
    end
    
    return options
end

local function readConfig(path)
    local f = fs.open(path, "r")
    if not f then
        log:error("failed to open config file:", path)
        return nil
    end
    local content = f.readAll()
    f.close()
    
    local obj, err = textutils.unserialiseJSON(content)
    if not obj then
        log:error("failed to deserialize config:", err)
        return nil
    end

    return obj
end

local function main()
    local options = parseArgs()
    
    -- Initialize logging
    common.initLogging({
        filename = options.logFile,
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    })

    log = common.getLogger()
    log:info("vault relay starting...")

    local _cfg = readConfig(options.config)
    assert(_cfg, "failed to parse config")
    cfg = _cfg

    common.openRednet()

    inv = initInventory()
    assert(inv, "inventory not found")

    warmingUpCache()

    scheduleConnect()

    api.client.onPing(onPing)
    api.client.onGetState(onGetState)

    loop:eventListener("redstone", onRedstone)
        :timer(cfg.pingInterval, pingTask)
        :task(connectTask)
        :run()
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    if log then
        log:error("fatal error: " .. tostring(err))
    else
        printError("fatal error: " .. tostring(err))
    end
end
common.shutdownLogging()