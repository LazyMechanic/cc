-- monitor.lua
-- Storage Monitor - Display UI

local common = require("common")

-- ################################################### --
-- Configuration
-- ################################################### --

local UI_REFRESH_INTERVAL = 1
local STORAGE_REFRESH_INTERVAL = 5
local MONITOR_TEXT_SCALE = 0.5

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

-- ################################################### --
-- State
-- ################################################### --

local log
local storages = {}
local storage_data = {}
local buffer_data = {}
local current_screen = SCREEN_STORAGE_LIST
local selected_storage_index = nil

-- Display state
local display = nil
local display_width = 0
local display_height = 0
local is_monitor = false

-- Pagination state
local current_page = 1
local items_per_page = 1
local total_pages = 1

-- Click zones for interaction
local click_zones = {}

local needs_redraw = false

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
        is_monitor = true
        display.setTextScale(MONITOR_TEXT_SCALE)
        log:info("using external monitor")
    else
        display = term.current()
        is_monitor = false
        log:info("using computer terminal")
    end
    
    display_width, display_height = display.getSize()
    log:info("display size:", display_width, "x", display_height)
    
    -- Calculate items per page (header = 1, column header = 1, separator = 1, summary = 1, footer = 1)
    items_per_page = display_height - 5
    if items_per_page < 1 then
        items_per_page = 1
    end
end

-- ################################################### --
-- Drawing Utilities
-- ################################################### --

local function markDirty()
    needs_redraw = true
end

local function clearScreen()
    display.setBackgroundColor(COLOR_BG)
    display.clear()
    click_zones = {}
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
    display.write(string.rep(" ", display_width))
end

