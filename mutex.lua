---@class Mutex
local Mutex = {}
local Mutex_mt = { __index = Mutex }

---@param loop Taskmaster
---@return Mutex
function Mutex.new(loop)
    local self = setmetatable({
        _locked = false,
        _waiters = 0,
        _unlockQueue = loop:createQueue(),
    }, Mutex_mt)

    return self
end

---@return boolean
function Mutex:tryLock()
    if not self._locked then 
        self._locked = true
        return true
    else
        return false
    end
end

function Mutex:lock()
    if self:tryLock() then
        return
    end

    self._waiters = self._waiters + 1
    while true do
        self._unlockQueue:pop()
        if self:tryLock() then
            self._waiters = self._waiters - 1
            return
        end
    end
end

function Mutex:unlock()
    self._locked = false

    if self._waiters > 0 then
        self._unlockQueue:push({})
    end
end

return Mutex