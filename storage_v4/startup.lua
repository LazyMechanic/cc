local pp = require("cc.pretty")

local loop = require("taskmaster")()

local logging = require("logging")
local Mutex = require("mutex")

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
---@field redstoneIn string
---@field redstoneOut string
---@field storage string

---@class StorageConfig
---@field name StorageName
---@field inventory string

---@class Config
---@field uiRefreshInterval number
---@field monitorTextScale number
---@field updateInventoriesInterval number
---@field moveItemsInterval number
---@field useCreateStock boolean
---@field buffer BufferConfig
---@field vaults VaultConfig[]
---@field storages StorageConfig[]
local cfg = {}


---@alias ItemName string

---@alias Slot number

---@alias PeripheralName string

---@class Item
---@field name ItemName
---@field count number
---@field nbt string|nil

---@class InventoryMetrics
---@field total number
---@field occupied number
---@field itemCount number
---@field percentage number

---@class InventoryCache
---@field items table<Slot, Item>
---@field metrics InventoryMetrics

---@class Redstone
---@field name PeripheralName
---@field peripheral table

---@class Inventory
---@field name PeripheralName
---@field peripheral table

---@class Buffer
---@field inv Inventory
---@field red Redstone
---@field invCache InventoryCache

---@class Vault
---@field name VaultName
---@field storage StorageName
---@field inv Inventory
---@field redIn Redstone
---@field redOut Redstone
---@field invCache InventoryCache

---@class Storage
---@field name StorageName
---@field gateInv Inventory
---@field sumMetrics InventoryMetrics

---@class Stock
---@field buffer Buffer
---@field vaults table<VaultName, Vault>
---@field storages table<StorageName, Storage>
---@field sumMetrics InventoryMetrics
local stock = {
    buffer = {
        inv = { name = "", peripheral = {} },
        red = { name = "", peripheral = {} },
        invCache = {
            items = {},
            metrics = {
                total = 0,
                occupied = 0,
                itemCount = 0,
                percentage = 0,
            },
        },
    },
    vaults = {},
    storages = {},
    sumMetrics = {
        total = 0,
        occupied = 0,
        itemCount = 0,
        percentage = 0,
    },
}
local stockMx = Mutex.new(loop)

---@class Index
---@field storagesOrdered StorageName[]
---@field vaultsOrdered VaultName[]
---@field storageToVaults table<StorageName, VaultName[]>
---@field redstoneToVault table<PeripheralName, VaultName>
local index = {
    storagesOrdered = {},
    vaultsOrdered = {},
    storageToVaults = {},
    redstoneToVault = {},
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

-- ################################################### --
-- Drawing Utilities
-- ################################################### --

local function markDirty(target)
    needsRedraw = true

    if not target then return end

    if target.buffer then
        dirtyInventories.buffer = true
    end
    
    if target.vault then
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

local function drawLoadingScreen()
    clearScreen()
    
    -- Header
    drawHeader("Storage Monitor")
    
    -- Waiting message
    centerText(math.floor(displayHeight / 2), "Loading...", COLOR_TEXT_DIM, COLOR_BG)
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
    layout.spacing = 3        -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = displayWidth - layout.nameWidth - layout.pctWidth - layout.slotsWidth - layout.spacing
    layout.progressWidth = math.max(6, remaining)
    
    return layout
end

local function drawStorageList()
    clearScreen()
    
    -- Header with total stats
    local totalPct = stock.sumMetrics.percentage
    local headerTitle = string.format("Storage Monitor [%d%%]", totalPct)
    drawHeader(headerTitle)
    
    -- Buffer percentage on top right
    local bufferPct = stock.buffer.invCache.metrics.percentage
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
    local numStorages = #index.storagesOrdered
    totalPages = math.max(1, math.ceil(numStorages / itemsPerPage))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, numStorages)
    
    -- Draw storage rows
    local rowY = 4
    for i = startIdx, endIdx do
        local storageName = index.storagesOrdered[i]
        if storageName then
            local storage = stock.storages[storageName]

            local x = 1
            
            -- Name column
            local name = truncateString(storage.name, layout.nameWidth)
            writeAt(x, rowY, padRight(name, layout.nameWidth), COLOR_TEXT, COLOR_BG)
            x = x + layout.nameWidth + 1
            
            -- Progress bar
            local progressColor = getProgressColor(storage.sumMetrics.percentage)
            drawProgressBar(x, rowY, layout.progressWidth, storage.sumMetrics.percentage, progressColor)
            x = x + layout.progressWidth + 1
            
            -- Percentage
            local pctStr = string.format("%3d%%", storage.sumMetrics.percentage)
            writeAt(x, rowY, pctStr, getProgressColor(storage.sumMetrics.percentage), COLOR_BG)
            x = x + layout.pctWidth + 1
            
            -- Slots
            local slotsStr = string.format("%d/%d", storage.sumMetrics.occupied, storage.sumMetrics.total)
            writeAt(x, rowY, padLeft(slotsStr, layout.slotsWidth), COLOR_TEXT_DIM, COLOR_BG)
            
            -- Register click zone for this row (store storage name)
            registerClickZone(1, rowY, displayWidth, rowY, "select_storage", storage.name)
            
            rowY = rowY + 1
        end
    end
    
    -- Summary line above footer
    local summaryY = displayHeight - 1
    local summary = string.format("Total: %d/%d slots, %d items",
        stock.sumMetrics.occupied,
        stock.sumMetrics.total,
        stock.sumMetrics.itemCount)
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
    layout.spacing = 3         -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = displayWidth - layout.nameWidth - layout.pctWidth - layout.slotsWidth - layout.itemsWidth - layout.spacing
    layout.progressWidth = math.max(6, remaining)
    
    return layout
