local Bytes = require("native.bytes")
local M = {}
local floor = math.floor
local JCC = { "jo", "jno", "jb", "jae", "je", "jne", "jbe", "ja", "js", "jns", "jp", "jnp", "jl", "jge", "jle", "jg" }
local ALU = { "add", "or", "adc", "sbb", "and", "sub", "xor", "cmp" }
local SHIFT = { "rol", "ror", "rcl", "rcr", "shl", "shr", "sal", "sar" }
local GRP3 = { "test", "test", "not", "neg", "mul", "imul", "div", "idiv" }
local GRP5 = { "inc", "dec", "call", "call", "jmp", "jmp", "push" }
M.JCC = {}
for _, name in ipairs(JCC) do
    M.JCC[name] = true
end
local TWO = {
    [0x10] = "movu",
    [0x11] = "movu",
    [0x12] = "movl",
    [0x13] = "movl",
    [0x14] = "unpckl",
    [0x15] = "unpckh",
    [0x16] = "movh",
    [0x17] = "movh",
    [0x18] = "prefetch",
    [0x1F] = "nop",
    [0x28] = "movaps",
    [0x29] = "movaps",
    [0x2A] = "cvtsi2",
    [0x2C] = "cvtt",
    [0x2D] = "cvt",
    [0x2E] = "ucomis",
    [0x2F] = "comis",
    [0x51] = "sqrt",
    [0x54] = "andps",
    [0x55] = "andnps",
    [0x56] = "orps",
    [0x57] = "xorps",
    [0x58] = "add",
    [0x59] = "mul",
    [0x5A] = "cvt",
    [0x5B] = "cvt",
    [0x5C] = "sub",
    [0x5D] = "min",
    [0x5E] = "div",
    [0x5F] = "max",
    [0x60] = "punpck",
    [0x6E] = "movd",
    [0x6F] = "movdq",
    [0x7E] = "movd",
    [0x7F] = "movdq",
    [0xA3] = "bt",
    [0xAB] = "bts",
    [0xAF] = "imul",
    [0xB1] = "cmpxchg",
    [0xB3] = "btr",
    [0xB6] = "movzx",
    [0xB7] = "movzx",
    [0xBC] = "bsf",
    [0xBD] = "bsr",
    [0xBE] = "movsx",
    [0xBF] = "movsx",
    [0xC1] = "xadd",
    [0xC6] = "shufps",
    [0xD6] = "movq",
    [0xEF] = "pxor",
}
local TWO_STORE = {
    [0x11] = true,
    [0x13] = true,
    [0x17] = true,
    [0x29] = true,
    [0x7E] = true,
    [0x7F] = true,
    [0xD6] = true,
    [0xA3] = true,
    [0xAB] = true,
    [0xB1] = true,
    [0xB3] = true,
    [0xC1] = true,
}
local function flag(v, place)
    return floor(v / place) % 2 == 1
