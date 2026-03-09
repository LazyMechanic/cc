local common = {}

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
-- Schema validation
-- ################################################### --

--[[ Schema example:
local userSchema = {
    id = "string",
    age = "number",
    tags = {"array", "string"},
    metadata = {"map", "string", "string"}, -- keys are strings, values are strings
    owner = {
        name = "string",
        age = "number"
    },
    permissions = {"map", "string", {"array", "string"}} -- map values are arrays
}

local validPayload = {
    id = "abc123",
    age = 42,
    tags = {"admin", "editor"},
    metadata = {foo="bar", baz="qux"},
    owner = {name="Alice", age=30},
    permissions = {
        files = {"read", "write"},
        settings = {"read"}
    }
}

local invalidPayload = {
    id = "abc123",
    age = "not a number", -- invalid type
    tags = {"admin", "editor"},
    metadata = {foo="bar"},
    owner = {name="Alice", age=30},
    permissions = {files = {"read"}}
}

print(validateSchema(validPayload, userSchema))   -- true
print(validateSchema(invalidPayload, userSchema)) -- false
]]
function common.validateSchema(data, schema)
    -- primitive schema (string type)
    if type(schema) == "string" then
        return type(data) == schema
    end

    -- schema must be a table now
    if type(schema) ~= "table" then
        return false
    end

    -- array schema: {"array", itemSchema}
    if schema[1] == "array" then
        if type(data) ~= "table" then
            return false
        end
        local itemSchema = schema[2]
        for i = 1, #data do
            if not common.validateSchema(data[i], itemSchema) then
                return false
            end
        end
        return true
    end

    -- map schema: {"map", keySchema, valueSchema}
    if schema[1] == "map" then
        if type(data) ~= "table" then
            return false
        end
        local keySchema = schema[2]
        local valueSchema = schema[3]
        for k, v in pairs(data) do
            if not common.validateSchema(k, keySchema) then
                return false
            end
            if not common.validateSchema(v, valueSchema) then
                return false
            end
        end
        return true
    end

    -- object schema (nested fields)
    if type(data) ~= "table" then
        return false
    end
    for field, fieldSchema in pairs(schema) do
        if data[field] == nil then
            return false
        end
        if not common.validateSchema(data[field], fieldSchema) then
            return false
        end
    end

    return true
end

---comment generate unique ID
---@return string ID
function common.generateID()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local ans = string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
    return ans
end

---comment open rednet on all sides
---@return table sides
function common.openRednet()
    local sides = {"top","bottom","left","right","front","back"}
    local opened = {}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then
                rednet.open(side)
                table.insert(opened, side)
            end
        end
    end

    return opened
end

return common