end

local function drawStorageDetail()
    clearScreen()
    
    -- Get selected storage data
    local storage = stock.storages[selectedStorageName]
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
    
    local title = string.format("%s [%d%%]", storage.name, storage.sumMetrics.percentage)
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
    local storageVaults = index.storageToVaults[storage.name]
    local numVaults = #storageVaults
    totalPages = math.max(1, math.ceil(numVaults / itemsPerPage))
    
    if currentPage > totalPages then
        currentPage = totalPages
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, numVaults)
    
    -- Draw vault rows
    local rowY = 4
    for i = startIdx, endIdx do
        local vaultName = storageVaults[i]
        if vaultName then
            local vault = stock.vaults[vaultName]
            local x = 1
            
            -- Name column
            local name = truncateString(vault.name, layout.nameWidth)
            writeAt(x, rowY, padRight(name, layout.nameWidth), COLOR_TEXT, COLOR_BG)
            x = x + layout.nameWidth + 1
            
            -- Progress bar
            local progressColor = getProgressColor(vault.invCache.metrics.percentage)
            drawProgressBar(x, rowY, layout.progressWidth, vault.invCache.metrics.percentage, progressColor)
            x = x + layout.progressWidth + 1
            
            -- Percentage
            local pctStr = string.format("%3d%%", vault.invCache.metrics.percentage)
            writeAt(x, rowY, pctStr, getProgressColor(vault.invCache.metrics.percentage), COLOR_BG)
            x = x + layout.pctWidth + 1
            
            -- Slots
            local slotsStr = string.format("%d/%d", vault.invCache.metrics.occupied, vault.invCache.metrics.total)
            writeAt(x, rowY, padLeft(slotsStr, layout.slotsWidth), COLOR_TEXT_DIM, COLOR_BG)
            x = x + layout.slotsWidth + 1
            
            -- Items
            local itemsStr = tostring(vault.invCache.metrics.itemCount)
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
        storage.sumMetrics.occupied, storage.sumMetrics.total, storage.sumMetrics.itemCount)
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

---@class ScanInventoryResult
---@field items table<Slot, Item>
---@field total number
---@field occupied number
---@field itemCount number
---@field percentage number

---@param inv Inventory
---@return ScanInventoryResult
local function scanInventory(inv)
    log:debug(("scanning inventory %s..."):format(inv.name))
    local items = inv.peripheral.list()
    local total = inv.peripheral.size()
    local occupied = 0
    local itemCount = 0
    for _, item in pairs(items) do
        occupied = occupied + 1
        itemCount = itemCount + item.count
    end
    local percentage = calculatePercentage(occupied, total)
    log:debug("scanned")
    return {
        items = items,
        total = total,
        occupied = occupied,
        itemCount = itemCount,
        percentage = percentage,
    }
end

