local Bytes = require("native.bytes")
local X64 = require("game.x64")
local M = {}
local floor = math.floor
local NO_EVENT = 2 ^ 30
local EDX = 2
local BRANCH = {
    je = function(a, b)
        return a == b
    end,
    jne = function(a, b)
        return a ~= b
    end,
    ja = function(a, b)
        return a > b
    end,
    jae = function(a, b)
        return a >= b
    end,
    jb = function(a, b)
        return a < b
    end,
    jbe = function(a, b)
        return a <= b
    end,
    jg = function(a, b)
        return a > b
    end,
    jge = function(a, b)
        return a >= b
    end,
    jl = function(a, b)
        return a < b
    end,
    jle = function(a, b)
        return a <= b
    end,
}
local function is_reg32(o)
    return o ~= nil and o.kind == "reg" and o.w == 32
end
local function is_imm(o)
    return o ~= nil and o.kind == "imm"
end
local function is_al(o)
    return o ~= nil and o.kind == "reg" and o.w == 8 and o.n == 0 and not o.hi
end
local function has(set, n)
    return floor(set / 2 ^ n) % 2 == 1
end
local function with_reg(set, n)
    if has(set, n) then
        return set
    end
    return set + 2 ^ n
end
local function without_reg(set, n)
    if has(set, n) then
        return set - 2 ^ n
    end
    return set
