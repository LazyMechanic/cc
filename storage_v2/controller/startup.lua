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

local function launch()
    if multishell then
        print("Launching with multishell...")
        
        local storage_tab = shell.openTab(STORAGE_SCRIPT)
        multishell.setTitle(storage_tab, "Storage")
        
        local monitor_tab = shell.openTab(MONITOR_SCRIPT)
        multishell.setTitle(monitor_tab, "Monitor")
        
        multishell.setFocus(monitor_tab)
        
        print("Started!")
        print("  Tab " .. storage_tab .. ": Storage system")
        print("  Tab " .. monitor_tab .. ": Monitor")
        print("")
        print("Use Ctrl+Tab to switch between tabs")
    else
        print("Launching with parallel...")
        print("Press Ctrl+T to terminate")
        sleep(1)
        
        parallel.waitForAny(
            function() shell.run(STORAGE_SCRIPT) end,
            function() shell.run(MONITOR_SCRIPT) end
        )
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