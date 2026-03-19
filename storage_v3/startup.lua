local pp = require("cc.pretty")

local loop = require("taskmaster")()

local logging = require("logging")

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

local ALL_SIDES = { "top", "bottom", "left", "right", "back", "front" }

-- ###################################################
-- State
-- ###################################################

---@alias VaultName string

---@alias StorageName string

local log = nil


---@class BufferConfig
---@field inventory string
---@field redstone string

---@class VaultConfig
---@field name VaultName
---@field inventory string
---@field redstone string
---@field storage string

---@class StorageConfig
---@field name StorageName
---@field inventory string

---@class Config
---@field uiRefreshInterval number
---@field monitorTextScale number
---@field checkBufferInterval number
---@field buffer BufferConfig
---@field vaults VaultConfig[]
---@field storages StorageConfig[]
local cfg = {}


---@alias ItemName string

---@alias Slot number

---@class Item
---@field name ItemName
---@field count number
---@field nbt string|nil

---@alias PeripheralName string

---@class Redstone
---@field name PeripheralName
---@field peripheral table

---@class Inventory
---@field name PeripheralName
---@field peripheral table

---@class Buffer
---@field inv Inventory
---@field red Redstone

---@class Storage
---@field name StorageName
---@field inv Inventory Gate inventory

---@class Vault
---@field name VaultName
---@field inv Inventory
---@field storage StorageName
---@field red Redstone

---@class Stock
---@field buffer Buffer
---@field vaults table<VaultName, Vault>
---@field storages table<StorageName, Storage>
---@field vaultRedstones table<PeripheralName, VaultName>
---@field vaultsOrdering VaultName[]
local stock = {
    buffer = {
        inv = { name = "", peripheral = {} },
        red = { name = "", peripheral = {} },
    },
    vaults = {},
    storages = {},
    vaultRedstones = {},
    vaultsOrdering = {},
}

---@alias MaxCountCache table<string, number>
local maxCountCache = {}

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


---@class BufferView
---@field total number
---@field occupied number
---@field itemCount number
---@field percentage number

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
---@field vaultList VaultView[]

-- Cached computed data for display
---@class ComputedData
---@field buffer BufferView
---@field storageList StorageView[] sorted array of storage data
---@field totalSlots number
---@field totalOccupied number
---@field totalItemCount number
---@field totalPercentage number
local computedData = {
    buffer = { total = 0, occupied = 0, itemCount = 0, percentage = 0 },
    storageList = {},
    totalSlots = 0,
    totalOccupied = 0,
    totalItemCount = 0,
    totalPercentage = 0,
}

---@class DirtyInventories
---@field buffer boolean
---@field vaults table<VaultName, boolean>
local dirtyInventories = {
    buffer = false,
    vaults = {},
}

-- ################################################### --
-- Data Computation
-- ################################################### --

local function calculatePercentage(part, total)
    return total > 0 and math.floor((part / total) * 100) or 0
end

