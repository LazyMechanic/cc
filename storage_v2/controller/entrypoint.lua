local pp = require("cc.pretty")

local loop = require("taskmaster")()

local common = require("common")
local vaultApi = require("vault_relay_api")(loop)
local bufApi = require("buffer_relay_api")(loop)

-- ###################################################
-- Configuration
-- ###################################################

local SCREEN_STORAGE_LIST = "storage_list"
local SCREEN_STORAGE_DETAILS = "storage_details"

-- Colors
local COLOR_BG = colors.black
local COLOR_HEADER_BG = colors.gray
local COLOR_HEADER_FG = colors.white
local COLOR_TEXT = colors.white
local COLOR_TEXT_DIM = colors.lightGray
local COLOR_SEPARATOR = colors.gray

-- Semantic colors
local COLOR_ACCENT = colors.blue
local COLOR_OK = colors.green
local COLOR_WARN = colors.yellow
local COLOR_ATTENTION = colors.red

-- Progress bar colors
local COLOR_PROGRESS_EMPTY = colors.gray
local COLOR_PROGRESS_LOW = COLOR_OK
local COLOR_PROGRESS_MED = COLOR_WARN
local COLOR_PROGRESS_HIGH = COLOR_ATTENTION

-- Button colors
local COLOR_BUTTON_BG = COLOR_ACCENT
local COLOR_BUTTON_FG = colors.white

-- ###################################################
-- State
-- ###################################################

---@alias VaultName string

---@alias BufferName string

---@alias PeripheralName string

---@alias ItemName string

---@class Inventory
---@field name PeripheralName
---@field peripheral table

---@class VaultView
---@field name VaultName
---@field total number
---@field occupied number
---@field itemCount number
---@field percentage number

---@class StorageView
---@field name StorageName
---@field total number
---@field occupied number
---@field itemCount number
---@field percentage number
---@field vaults VaultView[]

---@class Item
---@field name ItemName
---@field count number
---@field nbt number
---@field maxCount number

---@class Vault
---@field connected boolean Always true
---@field id number
---@field name VaultName
---@field total number
---@field occupied number
---@field itemCount number
---@field items table<number, Item>

---@class DisconnectedVault
---@field connected boolean Always false
---@field name VaultName

---@class Buffer
---@field connected boolean Always true
---@field id number
---@field name BufferName
---@field inv Inventory Buffer inventory
---@field total number
---@field occupied number
---@field itemCount number
---@field items table<number, Item>

---@class DisconnectedBuffer
---@field connected boolean Always false
---@field inv Inventory Buffer inventory

---@class Storage
---@field name StorageName
---@field inv Inventory Gate inventory
---@field vaultList VaultName[] List of vaults

local log = nil

---@class Config
---@field hostname string
---@field uiRefreshInterval number
---@field monitorTextScale number
---@field initTimeout number
---@field pingInterval number
---@field pongTimeout number
---@field requestStateInterval number
---@field bufferInventory string
---@field vaults table<VaultName, StorageName>
---@field storages table<StorageName, PeripheralName>
local cfg = {}

---@class Stock
---@field storageList StorageName[]
---@field storages table<StorageName, Storage>
---@field vaults table<VaultName, Vault | DisconnectedVault>
---@field vaultIds table<ComputerId, VaultName>
---@field buffer Buffer | DisconnectedBuffer | nil
local stock = {
    storageList = {},
    storages = {},
    vaults = {},
    vaultIds = {},
    buffer = nil,
}

local bufferStateChangedQueue = loop:createQueue()

local currentScreen = SCREEN_STORAGE_LIST
local selectedStorageName = nil

-- Display state
local display = nil
local displayWidth = 0
local displayHeight = 0
local isMonitor = false

-- Pagination state
local currentPage = 1
local itemsPerPage = 1
local totalPages = 1

-- Click zones for interaction
local clickZones = {}

local needsRedraw = false

-- Cached computed data for display
---@class ComputedData
---@field storageList StorageView[] sorted array of storage data
---@field totalSlots number
---@field totalOccupied number
---@field totalItemCount number
---@field totalPercentage number
local computedData = {
    storageList = {},
    totalSlots = 0,
    totalOccupied = 0,
    totalItemCount = 0,
    totalPercentage = 0,
}

-- ################################################### --
-- Data Computation
-- ################################################### --

