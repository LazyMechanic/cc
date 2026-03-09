local pp = require("cc.pretty")

local args = {...}

-- ################################################### --
-- Configuration
-- ################################################### --

local ROOT_URL = "https://raw.githubusercontent.com/LazyMechanic/cc/master/storage_v2"

local SCRIPT = "entrypoint.lua"

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
    local firmware_list = {}
    for line in io.lines("firmware_list") do
        local url, path = line:match("([^,]+),([^,]+)")
        if url and path then
            table.insert(firmware_list, { url = ROOT_URL .. url, path = path })
        end
    end

    for _, f in ipairs(firmware_list) do
        downloadFile(f.url, f.path)
    end
end

-- ################################################### --
-- Launch
-- ################################################### --

local UPDATE_PROTOCOL = "self_update"

local function waitUpdateRequest()
    local src_id, msg = rednet.receive(UPDATE_PROTOCOL)
    print(("Received message from %d: %s"):format(src_id, pp.render(pp.pretty(msg))))
end

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
            function() shell.run(SCRIPT) end,
            function()
                waitUpdateRequest()
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