local function computeDisplayData()
    log:debug("compute display data...")
    local dirtyBuffer = dirtyInventories.buffer
    local dirtyVaults = dirtyInventories.vaults

    dirtyInventories.buffer = false
    dirtyInventories.vaults = {}

    if dirtyBuffer then
        log:debug("buffer marked dirty, compute data...")
        computedData.buffer = {
            total = stock.buffer.inv.peripheral.size(),
            occupied = 0,
            itemCount = 0,
            percentage = 0,
        }
        for _, item in pairs(stock.buffer.inv.peripheral.list()) do
            computedData.buffer.occupied = computedData.buffer.occupied + 1
            computedData.buffer.itemCount = computedData.buffer.itemCount + item.count
        end
        computedData.buffer.percentage = calculatePercentage(computedData.buffer.occupied, computedData.buffer.total)
    end

    local vaultTasks = {}
    local updatedVaults = {}
    for _, vaultName in ipairs(stock.vaultsOrdering) do
        if dirtyVaults[vaultName] then
            local task = function()
                log:debug(("vault %s marked dirty, compute data..."):format(vaultName))
                local vault = stock.vaults[vaultName]

                local vaultView = {
                    name = vault.name,
                    total = vault.inv.peripheral.size(),
                    occupied = 0,
                    itemCount = 0,
                    percentage = 0,
                }
                for _, item in pairs(vault.inv.peripheral.list()) do
                    vaultView.occupied = vaultView.occupied + 1
                    vaultView.itemCount = vaultView.itemCount + item.count
                end

                vaultView.percentage = calculatePercentage(vaultView.occupied, vaultView.total)
                updatedVaults[vault.name] = vaultView
            end
            table.insert(vaultTasks, task)
        end
    end

    if #vaultTasks > 0 then
        parallel.waitForAll(table.unpack(vaultTasks))
    end

    if #vaultTasks == 0 then
        log:debug("compute display data done!")
        return
    end

    local storageTasks = {}
    for storageIdx, storage in ipairs(computedData.storageList) do
        log:debug(("compute storage %s data..."):format(storage.name))
        local currentStorageIdx = storageIdx
        local currentStorage = storage
        local task = function()
            computedData.storageList[currentStorageIdx].total = 0
            computedData.storageList[currentStorageIdx].occupied = 0
            computedData.storageList[currentStorageIdx].itemCount = 0
            computedData.storageList[currentStorageIdx].percentage = 0

            for vaultIdx, vault in ipairs(currentStorage.vaultList) do
                if updatedVaults[vault.name] then
                    currentStorage.vaultList[vaultIdx] = updatedVaults[vault.name]
                end

                computedData.storageList[currentStorageIdx].total = computedData.storageList[currentStorageIdx].total + currentStorage.vaultList[vaultIdx].total
                computedData.storageList[currentStorageIdx].occupied = computedData.storageList[currentStorageIdx].occupied + currentStorage.vaultList[vaultIdx].occupied
                computedData.storageList[currentStorageIdx].itemCount = computedData.storageList[currentStorageIdx].itemCount + currentStorage.vaultList[vaultIdx].itemCount
            end

            computedData.storageList[currentStorageIdx].percentage = calculatePercentage(computedData.storageList[currentStorageIdx].occupied, computedData.storageList[currentStorageIdx].total)
        end

        table.insert(storageTasks, task)
    end

    if #storageTasks > 0 then
        parallel.waitForAll(table.unpack(storageTasks))
    end

    log:debug("compute total data...")
    computedData.totalSlots = 0
    computedData.totalOccupied = 0
    computedData.totalItemCount = 0
    for _, storage in ipairs(computedData.storageList) do
            computedData.totalSlots = computedData.totalSlots + storage.total
            computedData.totalOccupied = computedData.totalOccupied + storage.occupied
            computedData.totalItemCount = computedData.totalItemCount + storage.itemCount
    end
    computedData.percentage = calculatePercentage(computedData.totalOccupied, computedData.totalSlots)

    log:debug("display data computed!")
end

-- ################################################### --
-- Drawing Utilities
-- ################################################### --

local function markDirty(target)
    needsRedraw = true

    if not target then return end

    if target.buffer then
        dirtyInventories.buffer = true
    elseif target.vault then
        dirtyInventories.vaults[target.vault] = true
    end
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
    -- Compute fresh data
    computeDisplayData()

    clearScreen()
    
    -- Header with total stats
    local totalPct = computedData.totalPercentage
    local headerTitle = string.format("Storage Monitor [%d%%]", totalPct)
    drawHeader(headerTitle)
    
    -- Buffer percentage on top right
    local bufferPct = computedData.buffer.percentage
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
    -- Compute fresh data
    computeDisplayData()

    clearScreen()
    
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
    local numVaults = #storage.vaultList
    totalPages = math.max(1, math.ceil(numVaults / itemsPerPage))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, numVaults)
    
    -- Draw vault rows
    local rowY = 4
    for i = startIdx, endIdx do
        local vault = storage.vaultList[i]
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

---@param red Redstone
---@return boolean
local function getRedstoneInput(red)
    for _, side in ipairs(ALL_SIDES) do
        if red.peripheral.getInput(side) then
            return true
        end
    end
    return false
end

---@param item Item
local function makeMaxCountCacheKey(item)
    return item.name .. ":" .. (item.nbt or "nil")
end

---@param inv Inventory
---@param slot Slot
---@param item Item
local function getMaxCount(inv, slot, item)
    local cacheKey = makeMaxCountCacheKey(item)
    if not maxCountCache[cacheKey] then
        log:debug("item limit cache miss")
        local detail = inv.peripheral.getItemDetail(slot)
        maxCountCache[cacheKey] = detail.maxCount
    end

    return maxCountCache[cacheKey]
end

