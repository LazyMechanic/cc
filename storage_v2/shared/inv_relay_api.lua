local Rpc = require("rpc")
local RpcApi = require("rpc_api")

-- ###################################################
-- Type definitions
-- ###################################################

---@alias ComputerId number

---@alias StorageName string

---@alias Slot number

---@class ItemData
---@field name string
---@field count number
---@field nbt number|string|nil
---@field maxCount number

---@class InventoryState
---@field items table<number, ItemData>
---@field totalSlots number

---@class ClientApi
---@field lookup fun(hostname: string): ComputerId | nil
---@field connect fun(target: RpcTarget, name: string): Promise
---@field announceState fun(target: RpcTarget, items: table<Slot, ItemData>, totalSlots: number)
---@field ping fun(target: RpcTarget): Promise
---@field onGetState fun(func: fun(sender: ComputerId): InventoryState)
---@field onPing fun(func: fun(sender: ComputerId): any)

---@class ServerApi
---@field host fun(hostname: string)
---@field getState fun(target: RpcTarget): Promise  -- Resolves to InventoryState
---@field ping fun(target: RpcTarget): Promise
---@field onConnect fun(func: fun(sender: ComputerId, name: string): any)
---@field onAnnounceState fun(func: fun(sender: ComputerId, items: table<Slot, ItemData>, totalSlots: number))
---@field onPing fun(func: fun(sender: ComputerId): any)

-- ###################################################
-- API implementation
-- ###################################################

local SCHEMAS = {
    connect = {
        args = {
            -- Name
            "string"
        },
        ret = "any",
        timeout = 5,
    },
    getState = {
        args = {},
        ret = {
            items = {
                "map",
                -- Slot
                "number",
                {
                    -- Item name
                    name = "string",
                    -- Current count
                    count = "number",
                    -- NBT tag
                    nbt = "string|nil",
                    -- Max count in stack in that slot
                    maxCount = "number",
                }
            },
            -- Slots count in vault
            totalSlots = "number",
        },
        timeout = 10,
    },
    announceState = {
        args = {
            -- Items
            {
                "map",
                -- Slot
                "number",
                {
                    -- Item name
                    name = "string",
                    -- Current count
                    count = "number",
                    -- NBT tag
                    nbt = "string|nil",
                    -- Max count in stack in that slot
                    maxCount = "number",
                }
            },
            -- Slots count in vault
            "number",
        },
        -- No return, it is a Fire & Forget cast
    },
    ping = {
        args = {},
        ret = "any",
        timeout = 1,
    },
}

local api = {}

---@param loop Taskmaster
---@param protocol string
---@return ClientApi
function api.newClient(loop, protocol)
    local rpc = Rpc.new(loop, protocol)
    local rpcApi = RpcApi.new(rpc)

    local client = {
        lookup = function(hostname) return rednet.lookup(protocol, hostname) end,

        -- Client pushes to Server
        connect = rpcApi:createCaller("connect", SCHEMAS.connect),
        announceState = rpcApi:createCaster("announceState", SCHEMAS.announceState),
        ping = rpcApi:createCaller("ping", SCHEMAS.ping),
        
        -- Client responds to Server
        onGetState = function(func) rpcApi:implementCall("getState", SCHEMAS.getState, func) end,
        onPing = function(func) rpcApi:implementCall("ping", SCHEMAS.ping, func) end,
    }
    return client
end

---@param loop Taskmaster
---@param protocol string
---@return ServerApi
function api.newServer(loop, protocol)
    local rpc = Rpc.new(loop, protocol)
    local rpcApi = RpcApi.new(rpc)

    local server = {
        host = function(hostname) return rednet.host(protocol, hostname) end,

        -- Server queries the Client
        getState = rpcApi:createCaller("getState", SCHEMAS.getState),
        ping = rpcApi:createCaller("ping", SCHEMAS.ping),
        
        -- Server listens for Client pushes
        onConnect = function(func) rpcApi:implementCall("connect", SCHEMAS.connect, func) end,
        onAnnounceState = function(func) rpcApi:implementCast("announceState", SCHEMAS.announceState, func) end,
        onPing = function(func) rpcApi:implementCall("ping", SCHEMAS.ping, func) end,
    }
    return server
end

return api