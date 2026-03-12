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
    downloadFile(ROOT_URL .. "/launcher.lua", "launcher.lua")
    downloadFile(ROOT_URL .. "/controller/firmware.json", "firmware.json")
    shell.run("launcher.lua", "--install")
end

local function installInvRelay()
    downloadFile(ROOT_URL .. "/startup.lua", "startup.lua")
    downloadFile(ROOT_URL .. "/launcher.lua", "launcher.lua")
    downloadFile(ROOT_URL .. "/inv_relay/firmware.json", "firmware.json")
    shell.run("launcher.lua", "--install")
end

local function main(args)
    if args[1] == "-h" or args[1] == "--help" then
        printHelp()
    elseif args[1] == "--controller" then
        installController()
    elseif args[1] == "--inv-relay" then
        installInvRelay()
    else
        error("It is not specified what to install")
    end
end

main({...})
