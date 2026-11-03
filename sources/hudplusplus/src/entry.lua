local Memory = require("native.access")
local Native = require("native.channel")
local Product = require("product")
local Runtime = require("core.runtime")
local Addons = require("core.addons")
local data = require("game.data")
local File = require("core.settings_file")
local Entry = {}
local RESOLVE_BUDGET = 2000
local RETIRED = { "hd2_hud_sites.txt", "hd2_hud_status.txt" }
local function remembered(directory)
    if directory == nil then
        return nil
    end
    local path = directory .. "/hd2_hud_resolved.txt"
    return {
        read = function()
            local file = io.open(path, "rb")
            if file == nil then
                return nil
            end
            local text = file:read("*a")
            file:close()
            return text
        end,
        write = function(text)
            local save = Native.save()
            if save ~= nil then
                save(path, text)
            end
        end,
    }
end
local Waiting = {}
Waiting.__index = Waiting
function Waiting:step(...)
    if self.done then
        return
    end
    local finished, okay, why, report = self.access.read:resolve(RESOLVE_BUDGET)
    if not finished then
        return
    end
    self.done = true
    if self.report_event ~= nil then
        self.report_event({
            event = "resolve",
            action = okay and "scanned" or why,
            us = report and report.spent and math.floor(report.spent) or nil,
            frames = report and report.slices or nil,
        })
    end
    if not okay then
        return
    end
    self.successor = self.build()
    return self.successor:step(...)
end
function Waiting:after() end
function Waiting:close()
    if self.successor ~= nil then
        return self.successor:close()
    end
end
function Entry.create(report_event, parts)
    local directory = os.getenv("APPDATA")
    local access = Memory.open(data, nil, { clock = Native.clock(), remember = remembered(directory) })
    local function build()
        local ready, _, report = access.read:status()
        local graph =
            { uses = data.uses, requires = data.requires, missing = ready and report and report.missing or nil }
        local product =
            Product.new(access, data.numbers, nil, report_event, Addons.load(report_event, nil, parts), graph)
        if directory ~= nil then
            File.bind(product.settings, directory .. "/hd2_hud_widgets.cfg")
        end
        return product
    end
    local _, why = access.read:status()
    if why == "resolving" then
        return setmetatable({ access = access, build = build, report_event = report_event }, Waiting), access
    end
    return build(), access
end
function Entry.start(environment, report_event, report)
    local directory = os.getenv("APPDATA")
    if directory ~= nil then
        for _, name in ipairs(RETIRED) do
            pcall(os.remove, directory .. "/" .. name)
        end
    end
    local program = Entry.create(report_event)
    return Runtime.new(program, report):install(environment)
end
return Entry
