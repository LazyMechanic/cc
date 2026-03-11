local pp = require("cc.pretty")

local args = {...}

local function getScriptArgs(args)
    local entry_args = {}
    local found = false

    for _, a in ipairs(args) do
        if found then
            table.insert(entry_args, a)
        elseif a == "--" then
            found = true
        end
    end

    return entry_args
end

-- ################################################### --
-- Configuration
-- ################################################### --

local SCRIPT_ARGS = getScriptArgs(args)

local FIRMWARE_DIR = "firmware"
local FIRMWARE_BACKUP_DIR = "firmware.bak"

local SCRIPT = "firmware/entrypoint.lua"

-- ################################################### --
-- Install
-- ################################################### --


    
---@class File
---@field path string
---@field url string

---@class Manifest
---@field origin string
---@field files File[]

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

---@return Manifest
local function readManifest()
    local file = fs.open("firmware.json", "r")
    if not file then
        error("Failed to open manifest file 'firmware.json'")
    end
    local content = file.readAll()
    file.close()
    return textutils.unserializeJSON(content)
end

local function installFirmware()
    local manifest = readManifest()

    if fs.exists(FIRMWARE_BACKUP_DIR) then
        print("Delete old firmware backup")
        fs.delete(FIRMWARE_BACKUP_DIR)
    end

    if fs.exists(FIRMWARE_DIR) then
        print("Backup old firmware...")
        fs.move(FIRMWARE_DIR, FIRMWARE_BACKUP_DIR)
    end

    print("Update manifest...")
    downloadFile(manifest.origin, "firmware.json")

    local manifest = readManifest()

    print("Update files")
    for _, f in ipairs(manifest.files) do
        local finalPath = ("%s/%s"):format(FIRMWARE_DIR, f.path)
        downloadFile(f.url, finalPath)
    end
end

-- ################################################### --
-- Launch
-- ################################################### --

local UPDATE_PROTOCOL = "firmware_update"

local function waitUpdateRequest()
    local src_id, msg = rednet.receive(UPDATE_PROTOCOL)
    print(("Received message from %d: %s"):format(src_id, pp.render(pp.pretty(msg))))
end

local function openRednet()
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

    openRednet()

    while true do
        local update_requested = false

        parallel.waitForAny(
            function()
                shell.run(SCRIPT, table.unpack(SCRIPT_ARGS))
            end,
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
            print("Press any key to continue...")
            os.pullEvent("key")
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
    else
        launch()
    end
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    printError("Launcher fatal error occurred: " .. tostring(err))
end