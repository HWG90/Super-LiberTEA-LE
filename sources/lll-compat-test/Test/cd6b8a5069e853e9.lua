-- HD2-Addon: mods/goose/compat-bml-test
-- LLL compatibility test: a mod written for Boot Mod Loader.
local B = rawget(_G, "CowboyBingusModLoader")
local log = B and B.open_log and B.open_log("compat_bml_test.log")
local function say(text) if log then log:write(os.date("%H:%M:%S ") .. text .. "\n"); if log.flush then log:flush() end end end
say("started; on_shutdown " .. type(B and B.on_shutdown) .. ", on_update " .. type(B and B.on_update)
    .. ", game " .. tostring(B and B.game and B.game.build_identifier))
local M, K = rawget(_G, "ModOptionsMenu"), rawget(_G, "ModBindingsMenu")
say("ModOptionsMenu " .. tostring(M and M.version) .. ", ModBindingsMenu " .. tostring(K and K.version))
if M then say("option registered: " .. tostring(M.register_option("compat_bml.speed",
    { type = "slider", label = "Test speed", min = 0, max = 10, step = 1, default = 5, mod = "LLL Compat BML" }))) end
if K then say("binding registered: " .. tostring(K.register_binding("compat_bml.ping", "Ping", nil, { default = "f7" }))) end
local frames = 0
if B and B.on_update then
    B.on_update("compat-bml-test", function(dt)
        frames = frames + 1
        if K and K.is_down("compat_bml.ping") then say("F7 pressed; speed option = " .. tostring(M and M.get("compat_bml.speed"))) end
    end)
end
if B and B.on_shutdown then B.on_shutdown(function() say("on_shutdown after " .. frames .. " frames") end) end
return true
