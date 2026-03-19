local expect = require("cc.expect")

---@alias RequestId string

---@alias MessageType
---| '"request"'
---| '"response"'

---@class Request
---@field type MessageType
---@field id RequestId
---@field method string
---@field args any
---@field expectResponse boolean

---@class Response
---@field type MessageType
---@field id RequestId
---@field success boolean
---@field result any
---@field error any

---@alias Message Request | Response

---@class Pending
---@field resolve fun(...)
---@field reject fun(err: any)
---@field timer Task | nil

---@class Rpc
---@field loop Taskmaster
---@field protocol string
---@field methods table<string, fun(sender: number, ...)>
---@field pending table<RequestId, Pending>
---@field counter number
local Rpc = {}
local Rpc_mt = {__index = Rpc}

---@param loop Taskmaster The Taskmaster loop to bind to
---@param protocol string The rednet communication protocol
function Rpc.new(loop, protocol)
    local self = setmetatable({
        loop = loop,
        protocol = protocol,
        methods = {},
        pending = {}, -- Stores promises waiting for responses: { [id] = {resolve, reject, timer} }
        counter = 0,
    }, Rpc_mt)

    
    -- Listen for all RPC messages
    loop:eventListener("rednet_message", function(_, sender, message, protocol)
        if protocol ~= self.protocol then return end
        if type(message) ~= "table" then return end

        if message.type == "request" then
            self:_handleRequest(sender, message)
        elseif message.type == "response" then
            self:_handleResponse(message)
        end
    end)

    return self
end

-- Internal: handle incoming request
function Rpc:_handleRequest(sender, msg)
    -- Run in its own task so it doesn't block other RPC calls
    self.loop:addTask(function()
        local func = self.methods[msg.method]
        local result, err
        
        if func then
            -- Safe call
            local args = msg.args or {n = 0}
            local ok, res = pcall(func, sender, table.unpack(args, 1, args.n or #args))
            if ok then
                result = res
            else
                err = res
            end
        else
            err = "Method not found: " .. tostring(msg.method)
        end

        -- FIRE AND FORGET: Only send a response if the client actually expects one
        if msg.expectResponse then
            rednet.send(sender, {
                type = "response",
                id = msg.id,
                success = not err,
                result = result,
                error = err
            }, self.protocol)
        elseif err then
            printError("RPC Cast Error from " .. sender .. ": " .. tostring(err))
        end
    end)
end

-- Internal: handle incoming response
function Rpc:_handleResponse(msg)
    local pending = self.pending[msg.id]
    if not pending then return end

    -- Cancel timeout
    if pending.timer then pending.timer:remove() end

    if msg.success then
        pending.resolve(msg.result)
    else
        pending.reject(msg.error)
    end

    self.pending[msg.id] = nil
end

--- Register a function that remote peers can call
---@param name string The method name
---@param func fun(sender: number, ...) The function to execute
function Rpc:register(name, func)
    self.methods[name] = func
end

--- Call a function on a remote peer and WAIT for a response
---@param targetId number The computer ID to call
---@param method string The method name to call
---@param timeout number | nil Seconds to wait before rejecting
---@param ... any Arguments to pass to the function
---@return Promise promise Resolves with the return value of the remote function
function Rpc:call(targetId, method, timeout, ...)
    expect(1, targetId, "number")
    expect(2, method, "string")
    expect(3, timeout, "number", "nil")

    local args = table.pack(...)

    return self.loop.Promise(function(resolve, reject)
        self.counter = self.counter + 1
        local id = os.getComputerID() .. "_" .. self.counter

        self.pending[id] = {
            resolve = resolve,
            reject = reject
        }

        -- Setup timeout
        if timeout and timeout > 0 then
            self.pending[id].timer =
                self.loop:addTimer(timeout, function()
                    local p = self.pending[id]
                    if p then
                        p.reject("RPC timeout after " .. timeout .. "s")
                        self.pending[id] = nil
                    end
                    return 0
                end)
        end

        rednet.send(targetId, {
            type = "request",
            id = id,
            method = method,
            args = args,
            expectResponse = true -- Explicitly expect a response
        }, self.protocol)
    end)
end

--- Call a function on a remote peer WITHOUT waiting for a response (Fire and Forget)
---@param targetId number The computer ID to call
---@param method string The method name to call
---@param ... any Arguments to pass to the function
function Rpc:cast(targetId, method, ...)
    expect(1, targetId, "number")
    expect(2, method, "string")

    local args = table.pack(...)
    self.counter = self.counter + 1
    local id = os.getComputerID() .. "_" .. self.counter

    rednet.send(targetId, {
        type = "request",
        id = id,
        method = method,
        args = args,
        expectResponse = false -- Tells the server not to send a reply
    }, self.protocol)
end

return Rpc