local function calculatePercentage(part, total)
    return total > 0 and math.floor((part / total) * 100) or 0
end

local function getBufferPercentage()
    if not stock.buffer
        or stock.buffer and not stock.buffer.connected
    then
        return 0
    end
    return calculatePercentage(stock.buffer.occupied, stock.buffer.total)
end

local function computeDisplayData()
    local storageMap = {}
    
    for _, vault in pairs(stock.vaults) do
        if vault.connected then
            local storageName = cfg.vaults[vault.name]
            if not storageName then
                log:warn(("unknown vault '%s', storage not found"):format(vault.name)) 
                storageName = "UNKNOWN"
            end

            local storage = storageMap[storageName]
            if not storage then
                storage = {
                    name = storageName,
                    total = 0,
                    occupied = 0,
                    itemCount = 0,
                    percentage = 0.0,
                    vaults = {},
                }
                storageMap[storageName] = storage
            end

            storage.total = storage.total + vault.total
            storage.occupied = storage.occupied + vault.occupied
            storage.itemCount = storage.itemCount + vault.itemCount
            storage.percentage = calculatePercentage(storage.occupied, storage.total)
            
            table.insert(storage.vaults, {
                name = vault.name,
                total = vault.total,
                occupied = vault.occupied,
                itemCount = vault.itemCount,
                percentage = calculatePercentage(vault.occupied, vault.total),
            })
        end
    end

    -- Sort all storages and vaults
    local totalSlots = 0
    local totalOccupied = 0
    local totalItemCount = 0
    local storageList = {}
    for _, storage in pairs(storageMap) do
        totalSlots = totalSlots + storage.total
        totalOccupied = totalOccupied + storage.occupied
        totalItemCount = totalItemCount + storage.itemCount

        table.sort(storage.vaults, function(a, b)
            local na = tonumber(a.name:match("_(%d+)$")) or 0
            local nb = tonumber(b.name:match("_(%d+)$")) or 0
            return na < nb
        end)
        table.insert(storageList, storage)
    end
    
    table.sort(storageList, function(a, b)
        local na = tonumber(a.name:match("_(%d+)$")) or 0
        local nb = tonumber(b.name:match("_(%d+)$")) or 0
        return na < nb
    end)
    
    computedData.storageList = storageList
    computedData.totalSlots = totalSlots
    computedData.totalOccupied = totalOccupied
    computedData.totalItemCount = totalItemCount
    computedData.totalPercentage = calculatePercentage(totalOccupied, totalSlots)
end

-- ################################################### --
-- Display Setup
-- ################################################### --

local function findMonitor()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "monitor" then
            local mon = peripheral.wrap(name)
            if mon.isColor() then
                return mon, true
            end
        end
    end
    return nil, false
end

local function setupDisplay()
    local mon, found = findMonitor()
    
    if found then
        display = mon
        isMonitor = true
        display.setTextScale(cfg.monitorTextScale)
        log:info("using external monitor")
    else
        display = term.current()
        isMonitor = false
        log:info("using computer terminal")
    end
    
    displayWidth, displayHeight = display.getSize()
    log:info("display size:", displayWidth, "x", displayHeight)
    
    -- Calculate items per page (header = 1, column header = 1, separator = 1, summary = 1, footer = 1)
    itemsPerPage = math.max(1, displayHeight - 6)
end

-- ################################################### --
-- Drawing Utilities
-- ################################################### --

local function markDirty()
    needsRedraw = true
end

local function clearScreen()
    display.setBackgroundColor(COLOR_BG)
    display.clear()
    clickZones = {}
end

local function setCursor(x, y)
    display.setCursorPos(x, y)
end

local function setColors(fg, bg)
    display.setTextColor(fg)
    display.setBackgroundColor(bg)
end

local function writeAt(x, y, text, fg, bg)
    fg = fg or COLOR_TEXT
    bg = bg or COLOR_BG
    setCursor(x, y)
    setColors(fg, bg)
    display.write(text)
end

local function fillLine(y, color)
    display.setBackgroundColor(color)
    setCursor(1, y)
    display.write(string.rep(" ", displayWidth))
end

