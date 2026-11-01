-- HD2-Boot: mods/goose/compat-boot-test
-- LLL compatibility test: a boot-style script in its own environment.
local frames = 0
function init() chef.log("boot-style init"); chef.share("goose.compat.boot", "boot-style init ran") end
function update(dt) frames = frames + 1 end
function shutdown() chef.log("boot-style shutdown after %d frames", frames) end
