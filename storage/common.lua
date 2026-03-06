local common = {}

common.VAULT_PER_STORAGE = 6
common.BUFFER = "create:item_vault_174"
common.BUFFER_SOURCES = {
    "create_connected:inventory_access_port_2",
    "create:item_vault_140",
    "create:item_vault_142",
    "create:item_vault_144",
    "create:item_vault_146",
    "create:item_vault_148",
    "create:item_vault_150",
    "create:item_vault_152",
    "create:item_vault_154",
    "create:item_vault_156",
    "create_connected:inventory_access_port_3",
    "create_connected:inventory_access_port_1",
    "create:item_vault_136",
    "create:item_vault_158",
    "create:item_vault_160",
    "create:item_vault_162",
    "create:item_vault_164",
    "create:item_vault_166",
    "create:item_vault_168",
    "create:item_vault_170",
    "create:item_vault_172",
    "create_connected:inventory_access_port_0",
}
common.BUFFER_DESTINATIONS = {
    "create:item_vault_138",
    "create:item_vault_139",
    "create:item_vault_141",
    "create:item_vault_143",
    "create:item_vault_145",
    "create:item_vault_147",
    "create:item_vault_149",
    "create:item_vault_151",
    "create:item_vault_153",
    "create:item_vault_155",
    "create:item_vault_157",
    "create:item_vault_135",
    "create:item_vault_137",
    "create:item_vault_159",
    "create:item_vault_161",
    "create:item_vault_163",
    "create:item_vault_165",
    "create:item_vault_167",
    "create:item_vault_169",
    "create:item_vault_171",
    "create:item_vault_173",
    "create:item_vault_134",
}
common.VAULTS = {
    "create:item_vault_5",
    "create:item_vault_4",
    "create:item_vault_3",
    "create:item_vault_2",
    "create:item_vault_1",
    "create:item_vault_0",
    "create:item_vault_11",
    "create:item_vault_10",
    "create:item_vault_9",
    "create:item_vault_8",
    "create:item_vault_7",
    "create:item_vault_6",
    "create:item_vault_17",
    "create:item_vault_16",
    "create:item_vault_15",
    "create:item_vault_14",
    "create:item_vault_13",
    "create:item_vault_12",
    "create:item_vault_23",
    "create:item_vault_22",
    "create:item_vault_21",
    "create:item_vault_20",
    "create:item_vault_19",
    "create:item_vault_18",
    "create:item_vault_29",
    "create:item_vault_28",
    "create:item_vault_27",
    "create:item_vault_26",
    "create:item_vault_25",
    "create:item_vault_24",
    "create:item_vault_35",
    "create:item_vault_34",
    "create:item_vault_33",
    "create:item_vault_32",
    "create:item_vault_31",
    "create:item_vault_30",
    "create:item_vault_41",
    "create:item_vault_40",
    "create:item_vault_39",
    "create:item_vault_38",
    "create:item_vault_37",
    "create:item_vault_36",
    "create:item_vault_47",
    "create:item_vault_46",
    "create:item_vault_45",
    "create:item_vault_44",
    "create:item_vault_43",
    "create:item_vault_42",
    "create:item_vault_53",
    "create:item_vault_52",
    "create:item_vault_51",
    "create:item_vault_50",
    "create:item_vault_49",
    "create:item_vault_48",
    "create:item_vault_59",
    "create:item_vault_58",
    "create:item_vault_57",
    "create:item_vault_56",
    "create:item_vault_55",
    "create:item_vault_54",
    "create:item_vault_65",
    "create:item_vault_64",
    "create:item_vault_63",
    "create:item_vault_62",
    "create:item_vault_61",
    "create:item_vault_60",
    "create:item_vault_71",
    "create:item_vault_70",
    "create:item_vault_69",
    "create:item_vault_68",
    "create:item_vault_67",
    "create:item_vault_66",
    "create:item_vault_77",
    "create:item_vault_76",
    "create:item_vault_75",
    "create:item_vault_74",
    "create:item_vault_73",
    "create:item_vault_72",
    "create:item_vault_83",
    "create:item_vault_82",
    "create:item_vault_81",
    "create:item_vault_80",
    "create:item_vault_79",
    "create:item_vault_78",
    "create:item_vault_89",
    "create:item_vault_88",
    "create:item_vault_87",
    "create:item_vault_86",
    "create:item_vault_85",
    "create:item_vault_84",
    "create:item_vault_95",
    "create:item_vault_94",
    "create:item_vault_93",
    "create:item_vault_92",
    "create:item_vault_91",
    "create:item_vault_90",
    "create:item_vault_101",
    "create:item_vault_100",
    "create:item_vault_99",
    "create:item_vault_98",
    "create:item_vault_97",
    "create:item_vault_96",
    "create:item_vault_107",
    "create:item_vault_106",
    "create:item_vault_105",
    "create:item_vault_104",
    "create:item_vault_103",
    "create:item_vault_102",
    "create:item_vault_113",
    "create:item_vault_112",
    "create:item_vault_111",
    "create:item_vault_110",
    "create:item_vault_109",
    "create:item_vault_108",
    "create:item_vault_119",
    "create:item_vault_118",
    "create:item_vault_117",
    "create:item_vault_116",
    "create:item_vault_115",
    "create:item_vault_114",
    "create:item_vault_125",
    "create:item_vault_124",
    "create:item_vault_123",
    "create:item_vault_122",
    "create:item_vault_121",
    "create:item_vault_120",
    "create:item_vault_131",
    "create:item_vault_130",
    "create:item_vault_129",
    "create:item_vault_128",
    "create:item_vault_127",
    "create:item_vault_126",
}

