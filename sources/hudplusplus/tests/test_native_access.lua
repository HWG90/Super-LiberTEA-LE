-- Run from this source folder: luajit tests/test_native_access.lua
local root = arg[1] or "."
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function fixture(mode, remember)
    local count = { signatures = 0, decode = 0, close = 0, resolve = 0, encode = 0 }
    local report = mode == "bad-report" and {} or { exe = { sha = "exe" }, game = { sha = "game" } }
    local channel = {
        counted = {},
        module = function(_, name)
            return name == "game" and 4096 or 8192
        end,
        pinned = function()
            return mode == "pinned", report
        end,
        load = function()
            return 19
        end,
    }
    local native = {
        bytes = {},
        bind = function()
            return {
                swap = function()
                    return true
                end,
                call = function()
                    return 7
                end,
            }
        end,
    }
    local signatures = {
        decode = function(text, key)
            count.decode = count.decode + 1
            check(key == "exe game 123", "cache key changed")
            check(text == (remember and "cached" or nil), "remembered text was lost")
            if mode == "cached" then
                return { answer = 42 }, {}
            end
        end,
        close = function()
            count.close = count.close + 1
        end,
        resolve = function(got_channel)
            count.resolve = count.resolve + 1
            check(got_channel == channel, "resolver received a different channel")
            return { answer = 84 }, {}
        end,
        encode = function(key, found)
            count.encode = count.encode + 1
            check(key == "exe game 123" and found.answer == 84, "scan cache contents changed")
            return "saved"
        end,
    }
    local dependencies = {
        ["native.channel"] = { channel = { layout = function() end, strided = function() end } },
        ["native.memory"] = native,
        ["native.bytes"] = {},
    }
    local loader = assert(loadfile(root .. "/src/native/access.lua"))
    setfenv(
        loader,
        setmetatable({
            require = function(name)
                if name == "native.signatures" then
                    count.signatures = count.signatures + 1
                    return signatures
                end
                return assert(dependencies[name], name)
            end,
        }, { __index = _G })
    )
    local memory = loader()
    check(count.signatures == 0, "module import loaded the signature resolver")
    local baked = { pin = { exe = "exe", game = "game" }, digest = 123, calls = {}, numbers = { answer = 11 } }
    baked.refuse_unpinned = mode == "refused"
    local access = memory.open(baked, {
        open = function()
            return channel
        end,
    }, { remember = remember })
    return access, count, baked
end

local access, count = fixture("pinned")
check(access.read:status() == true, "pinned build did not open")
check(access.read:value(100) == 19, "pinned memory reader did not open")
check(count.signatures == 0, "pinned build loaded the unused signature resolver")

access, count = fixture("refused")
local ready, why = access.read:status()
check(not ready and why == "unsupported-build", "unpinned build refusal changed")
check(count.signatures == 0, "refused build loaded the signature resolver")

access, count = fixture("bad-report")
ready, why = access.read:status()
check(not ready and why == "pin", "incomplete fingerprint report changed behavior")
check(count.signatures == 0, "incomplete fingerprint report loaded the resolver")

local saved
local remember = {
    read = function()
        return "cached"
    end,
    write = function(text)
        saved = text
    end,
}
local baked
access, count, baked = fixture("cached", remember)
local _, _, report = access.read:status()
check(access.read:status() == true and baked.numbers.answer == 42, "cached values did not settle")
check(report.resolve == "remembered", "cache source was not recorded")
check(count.signatures == 1 and count.decode == 1 and count.close == 1, "cache resolver lifecycle changed")
check(count.resolve == 0 and count.encode == 0, "cached values triggered a scan or rewrite")

access, count, baked = fixture("scan", remember)
ready, why = access.read:status()
check(not ready and why == "resolving", "fallback scan did not defer resolution")
local completed
completed, ready, why, report = access.read:resolve(1)
check(completed and ready and why == nil, "fallback scan did not complete")
check(baked.numbers.answer == 84 and report.resolve == "scanned", "scanned values did not settle")
check(
    count.signatures == 1 and count.decode == 1 and count.resolve == 1 and count.close == 1,
    "scan resolver lifecycle changed"
)
check(count.encode == 1 and saved == "saved", "scan result was not cached")

print("native.access: " .. checks .. " checks passed")
