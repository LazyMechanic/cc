local pp = require("cc.pretty")

local self_update = {}

self_update.PROTOCOL = "self_update"

function self_update.waitRequest()
    local src_id, msg = rednet.receive(self_update.PROTOCOL)
    print(("Received message from %d: %s"):format(src_id, pp.render(pp.pretty(msg))))
end

return self_update