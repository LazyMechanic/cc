local pp = require("cc.pretty")

local common = require("common")

-- ################################################### --
-- Configure
-- ################################################### --

local NEW_ITEMS_EVENT = "new_items"

-- ################################################### --
-- State
-- ################################################### --

local log = nil
local cfg = {
    ui_refresh_interval = nil,
    monitor_text_scale = nil,
    init_timeout = nil,
    buffer_inventory = nil,
    vaults = {},
    storages = {},
}

local stock = {
    storages = {},
    buffer = nil,
}

local gates = {}

-- ################################################### --
-- Storage Management
-- ################################################### --

local function readVaultState(payload)
    -- Init vault
    local vault = {
        name = payload.source_name,
        total = payload.total_slots,
        occupied = 0,
        item_count = 0,
        items = payload.items
    }
    for _, item in pairs(payload.items) do
        vault.occupied = vault.occupied + 1
        vault.item_count = vault.item_count + item.count
    end

    return vault
end

local function onVaultState(payload)
    log:info("received 'vault_state' message from", payload.source_name)
    local vault = readVaultState(payload)

    -- Init storage
    local storage_name = cfg.vaults[vault.name]
    if not storage_name then
        log:error(("unexpected vault name '%s', storage not found"):format(vault.name))
        return
    end
    
    local storage = stock.storages[storage_name]
    if not storage then
        storage = {
            name = storage_name,
            vaults = {},
        }
        stock.storages[storage_name] = storage
    end

    storage.vaults[vault.name] = vault
end

local function requestStoragesInitState()
    log:info("broadcast 'get_vault_state' message")
    local msg = {
        kind = "get_vault_state",
        payload = {}
    }
    rednet.broadcast(msg, common.VAULT_PROTOCOL)

    local responded_vaults = {}
    while true do
        local src_id, msg = rednet.receive(common.VAULT_PROTOCOL, cfg.init_timeout)
        if not src_id or not msg then
            break
        end

        responded_vaults[msg.payload.source_name] = true
        onVaultState(msg.payload)
    end

    log:info(("received initial state from next vaults: %s"):format(pp.render(pp.pretty(responded_vaults))))
end

local function storagesProcessingTask()
    requestStoragesInitState()

    while true do
        local _, msg = rednet.receive(common.VAULT_PROTOCOL)

        if msg.kind == "vault_state" then
            onVaultState(msg.payload)
            log:info("storages refreshed")
        end
    end
end

-- ################################################### --
-- Buffer Management
-- ################################################### --

local function notify()
    os.queueEvent(NEW_ITEMS_EVENT)
end

local function readBufferState(payload)
    local buffer = {
        name = payload.source_name,
        total = payload.total_slots,
        occupied = 0,
        item_count = 0,
        items = payload.items
    }
    for _, item in pairs(payload.items) do
        buffer.occupied = buffer.occupied + 1
        buffer.item_count = buffer.item_count + item.count
    end

    return buffer
end

local function onBufferState(payload)
    log:info("received 'buffer_state' message from", payload.source_name)
    stock.buffer = readBufferState(payload)
end

local function requestBufferInitState()
    log:info("broadcast 'get_buffer_state' message")
    local msg = {
        kind = "get_buffer_state",
        payload = {}
    }
    rednet.broadcast(msg, common.BUFFER_PROTOCOL)

    local src_id, response = rednet.receive(common.BUFFER_PROTOCOL, cfg.init_timeout)
    if src_id and response then
        onBufferState(response.payload)
        notify()
    else
        log:warn("timeout occurried, no response from buffer")
    end
end

local function bufferProcessingTask()
    requestBufferInitState()

    while true do
        local _, msg = rednet.receive(common.BUFFER_PROTOCOL)

        if msg.kind == "buffer_state" then
            onBufferState(msg.payload)
            notify()
            log:info("buffer refreshed")
        end
    end
end

-- ################################################### --
-- Items processing
-- ################################################### --

local function availableItemCount(storage, target_item)
    local available = 0
    for _, vault in pairs(storage.vaults) do
        -- If vault can fit any amount of item (1 stack max)
        if vault.occupied < vault.total then
            log:debug("there is extra slots")
            return target_item.count
        end

        for slot, item in pairs(vault.items) do
            if target_item.name == item.name
                and target_item.nbt == item.nbt
            then
                log:debug("vault", vault.name, "has identical items")

                if item.max_count then
                    local free = item.max_count - item.count
                    available = available + free
                    log:debug("item limit", item.max_count, "free", free, "available", available)
                end
            end

            if available >= target_item.count then
                log:debug("there is enough space in the storage", storage.name, "in vault", vault.name)
                return target_item.count
            end
        end
    end

    return available
end

local function itemsProcessingTask()
    while true do
        local _ = os.pullEvent(NEW_ITEMS_EVENT)

        log:info("new items arrived")

        local ordered_storage_list = {}
        for _, storage in pairs(stock.storages) do
            table.insert(ordered_storage_list, storage)
        end
        table.sort(ordered_storage_list, function(a, b)
            local na = tonumber(a.name:match("_(%d+)$")) or 0
            local nb = tonumber(b.name:match("_(%d+)$")) or 0
            return na < nb
        end)

        for slot, item in pairs(stock.buffer.items) do
            log:info("moving", item.name, "x" .. item.count)

            for _, storage in ipairs(ordered_storage_list) do
                -- How much storage can fit this item
                local can_fit = availableItemCount(storage, item)
                log:debug("storage", storage.name, "can fit", can_fit, "items")

                if can_fit > 0 then
                    local moved = gates[storage.name].pullItems(cfg.buffer_inventory, slot, can_fit)
                    log:info("  ->", storage.name, "x" .. moved)
                    
                    item.count = item.count - moved
                    
                    if item.count <= 0 then
                        log:debug("done with item", item.name)
                        break
                    end
                end
            end

            if item.count > 0 then
                log:warn("no space for", item.count, "x", item.name)
            end
        end
    end
end

-- ################################################### --
-- Initialization
-- ################################################### --

local function initRednet()
    local found = false
    local sides = {"top","bottom","left","right","front","back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            found = true
            if not rednet.isOpen(side) then
                rednet.open(side)
                log:info("opened rednet on " .. side)
            end
        end
    end

    return found
end

local function init()
    assert(initRednet())

    log:info("initialize gates...")
    for storage_name, gate_name in pairs(cfg.storages) do
        local inv = peripheral.wrap(gate_name)
        assert(inv, "gate not found")
        gates[storage_name] = inv
    end
    log:info("gates initialized")
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

-- ################################################### --
-- Main
-- ################################################### --

local function main()
    local options = parseArgs()
    
    -- Initialize logging
    common.initLogging({
        filename = "logs/storage.log",
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    })
    
    log = common.getLogger()
    log:info("starting storage system...")

    cfg = readConfig(options.config)
    assert(cfg, "failed to parse config")

    init()

    parallel.waitForAny(
        storagesProcessingTask,
        bufferProcessingTask,
        itemsProcessingTask
    )
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    log:error("fatal error occurried: " .. tostring(err))
end
common.shutdownLogging()