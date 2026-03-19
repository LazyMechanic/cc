local ROOT_URL = "https://raw.githubusercontent.com/LazyMechanic/cc/master/storage_v3"

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
end

local function install()
    downloadFile(ROOT_URL .. "/startup.lua", "startup.lua")
    downloadFile(ROOT_URL .. "/example.config.json", "example.config.json")
    downloadFile("https://gist.githubusercontent.com/MCJack123/1678fb2c240052f1480b07e9053d4537/raw/ad05fb4970c3364015742c0a78706fe1d0355e7f/taskmaster.lua", "taskmaster.lua")
end

local function main(args)
    if args[1] == "-h" or args[1] == "--help" then
        printHelp()
    elseif not args[1] then
        install()
    else
        error("It is not specified what to install")
    end
end

main({...})
