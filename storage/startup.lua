-- startup.lua
-- Launches Storage System and Monitor simultaneously

-- ################################################### --
-- Configuration
-- ################################################### --

local STORAGE_SCRIPT = "storage.lua"
local MONITOR_SCRIPT = "monitor.lua"

-- ################################################### --
-- Helper Functions
-- ################################################### --

local function fileExists(path)
    return fs.exists(path) and not fs.isDir(path)
end

-- ################################################### --
-- Launch Methods
-- ################################################### --

local function launchBoth()
    if multishell then
        print("Launching with multishell...")
        
        local storage_tab = shell.openTab(STORAGE_SCRIPT)
        multishell.setTitle(storage_tab, "Storage")
        
        local monitor_tab = shell.openTab(MONITOR_SCRIPT)
        multishell.setTitle(monitor_tab, "Monitor")
        
        multishell.setFocus(monitor_tab)
        
        print("Started!")
        print("  Tab " .. storage_tab .. ": Storage System")
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

local function launchStorageOnly()
    print("Launching Storage System...")
    sleep(0.5)
    shell.run(STORAGE_SCRIPT)
end

local function launchMonitorOnly()
    print("Launching Monitor...")
    sleep(0.5)
    shell.run(MONITOR_SCRIPT)
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    for _, a in ipairs(arg) do
        if a == "--storage" or a == "-s" then
            return "storage"
        elseif a == "--monitor" or a == "-m" then
            return "monitor"
        elseif a == "--help" or a == "-h" then
            return "help"
        end
    end
    return "both"
end

local function printHelp()
    print("Storage System Launcher")
    print("")
    print("Usage: startup [options]")
    print("")
    print("Options:")
    print("  (none)          Run both programs")
    print("  --storage, -s   Run storage system only")
    print("  --monitor, -m   Run monitor only")
    print("  --help, -h      Show this help")
end

-- ################################################### --
-- Main
-- ################################################### --

local function main()
    local mode = parseArgs()
    
    if mode == "help" then
        printHelp()
        return
    end
    
    if mode == "storage" then
        if not fileExists(STORAGE_SCRIPT) then
            printError("Missing: " .. STORAGE_SCRIPT)
            return
        end
        launchStorageOnly()
        
    elseif mode == "monitor" then
        if not fileExists(MONITOR_SCRIPT) then
            printError("Missing: " .. MONITOR_SCRIPT)
            return
        end
        launchMonitorOnly()
        
    else -- both
        if not fileExists(STORAGE_SCRIPT) then
            printError("Missing: " .. STORAGE_SCRIPT)
            return
        end
        if not fileExists(MONITOR_SCRIPT) then
            printError("Missing: " .. MONITOR_SCRIPT)
            return
        end
        launchBoth()
    end
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    printError("Startup failed: " .. tostring(err))
end