local function stateUpdateTask()
    stockMx:lock()

    local dirtyBuffer = dirtyInventories.buffer
    local dirtyVaults = dirtyInventories.vaults

    dirtyInventories.buffer = false
    dirtyInventories.vaults = {}

    if not dirtyBuffer
        and not next(dirtyVaults)
    then
        stockMx:unlock()
        return
    end

    log:debug(("vaults to update: %s"):format(pp.render(pp.pretty(dirtyVaults))))
    log:debug(("buffer update: %s"):format(tostring(dirtyBuffer)))

    local promises = {}

    if dirtyBuffer then
        local p = loop.Promise.new(function(resolve, _)
            local state = scanInventory(stock.buffer.inv)
            stock.buffer.invCache.items = state.items
            stock.buffer.invCache.metrics.total = state.total
            stock.buffer.invCache.metrics.occupied = state.occupied
            stock.buffer.invCache.metrics.itemCount = state.itemCount
            stock.buffer.invCache.metrics.percentage = state.percentage
            resolve()
        end)
        table.insert(promises, p)
    end

    for vaultName, _ in pairs(dirtyVaults) do
        local vault = stock.vaults[vaultName]
        local p = loop.Promise.new(function(resolve, _)
            local state = scanInventory(vault.inv)
            vault.invCache.items = state.items
            vault.invCache.metrics.total = state.total
            vault.invCache.metrics.occupied = state.occupied
            vault.invCache.metrics.itemCount = state.itemCount
            vault.invCache.metrics.percentage = state.percentage
            resolve()
        end)
        table.insert(promises, p)
    end

    if #promises == 0 then
        stockMx:unlock()
        return
    end

    log:info("start to update stock state")

    loop.Promise.all(promises)
        :next(function(_, _)
            stock.sumMetrics.total = 0
            stock.sumMetrics.occupied = 0
            stock.sumMetrics.itemCount = 0
            for _, storage in pairs(stock.storages) do
                log:debug(("update storage %s"):format(storage.name))
                storage.sumMetrics.total = 0
                storage.sumMetrics.occupied = 0
                storage.sumMetrics.itemCount = 0
                for _, vaultName in ipairs(index.storageToVaults[storage.name]) do
                    local vault = stock.vaults[vaultName]
                    storage.sumMetrics.total = storage.sumMetrics.total + vault.invCache.metrics.total
                    storage.sumMetrics.occupied = storage.sumMetrics.occupied + vault.invCache.metrics.occupied
                    storage.sumMetrics.itemCount = storage.sumMetrics.itemCount + vault.invCache.metrics.itemCount
                end
                storage.sumMetrics.percentage = calculatePercentage(storage.sumMetrics.occupied, storage.sumMetrics.total)

                stock.sumMetrics.total = stock.sumMetrics.total + storage.sumMetrics.total
                stock.sumMetrics.occupied = stock.sumMetrics.occupied + storage.sumMetrics.occupied
                stock.sumMetrics.itemCount = stock.sumMetrics.itemCount + storage.sumMetrics.itemCount
            end
            stock.sumMetrics.percentage = calculatePercentage(stock.sumMetrics.occupied, stock.sumMetrics.total)
            log:info("stock state updated")

            stockMx:unlock()
        end)
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
        local ok, detailResult = pcall(inv.peripheral.getItemDetail, slot)
        -- Pessimistic value
        local maxCount = 1
        if not ok then
            log:error(("failed to get item detail: %s"):format(tostring(detailResult)))
        elseif detailResult then
            maxCount = detailResult.maxCount
        end
        maxCountCache[cacheKey] = maxCount
    end

    return maxCountCache[cacheKey]
end

