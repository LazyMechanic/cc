local self_update = require("self_update")

local args = {...}

-- ################################################### --
-- Configuration
-- ################################################### --

local ROOT_URL = "https://raw.githubusercontent.com/LazyMechanic/cc/master/storage_v2"

local STORAGE_SCRIPT = "storage.lua"
local MONITOR_SCRIPT = "monitor.lua"

-- ################################################### --
-- Install
-- ################################################### --

local function downloadFile(url, path)
    print("Downloading " .. url .. " -> " .. path)
    local request = http.get(url)
    if request then
        local file = fs.open(path, "w")
        file.write(request.readAll())
        file.close()
        request.close()
    else
        error("Failed to download " .. url)
    end
end

local function installFirmware()
    downloadFile(ROOT_URL .. "/shared/common.lua", "common.lua")
    downloadFile(ROOT_URL .. "/controller/monitor.lua", MONITOR_SCRIPT)
    downloadFile(ROOT_URL .. "/controller/storage.lua", STORAGE_SCRIPT)
    downloadFile(ROOT_URL .. "/controller/example.config.json", "example.config.json")
end

-- ################################################### --
-- Launch
-- ################################################### --

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

local function launch()
    print("Press Ctrl+T to terminate")
    sleep(1)

    initRednet()
    while true do
        local update_requested = false
        parallel.waitForAny(
            function() shell.run(STORAGE_SCRIPT) end,
            function() shell.run(MONITOR_SCRIPT) end,
            function()
                self_update.onUpdate()
                update_requested = true
            end
        )

        if update_requested then
            print("Update requested")
            installFirmware()
        else
            print("Shell finished")
            break
        end
    end
end

-- ################################################### --
-- Main
-- ################################################### --

local function main()
    if args[1] == "--install" then
        installFirmware()
    elseif args[1] == "--launch" then
        launch()
    else
        installFirmware()
        launch()
    end
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    printError("Fatal error occurried: " .. tostring(err))
end