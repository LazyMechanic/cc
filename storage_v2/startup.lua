local args = {...}
local LAUNCHER_FILE = "launcher.lua"

local function main()
    -- Ensure the launcher exists
    if not fs.exists(LAUNCHER_FILE) then
        printError("Error: " .. LAUNCHER_FILE .. " not found!")
        print("Press any key to continue...")
        os.pullEvent("key")
        return
    end

    -- Check for Multishell support
    if multishell then
        print("Advanced system detected. Launching " .. LAUNCHER_FILE .. " in background tab...")
        
        -- Launch the firmware in a new tab, passing any arguments startup received
        local tabID = shell.openTab(LAUNCHER_FILE, table.unpack(args))
        
        if tabID then
            multishell.setTitle(tabID, "Firmware")
            multishell.setFocus(tabID)
        else
            printError("Failed to launch firmware tab.")
        end
    else
        -- Run blocking in the only tab
        print("Standard system detected. Running " .. LAUNCHER_FILE .. "...")
        shell.run(LAUNCHER_FILE, table.unpack(args))
    end
end

local ok, err = pcall(main)
if not ok then
    printError("Startup fatal error occurred: " .. tostring(err))
end