end
function M.new(bytes)
    local decoder = {}
    local function byte(s, p)
        return bytes.u8(s, p - 1)
    end
    local function word(s, p)
        return bytes.u32(s, p - 1)
    end
    local function sword(s, p)
        return bytes.i32(s, p - 1)
    end
    local function s8(s, p)
        local v = byte(s, p)
        if v >= 0x80 then
            return v - 0x100
        end
        return v
    end
    local function immz(s, p, wv, signed)
        if wv == 16 then
            local v = byte(s, p) + byte(s, p + 1) * 256
            if signed and v >= 0x8000 then
                v = v - 0x10000
            end
            return v, 2
        end
        if signed then
            return sword(s, p), 4
        end
        return word(s, p), 4
    end
    local function reg(n, w, rex)
        local r = { kind = "reg", n = n, w = w }
        if w == 8 and rex == 0 and n >= 4 and n <= 7 then
            r.hi = true
        end
        return r
    end
    local function imm(v)
        return { kind = "imm", v = v }
    end
    local function modrm(s, p, rex, w)
        local m = byte(s, p)
        if m == nil then
            return nil
        end
        p = p + 1
        local mod, r, rm = floor(m / 64), floor(m / 8) % 8, m % 8
        if flag(rex, 4) then
            r = r + 8
        end
        if mod == 3 then
            if flag(rex, 1) then
                rm = rm + 8
            end
            return reg(rm, w, rex), r, p
        end
        local mem = { kind = "mem", disp = 0, scale = 1, w = w }
        if rm == 4 then
            local sib = byte(s, p)
            p = p + 1
            local scale, index, base = floor(sib / 64), floor(sib / 8) % 8, sib % 8
            if flag(rex, 2) then
                index = index + 8
            end
            if index ~= 4 then
                mem.index, mem.scale = index, 2 ^ scale
            end
            if base == 5 and mod == 0 then
                mem.disp = sword(s, p)
                p = p + 4
            else
                if flag(rex, 1) then
                    base = base + 8
                end
                mem.base = base
            end
        elseif rm == 5 and mod == 0 then
            mem.rip, mem.disp = true, sword(s, p)
            p = p + 4
        else
            if flag(rex, 1) then
                rm = rm + 8
            end
            mem.base = rm
        end
        if mod == 1 then
            mem.disp = mem.disp + s8(s, p)
            p = p + 1
        elseif mod == 2 then
            mem.disp = mem.disp + sword(s, p)
            p = p + 4
        end
        return mem, r, p
    end
    local function done(ins, q)
        ins.size = q - 1
        local after, a, b, c = ins.at + ins.size, ins.a, ins.b, ins.c
        if a and a.kind == "mem" and a.rip then
            a.addr = after + a.disp
        end
        if b and b.kind == "mem" and b.rip then
            b.addr = after + b.disp
        end
        if c and c.kind == "mem" and c.rip then
            c.addr = after + c.disp
        end
        return ins
    end
    function decoder.decode(read, at)
        local s = read(at, 16)
        if s == nil or byte(s, 1) == nil then
            return nil, "읽기 실패"
        end
        local p, rex, opsize, rep = 1, 0, false, nil
        while true do
            local b = byte(s, p)
            if b == nil then
                return nil, "잘림"
            end
            if b == 0x66 then
                opsize = true
            elseif b == 0xF2 or b == 0xF3 then
                rep = b
            elseif not (b == 0x2E or b == 0x3E or b == 0x26 or b == 0x36 or b == 0x64 or b == 0x65 or b == 0xF0) then
                break
            end
            p = p + 1
        end
        local b = byte(s, p)
        if b >= 0x40 and b <= 0x4F then
            rex = b
            p = p + 1
            b = byte(s, p)
        end
        p = p + 1
        local wide = flag(rex, 8)
        local wv = 32
        if wide then
            wv = 64
        elseif opsize then
            wv = 16
        end
        local rexb = flag(rex, 1) and 8 or 0
        local ins = { at = at }
        if b < 0x40 and b % 8 <= 5 and b ~= 0x0F then
            ins.m = ALU[floor(b / 8) + 1]
            local form = b % 8
            if form <= 3 then
                local w = wv
                if form == 0 or form == 2 then
                    w = 8
                end
                local rm, r, q = modrm(s, p, rex, w)
                if rm == nil then
                    return nil, "ModRM"
                end
                if form <= 1 then
                    ins.a, ins.b = rm, reg(r, w, rex)
                else
                    ins.a, ins.b = reg(r, w, rex), rm
                end
                return done(ins, q)
            elseif form == 4 then
                ins.a, ins.b = reg(0, 8, rex), imm(s8(s, p))
                return done(ins, p + 1)
            end
            local v, n = immz(s, p, wv, true)
            ins.a, ins.b = reg(0, wv, rex), imm(v)
            return done(ins, p + n)
        elseif b >= 0x50 and b <= 0x5F then
            ins.m = b <= 0x57 and "push" or "pop"
            ins.a = reg(b % 8 + rexb, 64, rex)
            return done(ins, p)
        elseif b == 0x63 then
            local rm, r, q = modrm(s, p, rex, 32)
            ins.m, ins.a, ins.b = "movsxd", reg(r, wv, rex), rm
            return done(ins, q)
        elseif b == 0x68 then
            local v, n = immz(s, p, wv, true)
            ins.m, ins.a = "push", imm(v)
            return done(ins, p + n)
        elseif b == 0x6A then
            ins.m, ins.a = "push", imm(s8(s, p))
            return done(ins, p + 1)
        elseif b == 0x69 or b == 0x6B then
            local rm, r, q = modrm(s, p, rex, wv)
            ins.m, ins.a, ins.b = "imul", reg(r, wv, rex), rm
            if b == 0x69 then
                local v, n = immz(s, q, wv, true)
                ins.c = imm(v)
                return done(ins, q + n)
            end
            ins.c = imm(s8(s, q))
            return done(ins, q + 1)
        elseif b >= 0x70 and b <= 0x7F then
            ins.m = JCC[b - 0x70 + 1]
            ins.t = at + p + s8(s, p)
            ins.a = imm(ins.t)
            return done(ins, p + 1)
        elseif b == 0x80 or b == 0x81 or b == 0x83 then
            local w = b == 0x80 and 8 or wv
            local rm, r, q = modrm(s, p, rex, w)
            ins.m, ins.a = ALU[r % 8 + 1], rm
            if b == 0x81 then
                local v, n = immz(s, q, wv, true)
                ins.b = imm(v)
                return done(ins, q + n)
            end
            ins.b = imm(s8(s, q))
            return done(ins, q + 1)
        elseif b >= 0x84 and b <= 0x8B then
            local w = wv
            if b == 0x84 or b == 0x86 or b == 0x88 or b == 0x8A then
                w = 8
            end
            local rm, r, q = modrm(s, p, rex, w)
            if b <= 0x85 then
                ins.m = "test"
            elseif b <= 0x87 then
                ins.m = "xchg"
            else
                ins.m = "mov"
            end
            if b == 0x8A or b == 0x8B then
                ins.a, ins.b = reg(r, w, rex), rm
            else
                ins.a, ins.b = rm, reg(r, w, rex)
            end
            return done(ins, q)
        elseif b == 0x8D then
            local rm, r, q = modrm(s, p, rex, wv)
            ins.m, ins.a, ins.b = "lea", reg(r, wv, rex), rm
            return done(ins, q)
        elseif b == 0x90 then
            ins.m = "nop"
            return done(ins, p)
        elseif b == 0x98 or b == 0x99 then
            ins.m = b == 0x98 and "cdqe" or "cdq"
            return done(ins, p)
        elseif b == 0xA8 then
            ins.m, ins.a, ins.b = "test", reg(0, 8, rex), imm(s8(s, p))
            return done(ins, p + 1)
        elseif b == 0xA9 then
            local v, n = immz(s, p, wv, true)
            ins.m, ins.a, ins.b = "test", reg(0, wv, rex), imm(v)
            return done(ins, p + n)
        elseif b >= 0xB0 and b <= 0xB7 then
            ins.m, ins.a, ins.b = "mov", reg(b % 8 + rexb, 8, rex), imm(byte(s, p))
            return done(ins, p + 1)
        elseif b >= 0xB8 and b <= 0xBF then
            ins.m, ins.a = "mov", reg(b % 8 + rexb, wv, rex)
            if wide then
                ins.b = imm(sword(s, p + 4) * 0x100000000 + word(s, p))
                return done(ins, p + 8)
            end
            local v, n = immz(s, p, wv, false)
            ins.b = imm(v)
            return done(ins, p + n)
        elseif b == 0xC0 or b == 0xC1 or (b >= 0xD0 and b <= 0xD3) then
            local w = wv
            if b == 0xC0 or b == 0xD0 or b == 0xD2 then
                w = 8
            end
            local rm, r, q = modrm(s, p, rex, w)
            ins.m, ins.a = SHIFT[r % 8 + 1], rm
            if b <= 0xC1 then
                ins.b = imm(byte(s, q))
                return done(ins, q + 1)
            end
            return done(ins, q)
        elseif b == 0xC3 then
            ins.m = "ret"
            return done(ins, p)
        elseif b == 0xC2 then
            ins.m = "ret"
            return done(ins, p + 2)
        elseif b == 0xC6 or b == 0xC7 then
            local w = b == 0xC6 and 8 or wv
            local rm, _, q = modrm(s, p, rex, w)
            ins.m, ins.a = "mov", rm
            if b == 0xC6 then
                ins.b = imm(byte(s, q))
                return done(ins, q + 1)
            end
            if wide then
                ins.b = imm(sword(s, q))
                return done(ins, q + 4)
            end
            local v, n = immz(s, q, wv, false)
            ins.b = imm(v)
            return done(ins, q + n)
        elseif b == 0xCC then
            ins.m = "int3"
            return done(ins, p)
        elseif b == 0xE8 or b == 0xE9 then
            ins.m = b == 0xE8 and "call" or "jmp"
            ins.t = at + p + 3 + sword(s, p)
            ins.a = imm(ins.t)
            return done(ins, p + 4)
        elseif b == 0xEB then
            ins.m = "jmp"
            ins.t = at + p + s8(s, p)
            ins.a = imm(ins.t)
            return done(ins, p + 1)
        elseif b == 0xF6 or b == 0xF7 then
            local w = b == 0xF6 and 8 or wv
            local rm, r, q = modrm(s, p, rex, w)
            ins.m, ins.a = GRP3[r % 8 + 1], rm
            if r % 8 <= 1 then
                if b == 0xF6 then
                    ins.b = imm(s8(s, q))
                    return done(ins, q + 1)
                end
                local v, n = immz(s, q, wv, true)
                ins.b = imm(v)
                return done(ins, q + n)
            end
            return done(ins, q)
        elseif b == 0xFE or b == 0xFF then
            local w = b == 0xFE and 8 or wv
            local rm, r, q = modrm(s, p, rex, w)
            ins.m = GRP5[r % 8 + 1]
            if ins.m == nil then
                return nil, "FF /7"
            end
            ins.a = rm
            return done(ins, q)
        elseif b == 0x0F then
            local c = byte(s, p)
            p = p + 1
            if c >= 0x80 and c <= 0x8F then
                ins.m = JCC[c - 0x80 + 1]
                ins.t = at + p + 3 + sword(s, p)
                ins.a = imm(ins.t)
                return done(ins, p + 4)
            elseif c >= 0x90 and c <= 0x9F then
                local rm, _, q = modrm(s, p, rex, 8)
                ins.m, ins.a = "set", rm
                return done(ins, q)
            elseif c >= 0x40 and c <= 0x4F then
                local rm, r, q = modrm(s, p, rex, wv)
                ins.m, ins.a, ins.b = "cmov", reg(r, wv, rex), rm
                return done(ins, q)
            elseif c == 0x0B then
                ins.m = "ud2"
                return done(ins, p)
            elseif c == 0xBA then
                local rm, _, q = modrm(s, p, rex, wv)
                ins.m, ins.a, ins.b = "bt", rm, imm(byte(s, q))
                return done(ins, q + 1)
            elseif TWO[c] then
                local w, rw = wv, wv
                if c == 0xB6 or c == 0xBE then
                    w = 8
                elseif c == 0xB7 or c == 0xBF then
                    w = 16
                end
                if w ~= 8 and w ~= 16 then
                    rw = w
                end
                local rm, r, q = modrm(s, p, rex, w)
                ins.m = TWO[c]
                if (c == 0x10 or c == 0x11) and rep == 0xF3 then
                    ins.m = "movss"
                end
                if TWO_STORE[c] then
                    ins.a, ins.b = rm, reg(r, rw, rex)
                else
                    ins.a, ins.b = reg(r, rw, rex), rm
                end
                if c == 0xC6 then
                    ins.c = imm(byte(s, q))
                    return done(ins, q + 1)
                end
                return done(ins, q)
            end
            return nil, string.format("모르는 명령 0F %02X", c)
        end
        return nil, string.format("모르는 명령 %02X", b)
    end
    return decoder
end
M.decode = M.new(Bytes).decode
return M
