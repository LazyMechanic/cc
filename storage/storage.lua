-- storage.lua
-- Storage System - Item Router

local common = require("common")

-- ################################################### --
-- Configuration
-- ################################################### --

local CHECK_BUFFER_INTERVAL = 1

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

    local log = common.getLogger("Main")
    log:info("storage system starting...")

    local storages = common.initStorages()
    if not storages then
        log:error("failed to initialize storages!")
        common.shutdownLogging()
        return
    end

    local buf = peripheral.wrap(common.BUFFER)
    if not buf then
        log:error("failed to initialize buffer:", common.BUFFER)
        common.shutdownLogging()
        return
    end
    
    log:info("starting main loop...")

    while true do
        for slot, item in pairs(buf.list()) do
            log:info("moving", item.name, "x" .. item.count)

            for _, storage in ipairs(storages) do
                -- How much storage can fit this item
                local can_fit = storage:availableItemSize(item)
                log:debug("storage", storage:name(), "can fit", can_fit, "items")

                if can_fit > 0 then
                    local moved = storage:gate():moveItem(slot, can_fit)
                    log:info("  ->", storage:name(), "x" .. moved)
                    
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

        sleep(CHECK_BUFFER_INTERVAL)
    end
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    printError("storage system crashed: " .. tostring(err))
end
common.shutdownLogging()