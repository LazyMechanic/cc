local common = require("common")

-- ################################################### --
-- Configuration
-- ################################################### --

local MODEM_SIDE = "back"
local REDSTONE_SIDE = { "left", "right" }
local INVENTORY_SIDE = "bottom"
local TRIGGER_COUNT = 5
local TIMEOUT = 3

-- ################################################### --
-- State
-- ################################################### --

local log = nil
local timeout_timer = nil
local pulse_count = 0
local inv = nil

-- ################################################### --
-- Main logic
-- ################################################### --

local function getRedstoneInput()
    local left = redstone.getInput(REDSTONE_SIDE[1])
    local right = redstone.getInput(REDSTONE_SIDE[2])

    log:debug(("left = %s, right = %s"):format(tostring(left), tostring(right)))
    return left or right
end

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
        kind = "buffer_state",
        payload = {
            source_name = common.BUFFER_NAME,
            items = inv.list(),
            slots = inv.size(),
        },
    }
end

local function broadcastState()
    rednet.broadcast(stateMessage(), common.BUFFER_PROTOCOL)
    log:info("broadcasted self state")
    resetState()
end

local function sendState(dst_id)
    rednet.send(dst_id, stateMessage(), common.BUFFER_PROTOCOL)
    log:info("sent self state to", dst_id)
end

local function onRedstoneSignal()
    log:info("redstone enabled")
    pulse_count = pulse_count + 1

    if pulse_count >= TRIGGER_COUNT then
        broadcastState()
    else
        cancelTimeoutTimer()
        timeout_timer = os.startTimer(TIMEOUT)
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
    if msg.kind == "get_buffer_state"
    and (not msg.payload.target_name or (msg.payload.target_name and msg.payload.target_name == common.BUFFER_NAME))
    then
        sendState(src_id)
    end
end

local function onWakeup()
    log:info("host", common.BUFFER_NAME, "protocol", common.BUFFER_PROTOCOL)
    rednet.host(common.BUFFER_PROTOCOL, common.BUFFER_NAME)
    broadcastState()
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
    }
    
    for _, a in ipairs(arg) do
        if a == "--verbose" or a == "-v" then
            options.verbose = true
        end
    end
    
    return options
end

local function initRednet()
    if not rednet.isOpen(MODEM_SIDE) then
        rednet.open(MODEM_SIDE)
    end
    return rednet.isOpen(MODEM_SIDE)
end


local function initInventory()
    return peripheral.wrap(INVENTORY_SIDE)
end

local function main()
    local options = parseArgs()
    
    -- Initialize logging
    common.initLogging({
        filename = "logs/buffer_relay.log",
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    })

    log = common.getLogger()
    log:info("buffer relay starting...")

    assert(initRednet(), "modem not found")

    inv = initInventory()
    assert(inv, "inventory not found")

    onWakeup()

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "redstone" then
            log:debug("redstone event received")
            local is_on = getRedstoneInput()
            if is_on then
                onRedstoneSignal()
            end
        elseif event == "timer" and p1 == timeout_timer then
            onTimerEvent()
        elseif event == "rednet_message" and p3 == common.BUFFER_PROTOCOL then
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
    log:error("fatal error occurried: " .. tostring(err))
end
common.shutdownLogging()