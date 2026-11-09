-- Actual role resolver and retained screen-only tracker. No native/GUI/game access.
local project = assert(loadfile("tests/support.lua"))().project()
local Anchor = project.require("hud/anchor.lua")
local checks, cases = 0, 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, why)
    checks = checks + 1
    assert(math.abs(a - b) < 0.0000001, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function case(name, fn)
    local okay, why = pcall(fn)
    assert(okay, name .. ": " .. tostring(why))
    cases = cases + 1
end
local function fixture()
    local f =
        { values = { ["hud.anchor"] = 1 }, viewport = { width = 1920, height = 1080 }, tracker = Anchor.Tracker.new() }
    f.settings = {
        get = function(_, key)
            return f.values[key]
        end,
    }
    local function owned(x, y, unit, token)
        return {
            known = true,
            x = x,
            y = y,
            identity = 90000,
            context = 91000,
            generation = 1,
            camera = 92000,
            actor_id = 7,
            unit = unit,
            node = 4,
            token = token,
        }
    end
    f.model = {
        known = true,
        identity = 90000,
        generation = 1,
        follow_token = "same-actor-and-gun",
        aim = { known = true, first_person = false, aiming = false, switching = false },
        reticle = { known = true, x = 960, y = 540 },
        weapon = { reloading = false },
        anchors = {
            body = owned(800, 500, 10, "head"),
            weapon = owned(1000, 450, 11, "gun"),
            viewmodel = owned(1100, 550, 12, "fpv"),
        },
    }
    f.bounds = {
        weapon = { left = 60, right = 173, bottom = -142, top = -30 },
        vitals = { left = -150, right = -60, bottom = -100, top = -40 },
        central = { left = -60, right = 60, bottom = -110, top = -80 },
    }
    function f:begin(dt)
        self.tracker:begin(self.model, self.settings, self.viewport, dt)
    end
    function f:target(role)
        return assert(Anchor.target_role(self.model, self.settings, self.viewport, self.bounds[role], role))
    end
    function f:filter(role)
        return assert(self.tracker:filter(role, self:target(role)))
    end
    return f
end
case("hip head third-person gun and first-person shared sights", function()
    local f = fixture()
    eq(f:target("weapon").source, "body")
    eq(f:target("weapon").x, 800)
    f.model.aim.aiming = true
    eq(f:target("weapon").source, "weapon")
    eq(f:target("weapon").x, 1000)
    eq(f:target("vitals").source, "body")
    f.model.aim.first_person = true
    eq(f:target("weapon").source, "sights")
    eq(f:target("vitals").source, "sights")
    eq(f:target("weapon").x, 960)
    eq(f:target("vitals").x, 960)
    eq(f:target("central").source, "reticle")
    eq(f:target("central").x, 960)
    eq(Anchor.resolve(f.model, f.settings, f.viewport, f.bounds.weapon).source, "reticle", "legacy method stays pinned")
end)
case("fresh active viewmodel overrides the native first-person bit only while aiming", function()
    local f = fixture()
    f.model.aim.first_person, f.model.aim.aiming, f.model.aim.viewmodel_active = false, true, true
    eq(f:target("weapon").profile, "first_person")
    eq(f:target("weapon").source, "sights")
    eq(f:target("vitals").source, "sights")
    eq(f.model.aim.first_person, false, "derived presentation never rewrites native fact")
    f.model.aim.viewmodel_active = false
    eq(f:target("weapon").profile, "aim")
    eq(f:target("weapon").source, "weapon")
    eq(f:target("vitals").source, "body")
    f.model.aim.viewmodel_active, f.model.aim.aiming = true, false
    eq(f:target("weapon").profile, "hip")
    eq(f:target("weapon").source, "body")
    eq(f:target("vitals").source, "body")
end)
case("raw offset target precedes complete measured clamp", function()
    local f = fixture()
    f.model.aim.first_person = true
    f.values["hud.offset_x"], f.values["hud.offset_y"] = 10, 20
    f.values["hud.ads_offset_x"], f.values["hud.ads_offset_y"] = 5, 7
    eq(f:target("weapon").x, 975)
    eq(f:target("weapon").y, 513)
    f.model.anchors.viewmodel.x = 4000
    eq(f:target("weapon").x, 975, "offscreen rig coordinates cannot move the sights")
    f.model.reticle.x = 4000
    local target = f:target("weapon")
    eq(target.x, 4015)
    eq(Anchor.clamp(f.viewport, f.bounds.weapon, target).x, 1742)
    eq(Anchor.resolve_role(f.model, f.settings, f.viewport, f.bounds.weapon, "weapon").x, 1742)
end)
case("default exponential response snaps first sample and advances once per role", function()
    local f = fixture()
    f:begin(0)
    local out = f:filter("weapon")
    eq(out.x, 800)
    f.model.anchors.body.x, f.model.anchors.body.y = 1000, 600
    f:begin(0.016)
    eq(f:filter("weapon"), out, "retained output record")
    local alpha = 1 - math.exp(-0.016 / 0.08)
    near(out.x, 800 + 200 * alpha)
    near(out.y, 500 + 100 * alpha)
    local x, y = out.x, out.y
    f.model.anchors.body.x = 1800
    eq(f:filter("weapon").x, x, "a second pass cannot advance the same role")
    eq(f:filter("weapon").y, y)
    -- A distinct role receives its own first current point, not another alpha step.
    eq(f:filter("vitals").x, 1800)
end)
case("equal elapsed time has the same response at 30 60 and 144Hz", function()
    local expected = 800 + 200 * (1 - math.exp(-1 / 0.08))
    for _, rate in ipairs({ 30, 60, 144 }) do
        local f = fixture()
        f:begin(0)
        f:filter("weapon")
        f.model.anchors.body.x = 1000
        for _ = 1, rate do
            f:begin(1 / rate)
            f:filter("weapon")
        end
        near(f:filter("weapon").x, expected, rate .. "Hz")
    end
end)
case("zero elapsed time never advances while zero damping is immediate", function()
    local f = fixture()
    f:begin(0)
    f:filter("weapon")
    f.model.anchors.body.x = 1000
    for _, dt in ipairs({ 0, -1, 0 / 0 }) do
        f:begin(dt)
        eq(f:filter("weapon").x, 800)
    end
    f:begin(nil)
    eq(f:filter("weapon").x, 800)
    f.values["hud.anchor_damping_ms"] = 0
    f:begin(0)
    eq(f:filter("weapon").x, 1000)
    f.model.anchors.body.x = 1200
    f:begin(0.00001)
    eq(f:filter("weapon").x, 1200)
end)
case("stable owner blends head gun and sights source transitions", function()
    local f = fixture()
    local alpha = 1 - math.exp(-1)
    f:begin(0)
    local out = f:filter("weapon")
    f.model.aim.aiming = true
    f:begin(0.08)
    f:filter("weapon")
    near(out.x, 800 + 200 * alpha)
    eq(out.source, "weapon")
    local x = out.x
    f.model.aim.first_person = true
    f:begin(0.08)
    f:filter("weapon")
    near(out.x, x + (960 - x) * alpha)
    eq(out.source, "sights")
    x = out.x
    f.model.aim.first_person, f.model.aim.aiming = false, false
    f:begin(0.08)
    f:filter("weapon")
    near(out.x, x + (800 - x) * alpha)
    eq(out.source, "body")
end)
case("new global owners viewport camera context and choice reset immediately", function()
    for _, change in ipairs({
        "follow_token",
        "identity",
        "generation",
        "viewport",
        "camera",
        "context",
        "choice",
        "attachment",
    }) do
        local f = fixture()
        f:begin(0)
        f:filter("weapon")
        f.model.anchors.body.x = 1000
        f:begin(0.016)
        local out = f:filter("weapon")
        assert(out.x < 1000)
        f.model.anchors.body.x = 1200
        if change == "follow_token" then
            f.model.follow_token = "replacement-gun"
        elseif change == "viewport" then
            f.viewport.width = 2560
        elseif change == "choice" then
            f.values["hud.anchor"] = 2
        elseif change == "attachment" then
            f.model.anchors.body.token = "replacement-head"
        else
            local value = change == "generation" and 2 or 93000
            if change == "identity" or change == "generation" then
                f.model[change] = value
            end
            for _, p in pairs(f.model.anchors) do
                p[change] = value
            end
        end
        f:begin(0)
        eq(f:filter("weapon").x, change == "choice" and 960 or 1200, change)
    end
end)
case("unknown attachment fallback and explicit reset cannot replay old motion", function()
    local f = fixture()
    f.model.aim.aiming = true
    f:begin(0)
    local out = f:filter("weapon")
    eq(out.x, 1000)
    f.model.anchors.weapon.known = false
    f:begin(0.016)
    eq(f:filter("weapon").x, 800, "unknown gun falls back to current head immediately")
    eq(out.fallback, true)
    f.model.anchors.weapon.known, f.model.anchors.weapon.x = true, 1400
    f:begin(0)
    eq(f:filter("weapon").x, 1400)
    f.model.aim.first_person = true
    f.model.anchors.viewmodel.known = false
    f:begin(0.016)
    eq(f:filter("weapon").x, 960)
    eq(f:filter("vitals").x, 960)
    f.model.anchors.viewmodel.known, f.model.anchors.viewmodel.x = true, 1300
    f.model.reticle.x = 1300
    f:begin(0)
    eq(f:filter("weapon").x, 1300)
    eq(f:filter("vitals").x, 1300)
    f.tracker:reset()
    f.model.anchors.viewmodel.x = 1500
    f.model.reticle.x = 1500
    f:begin(0)
    eq(f:filter("weapon").x, 1500)
end)
case("unknown model invalid target and missing stable owner clear histories", function()
    local f = fixture()
    f:begin(0)
    f:filter("weapon")
    f.model.known = false
    f:begin(0.016)
    eq(f.tracker:filter("weapon", nil), nil)
    f.model.known, f.model.anchors.body.x = true, 1200
    f:begin(0)
    eq(f:filter("weapon").x, 1200)
    f.model.follow_token = nil
    f.model.anchors.body.x = 1300
    f:begin(0.016)
    eq(f:filter("weapon").x, 1300)
    f.model.anchors.body.x = 1400
    f:begin(0)
    eq(f:filter("weapon").x, 1400)
end)
case("screen choices central cues and urgent metadata are never delayed", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 300
    for _, choice in ipairs({ 2, 3 }) do
        f.values["hud.anchor"] = choice
        f.model.aim.first_person = true
        f:begin(0)
        local out = f:filter("weapon")
        eq(out.x, 960)
        f.model.reticle.x = 1000
        f:begin(0)
        eq(f:filter("weapon").x, 1000)
        f.model.reticle.x = 960
    end
    f.values["hud.anchor"] = 1
    f:begin(0)
    local center = f:filter("central")
    f.model.reticle.x = 1200
    f:begin(0)
    eq(f:filter("central").x, 1200)
    eq(f:filter("central"), center)
    eq(f.tracker:filter("invalid", {}), nil)
end)
print("anchor motion: " .. cases .. " cases / " .. checks .. " checks passed")