end
local function body(read, entry, stops, decoder)
    local seen, list, work = {}, {}, { entry }
    while #work > 0 do
        local at = table.remove(work)
        while not seen[at] do
            local ins, why = decoder.decode(read, at)
            if ins == nil then
                return nil, string.format("%s @%x", why, at)
            end
            seen[at] = true
            list[#list + 1] = ins
            if ins.m == "ret" or ins.m == "int3" or ins.m == "ud2" then
                break
            end
            if ins.m == "jmp" then
                if ins.t ~= nil and not stops[ins.t] then
                    work[#work + 1] = ins.t
                end
                break
            end
            if X64.JCC[ins.m] and ins.t ~= nil then
                work[#work + 1] = ins.t
            end
            at = at + ins.size
        end
    end
    table.sort(list, function(x, y)
        return x.at < y.at
    end)
    return list
end
local function via_with(via, fn, arg, answer)
    local out = {}
    for k in pairs(via) do
        out[k] = true
    end
    out[string.format("%x:%s:%s", fn, tostring(arg), tostring(answer))] = true
    return out
end
local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end
local function table_key(t)
    if t == nil then
        return ""
    end
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(t[k])
    end
    return table.concat(parts, ",")
end
local function layout(code)
    if code.index == nil then
        local index, joins = {}, { [1] = true }
        for i, ins in ipairs(code) do
            index[ins.at] = i
        end
        for _, ins in ipairs(code) do
            local j = ins.t ~= nil and index[ins.t]
            if j then
                joins[j] = true
            end
        end
        code.index, code.joins = index, joins
    end
    return code.index, code.joins
end
local function walk(code, e, frame, oracle, trail, emit)
    local span0, span1 = code[1].at, code[#code].at + code[#code].size
    local index, joins = layout(code)
    local answers, effects = oracle.answers, oracle.effects
    local seen = {}
    local start_via = nil
    if trail then
        start_via = {}
    end
    local work = { { i = 1, alias = 2 ^ EDX, via = start_via, state = copy(oracle.state), answered = 0 } }
    while #work > 0 do
        local p = table.remove(work)
        local i, alias, test, asked, r8, via, last = p.i, p.alias, p.test, p.asked, p.r8, p.via, p.last
        local state, dx, r9, eax, versus, answered = p.state, p.dx, p.r9, p.eax, p.versus, p.answered
        while i ~= nil and i <= #code do
            if joins[i] then
                local key = table.concat({
                    i,
                    alias,
                    tostring(test),
                    tostring(asked),
                    tostring(r8),
                    table_key(via),
                    last and (last[1] .. ":" .. tostring(last[2])) or "",
                    table_key(state),
                    tostring(dx),
                    tostring(r9),
                    tostring(eax),
                    tostring(versus),
                    answered,
                }, "|")
                if seen[key] then
                    break
                end
                seen[key] = true
            end
            local ins = code[i]
            local m, a, b = ins.m, ins.a, ins.b
            local writes = a ~= nil and a.kind == "reg" and m ~= "cmp" and m ~= "test"
            local test_al = m == "test" and is_al(a) and is_al(b)
            if (m == "cmp" or m == "test" or m == "call") and not test_al then
                asked, versus = nil, nil
            end
            if m == "cmp" and a ~= nil and a.kind == "reg" and a.n == 0 and a.w == 32 and is_imm(b) and eax ~= nil then
                versus = b.v
            elseif writes and a.n == 0 then
                eax = nil
            end
            if writes and a.n == EDX then
                if m == "mov" and is_imm(b) then
                    dx = b.v
                elseif m == "xor" and b ~= nil and b.kind == "reg" and b.n == EDX then
                    dx = 0
                else
                    dx = nil
                end
            end
            if writes and a.n == 9 then
                if m == "mov" and is_imm(b) then
                    r9 = b.v
                elseif m == "xor" and b ~= nil and b.kind == "reg" and b.n == 9 then
                    r9 = 0
                else
                    r9 = nil
                end
            end
            if m == "cmp" and is_reg32(a) and is_imm(b) then
                test = nil
                if has(alias, a.n) then
                    test = b.v
                end
            elseif m == "test" and is_reg32(a) and is_reg32(b) and a.n == b.n then
                test = nil
                if has(alias, a.n) then
                    test = 0
                end
            elseif m == "cmp" or m == "test" then
                test = nil
            elseif m == "mov" and is_reg32(a) and is_reg32(b) then
                if has(alias, b.n) then
                    alias = with_reg(alias, a.n)
                else
                    alias = without_reg(alias, a.n)
                end
            elseif m == "ret" then
                emit("out", nil, state, answered)
                break
            end
            if writes and a.n == 8 and (a.w == 32 or a.w == 64) then
                if m == "mov" and is_imm(b) then
                    r8 = b.v
                elseif m == "xor" and b ~= nil and b.kind == "reg" and b.n == 8 and b.w == a.w then
                    r8 = 0
                elseif
                    m == "lea"
                    and a.w == 32
                    and b ~= nil
                    and b.kind == "mem"
                    and b.base ~= nil
                    and b.index == nil
                    and not b.rip
                    and b.disp >= 0
                    and has(alias, b.base)
                then
                    r8 = frame + b.disp
                else
                    r8 = nil
                end
            end
            local nexti = i + 1
            local target = ins.t
            local finished = false
            if (m == "call" or m == "jmp") and target ~= nil and (target < span0 or target >= span1) then
                if target == e.seek then
                    local out = nil
                    if r8 ~= frame + 1 then
                        out = { ins.at, r8 }
                    end
                    emit("out", out, state, answered)
                    if trail then
                        emit("via", { out, via })
                    end
                    finished = true
                else
                    if trail then
                        last = { target, r8 }
                    end
                    local effect = effects[target]
                    if effect ~= nil then
                        state = copy(state)
                        effect(state, dx, r8, r9)
                    end
                    local reply = answers[target]
                    if reply ~= nil then
                        local value = reply(state, dx, r8, r9)
                        if value ~= nil then
                            answered = answered + 1
                        end
                        if type(value) == "number" then
                            eax = value
                        elseif value == true then
                            asked = 1
                        elseif value == false then
                            asked = 0
                        end
                    end
                    if m == "jmp" then
                        emit("out", nil, state, answered)
                        finished = true
                    end
                    r8, r9 = nil, nil
                end
            elseif m == "jmp" and target ~= nil then
                nexti = index[target]
            elseif m == "jmp" then
                emit("out", nil, state, answered)
                finished = true
            end
            if finished then
                break
            end
            local judge = BRANCH[m]
            if X64.JCC[m] and target ~= nil then
                if judge ~= nil and versus ~= nil and eax ~= nil then
                    if judge(eax, versus) then
                        nexti = index[target]
                    end
                elseif judge ~= nil and (test ~= nil or asked ~= nil) then
                    local taken
                    if asked ~= nil then
                        taken = judge(asked, 0)
                    else
                        taken = judge(frame, test)
                    end
                    if taken then
                        nexti = index[target]
                    end
                else
                    local k = i - 1
                    while k >= 1 and code[k].m ~= "test" and code[k].m ~= "cmp" and code[k].m ~= "call" do
                        k = k - 1
                    end
                    local on_al = k >= 1 and code[k].m == "test" and is_al(code[k].a) and is_al(code[k].b)
                    local yes = nil
                    if m == "jne" then
                        yes = true
                    elseif m == "je" then
                        yes = false
                    end
                    local asks = trail and last ~= nil and on_al
                    local dest = index[target]
                    if dest ~= nil then
                        local v = via
                        if asks then
                            v = via_with(via, last[1], last[2], yes)
                        end
                        work[#work + 1] = {
                            i = dest,
                            alias = alias,
                            test = test,
                            asked = asked,
                            r8 = r8,
                            via = v,
                            last = last,
                            state = state,
                            dx = dx,
                            r9 = r9,
                            eax = eax,
                            versus = versus,
                            answered = answered,
                        }
                    end
                    if asks then
                        local no = nil
                        if yes ~= nil then
                            no = not yes
                        end
                        via = via_with(via, last[1], last[2], no)
                    end
                end
            end
            i = nexti
        end
    end
end
local function fixed_chamber(e, answer)
    local answers = {}
    if answer ~= nil and e.chamber ~= nil then
        answers[e.chamber] = function()
            return answer
        end
    end
    return { state = {}, answers = answers, effects = {} }
end
local function outcomes(code, e, frame, oracle)
    local set = {}
    walk(code, e, frame, oracle, false, function(k, o)
        if k ~= "out" then
            return
        end
        if o == nil then
            set["-"] = false
        else
            set[o[1] .. ":" .. tostring(o[2])] = o
        end
    end)
    return set
end
local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end
local function frames(code)
    local set, list = {}, {}
    for _, ins in ipairs(code) do
        if ins.m == "cmp" and is_reg32(ins.a) and is_imm(ins.b) and ins.b.v >= 0 then
            set[ins.b.v] = true
        end
    end
    for f in pairs(set) do
        list[#list + 1] = f
    end
    table.sort(list)
    return list
end
local function resume_asks(code, e, oracle, frame)
    local paths = {}
    walk(code, e, frame, oracle, true, function(k, v)
        if k == "via" and v[1] ~= nil and v[1][2] ~= nil then
            local t = v[1][2]
            paths[t] = paths[t] or {}
            table.insert(paths[t], v[2] or {})
        end
    end)
    local out = {}
    for t, sets in pairs(paths) do
        local all = {}
        for _, set in ipairs(sets) do
            for k in pairs(set) do
                all[k] = true
            end
        end
        local got = {}
        for k in pairs(sets[1]) do
            local common = true
            for _, set in ipairs(sets) do
                if not set[k] then
                    common = false
                end
            end
            local fn, arg, ans = k:match("^(%x+):([^:]+):(%a+)$")
            if common and ans ~= "nil" then
                local opposite = fn .. ":" .. arg .. ":" .. (ans == "true" and "false" or "true")
                if not all[opposite] then
                    local value = nil
                    if arg ~= "nil" then
                        value = tonumber(arg)
                    end
                    got[#got + 1] = { fn = tonumber(fn, 16), arg = value, answer = ans == "true" }
                end
            end
        end
        out[t] = got
    end
    return out
end
local function profile(code, e, stop_frame, oracle)
    local common = {}
    for _, o in pairs(outcomes(code, e, NO_EVENT, oracle)) do
        if o then
            common[o[1]] = true
        end
    end
    local stop, loops, skips = stop_frame, {}, {}
    for _, n in ipairs(frames(code)) do
        if n > 0 and n < stop_frame then
            local outs = outcomes(code, e, n, oracle)
            local moves = {}
            for key, o in pairs(outs) do
                if o and not common[o[1]] then
                    moves[key] = o
                end
            end
            local sure = count(outs) == 1 and count(moves) == 1
            for _, o in pairs(moves) do
                local t = o[2]
                if t ~= nil then
                    if t < n then
                        loops[#loops + 1] = { t, n }
                    elseif t >= stop_frame and sure then
                        stop = math.min(stop, n)
                    elseif t > n then
                        skips[#skips + 1] = { n, t, sure }
                    end
                end
            end
        end
    end
    local resumes = {}
    for t, g in pairs(resume_asks(code, e, oracle, 0)) do
        if t > 0 then
            resumes[t] = g
        end
    end
    return { stop = stop, loops = loops, skips = skips, resumes = resumes }
end
function M.length_reader(read, length_rva, bytes)
    bytes = bytes or Bytes
    local decoder = X64.new(bytes)
    local at, cap, cases, leaves, default = length_rva, nil, nil, nil, nil
    for _ = 1, 16 do
        local ins, why = decoder.decode(read, at)
        if ins == nil then
            return nil, why
        end
        if ins.m == "cmp" and is_imm(ins.b) then
            cap = ins.b.v
        elseif ins.m == "ja" then
            default = ins.t
        elseif ins.m == "movzx" and ins.b.kind == "mem" and ins.b.index ~= nil then
            cases = ins.b.disp
        elseif ins.m == "mov" and ins.b ~= nil and ins.b.kind == "mem" and ins.b.scale == 4 then
            leaves = ins.b.disp
        elseif ins.m == "jmp" then
            break
        end
        at = at + ins.size
    end
    if cap == nil or cases == nil or leaves == nil then
        return nil, "길이 함수 꼴이 다르다"
    end
    local function leaf(rva)
        local ins = decoder.decode(read, rva)
        if ins == nil then
            return nil
        end
        if ins.m == "mov" and ins.a.kind == "reg" and ins.a.n == 0 and is_imm(ins.b) then
            return ins.b.v
        end
        if ins.m == "xor" and ins.a.kind == "reg" and ins.b.kind == "reg" and ins.a.n == ins.b.n then
            return 0
        end
        return nil
    end
    local frames = function(id)
        local idx = id - 1
        if idx < 0 or idx > cap then
            if default == nil then
                return nil
            end
            return leaf(default)
        end
        local case = bytes.u8(read(cases + idx, 1), 0)
        if case == nil then
            return nil
        end
        local slot = bytes.u32(read(leaves + case * 4, 4), 0)
        if slot == nil then
            return nil
        end
        return leaf(slot)
    end
    return { frames = frames, count = cap }
end
local function script_of(read, e, id, count, bytes, decoder)
    local idx = id - 1
    if idx < 0 or idx > count then
        return nil, "번호 밖"
    end
    local at = bytes.u32(read(e.jump_table + 4 * idx, 4), 0)
    if at == nil then
        return nil, "점프표 읽기 실패"
    end
    for _ = 1, 64 do
        local ins, why = decoder.decode(read, at)
        if ins == nil then
            return nil, why
        end
        if ins.m == "call" and ins.t ~= nil then
            return ins.t
        end
        if ins.m == "ret" or ins.m == "jmp" then
            return nil, "토막에 call 이 없다"
        end
        at = at + ins.size
    end
    return nil, "토막이 길다"
end
function M.ability(read, e, id, lengths, bytes)
    bytes = bytes or Bytes
    local decoder = X64.new(bytes)
    local fn, why = script_of(read, e, id, lengths.count, bytes, decoder)
    if fn == nil then
        return nil, why
    end
    local code
    code, why = body(read, fn, { [e.seek] = true }, decoder)
    if code == nil then
        return nil, why
    end
    local stop_frame = lengths.frames(id)
    if stop_frame == nil or stop_frame == 0 then
        return nil, "길이 없음"
    end
    local asks_chamber = false
    for _, ins in ipairs(code) do
        if (ins.m == "call" or ins.m == "jmp") and ins.t == e.chamber then
            asks_chamber = true
        end
    end
    local paths = {}
    if asks_chamber then
        paths.tactical = profile(code, e, stop_frame, fixed_chamber(e, true))
        paths.empty = profile(code, e, stop_frame, fixed_chamber(e, false))
    else
        paths.only = profile(code, e, stop_frame, fixed_chamber(e, nil))
    end
    return { script = fn, ["end"] = stop_frame, paths = paths, code = code, frames = frames(code) }
end
function M.calling_frame(read, e, id, lengths, targets, bytes)
    bytes = bytes or Bytes
    local decoder = X64.new(bytes)
    local fn, why = script_of(read, e, id, lengths.count, bytes, decoder)
    if fn == nil then
        return nil, why
    end
    local stops = { [e.seek] = true }
    for target in pairs(targets) do
        stops[target] = true
    end
    local code
    code, why = body(read, fn, stops, decoder)
    if code == nil then
        return nil, why
    end
    local calls = false
    for _, ins in ipairs(code) do
        if (ins.m == "call" or ins.m == "jmp") and ins.t ~= nil and targets[ins.t] then
            calls = true
        end
    end
    if not calls then
        return false
    end
    local oracle = { state = {}, answers = {}, effects = {} }
    for target in pairs(targets) do
        oracle.effects[target] = function(state)
            state.called = true
        end
    end
    local tries = { 0 }
    for _, c in ipairs(frames(code)) do
        tries[#tries + 1] = c
        tries[#tries + 1] = c + 1
    end
    table.sort(tries)
    for _, frame in ipairs(tries) do
        local called = false
        walk(code, e, frame, oracle, false, function(kind, _, state)
            if kind == "out" and state.called then
                called = true
            end
        end)
        if called then
            return frame
        end
    end
    return false
end
local function rounds_of(s, k)
    if k == 0 then
        return s.r0
    end
    return s.r1
end
local function set_rounds(s, k, v)
    if k == 0 then
        s.r0 = v
    else
        s.r1 = v
    end
end
local function capacity_of(s, k)
    if k == 0 then
        return floor(s.cap0)
    end
    return floor(s.cap1)
end
local function threshold_of(s, k)
    local t = floor(k == 0 and s.thr0 or s.thr1)
    if t == 0 then
        return capacity_of(s, k)
    end
    return t
end
local function chamber_adjust(s)
    if s.chambered ~= 0 and s.chamber ~= 0 then
        return 1
    end
    return 0
end
local function feeds_from_pack(s)
    return s.from_pack ~= 0 and s.pack ~= nil
end
local function reserve_of(s)
    if feeds_from_pack(s) then
        return s.reserve + s.pack
    end
    return s.reserve
end
local function assisted(s)
    return s.need ~= nil and s.worn ~= nil and reserve_of(s) <= 0
end
local function has_reserve(s)
    if reserve_of(s) > 0 then
        return true
    end
    return assisted(s) and s.worn >= s.need
end
local any_bit = Bytes.any_bit
local function set_bits(value, mask, on)
    for i = 0, 31 do
        local b = 2 ^ i
        if floor(mask / b) % 2 == 1 then
            local set = floor(value / b) % 2 == 1
            if on and not set then
                value = value + b
            elseif not on and set then
                value = value - b
            end
        end
    end
    return value
end
local function total_of(s)
    if s.same ~= 0 then
        return s.r0 + s.r1
    end
    return rounds_of(s, s.sel)
end
local function total_capacity(s)
    if s.same ~= 0 then
        return capacity_of(s, 0) + capacity_of(s, 1)
    end
    return capacity_of(s, s.sel)
end
local function room(s)
    local k = s.sel
    if rounds_of(s, k) + chamber_adjust(s) < threshold_of(s, k) then
        return true
    end
    if s.same ~= 0 then
        return rounds_of(s, 1 - k) + chamber_adjust(s) < threshold_of(s, 1 - k)
    end
    return false
end
local function rounds_rules(e)
    local answers, effects = {}, {}
    local function answer(name, fn)
        if e[name] ~= nil then
            answers[e[name]] = fn
        end
    end
    local function effect(name, fn)
        if e[name] ~= nil then
            effects[e[name]] = fn
        end
    end
    answer("chamber", function(s)
        return s.chamber ~= 0
    end)
    answer("mag_full", function(s)
        return rounds_of(s, s.sel) >= capacity_of(s, s.sel) - s.chambered
    end)
    answer("all_full", function(s)
        return total_of(s) >= total_capacity(s) - s.chambered
    end)
    local function reloadable(s)
        return has_reserve(s) and room(s)
    end
    answer("can_reload", reloadable)
    answer("reloadable", reloadable)
    answer("room", room)
    answer("empty", function(s)
        return rounds_of(s, s.sel) <= 0
    end)
    answer("count", function(s, n)
        if n == 0 then
            return rounds_of(s, s.sel)
        end
        if n == 1 then
            return total_of(s)
        end
        if n == 2 then
            return reserve_of(s)
        end
        if n == 3 then
            return capacity_of(s, s.sel) - rounds_of(s, s.sel)
        end
        return nil
    end)
    effect("insert", function(s)
        local k = s.sel
        if s.same ~= 0 and rounds_of(s, k) == capacity_of(s, k) then
            k = 1 - k
            s.sel = k
        end
        local add = s.amount
        if s.chambered ~= 0 and s.chamber == 0 then
            add = add - 1
        end
        set_rounds(s, k, rounds_of(s, k) + add)
        if assisted(s) then
            if s.worn ~= 0 then
                s.worn = s.worn - s.need
            end
        elseif feeds_from_pack(s) then
            s.pack = s.pack - 1
        else
            s.reserve = s.reserve - s.amount
        end
    end)
    effect("cock", function(s)
        s.chamber = 1
    end)
    answer("stage_bit", function(s, _, mask)
        if mask == nil then
            return nil
        end
        return any_bit(s.stage, mask)
    end)
    effect("set_stage_bit", function(s, _, mask, on)
        if mask ~= nil and on ~= nil then
            s.stage = set_bits(s.stage, mask, on ~= 0)
        end
    end)
    effect("switch_kind", function(s)
        s.sel = 1 - s.sel
    end)
    return answers, effects
end
function M.play(e, facts, path_name, start, state)
    local code, frame_list, path = facts.code, facts.frames, facts.paths and facts.paths[path_name]
    if code == nil or frame_list == nil or path == nil then
        return nil, "사실 없음"
    end
    local answers, effects = rounds_rules(e)
    local common = {}
    for _, o in pairs(outcomes(code, e, NO_EVENT, fixed_chamber(e, nil))) do
        if o then
            common[o[1]] = true
        end
    end
    local acting = { 0 }
    for _, x in ipairs(frame_list) do
        if x > 0 then
            acting[#acting + 1] = x
        end
    end
    local segments, from, f, first = {}, start, start, true
    local visited = {}
    while true do
        local n = nil
        for _, x in ipairs(acting) do
            if x >= f and x < path.stop and not (first and x == start) then
                n = x
                break
            end
        end
        if n == nil then
            segments[#segments + 1] = { from, path.stop }
            return segments
        end
        local here = n .. "|" .. tostring(first) .. "|" .. table_key(state)
        if visited[here] then
            return nil, "되풀이"
        end
        visited[here] = true
        local ends, most = {}, -1
        walk(code, e, n, { state = state, answers = answers, effects = effects }, false, function(k, v, st, answered)
            if k ~= "out" then
                return
            end
            local target = nil
            if v ~= nil and not common[v[1]] then
                target = v[2] or false
            end
            if answered > most then
                ends, most = {}, answered
            end
            if answered == most then
                ends[tostring(target) .. "|" .. table_key(st)] = { target, st }
            end
        end)
        local kinds, target, after = 0, nil, nil
        for _, got in pairs(ends) do
            kinds = kinds + 1
            target, after = got[1], got[2]
        end
        if kinds ~= 1 then
            return nil, "갈림"
        end
        if target == false then
            return nil, "목적지 모름"
        end
        state = after
        if target == nil then
            f = n + 1
        elseif target >= path.stop then
            segments[#segments + 1] = { from, n }
            return segments
        else
            segments[#segments + 1] = { from, n }
            from, f = target, target
        end
        first = false
    end
end
local function locate(arcs, frame)
    for index, arc in ipairs(arcs) do
        local played, total = nil, 0
        for k = 1, #arc, 2 do
            if played == nil and frame < arc[k + 1] then
                played = total + math.max(frame - arc[k], 0)
            end
            total = total + arc[k + 1] - arc[k]
        end
        if played ~= nil or index == #arcs then
            return index, played or total, total
        end
    end
    return nil
end
local function reload_route(paths, chamber)
    if paths.tactical ~= nil and chamber ~= nil then
        return chamber ~= 0 and "tactical" or "empty"
    end
    if paths.only ~= nil then
        return "only"
    end
    return nil
end
local function arcs_of(path)
    local stop, cuts = path.stop, { [0] = true }
    cuts[path.stop] = true
    for _, loop in ipairs(path.loops) do
        if loop[2] <= stop then
            cuts[loop[1]], cuts[loop[2]] = true, true
        end
    end
    local edges = {}
    for frame in pairs(cuts) do
        edges[#edges + 1] = frame
    end
    table.sort(edges)
    local skips = {}
    for _, skip in ipairs(path.skips) do
        if skip[3] then
            skips[#skips + 1] = skip
        end
    end
    table.sort(skips, function(x, y)
        return x[1] < y[1]
    end)
    local arcs = {}
    for k = 1, #edges - 1 do
        local from, to, arc = edges[k], edges[k + 1], {}
        for _, skip in ipairs(skips) do
            if skip[1] >= from and skip[1] < to then
                arc[#arc + 1], arc[#arc + 2] = from, skip[1]
                from = math.min(skip[2], to)
            end
        end
        if from < to then
            arc[#arc + 1], arc[#arc + 2] = from, to
        end
        if #arc > 0 then
            arcs[#arcs + 1] = arc
        end
    end
    return arcs
end
local function bolt_of(path, mag_full)
    if mag_full == nil then
        return nil
    end
    local bolt = nil
    for frame, asks in pairs(path.resumes) do
        for _, ask in ipairs(asks) do
            if ask.fn == mag_full and ask.answer == true and (bolt == nil or frame < bolt) then
                bolt = frame
            end
        end
    end
    return bolt
end
local function step_of(path, frame, bolt)
    if path == "tactical" or path == "only" then
        return path
    end
    if path ~= "empty" then
        return nil
    end
    if bolt ~= nil and frame >= bolt then
        return "chamber"
    end
    return "empty"
end
local function moves_on_state(path)
    if #path.loops > 0 then
        return true
    end
    for _, skip in ipairs(path.skips) do
        if not skip[3] then
            return true
        end
    end
    return false
end
local function follow(plan, k, last, frame)
    local seg = plan[k]
    if frame >= last and frame >= seg[1] and frame <= seg[2] then
        return k
    end
    for j = k + 1, #plan do
        if frame >= plan[j][1] and frame <= plan[j][2] then
            return j
        end
    end
    return nil
end
local function plan_played(plan, k, frame)
    local played, total = 0, 0
    for j, seg in ipairs(plan) do
        if j < k then
            played = played + seg[2] - seg[1]
        end
        if j == k then
            played = played + math.min(math.max(frame - seg[1], 0), seg[2] - seg[1])
        end
        total = total + seg[2] - seg[1]
    end
    return played, total
end
function M.advance(entry, facts, span, entity, ability, frame, chamber, state_of)
    if facts == nil or entity == nil or ability == nil or frame == nil then
        return nil, nil, nil
    end
    local events = {}
    local same = span ~= nil and span.entity == entity and span.ability == ability
    local rerun = not same
    if not same then
        local path = reload_route(facts.paths, chamber)
        span = { entity = entity, ability = ability, path = path }
        if path ~= nil then
            span.bolt = bolt_of(facts.paths[path], entry.mag_full)
        end
    elseif span.plan ~= nil then
        local k = follow(span.plan, span.seg, span.frame, frame)
        if k == nil then
            span.plan, rerun, events.replanned = nil, true, true
        else
            span.seg = k
        end
    else
        rerun = frame < span.frame
    end
    span.frame = frame
    if span.path == nil then
        return span, nil, events
    end
    local path = facts.paths[span.path]
    if rerun and moves_on_state(path) then
        local state, plan = state_of(), nil
        if state ~= nil then
            plan = M.play(entry, facts, span.path, math.floor(frame), state)
        end
        if plan ~= nil then
            span.plan, span.seg, span.arcs = plan, 1, nil
            events.planned = true
        else
            events.plan_failed = true
        end
    end
    local played, total
    if span.plan ~= nil then
        played, total = plan_played(span.plan, span.seg, frame)
        if rerun then
            span.base = played
        end
    else
        span.arcs = span.arcs or arcs_of(path)
        local index
        index, played, total = locate(span.arcs, frame)
        if rerun or index ~= span.arc then
            span.arc, span.base = index, rerun and played or 0
        end
    end
    return span,
        { step = step_of(span.path, frame, span.bolt), elapsed = played - span.base, length = total - span.base },
        events
end
local ROUNDS_KEYS = {
    "r0",
    "r1",
    "sel",
    "cap0",
    "cap1",
    "thr0",
    "thr1",
    "kind0",
    "kind1",
    "chambered",
    "reserve",
    "amount",
    "from_pack",
    "stage",
    "pack",
    "need",
    "worn",
}
local ROUNDS_REQUIRED = 14
function M.rounds_state(v)
    local state = {}
    for index = 1, ROUNDS_REQUIRED do
        local key = ROUNDS_KEYS[index]
        if type(v[key]) ~= "number" then
            return nil
        end
        state[key] = v[key]
    end
    if type(v.chamber) ~= "number" then
        return nil
    end
    state.chamber = v.chamber ~= 0 and 1 or 0
    state.same = state.kind0 == state.kind1 and 1 or 0
    state.kind0, state.kind1 = nil, nil
    if state.chambered ~= 0 then
        state.chambered = 1
    end
    if state.from_pack ~= 0 then
        if v.pack == nil then
            return nil
        end
        state.from_pack = 1
        state.pack = v.pack
    end
    state.need = v.need
    if state.need ~= nil then
        state.worn = v.worn
    end
    return state
end
local CODE_CHUNK = 4096
local function code_reader(read, game)
    local chunks = {}
    return function(rva, count)
        local base = rva - rva % CODE_CHUNK
        if rva + count <= base + CODE_CHUNK then
            local text = chunks[base]
            if text == nil then
                text = read:text(game + base, CODE_CHUNK) or false
                chunks[base] = text
            end
            if text then
                return string.sub(text, rva - base + 1, rva - base + count)
            end
        end
        return read:text(game + rva, count)
    end
end
local lengths = nil
local function lengths_of(span, n, bytes)
    if lengths == nil then
        lengths = M.length_reader(span, n.length, bytes) or false
    end
    return lengths
end
function M.calling_frame_in(read, n, id, targets)
    local game = read:module("game")
    if game == nil then
        return nil
    end
    local span = code_reader(read, game)
    local cap = lengths_of(span, n, read.bytes)
    if not cap then
        return false
    end
    return M.calling_frame(span, n, id, cap, targets, read.bytes) or false
end
local walked = {}
function M.timeline(read, state, v, n, state_of)
    if type(v.ability) ~= "number" or type(v.frame) ~= "number" or v.entity == nil then
        state.span = nil
        return nil
    end
    local facts = walked[v.ability]
    if facts == nil then
        local game = read:module("game")
        if game == nil then
            return nil
        end
        local span = code_reader(read, game)
        local cap = lengths_of(span, n, read.bytes)
        facts = cap and M.ability(span, n, v.ability, cap, read.bytes) or false
        walked[v.ability] = facts
    end
    if facts == false then
        return nil
    end
    local result
    state.span, result = M.advance(n, facts, state.span, v.entity, v.ability, v.frame, v.chamber, state_of)
    return result
end
return M
