local common = require("common")

-- ################################################### --
-- State
-- ################################################### --

local log = nil
local cfg = {
    hostname = nil,
    inventory_side = nil,
    redstone_side = nil,
    max_pulse_count = nil,
    last_signal_delay = nil,
}

local timeout_timer = nil
local pulse_count = 0
local inv = nil

-- ################################################### --
-- Main logic
-- ################################################### --

local function cancelTimeoutTimer()
    if timeout_timer then
        os.cancelTimer(timeout_timer)
        timeout_timer = nil
    end
end

local function resetPulseCount()
    pulse_count = 0
end

local function resetState()
    resetPulseCount()
    cancelTimeoutTimer()
end

local function stateMessage()
    return {
        kind = "vault_state",
        payload = {
            source_name = cfg.hostname,
            items = inv.list(),
            total_slots = inv.size(),
        },
    }
end

local function broadcastState()
    rednet.broadcast(stateMessage(), common.VAULT_PROTOCOL)
    log:info("broadcasted self state")
    resetState()
end

local function sendState(dst_id)
    rednet.send(dst_id, stateMessage(), common.VAULT_PROTOCOL)
    log:info("sent self state to", dst_id)
end

local function onRedstoneSignal()
    log:info("redstone enabled")
    pulse_count = pulse_count + 1

    if pulse_count >= cfg.max_pulse_count then
        broadcastState()
    else
        cancelTimeoutTimer()
        timeout_timer = os.startTimer(cfg.last_signal_delay)
    end
end

local function onTimerEvent()
    log:info("timer event occurried")
    if pulse_count > 0 then
        broadcastState()
    end
    cancelTimeoutTimer()
end

local function onRednetMessage(src_id, msg)
    log:info(("received '%s' message from %d computer"):format(msg.kind, src_id))
    if msg.kind == "get_vault_state"
    and (not msg.payload.target_name or (msg.payload.target_name and msg.payload.target_name == cfg.hostname))
    then
        sendState(src_id)
    end
end

local function initRednet()
    local found = false
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            found = true
            if not rednet.isOpen(side) then
                rednet.open(side)
                print("Opened rednet on " .. side)
            end
        end
    end

    return found
end

local function initInventory()
    return peripheral.wrap(cfg.inventory_side)
end

local function onWakeup()
    log:info("host", cfg.hostname, "protocol", common.VAULT_PROTOCOL)
    rednet.host(common.VAULT_PROTOCOL, cfg.hostname)
    broadcastState()
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
        config = "config.json",
    }
    
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--verbose" or a == "-v" then
            options.verbose = true
        elseif a == "--config" or a == "-c" then
            i = i + 1
            if arg[i] then
                options.config = arg[i]
            end
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
        filename = "logs/vault_relay.log",
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    })

    log = common.getLogger()
    log:info("vault relay starting...")

    cfg = readConfig(options.config)
    assert(cfg, "failed to parse config")

    assert(initRednet(), "modem not found")

    inv = initInventory()
    assert(inv, "inventory not found")

    onWakeup()

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "redstone" then
            local is_on = redstone.getInput(cfg.redstone_side)
            if is_on then
                onRedstoneSignal()
            end
        elseif event == "timer" and p1 == timeout_timer then
            onTimerEvent()
        elseif event == "rednet_message" and p3 == common.VAULT_PROTOCOL then
            local sender_id, message = p1, p2
            if sender_id and message then
                onRednetMessage(sender_id, message)
            end
        end
    end
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