local function centerText(y, text, fg, bg)
    local x = math.floor((display_width - #text) / 2) + 1
    writeAt(x, y, text, fg, bg)
end

local function registerClickZone(x1, y1, x2, y2, action, data)
    table.insert(click_zones, {
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
    local y = display_height
    fillLine(y, COLOR_HEADER_BG)
    
    -- Page indicator
    local page_text = string.format("Page %d/%d", current_page, total_pages)
    
    -- Navigation hints
    local nav_left = ""
    local nav_right = ""
    
    if total_pages > 1 then
        if current_page > 1 then
            nav_left = "< Prev"
        end
        if current_page < total_pages then
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
        local rx = display_width - #nav_right
        writeAt(rx, y, nav_right, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
        registerClickZone(rx, y, display_width, y, "next_page", nil)
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
    writeAt(1, y + 1, string.rep("-", display_width), COLOR_SEPARATOR, COLOR_BG)
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
    layout.name_width = 12     -- "storage_XX" + padding
    layout.pct_width = 4       -- "100%"
    layout.slots_width = 11    -- "9720/9720" + padding
    layout.spacing = 3         -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = display_width - layout.name_width - layout.pct_width - layout.slots_width - layout.spacing
    layout.progress_width = math.max(6, remaining)
    
    return layout
end

local function drawStorageList()
    clearScreen()
    
    -- Header with total stats
    local total_pct = storage_data.total_percentage or 0
    local header_title = string.format("Storage Monitor [%d%%]", total_pct)
    drawHeader(header_title)
    
    -- Buffer percentage on top right
    local buffer_pct = buffer_data.percentage or 0
    local buffer_text = string.format("Buffer: %d%%", buffer_pct)
    local buffer_color = buffer_pct > 0 and getProgressColor(buffer_pct) or COLOR_HEADER_FG
    writeAt(display_width - #buffer_text, 1, buffer_text, buffer_color, COLOR_HEADER_BG)
    
    local layout = calculateStorageListLayout()
    
    -- Column headers
    local columns = {
        { name = "Storage", width = layout.name_width },
        { name = "Fill", width = layout.progress_width },
        { name = "Pct", width = layout.pct_width },
        { name = "Slots", width = layout.slots_width },
    }
    drawColumnHeaders(2, columns)
    
    -- Calculate pagination
    local num_storages = #storage_data
    total_pages = math.max(1, math.ceil(num_storages / items_per_page))
    
    if current_page > total_pages then
        current_page = total_pages
    end
    
    local start_idx = (current_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, num_storages)
    
    -- Draw storage rows (starts at line 4 now)
    local row_y = 4
    for i = start_idx, end_idx do
        local storage = storage_data[i]
        if storage then
            local x = 1
            
            -- Name column
            local name = truncateString(storage.name, layout.name_width)
            writeAt(x, row_y, padRight(name, layout.name_width), COLOR_TEXT, COLOR_BG)
            x = x + layout.name_width + 1
            
            -- Progress bar
            local progress_color = getProgressColor(storage.percentage)
            drawProgressBar(x, row_y, layout.progress_width, storage.percentage, progress_color)
            x = x + layout.progress_width + 1
            
            -- Percentage
            local pct_str = string.format("%3d%%", storage.percentage)
            writeAt(x, row_y, pct_str, getProgressColor(storage.percentage), COLOR_BG)
            x = x + layout.pct_width + 1
            
            -- Slots
            local slots_str = string.format("%d/%d", storage.occupied, storage.total)
            writeAt(x, row_y, padLeft(slots_str, layout.slots_width), COLOR_TEXT_DIM, COLOR_BG)
            
            -- Register click zone for this row
            registerClickZone(1, row_y, display_width, row_y, "select_storage", i)
            
            row_y = row_y + 1
        end
    end
    
    -- Draw empty state if no storages
    if num_storages == 0 then
        centerText(math.floor(display_height / 2), "No storages found", COLOR_TEXT_DIM, COLOR_BG)
    end
    
    -- Summary line above footer
    local summary_y = display_height - 1
    local summary = string.format("Total: %d/%d slots, %d items",
        storage_data.total_occupied or 0,
        storage_data.total_slots or 0,
        storage_data.total_items or 0)
    fillLine(summary_y, COLOR_BG)
    centerText(summary_y, summary, COLOR_TEXT_DIM, COLOR_BG)
    
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
    layout.name_width = 22      -- "create:item_vault_126" format
    layout.pct_width = 4        -- "100%"
    layout.slots_width = 9      -- "1620/1620"
    layout.items_width = 7      -- "999999"
    layout.spacing = 4          -- spaces between columns
    
    -- Progress bar gets remaining space
    local remaining = display_width - layout.name_width - layout.pct_width - layout.slots_width - layout.items_width - layout.spacing
    layout.progress_width = math.max(6, remaining)
    
    return layout
end

local function drawStorageDetail()
    clearScreen()
    
    -- Get selected storage data
    local storage = storage_data[selected_storage_index]
    if not storage then
        drawHeader("Storage Details")
        centerText(math.floor(display_height / 2), "Storage not found", COLOR_ATTENTION, COLOR_BG)
        return
    end
    
    -- Header with storage name and fill percentage
    fillLine(1, COLOR_HEADER_BG)
    
    local title = string.format("%s [%d%%]", storage.name, storage.percentage)
    centerText(1, title, COLOR_HEADER_FG, COLOR_HEADER_BG)
    
    -- Back button on top left
    local back_text = "< Back"
    writeAt(2, 1, back_text, COLOR_BUTTON_FG, COLOR_BUTTON_BG)
    registerClickZone(1, 1, #back_text + 2, 1, "back", nil)
    
    local layout = calculateStorageDetailLayout()
    
    -- Column headers
    local columns = {
        { name = "Vault", width = layout.name_width },
        { name = "Fill", width = layout.progress_width },
        { name = "Pct", width = layout.pct_width },
        { name = "Slots", width = layout.slots_width },
        { name = "Items", width = layout.items_width },
    }
    drawColumnHeaders(2, columns)
    
    -- Calculate pagination
    local num_vaults = #storage.vaults
    total_pages = math.max(1, math.ceil(num_vaults / items_per_page))
    
    if current_page > total_pages then
        current_page = total_pages
    end
    
    local start_idx = (current_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, num_vaults)
    
    -- Draw vault rows (starts at line 4 now)
    local row_y = 4
    for i = start_idx, end_idx do
        local vault = storage.vaults[i]
        if vault then
            local x = 1
            
            -- Name column
            local name = truncateString(vault.name, layout.name_width)
            writeAt(x, row_y, padRight(name, layout.name_width), COLOR_TEXT, COLOR_BG)
            x = x + layout.name_width + 1
            
            -- Progress bar
            local progress_color = getProgressColor(vault.percentage)
            drawProgressBar(x, row_y, layout.progress_width, vault.percentage, progress_color)
            x = x + layout.progress_width + 1
            
            -- Percentage
            local pct_str = string.format("%3d%%", vault.percentage)
            writeAt(x, row_y, pct_str, getProgressColor(vault.percentage), COLOR_BG)
            x = x + layout.pct_width + 1
            
            -- Slots
            local slots_str = string.format("%d/%d", vault.occupied, vault.total)
            writeAt(x, row_y, padLeft(slots_str, layout.slots_width), COLOR_TEXT_DIM, COLOR_BG)
            x = x + layout.slots_width + 1
            
            -- Items
            local items_str = tostring(vault.items)
            writeAt(x, row_y, padLeft(items_str, layout.items_width), COLOR_TEXT_DIM, COLOR_BG)
            
            row_y = row_y + 1
        end
    end
    
    -- Draw empty state if no vaults
    if num_vaults == 0 then
        centerText(math.floor(display_height / 2), "No vaults found", COLOR_TEXT_DIM, COLOR_BG)
    end
    
    -- Summary line above footer
    local summary_y = display_height - 1
    local summary = string.format("Total: %d/%d slots, %d items", 
        storage.occupied, storage.total, storage.items)
    fillLine(summary_y, COLOR_BG)
    centerText(summary_y, summary, COLOR_TEXT_DIM, COLOR_BG)
    
    -- Footer with pagination
    drawFooter()
end

-- ################################################### --
-- Event Handling
-- ################################################### --

local function handleClick(x, y)
    for _, zone in ipairs(click_zones) do
        if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
            if zone.action == "select_storage" then
                selected_storage_index = zone.data
                current_screen = SCREEN_STORAGE_DETAILS
                current_page = 1
                markDirty()
                log:debug("selected storage:", zone.data)
            elseif zone.action == "back" then
                current_screen = SCREEN_STORAGE_LIST
                selected_storage_index = nil
                current_page = 1
                markDirty()
                log:debug("back to storage list")
            elseif zone.action == "prev_page" then
                if current_page > 1 then
                    current_page = current_page - 1
                    markDirty()
                    log:debug("prev page:", current_page)
                end
            elseif zone.action == "next_page" then
                if current_page < total_pages then
                    current_page = current_page + 1
                    markDirty()
                    log:debug("next page:", current_page)
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
    if not needs_redraw then return end

    if current_screen == SCREEN_STORAGE_LIST then
        drawStorageList()
    elseif current_screen == SCREEN_STORAGE_DETAILS then
        drawStorageDetail()
    end

    needs_redraw = false
end

local function uiTask()
    local refresh_timer = os.startTimer(UI_REFRESH_INTERVAL)
    
    -- Initial render
    markDirty()

    while true do
        render()
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == refresh_timer then
            refresh_timer = os.startTimer(UI_REFRESH_INTERVAL)
        elseif event == "monitor_touch" or event == "mouse_click" then
            -- p1 = button (for mouse_click) or side (for monitor_touch)
            -- p2 = x, p3 = y
            local click_x, click_y
            if event == "monitor_touch" then
                click_x, click_y = p2, p3
            else
                click_x, click_y = p2, p3
            end
            handleClick(click_x, click_y)
        elseif event == "key" then
            local key = p1
            if key == keys.left or key == keys.pageUp then
                if current_page > 1 then
                    current_page = current_page - 1
                    markDirty()
                end
            elseif key == keys.right or key == keys.pageDown then
                if current_page < total_pages then
                    current_page = current_page + 1
                    markDirty()
                end
            elseif key == keys.backspace and current_screen == SCREEN_STORAGE_DETAILS then
                current_screen = SCREEN_STORAGE_LIST
                selected_storage_index = nil
                current_page = 1
                markDirty()
            end
        end
    end
end

-- ################################################### --
-- Data Management
-- ################################################### --

local function calculatePercentage(part, total)
    return total > 0 and math.floor((part / total) * 100) or 0
end

local function refreshStorageData()
    log:debug("refreshing storage data...")
    
    local total_slots = 0
    local total_occupied = 0
    local total_items = 0
    
    local new_storage_data = {}
    
    for i, storage in ipairs(storages) do
        local vaults = {}
        local storage_total = 0
        local storage_occupied = 0
        local storage_item_count = 0
        for j, vault in ipairs(storage:vaults()) do
            local vault_state = vault:itemState()
            local vault_total = vault_state.slots
            local vault_occupied = vault_state.occupied
            local vault_item_count = vault_state.item_count
            local vault_pct = calculatePercentage(vault_occupied, vault_total)
            
            vaults[j] = {
                name = vault:name(),
                occupied = vault_occupied,
                total = vault_total,
                percentage = vault_pct,
                items = vault_item_count,
            }

            storage_total = storage_total + vault_total
            storage_occupied = storage_occupied + vault_occupied
            storage_item_count = storage_item_count + vault_item_count
        end

        local storage_pct = calculatePercentage(storage_occupied, storage_total)
        
        total_slots = total_slots + storage_total
        total_occupied = total_occupied + storage_occupied
        total_items = total_items + storage_item_count
        
        new_storage_data[i] = {
            name = storage:name(),
            occupied = storage_occupied,
            total = storage_total,
            percentage = storage_pct,
            items = storage_item_count,
            vaults = vaults,
        }
    end
    
    -- Store totals
    new_storage_data.total_slots = total_slots
    new_storage_data.total_occupied = total_occupied
    new_storage_data.total_percentage = calculatePercentage(total_occupied, total_slots)
    new_storage_data.total_items = total_items
    
    storage_data = new_storage_data
    
    -- Refresh buffer data
    local buffer = peripheral.wrap(common.BUFFER)
    if buffer then
        local buffer_size = buffer.size()
        local buffer_occupied = 0
        for slot, item in pairs(buffer.list()) do
            buffer_occupied = buffer_occupied + 1
        end
        buffer_data = {
            occupied = buffer_occupied,
            total = buffer_size,
            percentage = calculatePercentage(buffer_occupied, buffer_size),
        }
    else
        buffer_data = {
            occupied = 0,
            total = 0,
            percentage = 0,
        }
    end
    
    markDirty()

    log:debug("data refreshed")
end

local function refreshStorageDataTask()
    while true do
        refreshStorageData()
        os.sleep(STORAGE_REFRESH_INTERVAL)
    end
end

-- ################################################### --
-- Argument Parsing
-- ################################################### --

local function parseArgs()
    local options = {
        verbose = false,
        scale = MONITOR_TEXT_SCALE,
    }
    
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--verbose" or a == "-v" then
            options.verbose = true
        elseif a == "--scale" then
            i = i + 1
            if arg[i] then
                options.scale = tonumber(arg[i]) or MONITOR_TEXT_SCALE
            end
        end
        i = i + 1
    end
    
    return options
end

-- ################################################### --
-- Loading Animation
-- ################################################### --

local SPINNER_FRAMES = { "|", "/", "-", "\\" }
local SPINNER_SPEED = 0.1

local function drawLoadingScreen(message)
    clearScreen()
    
    local center_y = math.floor(display_height / 2)
    
    -- Title
    local title = "Storage Monitor"
    centerText(center_y - 2, title, COLOR_HEADER_FG, COLOR_BG)
    
    -- Loading message
    centerText(center_y, message, COLOR_TEXT_DIM, COLOR_BG)
end

local function runWithLoading(message, task_func)
    local task_complete = false
    local task_result = nil
    
    -- Wrapper for the actual task
    local function taskWrapper()
        task_result = task_func()
        task_complete = true
    end
    
    -- Animation loop
    local function animationLoop()
        local frame = 1
        while not task_complete do
            drawLoadingScreen(message)
            
            -- Draw spinner
            local center_y = math.floor(display_height / 2)
            local spinner_x = math.floor((display_width - #message) / 2) - 2
            if spinner_x < 1 then spinner_x = 1 end
            
            writeAt(spinner_x, center_y, SPINNER_FRAMES[frame], COLOR_TEXT, COLOR_BG)
            
            frame = frame + 1
            if frame > #SPINNER_FRAMES then
                frame = 1
            end
            
            os.sleep(SPINNER_SPEED)
        end
    end
    
    parallel.waitForAny(taskWrapper, animationLoop)
    
    return task_result
end

-- ################################################### --
-- Initialization
-- ################################################### --

local function init()
    -- Setup display
    setupDisplay()
    
    log:info("initializing storages...")
    
    -- Initialize storages with loading animation
    storages = runWithLoading("Initializing storages...", function()
        return common.initStoragesReadOnly()
    end)
    
    if not storages then
        log:error("failed to initialize storages!")
        -- Show error on screen
        clearScreen()
        centerText(math.floor(display_height / 2), "Failed to initialize!", COLOR_ATTENTION, COLOR_BG)
        os.sleep(3)
        return false
    end
    
    log:info("loaded", #storages, "storages")
    
    -- Load initial data with loading animation
    runWithLoading("Loading storage data...", function()
        refreshStorageData()
        return true
    end)
    
    return true
end

-- ################################################### --
-- Main
-- ################################################### --

local function main()
    local options = parseArgs()
    MONITOR_TEXT_SCALE = options.scale
    
    -- Initialize logging
    common.initLogging({
        filename = "logs/monitor.log",
        level = options.verbose and common.LogLevel.DEBUG or common.LogLevel.INFO,
        console = false,
    })
    
    log = common.getLogger("Monitor")
    log:info("starting monitor...")

    if not init() then
        return
    end

    parallel.waitForAny(refreshStorageDataTask, uiTask)
end

-- ################################################### --
-- Entry Point
-- ################################################### --

local ok, err = pcall(main)
if not ok then
    printError("fatal error: " .. tostring(err))
end
common.shutdownLogging()