local function moveBufferItems()
    stockMx:lock()

    local bufItems = stock.buffer.invCache.items
    if not next(bufItems) then
        stockMx:unlock()
        return
    end

    log:info("start move items from buffer")

    local tasks = {}
    for bufSlot, bufItem in pairs(bufItems) do
        local t = function()
            local bufItemMaxCount = getMaxCount(stock.buffer.inv, bufSlot, bufItem)
            for _, vaultName in ipairs(index.vaultsOrdered) do
                local vault = stock.vaults[vaultName]

                -- Use stock system from create mod
                if cfg.useCreateStock then
                    -- There is a free slot
                    if vault.invCache.metrics.occupied < vault.invCache.metrics.total then
                        -- Try to move item from buffer inventory to gate
                        local ok, movedResult = pcall(stock.buffer.inv.peripheral.pushItems, stock.storages[vault.storage].gateInv.name, bufSlot)
                        if not ok then
                            log:error(("failed to push items: %s"):format(tostring(movedResult)))
                        elseif movedResult then
                            log:debug(("%s x%d -> %s (%s)"):format(bufItem.name, movedResult, vault.storage, vault.name))
                            bufItem.count = bufItem.count - movedResult
                            -- We don't know which slot will when item will arrives to vault 
                        end
                    else
                        for _, vaultItem in pairs(vault.invCache.items) do
                            local isSameItem = vaultItem.name == bufItem.name
                                and vaultItem.nbt == bufItem.nbt
                                and vaultItem.count < bufItemMaxCount
                            if isSameItem then
                                local canFit = bufItemMaxCount - vaultItem.count

                                -- Try to move item from buffer inventory to gateLog
                                local ok, movedResult = pcall(stock.buffer.inv.peripheral.pushItems, stock.storages[vault.storage].gateInv.name, bufSlot, canFit)
                                if not ok then
                                    log:error(("failed to push items: %s"):format(tostring(movedResult)))
                                elseif movedResult then
                                    log:debug(("%s x%d -> %s (%s)"):format(bufItem.name, movedResult, vault.storage, vault.name))
                                    bufItem.count = bufItem.count - movedResult
                                    vaultItem.count = vaultItem.count + movedResult

                                    -- If item full processed
                                    if bufItem.count <= 0 then
                                        log:info(("moving done for %s"):format(bufItem.name))
                                        stock.buffer.invCache.items[bufSlot] = nil
                                        markDirty({ buffer = true })
                                        return
                                    end
                                end
                            end
                        end
                    end

                    -- If item full processed
                    if bufItem.count <= 0 then
                        log:info(("moving done for %s"):format(bufItem.name))
                        stock.buffer.invCache.items[bufSlot] = nil
                        markDirty({ buffer = true })
                        return
                    end

                    coroutine.yield()

                -- Use cc cable as inventory transport
                else
                    local ok, movedResult = pcall(stock.buffer.inv.peripheral.pushItems, vault.inv.name, bufSlot)
                    if not ok then
                        log:error(("failed to push items: %s"):format(tostring(movedResult)))
                    elseif movedResult then
                        if movedResult > 0 then
                            log:info(("moved %s x%d -> %s (%s)"):format(bufItem.name, movedResult, vault.storage, vault.name))
                            bufItem.count = bufItem.count - movedResult
                            markDirty({ vault = vault.name, buffer = true })
                        else
                            log:debug(("vault %s can't fit %s"):format(vault.name, bufItem.name))
                        end
                    end

                    -- If item full processed
                    if bufItem.count <= 0 then
                        log:info(("moving done for %s"):format(bufItem.name))
                        stock.buffer.invCache.items[bufSlot] = nil
                        return
                    end
                end
            end
        end
        table.insert(tasks, t)
    end

    parallel.waitForAll(table.unpack(tasks))
    log:info("all items moved from buffer to storages")
    stockMx:unlock()
end

local function onRedstoneEvent(_event, src)
    if index.redstoneToVault[src] then
        markDirty({ vault = index.redstoneToVault[src] })
        log:debug(("vault %s redstone signal received"):format(index.redstoneToVault[src]))
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

local function initIndex()
    for _, vault in ipairs(cfg.vaults) do
        table.insert(index.vaultsOrdered, vault.name)

        if not index.storageToVaults[vault.storage] then
            index.storageToVaults[vault.storage] = {}
        end
        table.insert(index.storageToVaults[vault.storage], vault.name)

        index.redstoneToVault[vault.redstoneIn] = vault.name
        index.redstoneToVault[vault.redstoneOut] = vault.name
    end

    for _, storage in ipairs(cfg.storages) do
        table.insert(index.storagesOrdered, storage.name)
    end
end

local function initBuffer()
    log:info("init buffer...")
    local invPer = peripheral.wrap(cfg.buffer.inventory)
    assert(invPer, ("failed to initialize buffer inventory %s"):format(cfg.buffer.inventory))
    local inv = {
        name = cfg.buffer.inventory,
        peripheral = invPer,
    }

    local redPer = peripheral.wrap(cfg.buffer.redstone)
    assert(redPer, ("failed to initialize buffer redstone %s"):format(cfg.buffer.redstone))
    local red = {
        name = cfg.buffer.redstone,
        peripheral = redPer
    }

    local invState = scanInventory(inv)
    local invCache = {
        items = invState.items,
        metrics = {
            total = invState.total,
            occupied = invState.occupied,
            itemCount = invState.itemCount,
            percentage = invState.percentage,
        },
    }

    stock.buffer = {
        inv = inv,
        red = red,
        invCache = invCache,
    }
    log:info("buffer initialized!")