-- ################################################### --
-- Log Levels
-- ################################################### --

common.LogLevel = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    NONE = 5,
}

local LEVEL_NAMES = {
    [1] = "DEBUG",
    [2] = "INFO",
    [3] = "WARN",
    [4] = "ERROR",
}

local LEVEL_COLORS = {
    [1] = colors.lightGray,
    [2] = colors.white,
    [3] = colors.yellow,
    [4] = colors.red,
}

-- ################################################### --
-- Logger Registry (Singleton)
-- ################################################### --

local LoggerRegistry = {
    _loggers = {},
    _config = {
        level = common.LogLevel.INFO,
        console = true,
        timestamp = true,
        filename = nil,
        file = nil,
    },
    _initialized = false,
}

--- Initialize the logging system (call once at program start)
--- @param options table
---   - filename: string|nil - Log file path
---   - level: number - Minimum log level
---   - console: boolean - Enable console output
---   - timestamp: boolean - Include timestamps
---   - append: boolean - Append to existing file
function LoggerRegistry.init(options)
    options = options or {}
    
    LoggerRegistry._config.level = options.level or common.LogLevel.INFO
    LoggerRegistry._config.console = options.console ~= false
    LoggerRegistry._config.timestamp = options.timestamp ~= false
    LoggerRegistry._config.filename = options.filename
    
    -- Close existing file if any
    if LoggerRegistry._config.file then
        LoggerRegistry._config.file.close()
        LoggerRegistry._config.file = nil
    end
    
    -- Open log file
    if options.filename then
        local dir = fs.getDir(options.filename)
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        
        local mode = options.append and "a" or "w"
        LoggerRegistry._config.file = fs.open(options.filename, mode)
    end
    
    LoggerRegistry._initialized = true
    LoggerRegistry._loggers = {}  -- Clear cached loggers
end

--- Shutdown logging system
function LoggerRegistry.shutdown()
    if LoggerRegistry._config.file then
        LoggerRegistry._config.file.close()
        LoggerRegistry._config.file = nil
    end
    LoggerRegistry._initialized = false
end

--- Set global log level
function LoggerRegistry.setLevel(level)
    LoggerRegistry._config.level = level
end

--- Enable/disable console output
function LoggerRegistry.setConsole(enabled)
    LoggerRegistry._config.console = enabled
end

-- ################################################### --
-- Logger Class
-- ################################################### --

local Logger = {}
Logger.__index = Logger

function Logger._new(name)
    local self = setmetatable({}, Logger)
    self._name = name
    return self
end

function Logger:_format(level, args)
    local parts = {}
    
    if LoggerRegistry._config.timestamp then
        local day = os.day()
        table.insert(parts, string.format("[Day%d %s]", day, textutils.formatTime(os.time(), true)))
    end
    
    table.insert(parts, "[" .. LEVEL_NAMES[level] .. "]")
    table.insert(parts, "[" .. self._name .. "]")
    
    local message_parts = {}
    for _, v in ipairs(args) do
        if type(v) == "table" then
            table.insert(message_parts, textutils.serialize(v))
        else
            table.insert(message_parts, tostring(v))
        end
    end
    table.insert(parts, table.concat(message_parts, " "))
    
    return table.concat(parts, " ")
end