local function centerText(y, text, fg, bg)
    local x = math.floor((displayWidth - #text) / 2) + 1
    writeAt(x, y, text, fg, bg)
end

local function registerClickZone(x1, y1, x2, y2, action, data)
    table.insert(clickZones, {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        action = action,
        data = data,
    })
end

local function getProgressColor(percentage)
    if percentage == 0 then
        return COLOR_PROGRESS_EMPTY
    elseif percentage <= 35 then
        return COLOR_PROGRESS_LOW
    elseif percentage <= 75 then
        return COLOR_PROGRESS_MED
    else
        return COLOR_PROGRESS_HIGH
    end
end

local function drawProgressBar(x, y, width, percentage, fg_color)
    local filled = math.floor((percentage / 100) * width)
    if percentage > 0 and filled == 0 then
        filled = 1  -- Show at least 1 char if not empty
    end
    
    setCursor(x, y)
    
    -- Draw filled portion
    if filled > 0 then
        display.setBackgroundColor(fg_color)
        display.write(string.rep(" ", filled))
    end
    
    -- Draw empty portion
    local empty = width - filled
    if empty > 0 then
        display.setBackgroundColor(COLOR_PROGRESS_EMPTY)
        display.write(string.rep(" ", empty))
    end
    
    display.setBackgroundColor(COLOR_BG)
end

local function truncateString(str, maxLen)
    if #str <= maxLen then
        return str
    end
    return string.sub(str, 1, maxLen - 2) .. ".."
end

local function padRight(str, width)
    if #str >= width then
        return string.sub(str, 1, width)
    end
    return str .. string.rep(" ", width - #str)
end

local function padLeft(str, width)
    if #str >= width then
        return string.sub(str, 1, width)
    end
    return string.rep(" ", width - #str) .. str
end

-- ################################################### --
-- UI Components
-- ################################################### --

local function drawHeader(title)
    fillLine(1, COLOR_HEADER_BG)
    centerText(1, title, COLOR_HEADER_FG, COLOR_HEADER_BG)
end

local function drawFooter()
    local y = displayHeight
    fillLine(y, COLOR_HEADER_BG)
    
    -- Page indicator
    local page_text = string.format("Page %d/%d", currentPage, totalPages)
    
    -- Navigation hints
    local nav_left = ""
    local nav_right = ""
    
    if totalPages > 1 then
        if currentPage > 1 then
            nav_left = "< Prev"
        end
        if currentPage < totalPages then
            nav_right = "Next >"
        end
    end
    
    -- Draw navigation
    if #nav_left > 0 then
        writeAt(2, y, nav_left, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
        registerClickZone(1, y, #nav_left + 2, y, "prev_page", nil)
    end
    
    centerText(y, page_text, COLOR_HEADER_FG, COLOR_HEADER_BG)
    
    if #nav_right > 0 then
        local rx = displayWidth - #nav_right
        writeAt(rx, y, nav_right, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
        registerClickZone(rx, y, displayWidth, y, "next_page", nil)
    end
end

local function drawColumnHeaders(y, columns)
    -- Column titles with light gray text on black background
    fillLine(y, COLOR_BG)
    local x = 1
    for _, col in ipairs(columns) do
        writeAt(x, y, padRight(col.name, col.width), COLOR_TEXT_DIM, COLOR_BG)
        x = x + col.width + 1
    end
    
    -- Separator line with dashes
    fillLine(y + 1, COLOR_BG)
    writeAt(1, y + 1, string.rep("-", displayWidth), COLOR_SEPARATOR, COLOR_BG)
end

-- ################################################### --
-- Waiting Screen
-- ################################################### --

local function drawWaitingScreen()
    clearScreen()
    
    -- Header
    drawHeader("Storage Monitor")
    
    -- Waiting message
    centerText(math.floor(displayHeight / 2), "Waiting for data...", COLOR_TEXT_DIM, COLOR_BG)
end

-- ################################################### --
-- Storage List Screen
-- ################################################### --

local function calculateStorageListLayout()
    -- Calculate column widths based on display width
    -- Columns: Name | Progress Bar | Pct | Slots
    -- Names are "storage_XX" format (10 chars)
    -- Slots: 6 vaults * 1620 = 9720 max, so "9720/9720" = 9 chars
    
    local layout = {}
    
    -- Fixed widths
    layout.nameWidth = 12     -- "storage_XX" + padding
    layout.pctWidth = 4       -- "100%"
    layout.slotsWidth = 11    -- "9720/9720" + padding
    layout.spacing = 3         -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = displayWidth - layout.nameWidth - layout.pctWidth - layout.slotsWidth - layout.spacing
    layout.progressWidth = math.max(6, remaining)
    
    return layout
end

local function drawStorageList()
    clearScreen()
    
    -- Compute fresh data
    computeDisplayData()
    
    -- Header with total stats
    local totalPct = computedData.totalPercentage
    local headerTitle = string.format("Storage Monitor [%d%%]", totalPct)
    drawHeader(headerTitle)
    
    -- Buffer percentage on top right
    local bufferPct = getBufferPercentage()
    local bufferText = string.format("Buffer: %d%%", bufferPct)
    local bufferColor = bufferPct > 0 and getProgressColor(bufferPct) or COLOR_HEADER_FG
    writeAt(displayWidth - #bufferText, 1, bufferText, bufferColor, COLOR_HEADER_BG)
    
    local layout = calculateStorageListLayout()
    
    -- Column headers
    local columns = {
        { name = "Storage", width = layout.nameWidth },
        { name = "Fill", width = layout.progressWidth },
        { name = "Pct", width = layout.pctWidth },
        { name = "Slots", width = layout.slotsWidth },
    }
    drawColumnHeaders(2, columns)
    
    -- Calculate pagination
    local numStorages = #computedData.storageList
    totalPages = math.max(1, math.ceil(numStorages / itemsPerPage))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, numStorages)
    
    -- Draw storage rows
    local rowY = 4
    for i = startIdx, endIdx do
        local storage = computedData.storageList[i]
        if storage then
            local x = 1
            
            -- Name column
            local name = truncateString(storage.name, layout.nameWidth)
            writeAt(x, rowY, padRight(name, layout.nameWidth), COLOR_TEXT, COLOR_BG)
            x = x + layout.nameWidth + 1
            
            -- Progress bar
            local progressColor = getProgressColor(storage.percentage)
            drawProgressBar(x, rowY, layout.progressWidth, storage.percentage, progressColor)
            x = x + layout.progressWidth + 1
            
            -- Percentage
            local pctStr = string.format("%3d%%", storage.percentage)
            writeAt(x, rowY, pctStr, getProgressColor(storage.percentage), COLOR_BG)
            x = x + layout.pctWidth + 1
            
            -- Slots
            local slotsStr = string.format("%d/%d", storage.occupied, storage.total)
            writeAt(x, rowY, padLeft(slotsStr, layout.slotsWidth), COLOR_TEXT_DIM, COLOR_BG)
            
            -- Register click zone for this row (store storage name)
            registerClickZone(1, rowY, displayWidth, rowY, "select_storage", storage.name)
            
            rowY = rowY + 1
        end
    end
    
    -- Summary line above footer
    local summaryY = displayHeight - 1
    local summary = string.format("Total: %d/%d slots, %d items",
        computedData.totalOccupied,
        computedData.totalSlots,
        computedData.totalItemCount)
    fillLine(summaryY, COLOR_BG)
    centerText(summaryY, summary, COLOR_TEXT_DIM, COLOR_BG)
    
    -- Footer with pagination
    drawFooter()
end

-- ################################################### --
-- Storage Details Screen
-- ################################################### --

local function calculateStorageDetailLayout()
    -- Calculate column widths based on display width
    -- Columns: Name | Progress Bar | Pct | Slots | Items
    -- Vault names like "create:item_vault_126" (22 chars)
    
    local layout = {}
    
    -- Fixed widths
    layout.nameWidth = 12      -- "vault_XXX" + padding
    layout.pctWidth = 4        -- "100%"
    layout.slotsWidth = 11     -- "1620/1620" + padding
    layout.itemsWidth = 7      -- "999999"
    layout.spacing = 3          -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = displayWidth - layout.nameWidth - layout.pctWidth - layout.slotsWidth - layout.itemsWidth - layout.spacing
    layout.progressWidth = math.max(6, remaining)
    
    return layout
end

local function findStorageByName(name)
    for _, storage in ipairs(computedData.storageList) do
        if storage.name == name then
            return storage
        end
    end
    return nil
end

local function drawStorageDetail()
    clearScreen()
    
    -- Compute fresh data
    computeDisplayData()
    
    -- Get selected storage data
    local storage = findStorageByName(selectedStorageName)
    if not storage then
        fillLine(1, COLOR_HEADER_BG)
        centerText(1, "Storage Details", COLOR_HEADER_FG, COLOR_HEADER_BG)
        
        local back_text = "< Back"
        writeAt(2, 1, back_text, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
        registerClickZone(1, 1, #back_text + 2, 1, "back", nil)
        
        centerText(math.floor(displayHeight / 2), "Storage not found", COLOR_ATTENTION, COLOR_BG)
        return
    end
    
    -- Header with storage name and fill percentage
    fillLine(1, COLOR_HEADER_BG)
    
    local title = string.format("%s [%d%%]", storage.name, storage.percentage)
    centerText(1, title, COLOR_HEADER_FG, COLOR_HEADER_BG)
    
    -- Back button on top left
    local backText = "< Back"
    writeAt(2, 1, backText, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
    registerClickZone(1, 1, #backText + 2, 1, "back", nil)
    
    local layout = calculateStorageDetailLayout()
    
    -- Column headers
    local columns = {
        { name = "Vault", width = layout.nameWidth },
        { name = "Fill", width = layout.progressWidth },
        { name = "Pct", width = layout.pctWidth },
        { name = "Slots", width = layout.slotsWidth },
        { name = "Items", width = layout.itemsWidth },
    }
    drawColumnHeaders(2, columns)
    
    -- Calculate pagination
    local numVaults = #storage.vaults
    totalPages = math.max(1, math.ceil(numVaults / itemsPerPage))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, numVaults)
    
    -- Draw vault rows
    local rowY = 4
    for i = startIdx, endIdx do
        local vault = storage.vaults[i]
        if vault then
            local x = 1
            
            -- Name column
            local name = truncateString(vault.name, layout.nameWidth)
            writeAt(x, rowY, padRight(name, layout.nameWidth), COLOR_TEXT, COLOR_BG)
            x = x + layout.nameWidth + 1
            
            -- Progress bar
            local progressColor = getProgressColor(vault.percentage)
            drawProgressBar(x, rowY, layout.progressWidth, vault.percentage, progressColor)
            x = x + layout.progressWidth + 1
            
            -- Percentage
            local pctStr = string.format("%3d%%", vault.percentage)
            writeAt(x, rowY, pctStr, getProgressColor(vault.percentage), COLOR_BG)
            x = x + layout.pctWidth + 1
            
            -- Slots
            local slotsStr = string.format("%d/%d", vault.occupied, vault.total)
            writeAt(x, rowY, padLeft(slotsStr, layout.slotsWidth), COLOR_TEXT_DIM, COLOR_BG)
            x = x + layout.slotsWidth + 1
            
            -- Items
            local itemsStr = tostring(vault.itemCount)
            writeAt(x, rowY, padLeft(itemsStr, layout.itemsWidth), COLOR_TEXT_DIM, COLOR_BG)
            
            rowY = rowY + 1
        end
    end
    
    -- Draw empty state if no vaults
    if numVaults == 0 then
        centerText(math.floor(displayHeight / 2), "No vaults found", COLOR_TEXT_DIM, COLOR_BG)
    end
    
    -- Summary line above footer
    local summaryY = displayHeight - 1
    local summary = string.format("Total: %d/%d slots, %d items",
        storage.occupied, storage.total, storage.itemCount)
    fillLine(summaryY, COLOR_BG)
    centerText(summaryY, summary, COLOR_TEXT_DIM, COLOR_BG)
    
    -- Footer with pagination
    drawFooter()
end

-- ################################################### --
-- Event Handling
-- ################################################### --

local function handleClick(x, y)
    for _, zone in ipairs(clickZones) do
        if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
            if zone.action == "select_storage" then
                selectedStorageName = zone.data  -- Now stores name instead of index
                currentScreen = SCREEN_STORAGE_DETAILS
                currentPage = 1
                markDirty()
                log:debug("selected storage:", zone.data)
            elseif zone.action == "back" then
                currentScreen = SCREEN_STORAGE_LIST
                selectedStorageName = nil
                currentPage = 1
                markDirty()
                log:debug("back to storage list")
            elseif zone.action == "prev_page" then
                if currentPage > 1 then
                    currentPage = currentPage - 1
                    markDirty()
                    log:debug("prev page:", currentPage)
                end
            elseif zone.action == "next_page" then
                if currentPage < totalPages then
                    currentPage = currentPage + 1
                    markDirty()
                    log:debug("next page:", currentPage)
                end
            end
            return true
        end
    end
    return false
end

-- ################################################### --
-- UI
-- ################################################### --

local function render()
    if not needsRedraw then return end

    if currentScreen == SCREEN_STORAGE_LIST then
        drawStorageList()
    elseif currentScreen == SCREEN_STORAGE_DETAILS then
        drawStorageDetail()
    end

    needsRedraw = false
end

local function uiTask(task)
    local refreshTimer = os.startTimer(cfg.uiRefreshInterval)
    
    -- Initial render
    markDirty()

    while true do
        render()
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == refreshTimer then
            markDirty()
            refreshTimer = os.startTimer(cfg.uiRefreshInterval)
        elseif event == "monitor_touch" or event == "mouse_click" then
            -- p1 = button (for mouse_click) or side (for monitor_touch)
            -- p2 = x, p3 = y
            local clickX, clickY
            if event == "monitor_touch" then
                clickX, clickY = p2, p3
            else
                clickX, clickY = p2, p3
            end
            handleClick(clickX, clickY)
        elseif event == "key" then
            local key = p1
            if key == keys.left or key == keys.pageUp then
                if currentPage > 1 then
                    currentPage = currentPage - 1
                    markDirty()
                end
            elseif key == keys.right or key == keys.pageDown then
                if currentPage < totalPages then
                    currentPage = currentPage + 1
                    markDirty()
                end
            elseif key == keys.backspace and currentScreen == SCREEN_STORAGE_DETAILS then
                currentScreen = SCREEN_STORAGE_LIST
                selectedStorageName = nil
                currentPage = 1
                markDirty()
            end
        end
    end
end

-- ################################################### --
-- Storage Management
-- ################################################### --

local function readVaultState(items, totalSlots)
    local state = {
        total = totalSlots,
        occupied = 0,
        itemCount = 0,
        items = items
    }
    for _, item in pairs(items) do
        state.occupied = state.occupied + 1
        state.itemCount = state.itemCount + item.count
    end
    return state
end

---@param sender ComputerId
---@param items table<ComputerId, Item>
---@param totalSlots number
local function onVaultAnnounceState(sender, items, totalSlots)
    local vaultName = stock.vaultIds[sender]
    if not vaultName then return false, "Unregistered vault ID" end
    
    log:info(("vault %s announced state"):format(vaultName))
    --log:debug(("vault %s state: %s"):format(vaultName, pp.render(pp.pretty({ items, totalSlots }))))
    
    local vault = stock.vaults[vaultName]
    if not vault.connected then return false, "Received state from disconnected vault" end

    local state = readVaultState(items, totalSlots)
    vault.total = state.total
    vault.occupied = state.occupied
    vault.itemCount = state.itemCount
    vault.items = state.items

    markDirty()
end

---@param sender ComputerId
---@param name string
local function onVaultConnect(sender, name)
    local vault = stock.vaults[name]
    if not vault then 
        log:warn("Unknown vault tried to connect: " .. tostring(name))
        return nil, "Unknown vault"
    end
    
    log:info(("vault %s connected"):format(name))

    if vault.connected then
        log:warn(("vault %s already connected as %d"):format(vault.name, vault.id))
    end

    -- Remove old
    if vault.id then stock.vaultIds[vault.id] = nil end
    stock.vaultIds[sender] = name

    local newVault = {
        connected = true,
        id = sender,
        name = name,
        total = 0,
        occupied = 0,
        itemCount = 0,
        items = {},
    }
    stock.vaults[name] = newVault
end

---@param sender ComputerId
local function onVaultPing(sender)
    log:debug(("received ping from vault %d"):format(sender))
end

local function vaultPingTask()
    for _, vault in pairs(stock.vaults) do
        if vault.connected then
            log:debug(("sending ping to %s vault"):format(vault.name))
            vaultApi.server.ping({ id = vault.id, timeout = cfg.pongTimeout })
                :next(function(_)
                    log:debug(("received pong from vault %s"):format(vault.name))
                end)
                :catch(function(err)
                    log:error(("failed to receive pong from vault: %s"):format(vault.name, err))
                    -- Disable vault
                    stock.vaults[vault.name].connected = false
                    markDirty()
                end)
        end
    end

    return nil
end

-- ###################################################
-- Buffer Management
-- ###################################################

local function scheduleItemMoving()
    bufferStateChangedQueue:push({})
end

local function nextMoveItemEvent()
    local _ = bufferStateChangedQueue:pop()
end

local function availableItemCount(storage, targetItem)
    local available = 0
    for _, vaultName in ipairs(storage.vaults) do
        local vault = stock.vaults[vaultName]
        if not vault.connected then
            log:warn(("vault %s is disconnected, skip"):format(vaultName))
            goto continue
        end

        -- If vault can fit any amount of item (1 stack max)
        if vault.occupied < vault.total then
            log:debug("there is extra slots")
            return targetItem.count
        end

        for _, item in pairs(vault.items) do
            if targetItem.name == item.name
                and targetItem.nbt == item.nbt
            then
                log:debug("vault", vault.name, "has identical items")

                local free = item.maxCount - item.count
                available = available + free
                log:debug("item limit", item.maxCount, "free", free, "available", available)
            end

            if available >= targetItem.count then
                log:debug("there is enough space in the storage", storage.name, "in vault", vault.name)
                return targetItem.count
            end
        end

        ::continue::
    end

    return available
end

local function itemsProcessingTask(task)
    while true do
        nextMoveItemEvent()

        log:info("try to distribute items from buffer to storages...")

        local allItemsMoved = true

        if stock.buffer.connected then
            for slot, item in pairs(stock.buffer.items) do
                log:info("moving", item.name, "x" .. item.count)

                for _, storageName in ipairs(stock.storageList) do
                    local storage = stock.storages[storageName]
                    -- How much storage can fit this item
                    local canFit = availableItemCount(storage, item)
                    log:debug("storage", storage.name, "can fit", canFit, "items")

                    if canFit > 0 then
                        local moved = stock.buffer.inv.peripheral.pushItems(storage.inv.name, slot)
                        if moved ~= canFit then
                            log:warn("gate are full")
                            allItemsMoved = false
                        end
                        
                        log:info(("  %s x%d -> %s "):format(item.name, moved, storage.name))
                        
                        item.count = item.count - moved
                        
                        if item.count <= 0 then
                            log:debug(("slot %d with %s x%d completely moved"):format(slot, item.name, item.count))
                            break
                        end
                    end
                end

                if item.count > 0 then
                    log:warn(("no space for %s x%d"):format(item.name, item.count))
                end
            end

            if not allItemsMoved then
                -- After timer try to move rest items
                loop:timer(3, function()
                    scheduleItemMoving()
                    return 0
                end)
            end

            markDirty()
        end
    end
end

local function readBufferState(items, totalSlots)
    local state = {
        total = totalSlots,
        occupied = 0,
        itemCount = 0,
        items = items
    }
    for _, item in pairs(items) do
        state.occupied = state.occupied + 1
        state.itemCount = state.itemCount + item.count
    end
    return state
end

---@param sender ComputerId
---@param items table<ComputerId, Item>
---@param totalSlots number
local function onBufferAnnounceState(sender, items, totalSlots)
    if not stock.buffer.connected then return nil, "Received state from disconnected buffer" end
    
    if sender ~= stock.buffer.id then return nil, "Unauthorized buffer sender" end

    log:info("buffer announced state")
    log:debug(("buffer state: %s"):format(pp.render(pp.pretty({ items, totalSlots }))))

    local state = readBufferState(items, totalSlots)
    stock.buffer.total = state.total
    stock.buffer.occupied = state.occupied
    stock.buffer.itemCount = state.itemCount
    stock.buffer.items = state.items

    scheduleItemMoving()
    markDirty()
end

---@param sender ComputerId
local function onBufferPing(sender)
    log:debug(("received ping from buffer %d"):format(sender))
end

---@param sender ComputerId
---@param name string
local function onBufferConnect(sender, name)
    if stock.buffer then
        log:warn(("buffer %s already connected as %d"):format(stock.buffer.name, stock.buffer.id))
    end

    local newBuffer = {
        connected = true,
        id = sender,
        name = name,
        inv = stock.buffer.inv,
        total = 0,
        occupied = 0,
        itemCount = 0,
        items = {}
    }

    stock.buffer = newBuffer
end

local function bufferPingTask()
    -- If no buffer then skip ping
    if not stock.buffer.connected then
        return nil
    end

    bufApi.server.ping({ id = stock.buffer.id, timeout = cfg.pongTimeout })
        :next(function(_) 
            log:debug(("received pong from buffer %s"):format(stock.buffer.name))
        end)
        :catch(function(err) 
            log:error(("failed to receive pong from buffer %s: %s"):format(stock.buffer.name, err))
            -- Disable buffer
            stock.buffer.connected = false
            markDirty()
        end)

    return nil
end

-- ################################################### --
-- Initialization
-- ################################################### --

local function initStock()-- Init buffer
    local inv = peripheral.wrap(cfg.bufferInventory)
    assert(inv, ("failed to initialize buffer %s inventory"):format(cfg.bufferInventory))
    stock.buffer = {
        connected = false,
        inv = {
            name = cfg.bufferInventory,
            peripheral = inv,
        },
    }

    -- Init storages
    for storageName, gateName in pairs(cfg.storages) do
        local inv = peripheral.wrap(gateName)
        assert(inv, ("failed to initialize gate %s inventory"):format(gateName))

        local storage = {
            name = storageName,
            inv = {
                name = gateName,
                peripheral = inv,
            },
            vaultList = {},
        }
        stock.storages[storageName] = storage
        table.insert(stock.storageList, storageName)
    end

    -- Init vaults
    for vaultName, storageName in pairs(cfg.vaults) do
        stock.vaults[vaultName] = {
            connected = false,
            name = vaultName,
        }
        table.insert(stock.storages[storageName].vaultList, vaultName)
    end

    -- Sort storage list
    table.sort(stock.storageList, function(a, b)
        local na = tonumber(a:match("_(%d+)$")) or 0
        local nb = tonumber(b:match("_(%d+)$")) or 0
        return na < nb
    end)

    -- Sort vaults in storage
    for _, storage in pairs(stock.storages) do
        table.sort(storage.vaultList, function(a, b)
            local na = tonumber(a:match("_(%d+)$")) or 0
            local nb = tonumber(b:match("_(%d+)$")) or 0
            return na < nb
        end)
    end
end

local function init()
    -- Setup display
    setupDisplay()

    common.openRednet()

    initStock()

    bufApi.server.host(cfg.hostname)
    vaultApi.server.host(cfg.hostname)
    
    -- Show waiting screen until data arrives
    drawWaitingScreen()
    
    log:info("waiting for storage data...")
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
        logFile = "logs/entrypoint.log",
        config = "config.json",
    }
    
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--verbose" or a == "-v" then
            options.verbose = true
        elseif a == "--log" or a == "-l" then
            i = i + 1
            if arg[i] then options.logFile = arg[i] end
        elseif a == "--config" or a == "-c" then
            i = i + 1
            if arg[i] then options.config = arg[i] end
        end
        i = i + 1
    end
    
    return options
end

---@return Config | nil
local function readConfig(path)
    local f = fs.open(path, "r")
    if not f then
        log:error("failed to open config file:", path)
        return nil
    end
    local content = f.readAll()
    f.close()
    
    local obj, err = textutils.unserializeJSON(content)
    if not obj then
        log:error("failed to deserialize config:", err)
        return nil
    end

    return obj
end

-- ################################################### --
-- Main
-- ################################################### --

local function main()
    local options = parseArgs()
    
    -- Initialize logging
    common.initLogging({
        filename = options.logFile,
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    })
    
    log = common.getLogger()
    log:info("starting monitor...")

    local _cfg = readConfig(options.config)
    assert(_cfg, "failed to parse config")
    cfg = _cfg

    init()

    bufApi.server.onConnect(onBufferConnect)
    bufApi.server.onPing(onBufferPing)
    bufApi.server.onAnnounceState(onBufferAnnounceState)

    vaultApi.server.onConnect(onVaultConnect)
    vaultApi.server.onPing(onVaultPing)
    vaultApi.server.onAnnounceState(onVaultAnnounceState)

    loop:task(uiTask)
        :task(itemsProcessingTask)
        :timer(cfg.pingInterval, bufferPingTask)
        :timer(cfg.pingInterval, vaultPingTask)
        :run()
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    if log then
        log:error("fatal error: " .. tostring(err))
    else
        printError("fatal error: " .. tostring(err))
    end
end
common.shutdownLogging()