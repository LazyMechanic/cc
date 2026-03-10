local ROOT_URL = "https://raw.githubusercontent.com/LazyMechanic/cc/master/storage_v2"

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

local function printHelp()
    print("Usage: install.lua [options]")
    print("Options:")
    print("  -h, --help        Show this help message")
    print("  --controller      Install controller firmware")
    print("  --vault-relay     Install vault relay firmware")
    print("  --buffer-relay    Install buffer relay firmware")
end

local function installController()
    downloadFile(ROOT_URL .. "/startup.lua", "startup.lua")
    downloadFile(ROOT_URL .. "/firmware_launcher.lua", "firmware_launcher.lua")
    downloadFile(ROOT_URL .. "/controller/firmware.json", "firmware.json")
    shell.run("firmware_launcher.lua", "--install")
end

local function installVaultRelay()
    downloadFile(ROOT_URL .. "/startup.lua", "startup.lua")
    downloadFile(ROOT_URL .. "/firmware_launcher.lua", "firmware_launcher.lua")
    downloadFile(ROOT_URL .. "/vault_relay/firmware.json", "firmware.json")
    shell.run("firmware_launcher.lua", "--install")
end

local function installBufferRelay()
    downloadFile(ROOT_URL .. "/startup.lua", "startup.lua")
    downloadFile(ROOT_URL .. "/firmware_launcher.lua", "firmware_launcher.lua")
    downloadFile(ROOT_URL .. "/buffer_relay/firmware.json", "firmware.json")
    shell.run("firmware_launcher.lua", "--install")
end

local function main(args)
    if args[1] == "-h" or args[1] == "--help" then
        printHelp()
    elseif args[1] == "--controller" then
        installController()
    elseif args[1] == "--vault-relay" then
        installVaultRelay()
    elseif args[1] == "--buffer-relay" then
        installBufferRelay()
    else
        error("It is not specified what to install")
    end
end

main({...})
