local Rpc = require("rpc")
local RpcApi = require("rpc_api")

-- ###################################################
-- Type definitions
-- ###################################################

---@alias ComputerId number

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

---@class Api
---@field client ClientApi
---@field server ServerApi

-- ###################################################
-- API implementation
-- ###################################################

---@param loop Taskmaster
---@return Api
return function(loop)
    local protocol = "storage_vault_relay"

    local rpc = Rpc.new(loop, protocol)
    local rpcApi = RpcApi.new(rpc)

    local schemas = {
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

    return {
        --- Methods that the CLIENT machine interacts with
        client = {
            lookup = function(hostname) return rednet.lookup(protocol, hostname) end,
            
            -- Client pushes to Server
            connect = rpcApi:createCaller("connect", schemas.connect),
            announceState = rpcApi:createCaster("announceState", schemas.announceState),
            ping = rpcApi:createCaller("ping", schemas.ping),
            
            -- Client responds to Server
            onGetState = function(func) rpcApi:implementCall("getState", schemas.getState, func) end,
            onPing = function(func) rpcApi:implementCall("ping", schemas.ping, func) end,
        },
        
        --- Methods that the SERVER machine interacts with
        server = {
            host = function(hostname) return rednet.host(protocol, hostname) end,

            -- Server queries the Client
            getState = rpcApi:createCaller("getState", schemas.getState),
            ping = rpcApi:createCaller("ping", schemas.ping),
            
            -- Server listens for Client pushes
            onConnect = function(func) rpcApi:implementCall("connect", schemas.connect, func) end,
            onAnnounceState = function(func) rpcApi:implementCast("announceState", schemas.announceState, func) end,
            onPing = function(func) rpcApi:implementCall("ping", schemas.ping, func) end,
        }
    }
end