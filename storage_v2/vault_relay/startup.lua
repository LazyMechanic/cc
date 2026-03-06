local args = {...}

-- ################################################### --
-- Configuration
-- ################################################### --

local ROOT_URL = "https://raw.githubusercontent.com/LazyMechanic/cc/master/storage_v2"

local SCRIPT = "vault_relay.lua"

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
    downloadFile(ROOT_URL .. "/vault_relay/vault_relay.lua", SCRIPT)
    downloadFile(ROOT_URL .. "/vault_relay/example.config.json", "example.config.json")
end

-- ################################################### --
-- Launch
-- ################################################### --

local function launch()
    if multishell then
        print("Launching with multishell...")
        
        local tab = shell.openTab(SCRIPT)
        multishell.setTitle(tab, "Vault relay")
        
        multishell.setFocus(tab)
        
        print("Started!")
        print("")
        print("Use Ctrl+Tab to switch between tabs")
    else
        print("Press Ctrl+T to terminate")
        sleep(1)
        
        shell.run(SCRIPT)
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