function Logger:_log(level, ...)
    if level < LoggerRegistry._config.level then
        return
    end
    
    local args = {...}
    local message = self:_format(level, args)
    
    if LoggerRegistry._config.console then
        local old_color = term.getTextColor()
        term.setTextColor(LEVEL_COLORS[level] or colors.white)
        print(message)
        term.setTextColor(old_color)
    end
    
    if LoggerRegistry._config.file then
        LoggerRegistry._config.file.writeLine(message)
        LoggerRegistry._config.file.flush()
    end
end

function Logger:debug(...) self:_log(common.LogLevel.DEBUG, ...) end
function Logger:info(...)  self:_log(common.LogLevel.INFO, ...)  end
function Logger:warn(...)  self:_log(common.LogLevel.WARN, ...)  end
function Logger:error(...) self:_log(common.LogLevel.ERROR, ...) end

-- ################################################### --
-- Get Logger Function (Main API)
-- ################################################### --

--- Get a logger by name (creates if doesn't exist)
--- @param name string - Logger name
--- @return Logger
function common.getLogger(name)
    name = name or "root"
    
    if not LoggerRegistry._loggers[name] then
        LoggerRegistry._loggers[name] = Logger._new(name)
    end
    
    return LoggerRegistry._loggers[name]
end

-- Expose registry functions
common.initLogging = LoggerRegistry.init
common.shutdownLogging = LoggerRegistry.shutdown
common.setLogLevel = LoggerRegistry.setLevel
common.setLogConsole = LoggerRegistry.setConsole

-- ################################################### --
-- Gate
-- ################################################### --

local Gate = {}
Gate.__index = Gate

-- Logger retrieved internally, not passed
local gateLog = nil

local function getGateLog()
    if not gateLog then
        gateLog = common.getLogger("Gate")
    end
    return gateLog
end

function Gate.new(src_name, dst_name)
    assert(src_name and type(src_name) == "string")
    assert(dst_name and type(dst_name) == "string")

    local log = getGateLog()

    local self = setmetatable({}, Gate)
    self._src_name = src_name
    self._dst_name = dst_name
    self._src_inv = peripheral.wrap(src_name)
    self._dst_inv = peripheral.wrap(dst_name)
    
    if not self._src_inv then
        log:error("peripheral not found:", src_name)
        return nil
    end
    if not self._dst_inv then
        log:error("peripheral not found:", dst_name)
        return nil
    end
    
    log:debug("created gate:", src_name, "->", dst_name)
    return self
end

function Gate:sourceName()
    return self._src_name
end

function Gate:destinationName()
    return self._dst_name
end

function Gate:moveItem(slot, limit)
    return self._src_inv.pushItems(self._dst_name, slot, limit)
end

common.Gate = Gate

-- ################################################### --
-- Vault
-- ################################################### --

local Vault = {}
Vault.__index = Vault

local vaultLog = nil

local function getVaultLog()
    if not vaultLog then
        vaultLog = common.getLogger("Vault")
    end
    return vaultLog
end


function Vault.new(name)
    assert(name and type(name) == "string")

    local log = getVaultLog()
    local self = setmetatable({}, Vault)
    
    self._name = name
    self._peripheral = peripheral.wrap(self._name)
    
    if not self._peripheral then
        log:error("peripheral not found:", self._name)
        return nil
    end
    
    self._size = self._peripheral.size()
    log:debug("created vault:", self._name, "size:", self._size)
    
    return self
end

function Vault:name()
    return self._name
end

function Vault:totalSlots()
    return self._size
end

function Vault:items()
    return self._peripheral.list()
end

function Vault:itemState()
    local slots = self:totalSlots()
    local occupied = 0
    local item_count = 0

    for _, item in pairs(self:items()) do
        occupied = occupied + 1
        item_count = item_count + item.count
    end

    return {
        slots = slots,
        occupied = occupied,
        item_count = item_count,
    }
end

function Vault:occupiedSlots()
    local slots = 0
    for _, _ in pairs(self:items()) do
        slots = slots + 1
    end
    return slots
end

function Vault:availableSlots()
    return self:totalSlots() - self:occupiedSlots()
end

function Vault:getItemDetail(slot)
    return self._peripheral.getItemDetail(slot)
end

function Vault:getItemLimit(slot)
    return self._peripheral.getItemLimit(slot)
end


function Vault:getItemCount()
    local total = 0
    for _, item in pairs(self:items()) do
        total = total + item.count
    end
    return total
end

common.Vault = Vault

-- ################################################### --
-- Storage
-- ################################################### --

local Storage = {}
Storage.__index = Storage

local storageLog = nil

local function getStorageLog()
    if not storageLog then
        storageLog = common.getLogger("Storage")
    end
    return storageLog
end

function Storage.new(gate, name)
    local log = getStorageLog()
    local self = setmetatable({}, Storage)
    
    self._vaults = {}
    self._gate = gate
    self._name = name
    
    log:debug("created storage:", name)
    return self
end

function Storage:name()
    return self._name
end

function Storage:vaults()
    return self._vaults
end

function Storage:gate()
    return self._gate
end

function Storage:addVault(vault)
    table.insert(self._vaults, vault)
    getStorageLog():debug("added vault to", self._name, "- total:", #self._vaults)
end

function Storage:totalSlots()
    local size = 0
    for _, vault in ipairs(self._vaults) do
        size = size + vault:totalSlots()
    end
    return size
end

function Storage:occupiedSlots()
    local size = 0
    for _, vault in ipairs(self._vaults) do
        size = size + vault:occupiedSlots()
    end
    return size
end

function Storage:availableSlots()
    return self:totalSlots() - self:occupiedSlots()
end

function Storage:totalItems()
    local total = 0
    for _, vault in ipairs(self._vaults) do
        total = total + vault:getItemCount()
    end
    return total
end

local max_count_cache = {}
function Storage:availableItemSize(target_item)
    local log = common.getLogger("Storage")

    local available = 0
    for _, vault in ipairs(self._vaults) do
        local items = vault:items()
        local item_count = 0

        for slot, item in pairs(items) do
            item_count = item_count + 1
            if target_item.name == item.name
                and target_item.nbt == item.nbt
            then
                log:debug("vault", vault:name(), "has identical items")

                local cache_key = { item.name, item.nbt }
                if not max_count_cache[cache_key] then
                    log:debug("item limit cache miss")
                    local detail = vault:getItemDetail(slot)
                    max_count_cache[cache_key] = detail.maxCount
                end

                local item_limit = max_count_cache[cache_key]
                if item_limit then
                    local free = item_limit - item.count
                    available = available + free
                    log:debug("item limit", item_limit, "free", free, "available", available)
                end
            end

            if available >= target_item.count then
                log:debug("there is enough space in the storage", self._name, "in vault", vault:name())
                return target_item.count
            end
        end

        -- If vault can fit any amount of item (1 stack max)
        if item_count < vault:totalSlots() then
            log:debug("there is extra slots")
            return target_item.count
        end
    end

    return available
end

common.Storage = Storage

-- ################################################### --
-- Factory Function
-- ################################################### --

function common.initStorages()
    local log = common.getLogger("Init")
    log:info("initializing storages...")
    
    local storages = {}
    local current_storage = nil
    
    for _, vault_name in ipairs(common.VAULTS) do
        if not current_storage or #current_storage:vaults() >= common.VAULT_PER_STORAGE then
            local storage_idx = #storages + 1
            local name = "storage_" .. storage_idx
            local src = common.BUFFER_SOURCES[storage_idx]
            local dst = common.BUFFER_DESTINATIONS[storage_idx]
            
            log:debug("creating storage", storage_idx, name)
            
            local gate = Gate.new(src, dst)
            if not gate then
                log:error("failed to create gate for storage", storage_idx)
                return nil
            end
            
            current_storage = Storage.new(gate, name)
            table.insert(storages, current_storage)
        end
        
        local vault = Vault.new(vault_name)
        if vault then
            current_storage:addVault(vault)
        else
            log:error("failed to create vault:", vault_name)
            return nil
        end
    end
    
    log:info("initialized", #storages, "storages")
    return storages
end

--- Initialize storages without gates (for monitor)
function common.initStoragesReadOnly()
    local log = common.getLogger("Init")
    log:info("initializing storages (read-only)...")
    
    local storages = {}
    local current_storage = nil
    
    for _, vault_name in ipairs(common.VAULTS) do
        if not current_storage or #current_storage:vaults() >= common.VAULT_PER_STORAGE then
            local storage_idx = #storages + 1
            local name = "storage_" .. storage_idx
            
            current_storage = Storage.new(nil, name)  -- No gate needed
            table.insert(storages, current_storage)
        end
        
        local vault = Vault.new(vault_name)
        if vault then
            current_storage:addVault(vault)
        end
    end
    
    log:info("initialized", #storages, "storages")
    return storages
end

-- ################################################### --

return common