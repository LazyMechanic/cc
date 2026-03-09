local expect = require("cc.expect")

---@class Target
---@field id number The Computer ID to call
---@field timeout? number Custom timeout in seconds
---@alias RpcTarget number|Target

---@class Schema
---@field args table
---@field ret table
---@field timeout? number Default timeout

local RpcApi = {}
local RpcApi_mt = {__index = RpcApi}

---@param rpc Rpc The configured Rpc instance
function RpcApi.new(rpc)
    expect(1, rpc, "table")
    return setmetatable({ rpc = rpc }, RpcApi_mt)
end

--- Deep, recursive schema validator
---@param val any
---@param schema Schema
---@param path string
local function validateValue(val, schema, path)
    local schemaType = type(schema)

    if schemaType == "string" then
        local actualType = type(val)
        local match = false
        for t in schema:gmatch("[^|]+") do
            if t == "any" or actualType == t then
                match = true
                break
            end
        end
        if not match then
            return false, string.format("Expected '%s' at %s, got '%s'", schema, path, actualType)
        end
        return true

    elseif schemaType == "table" then
        if type(val) ~= "table" then
            return false, string.format("Expected table at %s, got '%s'", path, type(val))
        end

        -- Array schema: { "array", elementSchema }
        if schema[1] == "array" then
            local count = 0
            for i, v in ipairs(val) do
                local ok, err = validateValue(v, schema[2], path .. "[" .. i .. "]")
                if not ok then return false, err end
                count = i
            end
            for k, _ in pairs(val) do
                if type(k) ~= "number" or k < 1 or k > count or math.floor(k) ~= k then
                    return false, string.format("Invalid array key '%s' at %s (must be sequential integer)", tostring(k), path)
                end
            end
            return true

        -- Map schema: { "map", keySchema, valueSchema }
        elseif schema[1] == "map" then
            for k, v in pairs(val) do
                local okK, errK = validateValue(k, schema[2], path .. ".<key:" .. tostring(k) .. ">")
                if not okK then return false, errK end
                local okV, errV = validateValue(v, schema[3], path .. "[" .. tostring(k) .. "]")
                if not okV then return false, errV end
            end
            return true

        -- Object schema: { field1 = "string" }
        else
            for k, expected_schema in pairs(schema) do
                local ok, err = validateValue(val[k], expected_schema, path .. "." .. tostring(k))
                if not ok then return false, err end
            end
            return true
        end
    end

    return false, "Invalid schema definition at " .. path
end

---@param methodName string
---@param schema Schema
---@param args any
local function validateArguments(methodName, schema, args)
    if not schema then return end
    for i, expected_schema in ipairs(schema) do
        local ok, err = validateValue(args[i], expected_schema, "Argument #" .. i)
        if not ok then
            error(string.format("RPC Schema Error in '%s': %s", methodName, err), 3)
        end
    end
end

--- SERVER: Implement a method that expects a response
--- @param method string
--- @param schema Schema
--- @param func fun(sender: number, ...): table
function RpcApi:implementCall(method, schema, func)
    local argsSchema = schema and (schema.args or schema)
    local retSchema = schema and schema.ret

    self.rpc:register(method, function(sender, ...)
        local args = table.pack(...)
        validateArguments(method .. " (Args)", argsSchema, args)
        
        -- Call user function
        local result = func(sender, table.unpack(args, 1, args.n or #args))
        
        -- Validate return value before sending back
        if retSchema then
            local ok, err = validateValue(result, retSchema, "Return Value")
            if not ok then
                -- This error is caught by Rpc:_handleRequest and sent to the client cleanly!
                error(string.format("Server Implementation Error: %s", err), 0)
            end
        end

        return result
    end)
end

--- SERVER: Implement a fire-and-forget method
--- @param method string
--- @param schema Schema
--- @param func fun(sender: number, ...)
function RpcApi:implementCast(method, schema, func)
    local argsSchema = schema and (schema.args or schema)
    self.rpc:register(method, function(sender, ...)
        local args = table.pack(...)
        local ok, err = pcall(validateArguments, method .. " (Args)", argsSchema, args)
        if not ok then
            printError(err) 
            return
        end
        func(sender, table.unpack(args, 1, args.n or #args))
    end)
end

--- CLIENT: Build a client caller function
--- @param method string
--- @param schema Schema
--- @return fun(target: Target, ...)
function RpcApi:createCaller(method, schema)
    local argsSchema = schema and (schema.args or schema)
    local retSchema = schema and schema.ret
    local defaultTimeout = schema and schema.timeout

    return function(target, ...)
        expect(1, target, "number", "table")
        
        -- Parse target configuration
        local targetId, timeout
        if type(target) == "table" then
            targetId = target.id
            timeout = target.timeout or defaultTimeout
        else
            targetId = target
            timeout = defaultTimeout
        end

        local args = table.pack(...)
        validateArguments(method .. " (Args)", argsSchema, args)
        
        local promise = self.rpc:call(targetId, method, timeout, table.unpack(args, 1, args.n or #args))

        -- Intercept the promise to validate the return value
        if retSchema then
            return promise:next(function(result)
                local ok, err = validateValue(result, retSchema, "Return Value")
                if not ok then
                    -- Safely reject the promise so we don't crash the event loop
                    return self.rpc.loop.Promise.reject(string.format("RPC Client Schema Error in '%s': %s", method, err))
                end
                return result
            end)
        end

        return promise
    end
end

--- CLIENT: Build a client caster function (fire and forget)
--- @param method string
--- @param schema Schema
function RpcApi:createCaster(method, schema)
    local argsSchema = schema and (schema.args or schema)
    return function(targetId, ...)
        local args = table.pack(...)
        validateArguments(method .. " (Args)", argsSchema, args)
        self.rpc:cast(targetId, method, table.unpack(args, 1, args.n or #args))
    end
end

return RpcApi