end

local function initVaults()
    log:info("init vaults...")
    for _, vault in ipairs(cfg.vaults) do
        local invPer = peripheral.wrap(vault.inventory)
        assert(invPer, ("failed to initialize vault %s inventory %s"):format(vault.name, vault.inventory))
        local inv = {
            name = vault.inventory,
            peripheral = invPer,
        }

        local invState = scanInventory(inv)
        local invCache = {
            items = invState.items,
            metrics = {
                total = invState.total,
                occupied = invState.occupied,
                itemCount = invState.itemCount,
                percentage = invState.percentage,
            },
        }

        local redInPer = peripheral.wrap(vault.redstoneIn)
        assert(redInPer, ("failed to initialize vault %s redstone %s"):format(vault.name, vault.redstoneIn))
        local redIn = {
            name = vault.redstoneIn,
            peripheral = redInPer,
        }
        
        local redOutPer = peripheral.wrap(vault.redstoneOut)
        assert(redOutPer, ("failed to initialize vault %s redstone %s"):format(vault.name, vault.redstoneOut))
        local redOut = {
            name = vault.redstoneOut,
            peripheral = redOutPer,
        }

        stock.vaults[vault.name] = {
            name = vault.name,
            storage = vault.storage,
            inv = inv,
            redIn = redIn,
            redOut = redOut,
            invCache = invCache,
        }
    end
    log:info("vaults initialized!")
end

local function initStorages()
    log:info("init storages...")
    for _, storage in ipairs(cfg.storages) do
        local invPer = peripheral.wrap(storage.inventory)
        assert(invPer, ("failed to initialize storage %s inventory %s"):format(storage.name, storage.inventory))
        local inv = {
            name = storage.inventory,
            peripheral = invPer,
        }

        local sumMetrics = {
            total = 0,
            occupied = 0,
            itemCount = 0,
            percentage = 0,
        }
        for _, vaultName in ipairs(index.storageToVaults[storage.name]) do
            local vault = stock.vaults[vaultName]
            sumMetrics.total = sumMetrics.total + vault.invCache.metrics.total
            sumMetrics.occupied = sumMetrics.occupied + vault.invCache.metrics.occupied
            sumMetrics.itemCount = sumMetrics.itemCount + vault.invCache.metrics.itemCount
        end
        sumMetrics.percentage = calculatePercentage(sumMetrics.occupied, sumMetrics.total)

        stock.storages[storage.name] = {
            name = storage.name,
            gateInv = inv,
            sumMetrics = sumMetrics,
        }
    end
    log:info("storages initialized!")
end

local function initStock()
    initBuffer()
    initVaults()
    initStorages()

    for _, storage in pairs(stock.storages) do
        stock.sumMetrics.total = stock.sumMetrics.total + storage.sumMetrics.total
        stock.sumMetrics.occupied = stock.sumMetrics.occupied + storage.sumMetrics.occupied
        stock.sumMetrics.itemCount = stock.sumMetrics.itemCount + storage.sumMetrics.itemCount
    end
    stock.sumMetrics.percentage = calculatePercentage(stock.sumMetrics.occupied, stock.sumMetrics.total)
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
            end
            log:debug(("caching done for %s"):format(vault.name))
            resolve()
        end)
        table.insert(tasks, p)
    end
    local p = loop.Promise.new(function(resolve, _)
        log:debug("scan buffer")
        for slot, item in pairs(stock.buffer.inv.peripheral.list()) do
            local detail = stock.buffer.inv.peripheral.getItemDetail(slot)
            local key = makeMaxCountCacheKey(item)
            maxCountCache[key] = detail.maxCount
        end
        log:debug("caching done for buffer")
        resolve()
    end)
    table.insert(tasks, p)

    loop.Promise.all(tasks):next(function() log:info("cache warmedup!") end)
end

local function init()
    -- Setup display
    setupDisplay()
    drawLoadingScreen()

    log:debug("dumb wait...")
    sleep(5)
    log:debug("done!")

    initIndex()
    initStock()

    warmingUpCache()
    
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
        :timer(cfg.updateInventoriesInterval, stateUpdateTask)
        :timer(cfg.moveItemsInterval, moveBufferItems)
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