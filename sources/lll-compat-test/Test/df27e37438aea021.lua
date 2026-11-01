-- HD2-Addon: mods/goose/compat-chef-test
-- HD2-Requires: chef-shared-loader >= 1.0.0
-- LLL compatibility test: a Chef Shared Loader addon.
local chef = ...
chef.log("started on %s (chef api %d, loader %s, %s); option greeting: %s", _VERSION, chef.api, chef.loader_version,
    tostring(chef.implementation), tostring(chef.options.greeting))
chef.title("LLL Compat Test")
chef.option("show", { type = "toggle", label = "Show the test line", default = true })
local ping = chef.bind("ping", "f8", "Ping")
local frames = chef.load("frames", 0)
chef.on("startup", function() chef.log("startup event; boot test says: %s", tostring(chef.shared("goose.compat.boot"))) end)
chef.after_startup(function() chef.log("after_startup ran; %d mods listed", #chef.mods()) end)
local seen_world
return {
    update = function(dt)
        frames = frames + 1
        if chef.get("show") then
            local _, h = chef.screen()
            chef.text(40, h - 140, "CHEF COMPAT OK  WORLD " .. chef.world_id() .. "  F8 PINGS", 16, chef.color(120, 255, 120, 255), 905)
        end
        if ping.pressed() then chef.notify("PING FROM THE CHEF TEST", 3); chef.log("F8 pressed (bound to %s)", ping.key()) end
        if chef.world_id() ~= seen_world then seen_world = chef.world_id(); chef.log("world %d", seen_world) end
    end,
    shutdown = function() chef.save("frames", frames); chef.log("shutdown after %d frames", frames) end,
}