local function moveBufferItems()
    local bufItems = stock.buffer.inv.peripheral.list()

    if not next(bufItems) then
        log:debug("no items in buffer")
        return
    end

    local vaults = {}
    log:debug("start prepare vaults...")
    for _, vaultName in ipairs(stock.vaultsOrdering) do
        local vault = stock.vaults[vaultName]
        local items = vault.inv.peripheral.list()
        local occupied = 0
        for _, _ in pairs(items) do occupied = occupied + 1 end
        table.insert(vaults, {
            name = vault.name,
            storage = vault.storage,
            inv = vault.inv,
            items = items,
            total = vault.inv.peripheral.size(),
            occupied = occupied,
        })
    end
    log:debug("vaults prepared!")

    local tasks = {}
    for bufSlot, bufItem in pairs(bufItems) do
        local t = function()
            local bufItemMaxCount = getMaxCount(stock.buffer.inv, bufSlot, bufItem)
            for _, vault in ipairs(vaults) do
                -- There is a free slot
                if vault.occupied < vault.total then
                    local moved = stock.buffer.inv.peripheral.pushItems(stock.storages[vault.storage].inv.name, bufSlot)
                    log:debug(("%s x%d -> %s (%s)"):format(bufItem.name, moved, vault.storage, vault.name))
                    bufItem.count = bufItem.count - moved
                    -- We don't know which slot will when item will arrives to vault 
                else
                    for _, vaultItem in pairs(vault.items) do
                        local isSameItem = vaultItem.name == bufItem.name
                            and vaultItem.nbt == bufItem.nbt
                            and vaultItem.count < bufItemMaxCount
                        if isSameItem then
                            local canFit = bufItemMaxCount - vaultItem.count
                            local moved = stock.buffer.inv.peripheral.pushItems(stock.storages[vault.storage].inv.name, bufSlot, canFit)
                            log:debug(("%s x%d -> %s (%s)"):format(bufItem.name, moved, vault.storage, vault.name))
                            bufItem.count = bufItem.count - moved
                            vaultItem.count = vaultItem.count + moved
                        end
                    end
                end

                if bufItem.count <= 0 then
                    log:info(("moving done for %s"):format(bufItem.name))
                    markDirty({ buffer = true })
                    return
                end

                coroutine.yield()
            end
        end
        table.insert(tasks, t)
    end

    parallel.waitForAll(table.unpack(tasks))
    log:info("all items moved from buffer to storages")
end

local function onRedstoneEvent(_event, src)
    if stock.vaultRedstones[src] then
        markDirty({ vault = stock.vaultRedstones[src] })
        log:debug(("vault %s redstone signal received"):format(stock.vaultRedstones[src]))
    elseif stock.buffer.red.name == src then
        markDirty({ buffer = true })
        log:debug("buffer redstone signal received")
    else
        log:warn(("unexpected redstone signal from %s"):format(src))
    end
end

-- ################################################### --
-- Initialization
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

    clearScreen()
end

local function initBuffer()
    log:info("init buffer...")
    local inv = peripheral.wrap(cfg.buffer.inventory)
    assert(inv, ("failed to initialize buffer inventory %s"):format(cfg.buffer.inventory))

    local redstone = peripheral.wrap(cfg.buffer.redstone)
    assert(redstone, ("failed to initialize buffer redstone %s"):format(cfg.buffer.redstone))

    stock.buffer = {
        inv = {
            name = cfg.buffer.inventory,
            peripheral = inv,
        },
        red = {
            name = cfg.buffer.redstone,
            peripheral = redstone,
        },
    }
    log:info("buffer initialized!")
end

local function initVaults()
    log:info("init vaults...")
    for _, vault in ipairs(cfg.vaults) do
        local inv = peripheral.wrap(vault.inventory)
        assert(inv, ("failed to initialize vault %s inventory %s"):format(vault.name, vault.inventory))

        local redstone = peripheral.wrap(vault.redstone)
        assert(redstone, ("failed to initialize vault %s redstone %s"):format(vault.name, vault.redstone))

        stock.vaults[vault.name] = {
            name = vault.name,
            inv = {
                name = vault.inventory,
                peripheral = inv,
            },
            storage = vault.storage,
            red = {
                name = vault.redstone,
                peripheral = redstone,
            },
        }
        stock.vaultRedstones[vault.redstone] = vault.name
        table.insert(stock.vaultsOrdering, vault.name)
    end
    log:info("vaults initialized!")
end

local function initStorages()
    log:info("init storages...")
    for _, storage in ipairs(cfg.storages) do
        local inv = peripheral.wrap(storage.inventory)
        assert(inv, ("failed to initialize storage %s inventory %s"):format(storage.name, storage.inventory))

        stock.storages[storage.name] = {
            name = storage.name,
            inv = {
                name = storage.inventory,
                peripheral = inv,
            }
        }
    end
    log:info("storages initialized!")
end

local function initStock()
    initBuffer()
    initVaults()
    initStorages()
end

