-- storage.lua
-- Storage System - Item Router

local common = require("common")

-- ################################################### --
-- Configure
-- ################################################### --


-- ################################################### --
-- State
-- ################################################### --

local stock = {
    storages = {},
    buffer = nil,
}

local log = nil

-- ################################################### --
-- Main logic
-- ################################################### --

-- ##### Vault ##### --

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
    local storage_name = common.VAULT_TO_STORAGE[vault.name]
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
        local src_id, msg = rednet.receive(common.VAULT_PROTOCOL, INIT_TIMEOUT)
        if not src_id or not msg then
            break
        end

        responded_vaults[msg.payload.source_name] = true
        onVaultState(msg.payload)
    end

    local responded_vaults_count = 0
    for key, _ in pairs(responded_vaults) do
        responded_vaults_count = responded_vaults_count + 1
    end

    if responded_vaults_count < common.VAULT_COUNT then
        log:warn("not all vaults responded")
    end
end

local function storagesProcessingTask()
    requestStoragesInitState()
    markDirty()

    while true do
        local _, msg = rednet.receive(common.VAULT_PROTOCOL)

        if msg.kind == "vault_state" then
            onVaultState(msg.payload)
            markDirty()
            log:info("storages refreshed")
        end
    end
end

-- ##### Buffer ##### --

local function readBufferState(payload)
    local buffer = {
        name = payload.source_name,
        total = payload.slots,
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

    local src_id, msg = rednet.receive(common.BUFFER_PROTOCOL, INIT_TIMEOUT)
    if src_id or msg then
        onBufferState(msg.payload)
    else
        log:warn("timeout occuried, no response from buffer")
    end
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

end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    log:error("fatal error occurried: " .. tostring(err))
end
common.shutdownLogging()