local function initUi()
    log:info("initialize UI...")

    needsRedraw = true
    dirtyInventories.buffer = true
    for name, _ in pairs(stock.vaults) do
        dirtyInventories.vaults[name] = true
    end

    -- Scan vaults

    for _, vaultName in ipairs(stock.vaultsOrdering) do
        local vault = stock.vaults[vaultName]
        local inv = vault.inv.peripheral

        local total = inv.size()
        local occupied = 0
        local itemCount = 0

        for _, item in pairs(inv.list()) do
            occupied = occupied + 1
            itemCount = itemCount + item.count
        end

        local vaultView = {
            name = vault.name,
            total = total,
            occupied = occupied,
            itemCount = itemCount,
            percentage = calculatePercentage(occupied, total),
        }

        if #computedData.storageList == 0 
            or computedData.storageList[#computedData.storageList].name ~= vault.storage
        then
            local storageView = {
                name = vault.storage,
                total = 0,
                occupied = 0,
                itemCount = 0,
                percentage = 0,
                vaultList = {},
            }
            table.insert(computedData.storageList, storageView)
        end

        
        table.insert(computedData.storageList[#computedData.storageList].vaultList, vaultView)

        computedData.storageList[#computedData.storageList].total = computedData.storageList[#computedData.storageList].total + total
        computedData.storageList[#computedData.storageList].occupied = computedData.storageList[#computedData.storageList].occupied + occupied
        computedData.storageList[#computedData.storageList].itemCount = computedData.storageList[#computedData.storageList].itemCount + itemCount
    end

    -- Finalize storage percentages

    computedData.totalSlots = 0
    computedData.totalOccupied = 0
    computedData.totalItemCount = 0

    for _, storage in ipairs(computedData.storageList) do
        storage.percentage = calculatePercentage(storage.occupied, storage.total)

        computedData.totalSlots = computedData.totalSlots + storage.total
        computedData.totalOccupied = computedData.totalOccupied + storage.occupied
        computedData.totalItemCount = computedData.totalItemCount + storage.itemCount
    end

    computedData.totalPercentage = calculatePercentage(
        computedData.totalOccupied,
        computedData.totalSlots
    )

    -- Buffer initial scan (so header is correct immediately)

    local bufInv = stock.buffer.inv.peripheral
    local bufTotal = bufInv.size()
    local bufOccupied = 0
    local bufItemCount = 0

    for _, item in pairs(bufInv.list()) do
        bufOccupied = bufOccupied + 1
        bufItemCount = bufItemCount + item.count
    end

    computedData.buffer = {
        total = bufTotal,
        occupied = bufOccupied,
        itemCount = bufItemCount,
        percentage = calculatePercentage(bufOccupied, bufTotal),
    }

    log:info("ui initialized")
end

local function warmingUpCache()
    log:info("warming up cache...")
    local tasks = {}
    for _, vault in pairs(stock.vaults) do
        local p = loop.Promise.new(function(resolve, _)
            log:debug(("scan %s vault"):format(vault.name))
            for slot, item in pairs(vault.inv.peripheral.list()) do
                local detail = vault.inv.peripheral.getItemDetail(slot)
                local key = makeMaxCountCacheKey(item)
                maxCountCache[key] = detail.maxCount
                coroutine.yield()
            end
            resolve()
        end)
        :next(function() log:debug(("caching done for %s"):format(vault.name)) end)
        table.insert(tasks, p)
    end
    local p = loop.Promise.new(function(resolve, _)
        log:debug("scan buffer")
        for slot, item in pairs(stock.buffer.inv.peripheral.list()) do
            local detail = stock.buffer.inv.peripheral.getItemDetail(slot)
            local key = makeMaxCountCacheKey(item)
            maxCountCache[key] = detail.maxCount
            coroutine.yield()
        end
        resolve()
    end)
    :next(function() log:debug("caching done for buffer") end)
    table.insert(tasks, p)

    loop.Promise.all(tasks):next(function() log:info("cache warmedup!") end)
end

local function init()
    -- Setup display
    setupDisplay()

    log:debug("dumb wait...")
    sleep(5)
    log:debug("done!")

    initStock()
    initUi()

    warmingUpCache()
    
    -- Show waiting screen until data arrives
    -- drawWaitingScreen()
    
    log:info("waiting for storage data...")
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
        logFile = nil,
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
    logging.initLogging({
        filename = options.logFile,
        level = options.verbose and logging.LogLevel.DEBUG or logging.LogLevel.INFO,
        console = true,
        timestamp = true,
        append = false,
    }) 
    
    log = logging.getLogger()
    log:info("starting monitor...")

    local _cfg = readConfig(options.config)
    assert(_cfg, "failed to parse config")
    cfg = _cfg

    init()

    loop:task(uiTask)
        :eventListener("redstone", onRedstoneEvent)
        :timer(cfg.checkBufferInterval, moveBufferItems)
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
logging.shutdownLogging()