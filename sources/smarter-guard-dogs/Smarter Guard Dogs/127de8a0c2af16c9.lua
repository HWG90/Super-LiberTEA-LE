-- HD2-Addon: mods/chef/smarter_guard_dogs_and_sentries
-- Smarter Guard Dogs & Sentries for Helldivers 2 (Bingus Shared Loader v15+ addon).
--  * Rover (laser): fast target switching so its burn spreads over the group.
--  * Rover, K-9 and Guard Dog: player safety - they will not fire through you or your teammates.
--  * All three go for the enemy closest to you first.
--  * They move on the moment their target dies instead of shooting the body.
--  * Sentries (4.0): the same safety for your sentries - no firing through you or your teammates, also not while
--    they swing round to a new target; mortars leave enemies next to a helldiver alone; the machine gun and
--    Gatling sentries skip armor they can't hurt; sentries stop firing into walls, go for the right target first,
--    and the Tesla Tower leaves helldivers alone.
--  * (5.0) The same for the guns on armed resupply pods (Armed Resupply Pods booster) and on the Supply FRV.
--  * Options (4.0.5), each a tiny addon that sets a flag read every frame: Guard Dogs; Sentries (all, or all but the
--    Tesla Tower); Intelligence (Armor Intelligence and/or Target Prioritization); Safety (you and/or your teammates);
--    Targeting Laser (your screen only).
--  * Finds the game addresses it needs by scanning the game's code after a patch.
-- Keeps a small status log (SmarterGuardDogsAndSentries.log) in the local app-data folder for bug reports.
-- (LuaJIT 26251122 port) game builds 26088801, 26251122 are added as known builds: their addresses and the AI behavior ids
-- that moved in 26088801 (KNOWN_BUILDS). Everything else is the 5.2.0 release unchanged.
local VERSION = '5.2.0'
local READ_ONLY = false            -- diagnostic builds set this to true: nothing is ever written to game memory
local TESTER = false               -- test builds only: F8 markers and the list of enemy types the dog picked, in the log
local TEST_BUILD = false           -- (4.6.4) numbered test builds (Test 1, 2, ...): their logs go in Logs\test (build.py sets it)

if rawget(_G, 'SmarterGuardDogs') then return end
local SGD = { version = VERSION, status = 'starting', read_only = READ_ONLY }
rawset(_G, 'SmarterGuardDogs', SGD)

local ffi = require('ffi')
local bit = require('bit')

-- ======================================================================================================
-- Windows API (declared under private names so they can never clash with another mod's declarations)
-- ======================================================================================================
for _, d in ipairs({
  'typedef struct { void *base; void *alloc_base; uint32_t alloc_protect; uint16_t partition; uint16_t pad; size_t size; uint32_t state; uint32_t protect; uint32_t type; } SgdRegion;',
  'void *SgdGetModuleHandleA(const char *name) __asm__("GetModuleHandleA");',
  'uint32_t SgdGetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity) __asm__("GetModuleFileNameW");',
  'void *SgdGetCurrentProcess(void) __asm__("GetCurrentProcess");',
  'int SgdReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *done) __asm__("ReadProcessMemory");',
  'int SgdWriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *done) __asm__("WriteProcessMemory");',
  'size_t SgdVirtualQuery(const void *address, void *region, size_t size) __asm__("VirtualQuery");',
  'void *SgdCreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security, uint32_t disposition, uint32_t flags, void *tmpl) __asm__("CreateFileW");',
  'int SgdReadFile(void *file, void *buffer, uint32_t size, uint32_t *done, void *overlapped) __asm__("ReadFile");',
  'int SgdCloseHandle(void *handle) __asm__("CloseHandle");',
  'void *SgdCreateFileA(const char *path, uint32_t access, uint32_t share, void *security, uint32_t disposition, uint32_t flags, void *tmpl) __asm__("CreateFileA");',
  'int SgdWriteFile(void *file, const char *buffer, uint32_t size, uint32_t *done, void *overlapped) __asm__("WriteFile");',
  'uint32_t SgdSetFilePointer(void *file, int32_t distance, int32_t *high, uint32_t method) __asm__("SetFilePointer");',
  'int SgdSetEndOfFile(void *file) __asm__("SetEndOfFile");',
  'int32_t SgdBCryptOpenAlgorithmProvider(void **alg, const uint16_t *id, const uint16_t *impl, uint32_t flags) __asm__("BCryptOpenAlgorithmProvider");',
  'int32_t SgdBCryptCloseAlgorithmProvider(void *alg, uint32_t flags) __asm__("BCryptCloseAlgorithmProvider");',
  'int32_t SgdBCryptCreateHash(void *alg, void **hash, void *obj, uint32_t objlen, const void *secret, uint32_t secretlen, uint32_t flags) __asm__("BCryptCreateHash");',
  'int32_t SgdBCryptHashData(void *hash, const void *data, uint32_t len, uint32_t flags) __asm__("BCryptHashData");',
  'int32_t SgdBCryptFinishHash(void *hash, void *out, uint32_t len, uint32_t flags) __asm__("BCryptFinishHash");',
  'int32_t SgdBCryptDestroyHash(void *hash) __asm__("BCryptDestroyHash");',
}) do pcall(ffi.cdef, d) end
local K32, BCRYPT = ffi.load('kernel32'), ffi.load('bcrypt')
local PROCESS = K32.SgdGetCurrentProcess()

-- ======================================================================================================
-- Log
-- ======================================================================================================
-- (4.5) the log lives with the other Bingus mods' logs, %LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs (a tester's call);
-- straight in %LOCALAPPDATA% only if that folder isn't there. The files left in %LOCALAPPDATA% by earlier versions are
-- moved (the cached scan) or removed (the old logs), once
local LOGDIR, CACHEDIR
do
  local base = os.getenv('LOCALAPPDATA')
  if base then
    local dir = base .. '\\CowboyBingus\\Helldivers2\\Logs'
    local f = io.open(dir .. '\\SmarterGuardDogsAndSentries.log', 'a')
    if f then f:close(); LOGDIR = dir else LOGDIR = base end
    CACHEDIR = LOGDIR
    -- (4.6.4, my rule for every mod) numbered test builds write their logs into a 'test' folder inside the logs
    -- folder, when that folder is there (Lua can't make folders without a console window, so it falls back to the logs
    -- folder). Releases - the release's Tester zip too - keep logging to the logs folder
    if TEST_BUILD then
      local t = LOGDIR .. '\\test'
      local g = io.open(t .. '\\SmarterGuardDogsAndSentries.log', 'a')
      if g then g:close(); LOGDIR = t end
    end
    pcall(function()
      local old, new = base .. '\\SmarterGuardDogs', base .. '\\SmarterGuardDogsAndSentries'
      local g = io.open(old .. '.cache', 'r')
      if g then g:close(); os.rename(old .. '.cache', new .. '.cache'); os.remove(old .. '.cache') end
      os.remove(old .. '.log'); os.remove(old .. '-glow.txt'); os.remove(new .. '-glow.txt')
      if CACHEDIR ~= base then
        local c = io.open(new .. '.cache', 'r')
        if c then c:close(); os.rename(new .. '.cache', CACHEDIR .. '\\SmarterGuardDogsAndSentries.cache'); os.remove(new .. '.cache') end
        os.remove(new .. '.log'); os.remove(new .. '-research.log')
      end
    end)
  end
end
local startup_notes = {}
-- (4.6.3 review: capped - some notes come during play, e.g. option changes and barrels found, and the list is written
-- into the log every 10 s)
local function note(s)
  local n = #startup_notes
  if n < 150 then startup_notes[n + 1] = s
  elseif n == 150 then startup_notes[n + 1] = '(further notes left out)' end
end
local stats = { polls = 0, switches = 0, retargets = 0, safety_switches = 0, holds = 0, cover_switches = 0, armor_switches = 0, noshot_switches = 0, guarded_polls = 0, ignored_redirects = 0, memory_writes = 0, laser_frames = 0, write_failures = 0, read_errors = 0 }
local last_reason, last_error = '-', nil
local T0 = os.clock()
-- session summary: how long each state lasted, which dogs were seen, what the mod did, and recent events
local session = { statuses = {}, state_time = {}, dog_time = {}, actions = {}, events = {}, errors = {}, dirty = true,
  started = os.date('%Y-%m-%d %H:%M'), markers = {}, types = {}, type_list = {}, steps = {}, noshots = {}, parts = {},
  team = { max = 0, stops = 0, last = 0, notes = 0 }, sentries = {}, sentry_nodes = {}, sentry_types = {}, other_sentries = 0 }
local function event(msg)
  local line = string.format('%8.1fs  %s', os.clock() - T0, msg)
  local ev = session.events
  ev[#ev + 1] = line
  if #ev > 60 then table.remove(ev, 1) end
  -- errors are also kept apart (the first 10), so they don't scroll out of the recent events
  if msg:find('^error') and #session.errors < 10 then session.errors[#session.errors + 1] = line end
  session.dirty = true
end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local function write_counts(f, title, t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return t[x] > t[y] end)
  f:write(title .. ':' .. (#keys == 0 and ' none' or '') .. '\n')
  for _, k in ipairs(keys) do f:write(string.format('  %-34s %d\n', k, t[k])) end
end
local function mmss(s) return string.format('%dm%02ds', math.floor(s / 60), math.floor(s % 60)) end
local function write_log_to(f)
  f:write('Smarter Guard Dogs & Sentries ' .. VERSION .. ' (LuaJIT 26251122 port)' .. (READ_ONLY and ' (read-only diagnostic build: actions below were NOT carried out)' or '') .. '\n')
  f:write('started ' .. tostring(session.started) .. ', running for ' .. mmss(os.clock() - T0) .. '\n')
  for _, n in ipairs(startup_notes) do f:write(n .. '\n') end
  f:write('status: ' .. tostring(SGD.status) .. (SGD.dog and (' (' .. SGD.dog .. ')') or '') .. ', last action: ' .. tostring(last_reason) .. '\n')
  -- ((5.1.5 Test 11) idling: what the mod is doing now, and how much of the time it had something to do)
  local I = session.idle
  if I and I.frames > 0 then f:write(string.format('now: %s; idle %d s so far; working frames %d of %d\n', I.working and 'working' or 'idle', math.floor(I.idle_s), I.work_frames, I.frames)) end
  f:write(string.format('health: polls=%d memory_writes=%d write_failures=%d read_errors=%d laser_frames=%d\n',
    stats.polls, stats.memory_writes, stats.write_failures, stats.read_errors, stats.laser_frames))
  if last_error then f:write('last error: ' .. tostring(last_error) .. '\n') end
  -- time rather than poll counts: polls run every frame while a dog is out, but only a few times a second otherwise
  local keys = {}
  for k in pairs(session.state_time) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return session.state_time[x] > session.state_time[y] end)
  f:write('time in each state:' .. (#keys == 0 and ' none' or '') .. '\n')
  for _, k in ipairs(keys) do f:write(string.format('  %-34s %s\n', k, mmss(session.state_time[k]))) end
  f:write('dogs:' .. (next(session.dog_time) and '' or ' none out yet') .. '\n')
  for name, d in pairs(session.dog_time) do
    f:write(string.format('  %-10s out %s, with a target %.0f%% of that, firing %.0f%% of the time it had one\n', name,
      mmss(d.out), d.out > 0 and 100 * d.targeted / d.out or 0, d.targeted > 0 and 100 * d.firing / d.targeted or 0))
    if TESTER and (d.lu_n or d.lu_cut) then
      f:write(string.format('             line-ups (test): %d to a first shot, average %.2f s, longest %.2f s; %d moved on before a shot\n',
        d.lu_n or 0, (d.lu_sum or 0) / math.max(1, d.lu_n or 0), d.lu_max or 0, d.lu_cut or 0))
    end
  end
  f:write(session.team.off and 'teammates: not checked (teammate safety option off)\n'
    or (session.team.max > 0 and string.format('teammates: up to %d seen at once, safety stops for a teammate: %d\n', session.team.max,
      (function() local n = session.team.stops; for _, d in pairs(session.sentries) do n = n + (d.mate_stops or 0) end; return n end)())   -- (the dog's and the sentries')
    or 'teammates: none seen\n'))
  -- (4.7.0 SEAF Safety) the dog's stops for SEAF soldiers and civilians (the sentries' are in their own lines)
  if (session.team.seaf_stops or 0) + (session.team.civ_stops or 0) > 0 then
    f:write(string.format('dog safety stops for SEAF: %d, for a civilian: %d\n', session.team.seaf_stops or 0, session.team.civ_stops or 0))
  end
  -- sentries (4.0): per kind, how long yours were out and what the mod did with them
  f:write('sentries:' .. (next(session.sentries) and '' or ' none of yours out yet') .. '\n')
  local snames = {}
  for name in pairs(session.sentries) do snames[#snames + 1] = name end
  table.sort(snames)
  for _, name in ipairs(snames) do
    local d = session.sentries[name]
    f:write(string.format('  %-27s placed %d%s, out %s, with a target %.0f%% of that; safety stops %d (for a teammate %d%s%s%s), armor skips %d, priority switches %d%s%s%s%s%s%s%s%s\n',
      name .. (d.ai and string.format(' (AI %d)', d.ai) or ''), d.placed, (d.max_out or 0) > 1 and string.format(' (up to %d out at once)', d.max_out) or '', mmss(d.out), d.out > 0 and 100 * d.targeted / d.out or 0, d.stops, d.mate_stops, (d.sentry_stops or 0) > 0 and string.format(', for a sentry %d', d.sentry_stops) or '', (d.seaf_stops or 0) > 0 and string.format(', for SEAF %d', d.seaf_stops) or '', (d.civ_stops or 0) > 0 and string.format(', for a civilian %d', d.civ_stops) or '', d.armour, d.priority or 0,
      d.cooldowns and string.format(', cool-downs %d', d.cooldowns) or '',
      d.sentry_burst_done and string.format(', short bursts %d', d.sentry_burst_done) or '',
      d.sentry_spread and string.format(', set alight and moved on %d', d.sentry_spread) or '',
      d.sentry_out_of_sight and string.format(', dropped one out of sight %d', d.sentry_out_of_sight) or '',
      d.sentry_behind_ground and string.format(', dropped one behind ground %d', d.sentry_behind_ground) or '',
      d.sentry_no_damage and string.format(', dropped one it was not hurting %d', d.sentry_no_damage) or '',
      d.sentry_on_dropship and string.format(', left one still on a dropship %d', d.sentry_on_dropship) or '',
      d.sentry_out_of_reach and string.format(', dropped one out of reach %d', d.sentry_out_of_reach) or '',
      d.too_close and d.too_close > 0 and string.format(', an enemy inside its minimum range %s', mmss(d.too_close)) or '',
      TESTER and d.masks_back and string.format(', hidden enemies shown again by the game %d', d.masks_back) or ''))
  end
  if session.other_sentries > 0 then
    f:write(string.format('  other players\' sentries seen (run by their own game, not changed from yours): up to %d\n', session.other_sentries))
  end
  write_counts(f, READ_ONLY and 'actions it would have taken' or 'actions taken', session.actions)
  if #session.errors > 0 then
    f:write('errors (first 10):\n')
    for _, e in ipairs(session.errors) do f:write('  ' .. e .. '\n') end
  end
  -- ((5.1.5 Test 5) the damage check: whether it is armed, and how many health lookups found a record)
  local H = session.health
  if TESTER and H then
    f:write(string.format('damage check (test): %s; health lookups %d, records found %d, odd values %d\n', H.off and 'off' or (H.proven and 'armed' or 'not armed yet (no health seen going down this mission)'),
      H.reads, H.found, H.bad))
    -- ((5.1.5 Test 6) how the drops turned out, per kind
    for kind, T in pairs(H.tally or {}) do
      f:write(string.format('  %s: %d dropped; meter moving %d, still %d, not readable %d; out of sight %d, someone in its line %d, ground over its line %d; next enemy hurt within 3 s %d (not %d); came back to it %d, hurt it at once %d; others hurt it while it was left alone %d\n',
        kind, T.drops, T.meter_moving, T.meter_still, T.meter_unknown, T.unseen, T.mate, T.rise, T.next_hurt, T.next_none, T.back, T.back_hurt, T.others_hurt))
    end
  end
  -- ((5.1.5 Test 18) every drop of the session, and what the ground map knew of the line at each 'not hurting' drop
  if TESTER and session.drop_tally and next(session.drop_tally) then write_counts(f, 'drops (test): sentry, reason: enemy (whole session)', session.drop_tally) end
  if TESTER and session.safety_tally and next(session.safety_tally) then write_counts(f, 'safety stops (test): sentry, why: enemy (whole session)', session.safety_tally) end
  if TESTER and session.ground_tally and next(session.ground_tally) then write_counts(f, 'holds for ground in the way (test): sentry, height above its line, where that ground came from', session.ground_tally) end
  if TESTER and session.nd_ground and next(session.nd_ground) then write_counts(f, 'not-hurting drops by what the ground map knew (test)', session.nd_ground) end
  -- ((5.1.5 Test 30) frames the Autocannon or a mortar had a target but showed no marker, and why
  if TESTER and session.mark_gaps and next(session.mark_gaps) then write_counts(f, 'marker gaps (test): frames with a target and no marker, by sentry and why', session.mark_gaps) end
  -- ((5.1.5 Test 26) every sentry's place when it came out and went (the recent events scroll: these are kept, 40 at most)
  if TESTER and session.places and #session.places > 0 then
    f:write('sentry places (test):\n')
    for _, l in ipairs(session.places) do f:write('  ' .. l .. '\n') end
  end
  -- ((5.1.5 Test 19) LuaJIT and this mod's code: the start lines it keeps giving up on (see engine_research.lua)
  local J = TESTER and session.jitw
  if J and J.starts > 0 then
    f:write(string.format('compiling (test): %d traces started in this mod, %d compiled, %d given up; trace cache flushed %d times%s\n', J.starts, J.stops, J.aborts, J.flushes, J.stopped and ' (counted over the first 3,000 trace events of any mod)' or ''))
    local lines = {}
    for ln, n in pairs(J.bad) do if n > (J.ok[ln] or 0) then lines[#lines + 1] = ln end end
    table.sort(lines, function(a, b) return J.bad[a] > J.bad[b] end)
    for i = 1, math.min(25, #lines) do
      local ln = lines[i]
      f:write(string.format('  line %d: given up %d, compiled %d - %s\n', ln, J.bad[ln], J.ok[ln] or 0, J.why[ln] or '?'))
    end
  end
  if TESTER and session.timing and session.timing.n > 0 then
    local T = session.timing
    f:write(string.format('mod cost per frame (test): average %.3f ms, highest %.2f ms, over 1 ms in %d of %d frames\n', T.sum / T.n, T.max, T.over, T.n))
    -- ((5.1.5 Test 19) how many sentry steps were full plans and how many the light step in between
    if session.full_frames then f:write(string.format('  sentry steps (test): %d full plans, %d light (between plans)\n', session.full_frames, session.light_frames or 0)) end
    for _, Pt in ipairs(T.parts or {}) do
      if Pt.n > 0 then f:write(string.format('  %-28s %d times, average %.3f ms, highest %.2f ms, over 1 ms %d\n', Pt.name, Pt.n, Pt.sum / Pt.n, Pt.max, Pt.over)) end
    end
  end
  -- ((5.0 Test 12) part armor: each time a gun's answer on a Hulk or Charger changed, and what its line of fire met)
  if next(session.parts) then write_counts(f, 'part armor (answer changes: what the line of fire met)', session.parts) end
  if TESTER then write_counts(f, 'enemy types the dog picked (type id: times; for bug reports)', session.types) end
  if TESTER and next(session.steps) then write_counts(f, 'what the dog was doing while out (polls; AI step 6 = lining up, 7 = firing)', session.steps) end
  if TESTER and next(session.sentry_nodes) then write_counts(f, 'what the sentries were doing (polls; by AI step)', session.sentry_nodes) end
  if TESTER and next(session.sentry_types) then write_counts(f, 'enemy types the sentries went for (type id: times)', session.sentry_types) end
  if TESTER and next(session.noshots) then write_counts(f, 'no_shot by enemy type and distance from the dog', session.noshots) end
  if TESTER and #session.markers > 0 then
    f:write('F8 markers:\n')
    for _, e in ipairs(session.markers) do f:write('  ' .. e .. '\n') end
  end
  f:write('recent events (last 60):\n')
  for _, e in ipairs(session.events) do f:write('  ' .. e .. '\n') end
end
-- ((4.6.6 review) the file is always closed, and an error while writing it is reported to the caller)
local function write_log()
  session.dirty = false
  if not LOGDIR then return end
  -- ((4.6.7) built in memory first and written in one go: the file is open only for that one write)
  local parts, n = {}, 0
  local buf = { write = function(_, ...) for i = 1, select('#', ...) do n = n + 1; parts[n] = select(i, ...) end end }
  local ok, err = pcall(write_log_to, buf)
  if not ok then error(err, 0) end
  -- ((5.0 Test 9) test builds: the last game session's log is kept as -prev.log before this session's first write -
  -- a restarted game wrote over the mission I had just played)
  if (TEST_BUILD or TESTER) and not session.prev_kept then
    session.prev_kept = true
    pcall(function()
      local o = io.open(LOGDIR .. '\\SmarterGuardDogsAndSentries.log', 'r')
      local old = o and o:read('*a')
      if o then o:close() end
      if old and #old > 0 then
        local w = io.open(LOGDIR .. '\\SmarterGuardDogsAndSentries-prev.log', 'w')
        if w then w:write(old); w:close() end
      end
    end)
  end
  local text = table.concat(parts, '', 1, n)
  -- ((5.1.4, my ask: "lets make the log tweak") a 5.1.4 Tester log: each rewrite still ~3.6 ms on the game thread,
  -- nearly all of it opening and closing the file (Windows checks a file as it is closed). Now the file is opened once
  -- and kept open: each rewrite goes back to its start, writes, and cuts it to the new length. Others can still read
  -- it. If anything about that fails, back to opening and closing it each time, as before)
  local h = session.log_handle
  if h == nil then
    h = K32.SgdCreateFileA(LOGDIR .. '\\SmarterGuardDogsAndSentries.log', 0x40000000, 3, nil, 4, 0x80, nil)   -- (write; others may read and write; open or create)
    if h == nil or ffi.cast('intptr_t', h) == -1 then h = false end
    session.log_handle, session.log_done = h, ffi.new('uint32_t[1]')
  end
  if h then
    if K32.SgdSetFilePointer(h, 0, nil, 0) ~= 0xFFFFFFFF and K32.SgdWriteFile(h, text, #text, session.log_done, nil) ~= 0
      and session.log_done[0] == #text and K32.SgdSetEndOfFile(h) ~= 0 then return end
    pcall(K32.SgdCloseHandle, h); session.log_handle = false
  end
  local f = io.open(LOGDIR .. '\\SmarterGuardDogsAndSentries.log', 'w')
  if not f then return end
  f:write(text)
  f:close()
end

-- ======================================================================================================
-- Memory access (ReadProcessMemory on our own process: a bad address fails cleanly instead of crashing)
-- ======================================================================================================
local SMALL = ffi.new('uint8_t[8192]')
local DONE = ffi.new('size_t[1]')
local read
do
  local PVOID = ffi.typeof('const void *')
  read = function(addr, n)
    if type(addr) ~= 'number' or addr < 65536 then return nil end
    local buf = n <= 8192 and SMALL or ffi.new('uint8_t[?]', n)
    if K32.SgdReadProcessMemory(PROCESS, ffi.cast(PVOID, addr), buf, n, DONE) == 0 or DONE[0] ~= n then return nil end
    return ffi.string(buf, n)
  end
end
-- (4.0.6) numbers are read straight out of the string's bytes, without first copying the piece into a new string
-- (reads past the end, which the old way turned into a short copy, still go the old way)
local U32, U64, F32 = ffi.new('uint32_t[1]'), ffi.new('uint64_t[1]'), ffi.new('float[1]')
local u32, u64, f32
do
  local cast = ffi.cast
  local PU8, PU32, PU64, PF32 = ffi.typeof('const uint8_t *'), ffi.typeof('const uint32_t *'), ffi.typeof('const uint64_t *'), ffi.typeof('const float *')
  -- ((5.1.5 Test 18) the whole numbers from the string's own bytes: the pointer casts made a small throwaway object per
  -- number whenever the code ran uncompiled - the most garbage of any one function in my big-fight sim)
  local byte = string.byte
  u32 = function(s, o)
    if o + 4 > #s then ffi.copy(U32, s:sub(o + 1, o + 4), 4); return tonumber(U32[0]) end
    local a, b, c, d = byte(s, o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  u64 = function(s, o)
    if o + 8 > #s then ffi.copy(U64, s:sub(o + 1, o + 8), 8); return tonumber(U64[0]) end
    local a, b, c, d, e, f, g, h = byte(s, o + 1, o + 8)
    return (a + b * 256 + c * 65536 + d * 16777216) + (e + f * 256 + g * 65536 + h * 16777216) * 4294967296
  end
  -- (4.5) a float whose bits are an unusual NaN (0xffffffff, say: memory past the end of a list) came back from LuaJIT
  -- as nil, not as NaN, and a nil stopped the sentries in a Test 27 log: every such value is returned as a plain NaN
  local NAN = 0 / 0
  -- ((5.1.5 Test 18) the float worked out from its four bytes too (sign, exponent, fraction), for the same reason
  local ldexp = math.ldexp
  f32 = function(s, o)
    if o + 4 > #s then
      ffi.copy(F32, s:sub(o + 1, o + 4), 4)
      local v = tonumber(F32[0])
      if v == nil or v ~= v then return NAN end
      return v
    end
    local a, b, c, d = byte(s, o + 1, o + 4)
    local e = (d % 128) * 2 + (c >= 128 and 1 or 0)
    local m = (c % 128) * 65536 + b * 256 + a
    local v
    if e == 255 then
      if m ~= 0 then return NAN end
      v = math.huge
    elseif e == 0 then v = ldexp(m, -149)
    else v = ldexp(m + 8388608, e - 150) end
    if d >= 128 then v = -v end
    return v
  end
end
local function ptr_of(s, o)
  local p = s and u64(s, o or 0)
  if not p or p < 65536 or p >= 140737488355328 then return nil end
  return p
end

-- all game reads go through need(): a failed read aborts the whole snapshot (nothing is written that tick)
local Abort = {}
local function need(v, what) if v == nil or v == false then error({ Abort, what }, 0) end return v end
local function rd(addr, n, what) return need(read(addr, n), what) end
local function rptr(addr, what) return need(ptr_of(read(addr, 8), 0), what) end

local REGION = ffi.new('SgdRegion[1]')
local function writable(addr, n)
  local a, stop = addr, addr + n
  while a < stop do
    if K32.SgdVirtualQuery(ffi.cast('const void *', a), REGION, ffi.sizeof('SgdRegion')) == 0 then return false end
    local r = REGION[0]
    -- committed, private, plain read/write memory only (never code, never mapped files)
    if r.state ~= 0x1000 or r.type ~= 0x20000 or r.protect ~= 0x04 then return false end
    local base = tonumber(ffi.cast('uintptr_t', r.base))
    local rend = base + tonumber(r.size)
    if rend <= a then return false end
    a = rend
  end
  return true
end
local function write(addr, bytes)
  if READ_ONLY then return false end
  if not writable(addr, #bytes) then return false end
  if K32.SgdWriteProcessMemory(PROCESS, ffi.cast('void *', addr), bytes, #bytes, DONE) == 0 or DONE[0] ~= #bytes then return false end
  stats.memory_writes = stats.memory_writes + 1
  return read(addr, #bytes) == bytes
end
local function u64bytes(v) U64[0] = v; return ffi.string(U64, 8) end

-- open-addressing hash map used by the game's component managers: { slots*, ?, capacity, empty_key, multiplier }
-- ((4.6.4 review) soft: running out of probes means "not found" instead of aborting the whole read - for the per-enemy
-- lookups, where one enemy in a long probe run left the dog unsteered every frame while it was listed)
local function map_lookup(addr, key, max_capacity, header, soft)
  local h = header or rd(addr, 20, 'map header')
  local cap, empty, mult = u32(h, 8), u32(h, 12), u32(h, 16)
  if cap == 0 then return nil end
  need(cap <= max_capacity and bit.band(cap, cap - 1) == 0, 'map capacity')
  local slots = need(ptr_of(h, 0), 'map slots')
  -- (4.6.3 review) the low 32 bits of key * mult in plain numbers (exact: each part stays below 2^49) - the 64-bit ffi
  -- boxes it replaces cost an allocation per call when not compiled, and this runs per enemy per frame
  local mlo = mult % 65536
  local hash = (key * mlo + (key * ((mult - mlo) / 65536) % 65536) * 65536) % 4294967296
  -- ((5.1.5 Test 18) four slots a read where they run on without wrapping round: a look-up needed 1.6 reads on average
  -- in my big-fight sim, now about one - these run for every sentry, the dog and the health check each frame)
  local i, n = 0, math.min(cap, 128)
  while i < n do
    local j = bit.band(hash + i, cap - 1)
    local w = (j + 4 <= cap and i + 4 <= n) and 4 or 1
    local e = rd(slots + 8 * j, 8 * w, 'map slot')
    for q = 0, w - 1 do
      local k = u32(e, q * 8)
      if k == key then
        local v = u32(e, q * 8 + 4)
        return v ~= 4294967295 and v or nil
      end
      if k == empty then return nil end
    end
    i = i + w
  end
  if soft then return nil end
  error({ Abort, 'map probe' }, 0)
end

-- ======================================================================================================
-- Guard dog types (entity type hashes of the backpack and of the drone, stored byte-reversed in memory)
-- ======================================================================================================
local function type_hash(h) return (h:gsub('..', function(x) return string.char(tonumber(x, 16)) end)):reverse() end
local AVATAR_TYPE = type_hash('4d1c334d294dfa97')
-- names for common enemy types, only so logs are easier to read (identified in play; not used for any decision)
local LABELS = {}
for h, n in pairs({
  -- Illuminate (unit names from Filediver: Wretch = cha_bodyhorror_bladed, Crusher = cha_bodyhorror_helmetguy)
  cc188f0c80505c6c = 'Wretch', ['905809a4c28d8a45'] = 'Crusher', ['78e1497571012c47'] = 'Voteless',
  ['0adc9f9173ad8e1d'] = 'Voteless (v2)', ['44458a2c52b002fb'] = 'Voteless (v3)', ['67dc32dca4f02d33'] = 'Fleshmob',
  ['0883366204e1ccc5'] = 'Illuminate turret',
  -- Terminids
  a1f37bf2a40fbde4 = 'Warrior (plus)', aab438596f5e8fd9 = 'Scavenger (predator)', f79cd8bb654397df = 'Big Warrior (tier 2)',
  ['64090088502435dd'] = 'Shrieker', f540ca9d9d4a422e = 'Stalker', ['672f7da17f3ba34a'] = 'Impaler tentacle',
  ['5ca832447445c0ba'] = 'Hunter', ccae5264acd591b7 = 'Spewer (tier 2)', ['72a83e49ced6db3d'] = 'Spitter',
  ['10081acef6163ef6'] = 'Acid Warrior', dcf8e74212fbee3b = 'Impaler',
  -- Automatons
  a6a68d8af177f3a1 = 'Berserker', ['0002ba767df856f3'] = 'Trooper (tier 3)', d8cbc4a807a6d035 = 'Trooper (melee)', ['2c1a7790c435fd67'] = 'Automaton MG Emplacement', a71aafd82c6ebc92 = 'Conscript commander', ['746a7f3beda32699'] = 'Elite Rusher', ['282eb766c1ffa6a1'] = 'Gunship',
  ['856e9710e45e760f'] = 'Trooper (jump pack, melee)', d37e8d120d2836e3 = 'Factory Strider',
  d1e990baf22d5a52 = 'Predator Stalker', ['883401af2a98a5f6'] = 'Predator Hunter',
}) do LABELS[type_hash(h)] = n end
-- ((5.0 Test 18, my note: the Rover "was avoiding a predator strain stalker") enemies that cloak: while cloaked the game marks
-- them out of its line of sight, so the cover rule (no firing into walls) hid them - a Stalker closing in on you left alone.
-- They count as in sight (read_candidates)
SGD.cloaks = { [type_hash('f540ca9d9d4a422e')] = true, [type_hash('d1e990baf22d5a52')] = true }   -- Stalker, Predator Stalker
-- (4.0) names from the HD2 Enemy Codex (the enemy models matched to their wiki pages; names checked by a tester);
-- armored enemies are named by the armor list (engine_armor.lua) instead
for h, n in pairs({
  ['67381f685e9b69a8'] = 'Agitator', ['9f44121c554dae89'] = 'Agitator',
  ['4fb6077f1597691d'] = 'Berserker (chainsaw)', ['54e107dacf6929cb'] = 'Berserker', a6a68d8af177f3a1 = 'Berserker',
  ['2d1636f2ee8a6306'] = 'Commissar (melee claw)', a71aafd82c6ebc92 = 'Commissar',
  cbce5f5f0310ef15 = 'Commissar (handgun)', e2e62fdd39407fe3 = 'Jet Brigade Trooper (jumppack)',
  ['426b3df007be9f18'] = 'MG Raider (backpack lmg)', ['68ba814ff35bf19c'] = 'MG Raider (lmg)',
  f4c0b6c9218fb571 = 'Pyro Trooper (flamer)', ['1338b552afe68f0a'] = 'Radical', ['746a7f3beda32699'] = 'Radical',
  ['71b285b6d2b161c9'] = 'Rocket Raider (cannon)', ['64ba5f030b114ec1'] = 'Trooper',
  ['9821303bd499cd62'] = 'Trooper', ['9f57782f00e6ed20'] = 'Trooper', b2b3056bdf28e57b = 'Trooper',
  bcb3210cf8ef49d3 = 'Trooper (smg)', e8f19a0aa958e46d = 'Crescent Overseer', ['905809a4c28d8a45'] = 'Crusher',
  ['604a794ec45bb820'] = 'Elevated Overseer', ['67dc32dca4f02d33'] = 'Fleshmob', ['453fe22c634eb30f'] = 'Gatekeeper',
  ['34dfd23365472e9e'] = 'Obtruder', da40bb347c7447f2 = 'Overseer', ['20b9c7734daead65'] = 'Veracitor',
  ['0adc9f9173ad8e1d'] = 'Voteless', ['44458a2c52b002fb'] = 'Voteless', ['78e1497571012c47'] = 'Voteless',
  ac60e78435098c9d = 'Watcher', cc188f0c80505c6c = 'Wretch', d522fd4748d443a5 = 'Brood Commander',
  ['72a83e49ced6db3d'] = 'Bile Spitter', ['10081acef6163ef6'] = 'Bile Warrior', a478d36a62a861f4 = 'Hunter',
  aab438596f5e8fd9 = 'Pouncer', d7e2c78b1ef4a8e1 = 'Predator Hunter', a35207c6f2150806 = 'Rupture Warrior',
  ['5b968cd78f8bc7a0'] = 'Scavenger', c14e0e887e7d2106 = 'Scavenger', ['64090088502435dd'] = 'Shrieker',
  c28b3482e73d1ea9 = 'Spore Burst Hunter', db964631be1cf501 = 'Spore Burst Scavenger',
  ['1baeef36a88ae579'] = 'Spore Burst Warrior', f540ca9d9d4a422e = 'Stalker', ['09872e66d1276e1f'] = 'Warrior',
  be39e313a1e46bb9 = 'Warrior (pale)', a1f37bf2a40fbde4 = 'Hive Guard', ['36aa99cce5e60146'] = 'Bile Spewer',
  ccae5264acd591b7 = 'Bile Spewer', cc7022fdd172089b = 'Nursing Spewer', a381a11c07d3eb94 = 'Rupture Spewer',
  f79cd8bb654397df = 'Alpha Commander', fb9937035d652c43 = 'Scout Strider pilot', ['4d1c334d294dfa97'] = 'Helldiver',
  -- (4.5, Codex check) the Illuminate's weapons and the Crusher's cleaver are entries of their own
  ['9c7ef47a463d5327'] = 'Overseer (lightspear)', ['0cf9b9b95edfef81'] = 'Elevated Overseer (rifle)',
  ['705362ad578943f6'] = 'Crescent Overseer (gun)', ['258bd988cd66c94b'] = 'Crusher (cleaver)',
  -- ((5.1.5 Test 25) unnamed in my Test 24 log, named from the game's entities (hd2api))
  ['089833d2880d9e06'] = 'MG Raider', ['82a87ad8d595b2ba'] = 'Pyro Trooper', ['09dfb04b2e578bc3'] = 'Trooper',
  e683d2ca5618d74a = 'Raider', ['1b5b9ac4f96b36e5'] = 'Commissar'
}) do LABELS[type_hash(h)] = n end
local DOGS = {
  { name = 'Rover', pack = type_hash('af9b683ccb6ddc02'), drone = type_hash('5beec97f4c7f4ae9'), laser = true,
    fast = true, radius = 0.35, safety_keep = 0.4, linger = 0.3, range = 35,
    gun = type_hash('2c66c201b2543d2c'), barrel = { 2, 1 } },   -- (4.5.3: its laser comes out of its barrel too, a tester's call)
    -- ((5.0 Test 5, my ask: "the beam should follow where the actual gun is turned like an actual laser mount")
    -- barrel: its muzzle part's axis 2, forward - the axis Test 17 kept finding - followed as it is, sweep and all,
    -- with no learning and no dropping; the old beam_to_aim (muzzle to the game's aim point) is gone)
    -- (4.5.3 Test 17: gun = its weapon's own entity, from a tester's Test 15 log; beam_to_aim: its muzzle part twists as
    -- it sweeps its beam over what it burns - the barrel axis was found and lost four times and the beam ran up to 19
    -- degrees off the game's aim - so its laser runs from its muzzle to where the game aims it)
    -- (its beam is thin, so its safety margin, look-ahead after a fast turn and hide time are a little shorter;
    -- beyond ~35 m it often lines up without firing, so farther enemies wait while something closer is available:
    -- it is a guard dog, the enemies near you come first)
  { name = 'K-9', pack = type_hash('c28da712b12e3dfa'), drone = type_hash('4b071633584e4594'), laser = true,
    fast = false, radius = 0.6, chain = 3.0, aim_rise = 1.0, gun = type_hash('a0532c3616528cbf'), barrel = { 2, 1 } },   -- (gun: 4.5.3 Test 15 log; (5.0) barrel as the Rover's)
    -- (4.5.3 Test 18: beam_to_aim like the Rover's - its arc weapon's muzzle part lost its barrel direction twice in a
    -- tester's Test 17 log (0.697, 0.883) and the laser twitched at times)   -- (4.5.3: out of its barrel too; its arc weapon sways, and so does the laser)
  { name = 'Guard Dog', pack = type_hash('255ebc5767d7ceec'), drone = type_hash('a0ff2f9a0ca6992a'), laser = false,
    fast = false, radius = 0.35, safety_keep = 0.4, linger = 0.3, range = 32, hard_range = true, aim_rise = 1.2,
    gun = type_hash('a32621e3bde13379') },   -- it only ever opens fire within ~32 m (measured from test logs); gun: its weapon's own entity (4.5.3 Test 11 log)
    -- (safety trimmed like the Rover's: slightly smaller margin, shorter look-ahead after a fast turn and hide time;
    -- hard_range: it never fires beyond ~32 m, so enemies farther out stay hidden even when nothing is closer)
}
local DOG_BY_PACK = {}
for _, d in ipairs(DOGS) do DOG_BY_PACK[d.pack] = d end

-- Sentries (4.0). Keyed by the sentry's entity type (the hash of its unit name, e.g. hellpod/turret_machinegun_gpmg;
-- the Gatling is hellpod/turret/gatling_turret) and checked against its AI behavior id where known.
--  line/spread: how far (meters) a shot line must stay from a body, plus this much per meter from the muzzle
--  splash: the shot explodes; nobody may stand within this many meters of the enemy
--  splash_heavy: ((5.1.5 Test 34) the Autocannon) a heavy (AV4+) is fired on even with a sentry inside 'splash' of it
--  min_range: it can't fire while an enemy is this close to it (meters; the rocket sentry, 10 m per the wiki): a red
--  ring of that radius flashes around it meanwhile
--  blast: mortars lob shells in an arc, so there is no line to check; nobody may stand within this of the enemy
--  sweep: keeps firing while it turns to its next target, so the turn must not pass over anyone either
--  barrel_axis: which axis of its muzzle part is the barrel, when known from testing (otherwise learned in play)
--  pen: the heaviest armor it can hurt (armor skipping); none = shoots everything the game lets it
--  prefer: 'heavy' = armored enemies first (rocket, autocannon), 'light' = unarmored enemies first (machine gun, Gatling)
--  heat: it overheats (Laser Sentry): rested before it burns out
--  spreads_fire: sets enemies alight and moves on, like the Rover (Laser Sentry); fire_node: its AI step while firing;
--  spares_helldivers: it would target helldivers itself (Tesla Tower): yours are hidden from it; ring: instead of a laser, a
--  ring of this radius (meters) around it, green while it engages and faint green while idle, plus the laser to its target
--  no_laser: no targeting laser (the mortars: they lob over cover, so their line is rarely in view; a tester's call)
--  salvo_node: an AI step of its own (besides step 10) in which it won't choose again: only safety stops are asked for then
--  hits_carried: may shoot enemies still aboard a dropship (rocket, autocannon: the splash hurts the dropship too);
--    the other sentries leave them until they land
--  bursts: short bursts at Heavy Devastators, like the Guard Dog (machine gun, Gatling)
--  loss_time (4.6.3): its AI record's +408 holds the time it lost its target (it fires on at the spot for 1 s after; since 4.6.5 that time is moved back for every dog and sentry kind but the salvo guns, so this flag only documents where it was first found);
--    found on the Supply FRV gun's AI and the Gatling's, which the Resupply Pod gun also runs
--  air_first: gunships and Stingrays before everything else (Gatling, autocannon, rocket, Laser)
--  reach (4.6.4): its range per the wiki (meters): only enemies this close count as a better target (Target Prioritization);
--    without it 100 m (Autocannon, Rocket)
--  barrel_min (4.6.4): the match its barrel axis needs to be learned (default 0.97): the Flame Sentry's arcing stream
--    only lines up with its barrel to about 0.969 (a 4.6.3 Tester log), so its turns went unchecked
--  laser_axis: (5.0 Test 7) the muzzle part's axis the laser runs along when the kind has no barrel_axis (rocket, autocannon:
--   axis 2, the tubes'/barrel's direction in the game models, as the other sentries'); used by the laser only
--  laser_at_enemy: no barrel axis to follow (rocket, autocannon): the laser runs from the muzzle to where the game aims
--  the gun. Every other sentry's laser comes out along its barrel (4.5.3)
-- The log says when a sentry-like AI shows up with a type that isn't in this list.
local SENTRIES = {
  { name = 'Machine Gun Sentry', type = type_hash('37cde43876ba26bb'), ai = 312, line = 0.45, spread = 0.01, sweep = true, barrel_axis = 2, pen = 3, bursts = true, reach = 75, prefer = 'light' },
  { name = 'Gatling Sentry', type = type_hash('ef85d6cf58e31d70'), ai = 213, line = 0.5, spread = 0.015, sweep = true, barrel_axis = 2, pen = 3, bursts = true, loss_time = true, reach = 75, prefer = 'light', air_first = true },
  -- ((5.1.5 Test 10 wiki check, my ask: "fact check all of the sentries and mortars") Autocannon: its shell's explosion
  -- (APHE_40mm, 150 damage) reaches 6 m (radius 2 / 6 / 8: full damage, damage ends, push), so 'splash' 6 (was 2); its
  -- shell is armor penetration 5 and the Rocket's too, so 'pen' 5 for both: they leave the Hive Lord's mandibles (AV6) alone
  -- (were 'shoot everything'). Range 100 m (its own wiki page; the Gas Mortar page's '75m' for it is wrong)
  { name = 'Autocannon Sentry', type = type_hash('54d86057f5dacfb9'), ai = 5, line = 0.45, spread = 0.005, splash = 6.0, splash_heavy = true, pen = 5, prefer = 'heavy', air_first = true, hits_carried = true, laser_at_enemy = true, laser_axis = 2, salvo = true,
    barrel_from = 21, barrel_node = 27, barrel_len = 1.81 },   -- (type confirmed in game; unit hellpod/autocannon_turret/autocannon_turret) ((5.1.5 Test 29) its barrel: gun housing part 21 -> muzzle part 27, 1.81 m, from the game model aa_turret)
  -- (wiki check: 100 m, 10 m minimum, its rockets' explosion reaches 4 m: 'splash' 4.5 stays)
  { name = 'Rocket Sentry', type = type_hash('37079568dc86e9c6'), ai = 611, line = 0.6, spread = 0.01, splash = 4.5, pen = 5, min_range = 10, prefer = 'heavy', air_first = true, hits_carried = true, laser_at_enemy = true, laser_axis = 2, axis_confirmed = true,
    salvo_node = 13 },   -- (mid-salvo it ignores being asked to choose again)
  -- (heat: the wiki says it heats 8 degrees a second while firing, burns out at 250 and cools 3.8-7.5 a second; in game it
  -- overheated after about 28 s on targets, so the estimate uses 11 a second. The game's own heat meter is used when found)
  { name = 'Laser Sentry', band = true, type = type_hash('56070f36cfffa8a8'), ai = 308, line = 0.35, spread = 0.002, sweep = true, barrel_axis = 2, pen = 4, heat = { cap = 250, rate = 11, cool = 3.8 },
    reach = 50, prefer = 'light', air_first = true, spreads_fire = true, fire_node = 13 },   -- (ours runs along its barrel, over its own beam, turning with it)
  { name = 'Flame Sentry', type = type_hash('820cc3bafe962858'), ai = 207, line = 1.0, spread = 0.03, splash = 2.5, sweep = true,
    range = 30, prefer = 'near', spreads_fire = 'keep', barrel_min = 0.95 },   -- ('range' = meters from its muzzle: 4.5.2 set 20, a tester's call as the game let it pick
    -- enemies well past its flames; 4.6.1 30, a tester's call as its flames reach about 34 m. 'near': closest first, no armor tiers;
    -- 4.6.2 'keep': it moves on from an enemy it has set alight to the next unlit one, a tester's call)
  -- (4.0) the Tesla Tower (hellpod/tesla_turret): its arc reaches 20 m and chains from its target to whoever stands
  -- next to it, and it zaps standing helldivers in range (wiki). 'spares_helldivers': it targets only enemies the mod
  -- has marked (4.5, engine_sentry.lua tesla_filter); the helldivers' entries are also hidden from it every frame, and
  -- it is asked to choose again whenever it is on one all the same. Enemies within 10 m of a helldiver are left alone
  -- (the arc's jump, 'splash'; 5 m before 4.5, a tester's call), and instead of a laser it shows its range as a ring
  -- ('ring', shown the whole time it is out). AI 661 (Test 28 log); its gun sits ~2.6 m up
  { name = 'Tesla Tower', type = type_hash('74599e56f72f9d7e'), ai = 661, line = 0.6, spread = 0.02, splash = 10.0, spares_helldivers = true,
    ring = 20, muzzle_up = 2.6, salvo_node = 4, height = 3.0, spares_sentries = true },   -- (step 4: its 1.5 s of firing, in which it doesn't choose again;
    -- 4.6.5 Sentry Safety: 'spares_sentries', hellpod items are arc-protected (wiki); 'height', how tall it stands)
  -- (4.6.4 wiki check: 'blast' = how far its shells must land from a helldiver - the Mortar's shockwave reaches 13 m
  -- (blast 9 m), the EMS Mortar's stun 10 m and its shockwave 12 m; were 12 and 8)
  -- (4.6.5 Sentry Safety, 'sentry_blast': how far its shells must land from a sentry - the Mortar's explosion does 400 out to
  -- 3 m, fading to nothing at 9 m (a sentry has 400-600 health); the EMS Mortar's does 150 out to 1 m, nothing past 2 m, its
  -- stun field does no damage)
  -- ((5.1.5 Test 9) reach 125: the wiki's "potential maximum targeting range of 125-meters" for the mortars (Gas Mortar
  -- page), used for where their markers show; their markers show like every sentry's now - no laser, my ask:
  -- "Mortars should draw markers. Just not lasers")
  { name = 'Mortar Sentry', type = type_hash('51a0812e3bce2d74'), ai = 322, reach = 125, blast = 13, sentry_blast = 7, no_laser = true },   -- (AI 322 in game, Test 27 log)
  -- ((5.1.5 Test 10 wiki check) its static field's damage (150) reaches 3 m (radius 1 / 2 / 3): 'sentry_blast' 3 (was 2.5))
  { name = 'EMS Mortar Sentry', type = type_hash('b2053a1838092f8b'), ai = 324, reach = 125, blast = 12, sentry_blast = 3, no_laser = true },   -- (AI 324 in game, Test 28 log)
  -- ((5.1.5 Test 8) the A/GM-17 Gas Mortar Sentry, the mortar's unit with its own entity (299c0d3dfd2f0994, the game's
  -- data): gas shells, a 7 m cloud (wiki attack data A/GM-17_P_IE, Gas + Gas_Confusion, no damage of its own) that
  -- lingers, so 'blast' 10 m from a helldiver; its shell does 20 on impact, so 'sentry_blast' 2.5 m as the EMS Mortar's.
  -- Its AI id isn't confirmed in game: the game data puts its behavior between the Mortar's and the EMS Mortar's, so
  -- 323 (the Mortar runs 322, the EMS Mortar 324). ((5.1.5 review) the game's AI dispatch table doesn't tell 319-324
  -- apart (separate but alike handlers), and its entity type is its own, so any of the mortar family's ids 319-324 is
  -- taken; the log's 'out (AI n)' line says which it runs)
  { name = 'Gas Mortar Sentry', type = type_hash('299c0d3dfd2f0994'), ai = 323, ais = { [319] = true, [320] = true, [321] = true, [322] = true, [323] = true, [324] = true }, reach = 125, blast = 10, sentry_blast = 2.5, no_laser = true },
  -- (5.0) the guns that come with a resupply pod (Armed Resupply Pods booster) and on the M-103 Supply FRV: both an
  -- automatic AR-23P Liberator Penetrator (medium armor penetration, 640 rpm, ~120-140 rounds, 30 m), run on the Gatling's
  -- AI template. Types from a 4.0.6 Test 8 log (AI 213 and 212); their units are unnamed, found in the resupply pod's
  -- archive (263277e5added56c, with the ammo rack) and the Supply FRV's (149f685717737cae). Treated like the machine gun:
  -- skips armor it can't hurt (saving its rounds), short bursts at Heavy Devastators, unarmored enemies first. 'ais':
  -- either of the Gatling template's two ids is accepted. The FRV's gun moves with the vehicle and fires past its driver
  { name = 'Resupply Pod Gun', mount = true, type = type_hash('73681ffd58fa1a90'), ai = 213, ais = { [212] = true, [213] = true }, line = 0.45, spread = 0.01, sweep = true, barrel_axis = 2, pen = 3, bursts = true, loss_time = true, reach = 30, prefer = 'light',
    turn_hold = 30, beam_inset = 0 },   -- ((5.1.5 Test 8, my note: the pod gun "should be almost identical to the Supply FRV
    -- Turret") the same gun and settings as the Supply FRV gun below. ((5.1.5 Test 9, my ask: "The supply frv and resupply
    -- pod range of 75m doesnt seem accurate") reach 30 m for both: the wiki's Armed Resupply Pods page - its gun "targets and
    -- shoots at any non-Helldiver hostiles within 30 metres" - and the Supply FRV's, whose turret is "similar to that of the
    -- Armed Resupply Pods turret". The 4.6.4 review's 75 m was the Machine Gun Sentry's, wrongly given to these two too.
    -- Only what comes from the vehicle differs (vehicle, laser_when_firing)
    -- (4.6.2: as the Supply FRV gun, whose AI it runs - turns to an enemy far round without firing;
    -- 5.1.1: the same gun model as the FRV's, its fire node at the barrel's tip - beam_inset 0, see add_beam)
  -- (4.5: barrel_axis 2 like the Gatling's, whose AI they run on: a Test 28 log found axis 2+ at 0.987 on the FRV gun;
  -- learning it on a moving vehicle failed as often as not)
  { name = 'Supply FRV Gun', type = type_hash('4df41f84668d07fb'), ai = 212, ais = { [212] = true, [213] = true }, line = 0.45, spread = 0.01, sweep = true, barrel_axis = 2, pen = 3, bursts = true, loss_time = true, reach = 30, prefer = 'light',
    vehicle = true, laser_when_firing = true, turn_hold = 30, beam_inset = 0 },   -- (test builds log where its riders sit relative to it and to its line of fire)
    -- (turn_hold, 4.6.2, a tester: it wasted ammo swinging from one enemy to the next while firing - after a kill, the
    -- next enemy more than this many degrees off its barrel is turned to without firing; see engine_sentry.lua)
}
local SENTRY_BY_TYPE = {}
for _, d in ipairs(SENTRIES) do d.sentry = true; SENTRY_BY_TYPE[d.type] = d end
-- AI behavior ids built on the game's sentry template (from the game code): anything else with one of these that
-- turns up on your side is reported in the log, so a missing sentry can be added
local SENTRY_AI = { [5] = true, [207] = true, [212] = true, [213] = true, [308] = true, [312] = true, [319] = true, [320] = true,
  [321] = true, [322] = true, [323] = true, [324] = true, [603] = true, [611] = true, [661] = true, [680] = true, [685] = true }
-- (filled in by engine_sentry.lua: the sentry lines for an F8 marker)
local sentry_marker_text
-- code patterns (found in the game's own code at start-up; wildcards "??" skip bytes that change between builds)
local PATTERNS = {
  dispatch = { p = 'ffca418bf8488bd981fa????????0f87????????4863c2488d0d????????8b9481????????4803d1', count_at = 10, table_at = 33 },
  laser_fn = '48895c2408574883ec40488b41088bda488bf93950080f84????????895008488b41080f29742430f30f1035????????c74004ffffffff488b41088b0885c974??83f90274??83f90574??83f90775??488bcfe8????????eb??b201488bcfe8????????0f28ce488bcfe8????????eb??488b0741b902000000488b0d????????41b8000000028b5008e8????????488b4708488b0f391874??8918817910ff7f000074??8b510841b801000000e8????????ffcb83fb060f87????????488d15????????8b8c9a????????4803caffe133d241b85706cc23488bcfe8????????488b4708488b17448b80e0010000418bc883c9048988e0010000817a10ff7f0000',
  stride = '8be84869dd????????48035f60393374??4533c94c8bc3488bcf',
  owner_index = '458b93????????33d248895c241041????????????48896c2418410fafd8418d6aff488974242048893c244585d274??498bbb????????418bb3????????6666660f1f840000000000',
  owner_rows = '8b4104488d0c40488d85????????488d04c8eb??488d05????????',
  globals = {
    perception = { { p = '4c8b15????????75??b8ffffffff8bc84869c1f813000049034250', disp_at = 3, size = 7 }, { p = '488b0d????????8bf04c69c6f8130000897424604c034150418b88200d000041038818080000410388100300004539b070120000', disp_at = 3, size = 7 }, { p = '488b0d????????8be84c69c5f8130000896c24244c034150', disp_at = 3, size = 7 } },
    clock = { { p = '488b05????????483b481877??b801000000', disp_at = 3, size = 7 }, { p = '488b05????????488b481849898880010000817a10ff7f000074??8b520841b8000000014883c4205be9????????4883c420', disp_at = 3, size = 7 }, { p = '488b3d????????488bd9488b4908488b8180010000', disp_at = 3, size = 7 } },
    targeting = { { p = '488b05????????4533c048895c2410488974241848893c24448b8858010000448b9860010000', disp_at = 3, size = 7 }, { p = '488b2d????????8b400889442438488b06', disp_at = 3, size = 7 }, { p = '4c8b05????????33c94889742438458b8858010000', disp_at = 3, size = 7 } },
    players = { { p = '488b05????????488d542448488b88e8000000', disp_at = 3, size = 7 }, { p = '488b15????????0fb6e883ba8400000000', disp_at = 3, size = 7 }, { p = '488b05????????3998840000000f86????????488b80e8000000488d542438448b4008e8????????8b4424383b05????????0f84????????4c8b0d????????48896c2430', disp_at = 3, size = 7 } },
    attachments = { { p = '488b3d????????4c89742438448b4f28448b5f30440fafd8', disp_at = 3, size = 7 }, { p = '4c8b15????????75??b8ffffffff8bc8488d044948c1e004490342404883c408', disp_at = 3, size = 7 }, { p = '488b1d????????458bd148897c24504c897c2420', disp_at = 3, size = 7 } },
    owners = { { p = '488b0d????????8b5008e8????????eb??488bcfe8????????ba5f218b6f488bcf', disp_at = 3, size = 7 }, { p = '488b0d????????8b5008e8????????bad8040000488bcbe8????????488b4308c74008ffffffff4883c4205bc3cccccc', disp_at = 3, size = 7 }, { p = '488b0d????????8b5008e8????????bad8040000488bcb4883c420', disp_at = 3, size = 7 } },
    behaviours = { { p = '488b0d????????c6442428008b5008f30f115c2420e8????????4883c4305bc3cccccccc40534883ec30', disp_at = 3, size = 7 }, { p = '488b0d????????c6442428008b5008f30f115c2420e8????????eb??ba50441555', disp_at = 3, size = 7 }, { p = '488b0d????????8b5008e9????????cccccccccccccccc40534883ec2048ba0936d1970ea21109', disp_at = 3, size = 7 } },
    backpacks = { { p = '488b1d????????4533db4c8be2458bc3', disp_at = 3, size = 7 }, { p = '488b1d????????3bc20f84????????8b7b28', disp_at = 3, size = 7 }, { p = '4c8b3d????????3bc10f84????????458b5f28458bd1418b5f300fafd8458d73ff4585db74??498b7f20418b772c90418bd6', disp_at = 3, size = 7 } },
    registry = { { p = '488b3d????????33d2448b8f58200100448b9760200100440fafd1458d71ff4585c974??4c8b9f502001008bb75c2001000f1f4000660f1f840000000000', disp_at = 3, size = 7 }, { p = '488b35????????33c9448b8658200100448b8e60200100440fafcb458d70ff4585c074??4c8b9650200100448b9e5c2001006690418bc6418d1409', disp_at = 3, size = 7 }, { p = '4c8b35????????33d2458b8e58200100458b9660200100440fafd1418d71ff4585c974??4d8b9e50200100418bbe5c2001000f1f4000660f1f840000000000', disp_at = 3, size = 7 } },
    mission = { { p = '488b05????????488bd9837808000f84????????8b4040ffc883f8060f87????????488b05????????8378500075??33c0eb??8b80c80a000083f80275??488b4108', disp_at = 3, size = 7 }, { p = '4d488b05????????8378080074??8b4040', disp_at = 4, size = 8 }, { p = '488b05????????837808000f84????????8b4040ffc883f80677??488b05????????', disp_at = 3, size = 7 } },
    equipment = { { p = '4c8b05????????33db8bcb458b4830458b5038', disp_at = 3, size = 7 }, { p = '4c8b0d????????48896c24304889742440', disp_at = 3, size = 7 }, { p = '4c8b0d????????48896c24404889742448458b4130458b5938', disp_at = 3, size = 7 } },
  },
  -- 4.0 (sentries): the weapon component manager, for where each sentry's muzzle is. Optional: without it the
  -- sentries are still steered, only their laser and turn check fall back to the sentry's own position
  optional = {
    weapons = { { p = '488b3d????????458bda8b77388b6f40', disp_at = 3, size = 7 }, { p = '4c8b1d????????4533f63b15????????', disp_at = 3, size = 7 }, { p = '488b3d????????413bd274??448b5738', disp_at = 3, size = 7 } },
    -- the sentries' heat/ammo meter (12-byte records: +4 how much is used up, +8 overheated): the Laser Sentry's heat
    heatbar = { { p = '4c8b1d????????33c9458b4b30418b5b38', disp_at = 3, size = 7 }, { p = '488b1d????????448b43308b7b380faff8', disp_at = 3, size = 7 }, { p = '488b35????????488bea74??448b4e30', disp_at = 3, size = 7 } },
    -- ((5.1.5 Test 5) the health component manager, for the damage check: entity id -> health record)
    health = { { p = '488b35????????4c8bf18bae1c1000003bae38100000', disp_at = 3, size = 7 }, { p = '488b35????????488bda4c8bf18b861c100000', disp_at = 3, size = 7 }, { p = '488b0d????????418b160f29b424a0010000', disp_at = 3, size = 7 } },
  },
  exe_units = { { p = '488905????????488d95c801000041b858010000', disp_at = 3, size = 7 }, { p = '488b3d????????4c8b35????????4885ff', disp_at = 3, size = 7 }, { p = '48892d????????4885ff74??488b0733d2488b35????????', disp_at = 3, size = 7 } },
}
-- known build (game.dll 2E2C3B7C / exe F5FEE03D, 2026-09-24 patch): addresses are RVAs
-- (4.6.4 review) dll_stamp/exe_stamp: the modules' PE time stamp and image size, checked first so a known build needs
-- no hashing of ~135 MB of game files at every start
local KNOWN = { dll_hash = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E', exe_hash = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
  dll_stamp = '1790161983/74727424', exe_stamp = '1790149348/60719104',
  globals = { mission = 53634720, players = 53634152, owners = 54968216, equipment = 53634872, backpacks = 53634536, attachments = 53636544, targeting = 53636400, behaviours = 53634880, perception = 53634376, registry = 53636280, clock = 53633864, weapons = 53636320, heatbar = 53636424, health = 53634696 },
  owner_index = 15871688, owner_rows = 15937304, stride = 504, exe_units = 27328752, laser_behaviour = 190 }
-- (LuaJIT 26251122 port) the ping record (SpottableComponent manager) of each known build: Ping Targeting kept it for
-- this build only
KNOWN.ping = 53634128
-- (LuaJIT 26251122 port) builds 26088801, 26251122 (the 2026-10-22 and 2026-10-29 patches): the same layout, their
-- addresses found by matching the 2026-09-24 build's code (behaviours, registry and the behavior dispatcher match
-- none of the patterns above in them, and their code pages are unreadable to the scan). From 26088801 on, AI
-- behavior ids 42-103 moved down one and 115-497 up one (ai_shift: first, last, by), so the laser drones run 191
-- and the Guard Dog 192, and the sentries' ids are moved at start-up (resolve_layout). 26251122 has the same
-- addresses and numbering as 26088801
local KNOWN_BUILDS = { KNOWN,
{ build = 26088801, dll_hash = '6D1D4D3BC6FC84801D9F8F1B310E13A603D07409F3D9495D74B42E1D0BB1C08F', exe_hash = '0ACC07DEBE04714AE04281E1A66BD2EB9D3D85232953E32A93C8A3DD0874EABE',
  dll_stamp = '1792524381/54009856', exe_stamp = '1792510989/44032000',
  globals = { mission = 47061072, players = 47060504, owners = 47071672, equipment = 47061224, backpacks = 47060888, attachments = 47062920, targeting = 47062768, behaviours = 47061232, perception = 47060728, registry = 47062648, clock = 47060216, weapons = 47062688, heatbar = 47062792, health = 47061048 },
  owner_index = 15878544, owner_rows = 15944160, stride = 504, exe_units = 28014328, laser_behaviour = 191, ping = 47060480,
  ai_shift = { { 42, 103, -1 }, { 115, 497, 1 } } },
{ build = 26251122, dll_hash = '61DCFCD201DACBF3545C97BEB8A5A6186E9850D2670BF60B0E058320B477F6DF', exe_hash = '257FD7DE21A04E8668E02E5C820EDF3435176FBDE3569765255CC52A5EA20F9D',
  dll_stamp = '1793123839/54009856', exe_stamp = '1793103434/44032000',
  globals = { mission = 47061072, players = 47060504, owners = 47071672, equipment = 47061224, backpacks = 47060888, attachments = 47062920, targeting = 47062768, behaviours = 47061232, perception = 47060728, registry = 47062648, clock = 47060216, weapons = 47062688, heatbar = 47062792, health = 47061048 },
  owner_index = 15878544, owner_rows = 15944160, stride = 504, exe_units = 28014328, laser_behaviour = 191, ping = 47060480,
  ai_shift = { { 42, 103, -1 }, { 115, 497, 1 } } } }

-- ======================================================================================================
-- Layout: where the game keeps things. Known build -> built-in table; new build -> scan the game's code.
-- ======================================================================================================
local function file_sha256(module)
  local path = ffi.new('uint16_t[4096]')
  local n = K32.SgdGetModuleFileNameW(module, path, 4096)
  assert(n > 0 and n < 4096, 'module path')
  local file = K32.SgdCreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
  assert(file ~= ffi.cast('void *', -1), 'cannot open module file')
  local alg, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
  local ok, res = pcall(function()
    assert(BCRYPT.SgdBCryptOpenAlgorithmProvider(alg, ffi.new('uint16_t[?]', 7, { 83, 72, 65, 50, 53, 54, 0 }), nil, 0) == 0, 'sha256')
    assert(BCRYPT.SgdBCryptCreateHash(alg[0], hash, nil, 0, nil, 0, 0) == 0, 'sha256')
    local buf, got = ffi.new('uint8_t[262144]'), ffi.new('uint32_t[1]')
    while true do
      assert(K32.SgdReadFile(file, buf, 262144, got, nil) ~= 0, 'read module file')
      if got[0] == 0 then break end
      assert(BCRYPT.SgdBCryptHashData(hash[0], buf, got[0], 0) == 0, 'sha256')
    end
    local out = ffi.new('uint8_t[32]')
    assert(BCRYPT.SgdBCryptFinishHash(hash[0], out, 32, 0) == 0, 'sha256')
    local t = {}
    for i = 0, 31 do t[#t + 1] = string.format('%02X', out[i]) end
    return table.concat(t)
  end)
  if hash[0] ~= nil then BCRYPT.SgdBCryptDestroyHash(hash[0]) end
  if alg[0] ~= nil then BCRYPT.SgdBCryptCloseAlgorithmProvider(alg[0], 0) end
  K32.SgdCloseHandle(file)
  if not ok then error(res, 0) end
  return res
end

local function code_section(module)
  local b = ffi.cast('uint8_t *', module)
  local function r32(p) return tonumber(ffi.cast('uint32_t *', p)[0]) end
  local function r16(p) return tonumber(ffi.cast('uint16_t *', p)[0]) end
  local pe = r32(b + 0x3c)
  local count, optsize = r16(b + pe + 6), r16(b + pe + 20)
  local sec = b + pe + 24 + optsize
  for i = 0, count - 1 do
    local s = sec + 40 * i
    local vsize, rva, flags = r32(s + 8), r32(s + 12), r32(s + 36)
    if bit.band(flags, 0x20000000) ~= 0 and vsize > 0x100000 then
      local text = read(tonumber(ffi.cast('uintptr_t', b)) + rva, vsize)
      assert(text, 'cannot read code section')
      return text, rva
    end
  end
  error('no code section', 0)
end

local function compile(p)
  local segs, cur_off, cur = {}, nil, {}
  local n = #p / 2
  for k = 0, n - 1 do
    local h = p:sub(2 * k + 1, 2 * k + 2)
    if h == '??' then
      if cur_off then segs[#segs + 1] = { cur_off, table.concat(cur) }; cur_off, cur = nil, {} end
    else
      cur_off = cur_off or k
      cur[#cur + 1] = string.char(tonumber(h, 16))
    end
  end
  if cur_off then segs[#segs + 1] = { cur_off, table.concat(cur) } end
  local anchor = 1
  for j = 2, #segs do if #segs[j][2] > #segs[anchor][2] then anchor = j end end
  return segs, anchor, n
end

-- 0-based offset of the single place the pattern matches, or nil + why
local function find_once(text, p)
  local segs, anchor, n = compile(p)
  local a = segs[anchor]
  local init, found, count = 1, nil, 0
  while true do
    local s = string.find(text, a[2], init, true)
    if not s then break end
    local start = s - 1 - a[1]
    local ok = start >= 0 and start + n <= #text
    if ok then
      for j, seg in ipairs(segs) do
        if j ~= anchor and text:sub(start + seg[1] + 1, start + seg[1] + #seg[2]) ~= seg[2] then ok = false; break end
      end
    end
    if ok then
      count = count + 1; found = start
      if count > 1 then return nil, 'matches more than once' end
    end
    init = s + 1
  end
  if count == 0 then return nil, 'not found' end
  return found
end

local function su32(t, o) local a, b2, c, d = t:byte(o + 1, o + 4); return a + b2 * 256 + c * 65536 + d * 16777216 end
local function si32(t, o) local v = su32(t, o); return v >= 2147483648 and v - 4294967296 or v end

local function scan_layout(game, exe, dll_hash, exe_hash)
  local t0 = os.clock()
  local text, rva = code_section(game)
  local L = { dll_hash = dll_hash, exe_hash = exe_hash, globals = {} }
  local function at(p, what) local o, why = find_once(text, p); assert(o, what .. ': ' .. tostring(why)); return o end
  -- ((4.6.4 review) when the patterns disagree the value most of them agree on wins and the odd one is noted; only a
  -- tie is an error - before, one pattern finding the wrong place after a patch turned the whole mod off)
  local function target(txt, base_rva, pats, what)
    local votes, order = {}, {}
    for _, p in ipairs(pats) do
      local o = find_once(txt, p.p)
      if o then
        local v = base_rva + o + p.size + si32(txt, o + p.disp_at)
        if not votes[v] then votes[v] = 0; order[#order + 1] = v end
        votes[v] = votes[v] + 1
      end
    end
    local val, best, tie = nil, 0, false
    for _, v in ipairs(order) do
      if votes[v] > best then val, best, tie = v, votes[v], false elseif votes[v] == best then tie = true end
    end
    assert(val, what .. ': not found')
    assert(not tie, what .. ': patterns disagree')
    if #order > 1 then note(string.format('%s: %d of the patterns agree (the others found another place)', what, best)) end
    return val
  end
  for name, pats in pairs(PATTERNS.globals) do L.globals[name] = target(text, rva, pats, name) end
  for name, pats in pairs(PATTERNS.optional or {}) do
    local ok, v = pcall(target, text, rva, pats, name)
    if ok then L.globals[name] = v else note('optional game address not found (' .. name .. '): ' .. tostring(v)) end
  end
  L.stride = su32(text, at(PATTERNS.stride, 'behavior stride') + 5)
  L.owner_index = su32(text, at(PATTERNS.owner_index, 'owner map') + 3) - 8
  L.owner_rows = su32(text, at(PATTERNS.owner_rows, 'owner entities') + 10) - 8
  -- the laser drones' AI behavior id: the dispatcher case that calls the laser drone handler
  -- ((4.6.4 review) all of it in a pcall with the jump table bounds-checked: if it fails after a patch, the last known
  -- id is used instead of turning the whole mod off)
  local okd, whyd = pcall(function()
    local d = at(PATTERNS.dispatch.p, 'behavior dispatcher')
    local count, tbl = su32(text, d + PATTERNS.dispatch.count_at), su32(text, d + PATTERNS.dispatch.table_at)
    local handler = find_once(text, PATTERNS.laser_fn)
    if handler and count < 4096 then
      for i = 0, count do
        local o = tbl - rva + 4 * i
        if o < 0 or o + 4 > #text then break end
        local e = su32(text, o) - rva
        if e >= 0 and e + 17 <= #text and text:sub(e + 1, e + 6) == '\139\215\72\139\203\232'
          and text:sub(e + 11, e + 17) == '\72\129\196\208\1\0\0' and e + 10 + si32(text, e + 6) == handler then
          assert(not L.laser_behaviour, 'laser handler found twice')
          L.laser_behaviour = i + 1
        end
      end
    end
  end)
  if not okd then L.laser_behaviour = nil; note('laser behavior scan failed: ' .. tostring(whyd)) end
  if not L.laser_behaviour then note('laser behavior not identified; using the last known id'); L.laser_behaviour = KNOWN.laser_behaviour end
  text = nil
  local etext, erva = code_section(exe)
  L.exe_units = target(etext, erva, PATTERNS.exe_units, 'exe units')
  note(string.format('scan took %.2fs', os.clock() - t0))
  return L
end

local function serialize(v)
  if type(v) == 'number' then return string.format('%.17g', v) end
  if type(v) == 'string' then return string.format('%q', v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = '[' .. serialize(k) .. ']=' .. serialize(x) end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- (4.6.4 review) a module's PE time stamp and image size, from its header in memory ('stamp/size')
local function pe_stamp(module)
  local h = read(tonumber(ffi.cast('uintptr_t', module)), 1024)
  if not h then return nil end
  local pe = su32(h, 0x3c)
  if pe + 24 + 60 > #h or h:sub(pe + 1, pe + 4) ~= 'PE\0\0' then return nil end
  return su32(h, pe + 8) .. '/' .. su32(h, pe + 24 + 56)
end

-- (the mod's version and its pattern set: a cached scan from another version of the mod is scanned again)
-- ((4.6.6 review) and a checksum of the patterns themselves: a test build with changed pattern bytes shares the version
-- number, and reused the previous build's cached addresses without running its own patterns)
local function canonical(v)
  if type(v) ~= 'table' then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. '=' .. canonical(v[k]) end
  return '{' .. table.concat(out, ',') .. '}'
end
local function cache_tag()
  local names = {}
  for k in pairs(PATTERNS.globals) do names[#names + 1] = k end
  for k in pairs(PATTERNS.optional or {}) do names[#names + 1] = k end
  table.sort(names)
  local s, h = canonical(PATTERNS), 0x811c9dc5          -- FNV-1a, 32 bits
  for i = 1, #s do
    local x = bit.bxor(h, s:byte(i)) % 4294967296           -- (16777619 = 2^24 + 403, split so the double stays exact)
    h = (x * 16777216 % 4294967296 + x * 403) % 4294967296
  end
  -- ((4.6.4 release review) the plain version number: the release and its Tester share a scan)
  return (VERSION:match('^[%d%.]+') or VERSION) .. '|' .. bit.tohex(h) .. '|' .. table.concat(names, ',')
end

local function resolve_layout()
  local game, exe = K32.SgdGetModuleHandleA('game.dll'), K32.SgdGetModuleHandleA(nil)
  assert(game ~= nil and exe ~= nil, 'game modules not loaded')
  local gst, est = pe_stamp(game), pe_stamp(exe)
  local L, gsha, esha
  local cache = CACHEDIR and (CACHEDIR .. '\\SmarterGuardDogsAndSentries.cache')
  -- the cached scan, when it is complete and from this version of the mod ((4.6.4 review) with every required address)
  local function cached()
    local f = cache and io.open(cache, 'r')
    if not f then return nil end
    local src = f:read('*a'); f:close()
    local fn = loadstring and loadstring('return ' .. src)
    local ok, c = pcall(fn or error)
    if not (ok and type(c) == 'table') then return nil end
    local whole = type(c.globals) == 'table'
    if whole then for k in pairs(PATTERNS.globals) do if not c.globals[k] then whole = false end end end
    return c, whole and c.mod == cache_tag()
  end
  -- (LuaJIT 26251122 port) any of the known builds
  local known
  for _, k in ipairs(KNOWN_BUILDS) do if gst and est and gst == k.dll_stamp and est == k.exe_stamp then known = k end end
  if known then
    -- (a known build, by its stamps: no hashing)
    gsha, esha = known.dll_hash, known.exe_hash
    note('game.dll ' .. gsha:sub(1, 16) .. '  exe ' .. esha:sub(1, 16) .. ' (by stamp)')
  else
    -- ((4.6.6 review) a cached scan of this build, by its stamps: no hashing either - before, every start after a game
    -- patch hashed both files, about 135 MB, until a mod update knew the new build)
    local c, usable = cached()
    if c and usable and gst and est and c.dll_stamp == gst and c.exe_stamp == est then
      L, gsha, esha = c, c.dll_hash, c.exe_hash
      note('game.dll ' .. tostring(gsha):sub(1, 16) .. '  exe ' .. tostring(esha):sub(1, 16) .. ' (by stamp, cached)')
    else
      gsha, esha = file_sha256(game), file_sha256(exe)
      note('game.dll ' .. gsha:sub(1, 16) .. '  exe ' .. esha:sub(1, 16))
    end
  end
  -- ((5.1.5 Test 18, test builds) whether the game's Lua compiles mod code or only interprets it: it decides what
  -- costs the most in a big fight (uncompiled, every small throwaway object counts)
  if TESTER then
    local okj, j = pcall(function() return rawget(_G, 'jit') or require('jit') end)
    if okj and type(j) == 'table' then
      local okst, on = pcall(j.status)
      note(string.format('lua (test): %s, compiler %s', tostring(j.version), okst and (on and 'on' or 'off') or 'unknown'))
    else note('lua (test): no jit library') end
  end
  if not known then for _, k in ipairs(KNOWN_BUILDS) do if gsha == k.dll_hash and esha == k.exe_hash then known = k end end end
  if L then
    note('layout: cached scan of this game version')
  elseif known then
    L = known; note('layout: built-in (known game version' .. (known.build and ' ' .. known.build .. ', added by the LuaJIT port' or '') .. ')')
  else
    local c, usable = cached()
    if c and usable and c.dll_hash == gsha and c.exe_hash == esha then L = c; note('layout: cached scan of this game version')
    elseif c and c.dll_hash == gsha then note(c.mod ~= cache_tag() and 'layout: the cached scan is from another version of the mod' or 'layout: the cached scan is from another game build') end   -- ((4.6.7 review) which one)
    if not L then
      note('layout: new game version, scanning game code...')
      L = scan_layout(game, exe, gsha, esha)
      L.mod = cache_tag()
      L.dll_stamp, L.exe_stamp = gst, est      -- ((4.6.6 review) so the next start finds it without hashing)
      if cache then local w = io.open(cache, 'w'); if w then w:write(serialize(L)); w:close() end end
    end
  end
  -- absolute addresses
  local gbase, ebase = tonumber(ffi.cast('uintptr_t', game)), tonumber(ffi.cast('uintptr_t', exe))
  local A = { stride = L.stride, owner_index = L.owner_index, owner_rows = L.owner_rows, laser_behaviour = L.laser_behaviour,
    exe_units = ebase + L.exe_units, g = {}, gbase = gbase, ping = L.ping and gbase + L.ping }
  for k, v in pairs(L.globals) do A.g[k] = gbase + v end
  note(string.format('laser behavior %d, guard dog behavior %d', L.laser_behaviour, L.laser_behaviour + 1))
  -- (LuaJIT 26251122 port) the sentries' AI behavior ids (written for the 2026-09-24 build) in this build's numbering
  if L.ai_shift and not SGD.ai_shifted then
    SGD.ai_shifted = L.build or true
    local function shifted(id)
      for _, r in ipairs(L.ai_shift) do if id >= r[1] and id <= r[2] then return id + r[3] end end
      return id
    end
    local function moved(set) local out = {}; for id, v in pairs(set) do out[shifted(id)] = v end; return out end
    for _, d in ipairs(SENTRIES) do
      if d.ai then d.ai = shifted(d.ai) end
      if d.ais then d.ais = moved(d.ais) end
    end
    local ids = moved(SENTRY_AI)
    for id in pairs(SENTRY_AI) do SENTRY_AI[id] = nil end
    for id, v in pairs(ids) do SENTRY_AI[id] = v end
    local l = {}
    for _, d in ipairs(SENTRIES) do l[#l + 1] = d.name .. ' ' .. d.ai end
    note('AI behavior ids of build ' .. tostring(L.build) .. ': ' .. table.concat(l, ', '))
  end
  return A
end

-- ======================================================================================================
-- Reading the game: the local player's guard dog, its AI record and what it can see
-- ======================================================================================================
local A   -- absolute layout, set at start-up

-- (4.6.3) the names other files use are declared here; the rest of this file sits in a do-block so its own
-- helpers stop counting toward Lua's 200 locals of the main chunk once the file ends
local is_local, unit_position, team, team_wanted, OPT, FRAME, teammates, team_detail, GROUPS, SINGLES, find_player, read_candidates, in_mission, read_state, PERC, loss_cut, HEALTH, IDLE   -- ((4.6.6 review) loss_cut: was a global)
-- ((5.1.5 Test 5) HEALTH: the game's health records, for the damage check of the sentries and dogs (below))
-- ((5.1.5 Test 11) IDLE: the mod idling while it has nothing to do (my ask: "If a guard dog is put away and there
-- are no deployed sentries, the mod shouldnt run. If there are no enemies within 150, then the mod shouldnt run as no
-- sentry/dog can engage at that range"): one cheap look every 0.25 s instead, see near_hostile, dog_peek (below), the
-- sentries' sleep in sentry_tick and the main loop
do
function is_local(entity) return bit.band(entity:byte(21), 3) == 1 end

-- world pose of a unit (position + rotation axes), from the engine's unit table in helldivers2.exe.
-- The first lookup of a unit walks the table and checks it thoroughly; after that its object is remembered
-- and only its id is re-checked (the remembered objects are dropped whenever the dog is looked up afresh).
local VTABLE_CHECK = '\72\141\65\96\195'   -- the unit class's "world pose" accessor: lea rax,[rcx+60h]; ret
local unit_cache = {}
local function unit_object(id)
  local obj = unit_cache[id]
  if obj then
    local h = read(obj, 144)
    if h and u32(h, 8) == id then return obj, h end
    unit_cache[id] = nil
  end
  local units = rptr(A.exe_units, 'unit table')
  local index = id % 4194304
  local count = u32(rd(units + 152, 4, 'unit count'), 0)
  if index >= count then return nil end
  local gen = rd(rptr(units + 160, 'unit generations') + index, 1, 'unit generation'):byte()
  if gen ~= math.floor(id / 4194304) % 256 then return nil end
  obj = rptr(rptr(units + 136, 'unit array') + 8 * index, 'unit')
  local h = rd(obj, 144, 'unit')
  if u32(h, 8) ~= id then return nil end
  if rd(rptr(rptr(obj, 'unit vtable') + 232, 'unit accessor'), 5, 'unit accessor') ~= VTABLE_CHECK then return nil end
  unit_cache[id] = obj
  return obj, h
end
-- ((4.6.4 review) the work in a named function: a new closure for every call - the drone, you, each teammate, each
-- sentry, every weapon record looked at - stopped LuaJIT from compiling these paths)
local function unit_position_raw(id, want_axes)
    local obj, h = unit_object(id)
    if not obj then return nil end
    local pose = need(ptr_of(h, 136), 'unit pose')
    local m = rd(pose, 64, 'unit pose')
    local x, y, z = f32(m, 48), f32(m, 52), f32(m, 56)
    if x ~= x or y ~= y or z ~= z or math.abs(x) > 1e6 or math.abs(y) > 1e6 or math.abs(z) > 1e6 then return nil end
    local p = { x, y, z, pose = pose }
    if want_axes then
      -- rotation rows, normalized; dropped if they do not look like a rotation
      local axes = {}
      for r = 0, 2 do
        local a = { f32(m, r * 16), f32(m, r * 16 + 4), f32(m, r * 16 + 8) }
        local len = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
        if not (len > 0.5 and len < 2) then axes = nil; break end
        axes[r + 1] = { a[1] / len, a[2] / len, a[3] / len }
      end
      p.axes = axes
    end
    return p
end
function unit_position(id, want_axes)
  if not id or id == 0 then return nil end
  local ok, pos = pcall(unit_position_raw, id, want_axes)
  return ok and pos or nil
end

-- Teammates: every helldiver has a row in the same owner table as ours (2048 rows of 24 bytes; the game's own
-- code wraps its free-row search at 0x800). The whole table is read in one go once a second and the rows of
-- other players' helldivers kept; in between only their positions are read (two small reads each).
local OWNER_ROWS = 2048
local TEAM_SCAN_SECONDS = 1.0
local TEAM_MAX = 8
team = { units = {}, next_scan = 0, key = nil, last = {}, found = 0, rows = {}, moved = {}, players = '?' }
local function scan_teammates(owners, player_unit)
  local rows = read(owners + A.owner_rows, OWNER_ROWS * 24)
  local units = {}
  if not rows then return units, 0 end
  local found, at = 0, 1
  team.rows = {}
  while true do
    local p = rows:find(AVATAR_TYPE, at, true)
    if not p then break end
    if (p - 1) % 24 == 0 then
      local row = rows:sub(p, p + 23)
      local unit = u32(row, 12)
      if not is_local(row) and unit ~= 0 and unit ~= 4294967295 and unit ~= player_unit then
        found = found + 1
        -- (test builds: what each row looks like, to tell live teammates from leftovers such as bodies)
        if TESTER then team.rows[#team.rows + 1] = { index = (p - 1) / 24, owner = u32(row, 8), unit = unit, raw = row:sub(17, 24) } end
        if #units < TEAM_MAX then units[#units + 1] = unit end
      end
    end
    at = p + 1
  end
  return units, found
end

-- switched on by the optional 'Teammate safety' part of the mod (a tiny second addon that sets this flag); read
-- every frame, so load order does not matter. While it is off, teammates are not looked up at all.
local team_state
function team_wanted()
  local on = rawget(_G, 'SmarterGuardDogsTeammates') == true
  if on ~= team_state then
    team_state = on; session.team.off = not on
    note('teammate safety: ' .. (on and 'on' or (rawget(_G, 'SmarterGuardDogsMenu') and 'off (in the mod options menu)' or 'off (option not installed)')))
  end
  return on
end

-- (4.0.1) the optional parts that choose what the mod handles: Safety (you), Guard Dogs and Sentries (each set by a
-- tiny addon, like the laser's). Read every frame, so load order doesn't matter.
OPT = {}
do
  local noted = {}
  local function flag(key, name, off_text)
    local on = rawget(_G, key) == true
    if noted[key] ~= on then
      noted[key] = on
      note(name .. ': ' .. (on and 'on' or ((rawget(_G, 'SmarterGuardDogsMenu') and 'off (in the mod options menu)' or 'off (option not installed)') .. off_text)))
    end
    return on
  end
  OPT.safety = function() return flag('SmarterGuardDogsSafety', 'safety for you', ': your dogs and sentries may fire through you') end
  OPT.dogs = function() return flag('SmarterGuardDogsDogs', 'guard dogs', ': left to the game') end
  OPT.sentries = function() return flag('SmarterGuardDogsSentries', 'sentries', ': left to the game') end
  OPT.tesla = function() return flag('SmarterGuardDogsTesla', 'tesla tower', ': left to the game') end
  -- (4.6.5) Sentry Safety: your sentries don't fire through or blast any sentry out - yours or another player's
  OPT.sentry_safety = function() return flag('SmarterGuardDogsSentrySafety', 'sentry safety', ': your sentries may fire through other sentries') end
  -- (4.7.0) SEAF Safety: your dog and sentries don't fire through, swing across or blast SEAF soldiers and civilians
  OPT.seaf_safety = function() return flag('SmarterGuardDogsSEAFSafety', 'SEAF safety', ': your dog and sentries may fire through SEAF soldiers and civilians') end
  -- (5.0) Ping Targeting: your sentries go for a pinged enemy they can hurt first
  OPT.ping = function() return flag('SmarterGuardDogsPing', 'ping targeting', ': your sentries pick their own targets, pinged or not') end
  -- (5.0 Test 13) Targeting Marker: the gun's icon over the enemy it is on (its own option; works without the laser)
  OPT.marker = function() return flag('SmarterGuardDogsMarker', 'targeting marker', ': no markers over enemies') end
  OPT.priority = function() return flag('SmarterGuardDogsPriority', 'target prioritization', ': the game decides the order') end
end

-- positions of the other players' helldivers (with a smoothed velocity, for a short look-ahead). Worked out once
-- per frame: the dogs and the sentries share the result.
FRAME = 0   -- counts the mod's frames (the main loop adds one each tick)
function teammates(c, t)
  if team.frame == FRAME and team.frame_key == c.team_key and team.frame_mates then return team.frame_mates end
  if t >= team.next_scan or team.key ~= c.team_key then
    team.units, team.found = scan_teammates(c.owners, c.player_unit)
    team.next_scan, team.key = t + TEAM_SCAN_SECONDS, c.team_key
    local keep, moved = {}, {}
    for _, u in ipairs(team.units) do keep[u] = team.last[u]; moved[u] = team.moved[u] end
    team.last, team.moved = keep, moved   -- (4.6.3 review: 'moved' was never pruned - every respawn added a unit)
  end
  local mates = {}
  for _, u in ipairs(team.units) do
    local p = unit_position(u)
    if p then
      local prev = team.last[u]
      local vel = prev and prev.vel
      if not prev or p[1] ~= prev[1] or p[2] ~= prev[2] or p[3] ~= prev[3] then team.moved[u] = t end
      if prev and (p[1] ~= prev[1] or p[2] ~= prev[2] or p[3] ~= prev[3]) then
        -- remote helldivers move in network steps (the same spot for a few frames, then a jump), so the speed is
        -- taken between position changes, smoothed, and teleports (respawn, ragdoll) are ignored
        local dt = t - prev.t
        if dt > 0.004 and dt < 0.3 then
          local v = { (p[1] - prev[1]) / dt, (p[2] - prev[2]) / dt, (p[3] - prev[3]) / dt }
          if v[1] * v[1] + v[2] * v[2] + v[3] * v[3] < 15 * 15 then
            vel = vel and { vel[1] * 0.5 + v[1] * 0.5, vel[2] * 0.5 + v[2] * 0.5, vel[3] * 0.5 + v[3] * 0.5 } or v
          end
        else vel = nil end
        team.last[u] = { p[1], p[2], p[3], t = t, vel = vel }
      elseif not prev then
        team.last[u] = { p[1], p[2], p[3], t = t }
      elseif t - prev.t > 0.3 then
        vel = nil; prev.vel = nil   -- not moving
      end
      mates[#mates + 1] = { p[1], p[2], p[3], vel = vel, unit = u }
    end
  end
  team.frame, team.frame_key, team.frame_mates = FRAME, c.team_key, mates
  return mates
end

-- test builds: one line describing every teammate row found (for the log)
function team_detail(me)
  local out = { 'players ' .. tostring(team.players) }
  for _, r in ipairs(team.rows) do
    local last = team.last[r.unit]
    local d = (last and me) and string.format('%.0f m', math.sqrt((last[1] - me[1]) ^ 2 + (last[2] - me[2]) ^ 2 + (last[3] - me[3]) ^ 2)) or 'no position'
    local still = team.moved[r.unit] and string.format('still %.0fs', os.clock() - team.moved[r.unit]) or 'never seen'
    out[#out + 1] = string.format('row %d owner %d unit %d [%s] %s %s', r.index, r.owner, r.unit,
      (r.raw:gsub('.', function(c) return string.format('%02x', c:byte()) end)), d, still)
  end
  return table.concat(out, '; ')
end

-- (count offset, first entry, and the name the research log shows; singles: entry and name)
GROUPS = { { 784, 792, 'g1' }, { 2072, 2080, 'g2' }, { 3360, 3368, 'g3' } }
SINGLES = { { 4648, 's1' }, { 4728, 's2' }, { 4808, 's3' } }

-- The walk from the game's player table to our dog's AI and perception records takes ~30 reads. It is done
-- four times a second (and at once if anything looks different); in between the addresses it found are
-- reused and checked against the dog's own AI record every frame.
local LOCATE_SECONDS = 0.25
-- your helldiver: its owner row (id, unit) and the owner table itself (also used for teammates and sentries)
function find_player()
  local g = A.g
  local function global(name) return rptr(g[name], name) end
  local players = global('players')
  local pp = rd(players + 132, 8, 'players')
  need(u32(pp, 0) <= 4 and u32(pp, 4) <= 4, 'player count')
  if u32(pp, 0) == 0 or u32(pp, 4) == 0 then return nil, 'no local player yet' end
  team.players = u32(pp, 0) .. '/' .. u32(pp, 4)
  local avatar = u32(rd(players + 936, 4, 'avatar'), 0)
  if avatar == 32767 then return nil, 'no helldiver yet' end

  local owners = global('owners')
  local e = map_lookup(owners + A.owner_index, avatar, 1048576)
  if not e then return nil, 'no helldiver yet' end
  need(e < 262144, 'owner index')
  local me = rd(owners + A.owner_rows + e * 24, 24, 'owner entity')
  if not is_local(me) then return nil, 'helldiver is not ours' end
  -- (4.6.5, a commenter: players in exosuits weren't protected) while you pilot something (an exosuit, say) the game's
  -- avatar is that unit, not your helldiver: it used to end here - no body for you, the sentries' safety off for you.
  -- Now it is returned as a vehicle (its type), and the sentries keep a larger body round it (bodies_for)
  if me:sub(1, 8) ~= AVATAR_TYPE then
    return { me = me, owner_id = u32(me, 8), player_unit = u32(me, 12), owners = owners, team_key = me:sub(1, 20), vehicle = me:sub(1, 8) }
  end
  return { me = me, owner_id = u32(me, 8), player_unit = u32(me, 12), owners = owners, team_key = me:sub(1, 20) }
end

local function locate()
  local g = A.g
  local function global(name) return rptr(g[name], name) end
  -- (the Guard Dogs option off: nothing to look up, your dog is left to the game)
  if not OPT.dogs() then return nil, 'guard dogs option off (left alone)' end
  local pl, why = find_player()
  if not pl then return nil, why end
  if pl.vehicle then return nil, 'piloting a vehicle' end   -- (4.6.5: as before, the dog is left alone then)
  local me, owner_id, player_unit, owners = pl.me, pl.owner_id, pl.player_unit, pl.owners

  local equipment = global('equipment')
  local q = map_lookup(equipment + 40, owner_id, 8192)
  if not q then return nil, 'no loadout' end
  need(q < 4096, 'equipment index')
  need(rd(rptr(rptr(equipment + 64, 'equipment owners') + q * 8, 'equipment owner'), 20, 'equipment owner') == me:sub(1, 20), 'equipment owner')
  local slot = rd(rptr(equipment + 80, 'equipment slots') + q * 48, 16, 'equipment slot')
  local pack_id = u32(slot, 12)
  if pack_id == 0 or pack_id == 4294967295 then return nil, 'no backpack worn' end

  local backpacks = global('backpacks')
  local n = u32(rd(backpacks + 16, 4, 'backpack count'), 0)
  need(n <= 256, 'backpack count')
  local packs, drones = rptr(backpacks + 56, 'backpack list'), rptr(backpacks + 80, 'backpack drones')
  local dog, drone_index, pack_i, pack_p
  for i = 0, n - 1 do
    local pp = ptr_of(read(packs + i * 8, 8), 0)
    local pe = read(pp or 0, 24)
    if pe and u32(pe, 8) == pack_id then
      dog = DOG_BY_PACK[pe:sub(1, 8)]
      if not dog then return nil, 'backpack is not a supported dog' end
      if not is_local(pe) then return nil, 'backpack is not ours' end
      drone_index = u32(rd(drones + i * 8, 8, 'backpack drone'), 4)
      pack_i, pack_p = i, pp
      break
    end
  end
  if not dog then return nil, 'no backpack worn' end
  if not drone_index or drone_index == 32767 then
    -- ((5.1.5 Test 11) where its drone will show when it is launched: looked at every 0.25 s while it is put away)
    IDLE.pack = pack_i and { packs + pack_i * 8, pack_p, drones + pack_i * 8 } or nil
    return nil, 'dog not deployed'
  end
  IDLE.pack = nil

  local attachments = global('attachments')
  local at = map_lookup(attachments + 32, pack_id, 8192)
  if not at then return nil, 'backpack not attached' end
  need(at < 4096, 'attachment index')
  if u32(rd(rptr(attachments + 64, 'attachments') + at * 48, 8, 'attachment'), 4) ~= owner_id then return nil, 'backpack not on our helldiver' end

  local targeting, behaviours = global('targeting'), global('behaviours')
  local reg = rd(targeting + 308, 84, 'targeting registry')
  local tn, ta, tb = u32(reg, 0), u32(reg, 12), u32(reg, 16)
  need(tb <= ta and ta <= tn and tn <= 8192, 'targeting registry')
  local tents, tstates = rptr(targeting + 360, 'targeting entities'), rptr(targeting + 376, 'targeting states')
  local slot_i, drone_ptr, drone_ent
  local function try(i, p)
    local de = p and read(p, 24)
    if de and de:sub(1, 8) == dog.drone and u32(de, 16) == drone_index then slot_i, drone_ptr, drone_ent = i, p, de; return true end
  end
  -- ((5.1.5 Test 11) the slot it had at the last look first (from its id in the targeting map): this look runs every
  -- 0.25 s while the dog is out, and walked the whole agent list - two reads an agent, hundreds in a big fight - each time)
  local last = IDLE.drone
  if last and last.index == drone_index then
    local i = map_lookup(targeting + 336, last.id, 16384)
    if i and i < tn then try(i, ptr_of(read(tents + i * 8, 8), 0)) end
  end
  if not slot_i and tn > 0 then
    local ptrs = rd(tents, 8 * tn, 'targeting entities')   -- (one read for the whole list)
    for i = 0, tn - 1 do if try(i, ptr_of(ptrs, i * 8)) then break end end
  end
  if slot_i and not is_local(drone_ent) then return nil, 'dog is not ours' end
  if not slot_i then return nil, 'dog has no targeting' end
  local drone_id, drone_unit = u32(drone_ent, 8), u32(drone_ent, 12)
  need(map_lookup(targeting + 336, drone_id, 16384) == slot_i, 'targeting slot')
  IDLE.drone = { id = drone_id, index = drone_index }

  local bi = map_lookup(behaviours + 64, drone_id, 32768)
  if not bi then return nil, 'dog has no AI record' end
  need(bi < u32(rd(behaviours + 32, 4, 'behavior count'), 0) and bi < 16384, 'behavior index')
  need(rptr(rptr(behaviours + 88, 'behavior owners') + bi * 8, 'behavior owner') == drone_ptr, 'behavior owner')
  local rec_addr = rptr(behaviours + 96, 'behavior records') + bi * A.stride
  local rec = rd(rec_addr, 160, 'behavior record')
  local want_behaviour = dog.laser and A.laser_behaviour or A.laser_behaviour + 1
  if u32(rec, 0) ~= want_behaviour then return nil, 'dog AI type ' .. u32(rec, 0) end
  need(u32(rec, 104) == drone_id, 'perception owner')

  local perception = global('perception')
  local pi = map_lookup(perception + 48, drone_id, 32768)
  if not pi then return nil, 'dog has no perception' end
  need(pi < 16384, 'perception index')
  need(rptr(rptr(perception + 72, 'perception owners') + pi * 8, 'perception owner') == drone_ptr, 'perception owner')
  local pbase = rptr(perception + 80, 'perception records') + pi * 5112
  -- (4.5.3 Test 9) the dog's fire node: the part the game fires its weapon from (the muzzle), from the same weapon
  -- records as the sentries' (optional). The laser starts there. Before, the barrel was guessed from the drone's parts,
  -- and the guess could land on an aiming helper higher up on the drone (a tester's picture: the Guard Dog's beam
  -- above its gun; the Rover's guess was dropped and its beam left the drone's front as before)
  local fire_nodes, wr_addr, fire_unit, fire_how
  -- (4.6.0 review: only while the laser is on - nothing else uses it)
  if A.g.weapons and rawget(_G, 'SmarterGuardDogsLaser') == true then
    pcall(function()
      local wm = rptr(A.g.weapons, 'weapons')
      local owners, runtimes = rptr(wm + 72, 'weapon owners'), rptr(wm + 88, 'weapon runtimes')
      local function nodes_of(wi)
        local addr = runtimes + wi * 1008
        local wr = rd(addr, 228, 'weapon runtime')
        local count = u32(wr, 216)
        if count == 0 or count > 24 then return nil end
        local l = {}
        for j = 0, count - 1 do
          local nj = u32(wr, 120 + 4 * j)
          if nj < 1024 then l[j] = nj end
        end
        if next(l) then return l, addr end
      end
      local wi = map_lookup(wm + 48, drone_id, 32768)
      if wi and wi < 16384 and rptr(owners + wi * 8, 'weapon owner') == drone_ptr then
        fire_nodes, wr_addr = nodes_of(wi)
        fire_unit, fire_how = drone_unit, 'the drone'
        return
      end
      -- (4.5.3 Test 11) the dogs' guns have weapon records of their own (Test 10 log: none under the drone's id), so the
      -- gun is looked for among all weapon records: the dog's own gun type (Guard Dog, Rover, K-9 from tester logs)
      -- within 3 m of the drone, else a weapon of another type within 0.5 m of it and not on you. Up to 3 tries 5 s apart
      -- per deployment; a gun found is kept while its record still belongs to the same owner
      local F = dog.fire_found
      -- (4.6.3 review: read without raising - an empty owner slot raised before, which skipped the search below for
      -- the rest of the deployment)
      if F and F.drone == drone_id then
        if ptr_of(read(owners + F.wi * 8, 8), 0) == F.ptr then
          fire_nodes, wr_addr = nodes_of(F.wi)
          fire_unit, fire_how = F.unit, F.how
          return
        end
        dog.fire_found = nil
      end
      -- (4.6.0 review: the tries start again for each deployment - before, three failed tries for one drone stopped the
      -- search for every later one in the session)
      if dog.fire_scan_drone ~= drone_id then dog.fire_found, dog.fire_scans, dog.fire_scan_t, dog.fire_scan_drone = nil, 0, nil, drone_id end
      if (dog.fire_scans or 0) >= 3 or (dog.fire_scan_t and os.clock() < dog.fire_scan_t) then return end
      dog.fire_scan_t, dog.fire_scans = os.clock() + 5, (dog.fire_scans or 0) + 1
      local D = unit_position(drone_unit)
      if not D then return end
      local ME = unit_position(player_unit)
      local h = rd(wm + 48, 20, 'map header')
      local cap, empty = u32(h, 8), u32(h, 12)
      if cap == 0 or cap > 32768 or bit.band(cap, cap - 1) ~= 0 then return end
      local raw = read(need(ptr_of(h, 0), 'map slots'), cap * 8)
      if not raw then return end
      local function hx(b) return (b:reverse():gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
      -- (4.6.0 review) the dog's own gun type first: only those records' positions are read. Every record's position
      -- (enemies' weapons too) only when that finds nothing, or once per dog in test builds for their list
      local full = TESTER and not dog.fire_scan_noted
      local best, bd, seen
      for pass = 1, 2 do
        if pass == 2 and best and not full then break end
        best, bd, seen = nil, 9, full and {} or nil
        for i = 0, cap - 1 do
          local key, v = u32(raw, 8 * i), u32(raw, 8 * i + 4)
          if key ~= empty and v < 16384 then
            local op = ptr_of(read(owners + v * 8, 8), 0)   -- ((4.6.6 review) no "or ''": that read 8 bytes past an empty string
            local oe = op and read(op, 24)
            local kind = oe and oe:sub(1, 8)
            local mine = dog.gun and kind == dog.gun
            if oe and kind ~= AVATAR_TYPE and (pass == 2 or mine or not dog.gun) then
              local unit = u32(oe, 12)
              local p = unit_position(unit)
              if p then
                local d2 = (p[1] - D[1]) ^ 2 + (p[2] - D[2]) ^ 2 + (p[3] - D[3]) ^ 2
                if d2 < 9 then
                  if seen then seen[#seen + 1] = string.format('%s id %d unit %d at %.2f m', hx(kind), u32(oe, 8), unit, math.sqrt(d2)) end
                  -- (your own weapons are 0.6-1.2 m from the drone when it leaves your back - a tester's logs; the dogs'
                  -- guns 0.20-0.23 m: a weapon of another type only counts within 0.5 m and not within 0.6 m of you)
                  local on_me = ME and (p[1] - ME[1]) ^ 2 + (p[2] - ME[2]) ^ 2 + (p[3] - ME[3]) ^ 2 < 0.36
                  -- (4.6.3 review: the closest of the dog's own gun type - before, the last one within 3 m won, which
                  -- could be a teammate's dog launched next to yours)
                  if (mine and not (best and best.mine and best.d2 <= d2)) or (not mine and not (best and best.mine) and d2 < bd and d2 < 0.25 and not on_me) then
                    best, bd = { wi = v, unit = unit, id = u32(oe, 8), kind = hx(kind), ptr = op, mine = mine, d2 = d2 }, mine and -1 or d2
                  end
                end
              end
            end
          end
        end
        if not dog.gun then break end   -- (a dog without a known gun type: the one full pass above)
      end
      if seen then
        dog.fire_scan_noted = true
        note('laser (test): weapon records within 3 m of the ' .. dog.name .. ': ' .. (#seen > 0 and table.concat(seen, '; ') or 'none'))
      end
      if best then
        fire_nodes, wr_addr = nodes_of(best.wi)
        fire_unit, fire_how = best.unit, string.format('its gun %s (id %d, unit %d)', best.kind, best.id, best.unit)
        if fire_nodes then dog.fire_found = { drone = drone_id, wi = best.wi, ptr = best.ptr, unit = best.unit, how = fire_how } end
      end
    end)
  end
  if fire_nodes and dog.fire_noted ~= 'found' then
    dog.fire_noted = 'found'
    local l = {}
    for j = 0, 23 do if fire_nodes[j] then l[#l + 1] = tostring(fire_nodes[j]) end end
    note('laser: the ' .. dog.name .. ' fires from part ' .. table.concat(l, ', ') .. ' of ' .. (fire_how or '?') .. ' (its muzzle)')
  elseif not fire_nodes and not dog.fire_noted then
    dog.fire_noted = 'missing'
    note('laser: the ' .. dog.name .. "'s weapon record was not found (yet); its barrel is learned from its parts")
  end
  return {
    dog = dog, key = me:sub(1, 20) .. pack_id .. drone_ent:sub(1, 20), team_key = me:sub(1, 20), rec_addr = rec_addr, want = want_behaviour,
    drone_id = drone_id, drone_unit = drone_unit, player_unit = player_unit, tstate = tstates + slot_i * 208, owners = owners,
    fire_nodes = fire_nodes, wr_addr = wr_addr, fire_unit = fire_nodes and fire_unit,
    pbase = pbase, registry = global('registry'), clock = rptr(g.clock, 'clock'), bi = bi, pi = pi,
  }
end

local ctx, ctx_until = nil, 0
local reg_rows = {}   -- registry index -> entity row address (re-checked on every read)
local reg_frame, reg_seen = -1, {}   -- enemies already looked up this frame (id -> its row, or false)
-- ((5.1.5 Test 18) an enemy's place in the registry map, kept a while (ix: id -> { index, until frame }): the map was
-- looked up afresh for every enemy every frame - over a third of all the mod's reads in my big-fight sim. Its row is
-- still read each frame (still it, still there), and the map asked again after 'keep' frames or as soon as the row
-- isn't it any more. 'fresh': ids looked up in the map this frame. The map's header and row list: once a frame
-- (one table: the main chunk is near LuaJIT's 200 locals)
local REG = { ix = {}, n = 0, keep = 24, fresh = {}, hf = -1, gone = {}, gn = 0, pos = {} }

-- the enemies one AI agent (a dog or a sentry) is currently considering, from its perception record. 'origin' is
-- where distances (d2) are measured from. Also returns the raw record, for the research log.
-- ((4.6.4 review) the perception record is read into one buffer kept for the whole session and parsed in place: before,
-- every dog and busy sentry made a new 5 KB string every frame - about 1.5 MB a second of garbage with five out. Only
-- what the groups and the three singles use (up to 4888 bytes) is read)
local PERC_N = 4888
local PBUF = ffi.new('uint8_t[?]', PERC_N)
local pread, bu32, bf32
do
  local PV, PU32p, PF32p = ffi.typeof('const void *'), ffi.typeof('const uint32_t *'), ffi.typeof('const float *')
  local NAN = 0 / 0
  pread = function(addr)
    return K32.SgdReadProcessMemory(PROCESS, ffi.cast(PV, addr), PBUF, PERC_N, DONE) ~= 0 and DONE[0] == PERC_N
  end
  -- ((5.1.5 Test 18) through typed views of the buffer made once: indexing them gives a plain number, where the
  -- pointer sums before made a small throwaway object per number whenever the code wasn't compiled - every field of
  -- every enemy in every sentry's list, every frame. Every offset read here is a multiple of 4; any other goes the old way)
  local V32, VF = ffi.cast(PU32p, PBUF), ffi.cast(PF32p, PBUF)
  bu32 = function(o)
    if o % 4 == 0 then return V32[o / 4] end
    return tonumber(ffi.cast(PU32p, PBUF + o)[0])
  end
  bf32 = function(o)
    local v
    if o % 4 == 0 then v = VF[o / 4] else v = tonumber(ffi.cast(PF32p, PBUF + o)[0]) end
    if v == nil or v ~= v then return NAN end
    return v
  end
end
-- ((4.6.4 release review) the same buffer for the Tesla Tower's pass right after the game's update (sentry_after),
-- which made a new 5 KB string every frame while a tower was out)
PERC = { read = function(addr) return pread(addr) end, u32 = function(o) return bu32(o) end, str = function(o, n) return ffi.string(PBUF + o, n) end }

-- ((4.6.4 release review) 'want_header': the 264-byte faction list at its start as a string - only the Tesla Tower
-- uses it; every other dog and sentry skipped making it each frame)
-- ((5.1.5 Test 18) 'pool' (a sentry's): its candidate entries are reused from two frames back instead of made anew.
-- They were most of the mod's garbage in a big fight - one table per enemy per sentry per frame, ~350 a frame with 8
-- sentries and 40 enemies. Two sets taken in turn, so last frame's list (its 'st', which the beams and a failed read
-- fall back on) is never written over. Every field is set on each use; 'pos' stays a fresh table, as places are kept
-- (the mortar's landing spot, the laser's ends)
-- ('fresh': the id of its current target, whose place in the map is always looked up afresh: the dead-target rules
-- lean on an enemy dropping out of the registry the frame it does)
-- ((5.1.5 Test 31) an entity's registry row by its id (nil if it isn't there): for a sentry's target that isn't in its own
-- list - my Test 30 log had mortars and the Autocannon on targets missing from their lists for 1,435 frames, so no marker)
function entity_row(registry, id)
  if not (registry and id and id ~= 0) then return nil end
  if REG.hf ~= FRAME or REG.hr ~= registry then
    REG.head = rd(registry + 73808, 20, 'registry map')
    REG.list = ptr_of(read(registry + 73832, 8), 0)
    REG.hf, REG.hr = FRAME, registry
  end
  local ri = map_lookup(registry + 73808, id, 32768, REG.head, true)
  if not ri or ri >= 16384 then return nil end
  local rp = reg_rows[ri]
  local re = rp and read(rp, 24)
  if not (re and u32(re, 8) == id) then
    rp = REG.list and ptr_of(read(REG.list + ri * 8, 8), 0)
    re = rp and read(rp, 24)
    if re then reg_rows[ri] = rp end
  end
  if re and u32(re, 8) == id then return re end
  return nil
end
function read_candidates(pbase, origin, registry, want_header, pool, fresh)
  if pbase == 'forget' then REG.ix, REG.n, REG.gone, REG.gn = {}, 0, {}, 0; return end   -- ((5.1.5 Test 18) a mission's end: ids start over
  need(type(pbase) == 'number' and pbase >= 65536 and pread(pbase), 'perception record')
  local fcount = bu32(0)
  need(fcount <= 32, 'faction filter')
  local filter = 0
  for j = 0, fcount - 1 do
    local f = bu32(8 + j * 8)
    need(f < 32, 'faction id')
    filter = bit.bor(filter, bit.lshift(1, f))
  end

  if REG.hf ~= FRAME or REG.hr ~= registry then
    REG.head = rd(registry + 73808, 20, 'registry map')
    REG.list = ptr_of(read(registry + 73832, 8), 0)
    REG.hf, REG.hr = FRAME, registry
  end
  local reg_head, reg_list = REG.head, REG.list
  local candidates, items, pk
  if pool then
    -- (the set not handed out last time; it only counts as handed out once this read gets through)
    pk = pool.k == 1 and 2 or 1
    candidates, items = pool[pk], pool[pk + 2]
    if not candidates then candidates, items = {}, {}; pool[pk], pool[pk + 2] = candidates, items end
    for i = #candidates, 1, -1 do candidates[i] = nil end
  else candidates = {} end
  local function add(off, group)
    local id = bu32(off)
    if id == 0 then return end
    local flags, faction, score = bu32(off + 72), bu32(off + 76), bf32(off + 68)
    need(score == score and math.abs(score) < 100000, 'candidate score')
    local alive, ent = false, nil
    -- (the dog and every sentry mostly see the same enemies: each is looked up once per frame)
    if reg_frame ~= FRAME then reg_frame, reg_seen, REG.fresh, REG.pos = FRAME, {}, {}, {} end
    local known = reg_seen[id]
    if known ~= nil and (id ~= fresh or REG.fresh[id]) then alive, ent = known ~= false, known or nil
    else
      local kx = REG.ix[id]
      local ri
      if kx and FRAME < kx[2] and id ~= fresh then ri = kx[1]
      -- (one the game itself has down as dead and the map didn't have: not asked again for a while - the dead stay
      -- listed ~1 s, and were each looked up every frame)
      elseif REG.gone[id] and FRAME < REG.gone[id] and bit.band(flags, 1) == 0 then ri = nil
      else
        REG.fresh[id] = true
        ri = map_lookup(registry + 73808, id, 32768, reg_head, true)
        if ri then
          -- (staggered by id, so they don't all come due in the same frame)
          if not kx then
            kx = {}; REG.ix[id] = kx; REG.n = REG.n + 1
            if REG.n > 4096 then REG.ix, REG.n = { [id] = kx }, 1 end   -- (a long mission: started afresh)
          end
          kx[1], kx[2] = ri, FRAME + REG.keep + id % 8
        else
          if kx then REG.ix[id] = nil; REG.n = REG.n - 1 end
          if bit.band(flags, 1) == 0 then
            if not REG.gone[id] then REG.gn = REG.gn + 1; if REG.gn > 1024 then REG.gone, REG.gn = {}, 1 end end
            REG.gone[id] = FRAME + REG.keep
          end
        end
      end
      if ri then
        need(ri < 16384, 'registry index')
        local rp = reg_rows[ri]
        local re = rp and read(rp, 24)
        if not (re and u32(re, 8) == id) then
          rp = reg_list and ptr_of(read(reg_list + ri * 8, 8), 0)
          re = rp and read(rp, 24)
          reg_rows[ri] = rp
        end
        alive = re ~= nil and u32(re, 8) == id
        if alive then ent = re
        elseif REG.ix[id] then REG.ix[id] = nil; REG.n = REG.n - 1 end   -- (not it any more: the map again next time)
      end
      reg_seen[id] = ent or false
    end
    local x, y, z = bf32(off + 4), bf32(off + 8), bf32(off + 12)
    local pos, d2
    if x == x and y == y and z == z and math.abs(x) < 1e6 and math.abs(y) < 1e6 and math.abs(z) < 1e6 then
      -- ((5.1.5 Test 19) one place table per enemy a frame when the lists agree on where it is (they mostly do): every
      -- sentry made its own copy. Nothing changes a place table once made, so sharing it is safe)
      local sp = REG.pos[id]
      if sp and sp[1] == x and sp[2] == y and sp[3] == z then pos = sp
      else pos = { x, y, z }; REG.pos[id] = pos end
      if origin then d2 = (x - origin[1]) ^ 2 + (y - origin[2]) ^ 2 + (z - origin[3]) ^ 2 end
    end
    local n = #candidates + 1
    local c = items and items[n]
    if not c then c = {}; if items then items[n] = c end end
    local o = off + 76
    c.id, c.pos, c.d2, c.entry = id, pos, d2, pbase + off
    c.mask_addr, c.mask = pbase + o, string.char(PBUF[o], PBUF[o + 1], PBUF[o + 2], PBUF[o + 3])
    c.alive, c.score = alive and bit.band(flags, 1) ~= 0, score
    c.group, c.flags, c.off, c.ent = group, flags, off, ent
    c.kind = ent and ent:sub(1, 8) or nil
    -- the dog's own line of sight: set while it can see the enemy, cleared when cover blocks it; the
    -- float after it is how well it still remembers the enemy (1 = seen now, runs down to 0 over ~1 s)
    c.visible = PBUF[off + 48] ~= 0 or (ent ~= nil and SGD.cloaks[ent:sub(1, 8)] == true)
    c.memory = bf32(off + 64)
    c.eligible = alive and bit.band(flags, 1) ~= 0 and bit.band(faction, filter) ~= 0 and score > 0
    -- (what other parts note on an entry, cleared for its reuse: the live place, guarded by the frame anyway)
    c.live_f, c.live_p, c.dp = nil, nil, nil
    candidates[n] = c
  end
  for _, grp in ipairs(GROUPS) do
    local c = bu32(grp[1])
    need(c <= 16, 'candidate group')
    for k = 0, c - 1 do add(grp[2] + k * 80, grp[3]) end
  end
  for _, one in ipairs(SINGLES) do if bu32(one[1] + 72) ~= 0 then add(one[1], one[2]) end end
  if pool then pool.k = pk end
  -- (the faction list at its start, for the Tesla Tower's filter and its test notes)
  return candidates, want_header and ffi.string(PBUF, 264) or nil
end


-- (4.6.5, my note: no more firing at the spot for a second after a target is lost, for every dog and sentry) the AI keeps
-- shooting where its target was until 1 s after the loss time in its record (+408, stamped by the game; found on the
-- Gatling / pod / FRV guns, 4.6.2-4.6.3; the dump shows other sentry AIs with the same check). Moving that time back
-- a second lets the game's own check end the firing at its next update. Only when +408 reads a time from the last
-- second (the loss just happened); returns its age in seconds, written or not, or nil (not a recent time)
function loss_cut(rec_addr, now)
  if (A.stride or 0) < 416 then return nil end
  local lt = read(rec_addr + 408, 8)
  if not lt then return nil end
  local age = now - u64(lt, 0)
  if age < 0 or age >= 1000000 then return nil, age end
  if not write(rec_addr + 408, u64bytes(now - 1000001)) then stats.write_failures = stats.write_failures + 1; return nil end
  return age / 1e6
end

-- ((5.1.5 Test 11) once a frame: the dog's look and the sentries' each asked, 4 reads a poll out of a mission)
local inm_frame, inm_v = -1, false
function in_mission()
  if inm_frame == FRAME then return inm_v end
  local mission_ptr = ptr_of(read(A.g.mission, 8), 0)
  local mission = mission_ptr and read(mission_ptr, 68)
  inm_frame, inm_v = FRAME, mission ~= nil and u32(mission, 8) ~= 0 and u32(mission, 64) ~= 0
  return inm_v
end

-- returns a state table, or nil + a short reason. Game-structure surprises raise an Abort error.
local locate_fail_until, locate_fail_why = 0, nil
function read_state()
  if not in_mission() then
    ctx = nil
    if next(unit_cache) then unit_cache = {} end   -- (4.6.3 review: with no dog out it was never emptied)
    return nil, 'not in a mission'
  end

  local t = os.clock()
  -- (4.6.3 review) after a failed look for your dog (none out, another backpack...) the next is LOCATE_SECONDS later:
  -- while a sentry kept the polls going every frame, it was repeated every frame
  if not ctx and t < locate_fail_until then
    -- ((5.1.5 Test 11) a dog that is put away: only the backpack's drone slot is looked at (2 reads), every 0.25 s)
    local K = IDLE.pack
    if not (K and locate_fail_why == 'dog not deployed' and t >= IDLE.pack_next) then return nil, locate_fail_why end
    IDLE.pack_next = t + IDLE.look
    local pp = ptr_of(read(K[1], 8), 0)
    local dv = pp == K[2] and read(K[3], 8)
    if dv and u32(dv, 4) == 32767 then return nil, locate_fail_why end
    locate_fail_until = 0   -- (launched, or its backpack changed: the full look now)
  end
  local rec
  for attempt = 1, 2 do
    if not ctx or t >= ctx_until or attempt == 2 then
      -- ((4.6.4 review) a look that aborts on a failed read waits LOCATE_SECONDS too, like one that finds nothing:
      -- before, a check that kept failing repeated the whole look - ~30 reads - every frame while a sentry was busy)
      local okl, c, why = pcall(locate)
      if not okl then
        ctx = nil
        locate_fail_until = t + LOCATE_SECONDS
        locate_fail_why = type(c) == 'table' and c[1] == Abort and ('read_failed: ' .. tostring(c[2])) or 'read_failed'
        error(c, 0)
      end
      -- ((5.1.5 Test 11) no dog out (none worn, put away, the option off...): the full look once a second, not four times)
      -- (a dog put away: every 5 s, as its drone slot is looked at in between)
      if not c then
        ctx = nil
        locate_fail_until, locate_fail_why = t + ((why == 'dog not deployed' and IDLE.pack) and 5.0 or IDLE.why[why] and 1.0 or LOCATE_SECONDS), why
        IDLE.pack_next = t + IDLE.look
        return nil, why
      end
      ctx, ctx_until, unit_cache, reg_rows = c, t + LOCATE_SECONDS, {}, {}
      c.peek_t, c.peek_full = t, t
    end
    rec = read(ctx.rec_addr, 160)
    if rec and u32(rec, 0) == ctx.want and u32(rec, 104) == ctx.drone_id then break end
    rec = nil
    if attempt == 2 then need(false, 'behavior record') end
  end
  local dog, rec_addr, pbase, registry = ctx.dog, ctx.rec_addr, ctx.pbase, ctx.registry
  local tstate = rd(ctx.tstate, 32, 'targeting state')
  local drone_pos = unit_position(ctx.drone_unit)
  local candidates = read_candidates(pbase, drone_pos, registry, nil, nil, u32(rec, 24))

  local now = u64(rd(ctx.clock + 24, 8, 'clock'), 0)
  need(now > 0 and now < 9007199254740991, 'clock')
  local deadline = u64(rec, 152)
  need(deadline < 9007199254740991, 'deadline')
  local target = u32(rec, 24)
  -- (the weapon's current fire node, only while the laser is on: one small read)
  local fire_node
  if ctx.wr_addr and rawget(_G, 'SmarterGuardDogsLaser') == true then
    local w = read(ctx.wr_addr + 216, 8)
    if w then
      local count, index = u32(w, 0), u32(w, 4)
      if index < count then fire_node = ctx.fire_nodes[index] end
    end
    fire_node = fire_node or ctx.fire_nodes[0]
  end
  -- (the gun's own pose array when its weapon belongs to another unit than the drone's)
  local fire_pose
  if fire_node and ctx.fire_unit and ctx.fire_unit ~= ctx.drone_unit then
    local gp = unit_position(ctx.fire_unit)
    fire_pose = gp and gp.pose
    if not fire_pose then fire_node = nil end
  end
  -- ((4.6.7 review) your position for the safety: when it can't be read for a moment, the last one read (up to 0.5 s
  -- old) - before, that frame had no safety check at all)
  local me = unit_position(ctx.player_unit, true)
  if me then ctx.me_last, ctx.me_t = me, t elseif ctx.me_last and t - (ctx.me_t or -99) < 0.5 then me = ctx.me_last end
  return {
    dog = dog, key = ctx.key,
    rec_addr = rec_addr, rec_head = rec:sub(1, 4), node = u32(rec, 8), target = target,
    synced = target ~= 0 and u32(tstate, 0) == target and rec:byte(121) == 1 and bit.band(u32(rec, 96), 1) ~= 0,
    candidates = candidates, now = now, deadline = deadline,
    player_pos = me, drone_pos = drone_pos, fire_node = fire_node, fire_pose = fire_pose,
    -- (4.5.3 Test 12) where the game aims the dog's gun (its targeting state; already read): the laser's fallback
    -- points there, and test builds check the beam against it (only built with a fire node: nothing else uses it)
    aim = fire_node and target ~= 0 and u32(tstate, 0) == target and { f32(tstate, 20), f32(tstate, 24), f32(tstate, 28) } or nil,
    mates = team_wanted() and teammates(ctx, t) or {}, mates_found = team_state and team.found or 0,
  }
end

-- ------------------------------------------------------------------ idle (5.1.5 Test 11)
-- IDLE.range: no dog or sentry engages farther than the mortars' 125 m, so with no enemy within 150 m of a gun it has
-- nothing to do. IDLE.look: how often a part with nothing to do looks again. IDLE.settle: how long a part must have had
-- nothing to do before it idles (a red safety flash or a gray marker still showing, a target just lost)
IDLE = { range = 150, look = 0.25, settle = 1.0, pack = nil, pack_next = 0, drone = nil, dog_asleep = false, dog_next = 0, dog_since = nil, dog_skip = nil,
  on = false, wake_scan = false, last_row = nil, working = nil, state = nil, notes = 0, frames = 0, work_frames = 0, idle_s = 0,
  -- (the reasons the dog's full look waits a second: no dog worn, or one put away (its drone slot is looked at every
  -- IDLE.look s, read_state). Not a helldiver missing for a moment or a vehicle you may step out of: those stay at 0.25 s)
  why = { ['no backpack worn'] = true, ['dog not deployed'] = true, ['backpack is not a supported dog'] = true, ['no loadout'] = true,
    ['guard dogs option off (left alone)'] = true } }
session.idle, SGD.idle = IDLE, IDLE
-- is an enemy this gun may pick within r m of 'origin'? One read (its perception record): an entry with an id, its
-- alive flag and a faction it fights, not in 'skip' (the bodies in its list when it went idle). Not only those the game
-- rates above 0 now: a dog still picks the others now and then. true too when the record can't be read or looks wrong
-- (better awake than blind); a hidden entry (the mod's blank mask) isn't counted, but a gun with anything hidden never idles
function IDLE.near_hostile(pbase, origin, r, skip)
  if not (pbase and origin and pbase >= 65536 and pread(pbase)) then return true end
  local fcount = bu32(0)
  if fcount > 32 then return true end
  local filter = 0
  for j = 0, fcount - 1 do
    local f = bu32(8 + j * 8)
    if f >= 32 then return true end
    filter = bit.bor(filter, bit.lshift(1, f))
  end
  local r2, ox, oy, oz = r * r, origin[1], origin[2], origin[3]
  local function hot(off)
    local id = bu32(off)
    if id == 0 or bit.band(bu32(off + 72), 1) == 0 or bit.band(bu32(off + 76), filter) == 0 or (skip and skip[id]) then return false end
    local x, y, z = bf32(off + 4), bf32(off + 8), bf32(off + 12)
    if not (x == x and y == y and z == z) then return true end
    return (x - ox) ^ 2 + (y - oy) ^ 2 + (z - oz) ^ 2 < r2
  end
  for _, grp in ipairs(GROUPS) do
    local c = bu32(grp[1])
    if c > 16 then return true end
    for k = 0, c - 1 do if hot(grp[2] + k * 80) then return true end end
  end
  for _, one in ipairs(SINGLES) do if bu32(one[1] + 72) ~= 0 and hot(one[1]) then return true end end
  return false
end
-- the dog's look while it idles: true while it still has nothing to do (its AI record still its own, no target, no
-- enemy within IDLE.range of it); nil wakes it. Once a second its AI and perception records are checked to be where
-- they were (the game moves them now and then; an old copy is no longer kept up to date) and the drone's place read
-- (the 150 m leave room for a second of walking); the full look (locate) every 5 s
local function same_records()
  local beh, per = rptr(A.g.behaviours, 'behaviours'), rptr(A.g.perception, 'perception')
  return map_lookup(beh + 64, ctx.drone_id, 32768) == ctx.bi and map_lookup(per + 48, ctx.drone_id, 32768) == ctx.pi
    and rptr(beh + 96, 'behavior records') + ctx.bi * A.stride == ctx.rec_addr and rptr(per + 80, 'perception records') + ctx.pi * 5112 == ctx.pbase
end
function IDLE.dog_peek(t)
  if not ctx or not in_mission() then return nil end
  if t - (ctx.peek_full or ctx.peek_t or 0) >= 5.0 then
    local okl, c = pcall(locate)
    if not (okl and c and c.rec_addr == ctx.rec_addr and c.drone_id == ctx.drone_id and c.pbase == ctx.pbase and c.key == ctx.key) then return nil end
    ctx.peek_full, ctx.peek_t, ctx.peek_pos = t, t, nil
  elseif t - (ctx.peek_t or 0) >= 1.0 then
    local okc, same = pcall(same_records)
    if not (okc and same) then return nil end
    ctx.peek_t, ctx.peek_pos = t, nil
  end
  if not ctx.peek_pos then ctx.peek_pos = unit_position(ctx.drone_unit); if not ctx.peek_pos then return nil end end
  local rec = read(ctx.rec_addr, 108)
  if not (rec and u32(rec, 0) == ctx.want and u32(rec, 104) == ctx.drone_id and u32(rec, 24) == 0) then return nil end
  if IDLE.near_hostile(ctx.pbase, ctx.peek_pos, IDLE.range, IDLE.dog_skip) then return nil end
  return true
end
-- (waking: the dog is looked up afresh before anything is acted on)
function IDLE.dog_wake() ctx_until = 0 end

-- ------------------------------------------------------------------ the damage check (5.1.5 Test 5)
-- (my ask: "is there a way for sentries to know when they are actually dealing damage?" ... "It should still keep
-- its targeting, but if after a short delay, its realizing its firing at something that isnt taking damage, it should
-- change targets") The game keeps every enemy's health in its health component (manager at the 'health' global, from
-- the 2026-09-24 module dump, our own reading): entity id -> index in a hash map at +0x1030 (slots, capacity, empty,
-- multiplier), the entity objects at +0x1048 (id at +8), the records at +0x1058 (0x1b8 bytes; +0x14 = health now, an
-- integer, which goes negative while bleeding out) and the settings at +0x1060 (0x1c bytes; +0x14 = full health).
-- A shooter's target whose health hasn't gone down over a while of firing at it isn't being hurt: a wall, a rock,
-- cover or armor in the way. Only armed once a health value has been seen going down this mission (so the check never
-- acts where the records don't follow the fight, e.g. if a joined game doesn't keep them up to date).
HEALTH = { proven = false, off = false, reads = 0, found = 0, bad = 0 }
-- ((5.1.5 review) enemies whose shield takes the hits first, so their health stays put for a while under fire that is
-- working: the Overseer and the Harvester (shield 1,500), the Gatekeeper and the Veracitor (1,300) - the Codex's
-- shield parts. A Test 5 log had a Laser Sentry and a Gatling drop the same Overseer at 598 of 600 health. They are
-- left out of the damage check (the Heavy Devastator's shield already was, with the burst rule)
HEALTH.shielded = {}
for _, h in ipairs({ 'da40bb347c7447f2', '965eae5a51acdd4a', '453fe22c634eb30f', '20b9c7734daead65' }) do
  HEALTH.shielded[(h:gsub('..', function(x) return string.char(tonumber(x, 16)) end)):reverse()] = true
end
session.health = HEALTH
local function s32(v) return v >= 2147483648 and v - 4294967296 or v end
-- ((5.1.5 Test 18) the health manager, its map's header and its array header once a frame (HEALTH.fc), not per look-up)
local function hp_raw(g, id)
  local C = HEALTH.fc
  if not C or C.f ~= FRAME or C.g ~= g then
    C = C or {}; HEALTH.fc = C
    C.f, C.g = FRAME, g
    C.mgr = ptr_of(read(g, 8), 0)
    C.mh = C.mgr and read(C.mgr + 0x1030, 20)
    C.hdr = C.mgr and read(C.mgr + 0x1010, 0x58)
  end
  local mgr, hdr = C.mgr, C.hdr
  if not (mgr and C.mh) then return nil end
  local idx = map_lookup(mgr + 0x1030, id, 1048576, C.mh, true)
  if not idx then return nil end
  if not hdr or idx >= u32(hdr, 0) then return nil end
  local ents, recs, sets = ptr_of(hdr, 0x38), ptr_of(hdr, 0x48), ptr_of(hdr, 0x50)
  if not (ents and recs and sets) then return nil end
  local eo = ptr_of(read(ents + idx * 8, 8), 0)
  local ek = eo and read(eo + 8, 4)
  if not ek or u32(ek, 0) ~= id then return nil end
  local r, m = read(recs + idx * 0x1b8 + 0x14, 4), read(sets + idx * 0x1c + 0x14, 4)
  if not (r and m) then return nil end
  return s32(u32(r, 0)), s32(u32(m, 0))
end
-- an enemy's health now and its full health (nil when it has no health record or it can't be read)
function HEALTH.of(id)
  if HEALTH.off then return nil end
  local g = A and A.g and A.g.health
  if not g then HEALTH.off = true; note('damage check: off (the health records were not found in this game build)'); return nil end
  HEALTH.reads = HEALTH.reads + 1
  local ok, hp, mx = pcall(hp_raw, g, id)
  if not ok or not hp then
    -- ((5.1.5 review) not one record found in 200 looks: the records are not where this build is read from (a game
    -- update that moved them, say) - the check goes off rather than looking up every target for nothing)
    if HEALTH.found == 0 and HEALTH.reads >= 200 then HEALTH.off = true; note('damage check: off (no health record found in 200 looks: this game build keeps them elsewhere)') end
    return nil
  end
  if mx <= 0 or mx > 10000000 or hp > mx * 2 + 10 or hp < -10000000 then
    HEALTH.bad = HEALTH.bad + 1
    if HEALTH.bad >= 20 then HEALTH.off = true; note('damage check: off (the health records do not read as expected in this game build)') end
    return nil
  end
  HEALTH.found = HEALTH.found + 1
  return hp, mx
end
-- ((5.1.5 Test 6, test builds: I can't watch every sentry) how each drop turned out, judged by the game's
-- health values: was the next enemy it went for hurt within 3 s (the switch paid off), did anyone else hurt the
-- dropped one while it was left alone (it wasn't immune), and when it came back to it, did it hurt it within its wait
-- (then the drop was likely wrong, or the enemy had come out of cover). Kept for 15 s per drop, tallied per kind.
HEALTH.tally, HEALTH.open = {}, {}
function HEALTH.track_new(key, kind, id, wait, info)
  local T = HEALTH.tally[kind]
  if not T then T = { drops = 0, meter_moving = 0, meter_still = 0, meter_unknown = 0, unseen = 0, mate = 0, rise = 0, next_hurt = 0, next_none = 0,
    back = 0, back_hurt = 0, others_hurt = 0 }; HEALTH.tally[kind] = T end
  T.drops = T.drops + 1
  if info.meter == nil then T.meter_unknown = T.meter_unknown + 1 elseif info.meter then T.meter_moving = T.meter_moving + 1 else T.meter_still = T.meter_still + 1 end
  if info.unseen then T.unseen = T.unseen + 1 end
  if info.mate then T.mate = T.mate + 1 end
  if info.rise then T.rise = T.rise + 1 end
  if #HEALTH.open < 60 then
    HEALTH.open[#HEALTH.open + 1] = { key = key, kind = kind, id = id, t0 = info.t, wait = wait, hp = info.hp, hold = info.hold, next_hp = {}, back_f = nil }
  end
end
-- each frame for a shooter (key) that has open drops: its target now, and how long it has fired at it
function HEALTH.track_step(key, target, fired, t)
  local L = HEALTH.open
  local i = 1
  while i <= #L do
    local D = L[i]
    local done = false
    if D.key == key and t >= (D.next or 0) then
      D.next = t + 0.2
      local T = HEALTH.tally[D.kind]
      -- the dropped enemy: anyone hurting it while it is left alone
      if not D.others and t - D.t0 <= D.hold then
        local hp = HEALTH.of(D.id)
        if hp and D.hp and hp < D.hp and target ~= D.id then D.others = true; T.others_hurt = T.others_hurt + 1 end
      end
      -- the next enemy it fires at, within 3 s
      if not D.next_done and target ~= 0 and target ~= D.id and t - D.t0 <= 3 then
        local hp = HEALTH.of(target)
        local h0 = D.next_hp[target]
        if hp and not h0 then D.next_hp[target] = hp elseif hp and h0 and hp < h0 then D.next_done = true; T.next_hurt = T.next_hurt + 1 end
      end
      if not D.next_done and t - D.t0 > 3 then D.next_done = true; T.next_none = T.next_none + 1 end
      -- back on the dropped one after its hold: hurt within its wait of firing?
      if target == D.id and t - D.t0 > D.hold * 0.9 and not D.back_done then
        local hp = HEALTH.of(D.id)
        if not D.back_f then D.back_f, D.back_hp = fired, hp; T.back = T.back + 1
        elseif hp and D.back_hp and hp < D.back_hp then D.back_done = true; T.back_hurt = T.back_hurt + 1
        elseif fired - D.back_f >= D.wait then D.back_done = true end
      end
      done = t - D.t0 > 15
    elseif t - D.t0 > 30 then done = true end
    if done then table.remove(L, i) else i = i + 1 end
  end
end

-- W: the shooter's own watch (a table it keeps); fired: how long it has fired at its current target 'id' (counted from
-- when it picked it). Returns how many seconds of firing at 'id' have gone by without its health changing, added up
-- over its turns on that enemy (the Rover's fire spreading leaves an enemy after about 0.6 s and comes back), or nil:
-- not known, or not armed yet. An enemy not fired at for 5 s is forgotten.
function HEALTH.watch(W, id, fired, t, who)
  if HEALTH.off then return nil end
  W.e = W.e or {}
  local e = W.e[id]
  if not e then e = { acc = 0, f = fired, next = 0 }; W.e[id] = e end
  if W.cur ~= id then W.cur = id; e.f = fired end
  e.t = t
  if t - (W.clean or 0) > 2 then
    W.clean = t
    for k, x in pairs(W.e) do if t - x.t > 5 then W.e[k] = nil end end
  end
  if t < e.next then return e.secs end
  e.next = t + 0.1
  local df = math.max(0, fired - e.f)
  e.f = fired
  local hp, mx = HEALTH.of(id)
  if not hp then e.hp, e.acc, e.secs = nil, 0, nil; return nil end
  if e.hp and hp < e.hp and not HEALTH.proven then
    HEALTH.proven = true
    note(string.format('damage check: on (%s\'s target %d went from %d to %d health of %d)', who or '?', id, e.hp, hp, mx))
  end
  -- ((5.1.5 Test 16) when it last hurt it: a sentry finishes the enemy it is hurting before switching by priority)
  if e.hp and hp < e.hp then e.hurt_t = t end
  if not e.hp or hp ~= e.hp then e.hp, e.acc = hp, 0 else e.acc = e.acc + df end
  W.hp, W.mx = hp, mx
  e.secs = HEALTH.proven and e.acc or nil
  return e.secs
end
end
-- (5.0) generated by tools/icons_gen.py from the game's stratagem HUD icons: per icon, the weapon glyph (g) and
-- the body (b) as runs of three symbols each - the band (0 = bottom of 32), the first column and the end column (of 64)
local ICON_DATA = { rows = 32, cols = 64, abc = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-*',
  mg = { g = 'O8KN8PM8KL8KK8PJ8KI8KH8PG8K', b = 'QITQcuPIaPduOQdOguNTfNhuMQgLQiKTiJQjIQkHTkGQkFIkEIkDMgCMgBMgAMg8Hl7Fn6Eo5Dp' },
  gatling = { g = 'N8OM8OK8OJ8OH8OG8OE8OD8OB8OA8O', b = 'QITQcuPIaPduOOdOguNSfNhuMSgLPiKSiJSjIPkHSkGSkFPkESkDSgCPgBSgASg8Hl7Fn6Eo5Dp' },
  ac = { g = 'N8HNKOM8GMIQL8ELGQK8CKFOJ8HJKOI8GIIQH8EHGQG8CGFOF8HFKOE8GEIQD8EDGQC8CCFO', b = 'QITQcuPIaPduOIdOguNRfNhuMSgLSiKRiJRjISkHSkGRkFRkESkDSgCRgBMgAMg8Hl7Fn6Eo5Dp' },
  rocket = { g = 'MPWLNWKLWJEVICTHARG8PFIPEAEEIPD9CDEGDIOCDGCIMBDEBIK', b = 'QITQcuPIaPduOIdOguNIONYfNhuMIMMYgLIKLYiKYiJYjIWkHUkGSkFRkERkDRgCPgBNgAMg8Hl7Fn6Eo5Dp' },
  laser = { g = 'NRSMMOMVXLQTK7VKXZJPUHMNHRSHWXGRS', b = 'QISQcuPIaPduOIPOUdOguNIKNZfNhuMIJMagLZhKbiJbjIIKIZkHIJHakGILGOPGUVGYkFIPFUkEIkDMgCMgBMgAMg8Hl7Fn6Eo5Dp' },
  flame = { g = 'OHJNHLMHNLHPKGQJEQJSTICVHAKHLXGAJGLXFAHFMVEBHEOUDDJDNSCFJCNQBHJBNO', b = 'QJTQcuPKaPduOMdOguNOfNhuMQgLSiKUiJWjIYkHakGakFYkEXkDUgCTgBRgAPg8Hl7Fn6Eo5Dp' },
  mortar = { g = 'QJMPINOINNHOMGPLGPKFQJGPIGPHHOGINFINEJMDJMCJMBHOAGP9GP8GP', b = 'QPTQcuPPaPduOPdOguNQfNhuMRgLRiKSiJRjIRkHQkGPkFPkEPkDOgCPgBRgARg8Rl7Fn6Eo5Dp' },
  ems = { g = 'RKNQJOPIPODEOIPNCENHQMAEMGRL9DLMRK8IKLQJDHJJPICGIIPHCEHJOGBDGKNFKNEKNDJOCHQBHQAHQ', b = 'RPXRcuQQbQfuPRePhuORgOiuNShMTiLTjKSjJRkIRkHQkGPkEPgDRgCSgBSgATk9Sm8Eo7Dp' },
  tesla = { g = 'RWXQVWPTWOSVNRZMVYLUXKMPKUVKdgJMPJTUJdgIMPIVXIdgHMPHVXHdgGMPGVXGdgFMPFTZFdgEMPETZEdgDMgCMgBMgALh9KU9Yi8LP8dh', b = '8CG8UY8mq77L7Pd7hv64y54y44y34y24y' },
  dog = { g = 'LIMKHNJCDJHNJRSIAUH9VG8DGPWF8DFPWE8WD8DDPWC8DCPWB8WA8DAPW98D9PW89W7AU6CD6HN6RT5HN4IM', b = 'QSsPSsOSsNUqMSTMWoMrsLSVLpsKTbKdhKjsJUbJdhJjsIWbIjsHXsGYsFYsEYsDYsCYsBYsAYs9Yq8Yo' },
  rover = { g = 'MIMLCDLHNLRSKBDKGOKRTJAUI9VH8JHLWG8FGHNGPWF8IFMWENOESWD8IDMWC8FCHNCPWB8JBLWA8W9AV8BD8GO8RT7CD7HN7RS6IM', b = 'RSsQSsPTrOVpNSUNXnNqsMTbMdhMjsLUbLdhLjsKVbKdhKjsJWsIYsHYsGYsFYsEYsDYsCYsBYrAYp' },
  k9 = { g = 'MHMLCDLHNLRSKBDKGOKRTJAUI9WH8KHMWG8IGLWF8HFQWE8FEPWD8EDNWC8JCMWB8JBKWA9W9AU8BD8GO8RT7CD7HN7RS6IM', b = 'RSsQSsPTrOSTOVpNSVNqsMTbMdhMjsLUbLdhLjsKVbKdhKjsJWsIXsHYsGYsFYsEYsDYsCYsBYsAYq' },
  frv = { g = 'RRURXbQRbPRbORbNRbLLOLSVLXaLdhKLVKXhJLVJXhILVIXhHLVHXh', b = 'ENZDNZBHaAHc9Hl8Hl7Hl5HN5fl4JL4hj' },
  pod = { g = 'FWgFhpEWiEjpDWjCWkBWkAWl9ah8Zi7ah6Xl5Wl', b = 'TKdSJeRDkQDkPDkOHgNGgLGhKFhJFhIFiHFVGFVFGVEGVDGVCHVBHVAIV9IV8JU6LU5MV4NV3PV2RV' },
  gasmortar = { g = 'QJMPINOINNBINKOM9KMLPL8BLILLNPK8AKJLKNQJ8BJDGJILJNPI9KIMPH9AHBIHJKHMOG9CGDGGHKGMNFBDFGIFKNEJMDJMCJMBHOAGP9GP8GP', b = 'QPTQcuPPaPduOPdOguNQfNhuMRgLRiKSjJRjIRkHQkGPkFPkEPkDOgCPgBRgARg8Rl7Gn6Eo5Dp' },
}

-- (5.1.0) VECTOR: tools/icons_vec.py - per icon its glyph (tg), body (tb) and dark edge (te) as triangles: three
-- points of two coordinates, two symbols each (4096 steps), across -0.5..0.5 and up 0..1 of the icon
ICON_DATA.vabc = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-'
ICON_DATA.mg.tg, ICON_DATA.mg.tb, ICON_DATA.mg.te = '84X380axJua-84X3Jua-KaaF84X3KaaFNuaF84X3NuaFPyYtPyYtNuXpKaXpKaXpJuX384X3KaXp84X3PyYt84d380gxJug-84d3Jug-KagF84d3KagFNugF84d3NugFPyetPyetNudpKadpKadpJud384d3Kadp84d3Pyet84j380mxJum-84j3Jum-KamF84j3KamFNumF84j3NumFPyktPyktNujpKajpKajpJuj384j3Kajp84j3Pykt', 'ptB4C4BGHqI0ptB4HqI0k7I0M4K4M0QyftR0M4K4ftR0fxK8edo3a3qxttq-edo3ttq-txk7edo3txk7hpk3I4p3I0qxUeqlI4p3UeqlY7plI4p3Y7plctm-ctm-fxjhiBfhctm-iBfhjxYxctm-jxYxjxT8jxT8I4T4I4V0jxT8I4V0O8VmjxT8O8VmU0YtjxT8U0YtOmcBjxT8OmcBU0fBU0fBOmiBU0lBO8oJI4p3ctm-ctm-jxT8U0fBctm-U0fBU0lBctm-U0lBO8oJ', '6GVe6GoRFepF6GVeFepFI4tF6GVeI4tFvNslvNslvNiJjhhhjhhhmBSeiBQiiBKOlxJSrhCiiBKOrhCirh9eiBKOrh9eAa9KiBKOAa9KAGCiiBKOAGCiGKJmiBKOGKJmJmKOiBKOJmKOJmQiiBKOJmQiGGReiBKOGGReFeUqFeUq6GVevNslFeUqvNsljhhhFeUqjhhhiBQiFeUqiBQiiBKO'
ICON_DATA.gatling.tg, ICON_DATA.gatling.tb, ICON_DATA.gatling.te = '84K480NyJuO084K4JuO0KaNG84K4KaNGNuNG84K4NuNGPyLuPyLuNuKqKaKqKaKqJuK484K4KaKq84K4PyLu84Q480TyJuU084Q4JuU0KaTG84Q4KaTGNuTG84Q4NuTGPyRuPyRuNuQqKaQqKaQqJuQ484Q4KaQq84Q4PyRu84W380ZxJuZ-84W3JuZ-KaZF84W3KaZFNuZF84W3NuZFPyXtPyXtNuWpKaWpKaWpJuW384W3KaWp84W3PyXt84c380fxJuf-84c3Juf-KafF84c3KafFNufF84c3NufFPydtPydtNucpKacpKacpJuc384c3Kacp84c3Pydt84i380lxJul-84i3Jul-KalF84i3KalFNulF84i3NulFPyjtPyjtNuipKaipKaipJui384i3Kaip84i3Pyjt', 'ptB4C4BGHqI0ptB4HqI0k7I0U0MCOmPCS4R0U0MCS4R0ftR0U0MCftR0fxK8U0MCfxK8QeK4edo3a3qxttq-edo3ttq-txk7edo3txk7hpk3I4o3I0qxUeqlI4o3UeqlY7plI4o3Y7plctm-ctm-fxjhiBfhctm-iBfhjxYxctm-jxYxjxT8ctm-jxT8S4T4S4T4OqUqU0YBU0YBOmbBU0eBU0eBOmhBU0kBO8nJI4o3ctm-ctm-S4T4U0YBctm-U0YBU0eBctm-U0eBU0kBctm-U0kBO8nJ', '5mJe6GnRFeoFFeoFFmrRI4tFFeoFI4tFvNslFeoFvNslvNiJFeoFvNiJjhhhFeoFjhhhmBSeFeoFmBSeiBQiFeoFiBQiiBKOiBKOlxJSrhCiiBKOrhCirh9eiBKOrh9eAa9KiBKOAa9K9mBiiBKO9mBiEWHiiBKOEWHi84HqiBKO84Hq5mJeiBKO5mJeFeoF'
ICON_DATA.ac.tg, ICON_DATA.ac.tb, ICON_DATA.ac.te = 'NuV0PiTiPiQONuV0PiQONuP4NuV0NuP4EaP4NuV0EaP4KKV0BeP480P884V0BeP484V0HOV0Nuc-PibhPiYNNuc-PiYNNuX3Nuc-NuX3EaX3Nuc-EaX3KKc-BeX380X784c-BeX384c-HOc-Nuk-PijhPigNNuk-PigNNuf3Nuk-Nuf3Eaf3Nuk-Eaf3KKk-Bef380f784k-Bef384k-HOk-', 'ptB4C4BGHqI0ptB4HqI0k7I0M4K4M0MyQ8O0Q8O0RqR0fxQyQ8O0fxQyftK4Q8O0ftK4M4K4edo3a3qxttq-edo3ttq-txk7edo3txk7hpk3I4n3I0qxUeqlI4n3UeqlY7plY7plctm-fxjhY7plfxjhiBfhY7pliBfhjxYxY7pljxYxjxT8Y7pljxT8RqT4RqT4QGVuS0Z7RmbxQGdtS0h7Nun3I4n3Y7plY7plRqT4S0Z7Y7plS0Z7RmbxY7plRmbxS0h7Y7plS0h7RmjxY7plRmjxQ8m3Y7plQ8m3Nun3', '6GNe6GmRFenFFenFFmrRI4tFFenFI4tFvNslFenFvNslvNiJFenFvNiJjhhhFenFjhhhmBSeFenFmBSeiBQiFenFiBQiiBKOiBKOlxJSrhCiiBKOrhCirh9eiBKOrh9eAa9KiBKOAa9KAGCiiBKOAGCiGKJmiBKOGKJmJmKOiBKOJmKOJmMiJmMi6GNeFenFJmMiFenFiBKO'
ICON_DATA.rocket.tg, ICON_DATA.rocket.tb, ICON_DATA.rocket.te = 'D0PiFuSSFyOuD0PiFyOuD4M8AqU0EOU0BeR4AqU0BeR484R4Pqj-Vuj-VydtPqj-VydtOyWxOyWxOyRuICL8OyWxICL8HuW3OyWxHuW374W3OyWx74W3E4c-OyWxE4c-Iuc-OyWxIuc-Pqj-', 'ptB4C4BGHqI0ptB4HqI0k7I0M4K4M0MCQqR0M4K4QqR0fxQyM4K4fxQyftK4edo3a3qxttq-edo3ttq-txk7edo3txk7hpk3I0qxUeqlY7plI0qxY7plctm-I0qxctm-fxjhfxjhiBfhjxYxfxjhjxYxjxT8fxjhjxT8R4T4fxjhR4T4R0WBfxjhR0WBX-d7fxjhX-d7X-lxP4m3I4f7I0qxI0qxfxjhX-lxI0qxX-lxP4m3', 'FmfNGaslvhsRvhsRvNiJjhhhjhhhmBSeiBQiiBKOldJmsBBiiBKOsBBirN9KiBKOrN9KAG9eiBKOAG9eAGCiiBKOAGCiGGJyiBKOGGJyFiLGFiLGBaKKAeOqAeOq6GPe7CTm7CTm4mWhCael7CTmCaelFmfN7CTmFmfNvhsR7CTmvhsRjhhh7CTmjhhhiBQi7CTmiBQiiBKO7CTmiBKOFiLG7CTmFiLGAeOq'
ICON_DATA.laser.tg, ICON_DATA.laser.tb, ICON_DATA.laser.te = 'QmWNQqY-SCYxQmWNSCYxS8WJUqa3Vaa-XdZFUqa3XdZFWtYJLWZRNObBOCZtLWZROCZtMKYJWpdZWlexZNe-WpdZZNe-ZRddTOg-UifBUCcdTOg-UCcdSObJTOg-SObJPabpTOg-PabpOOdZOOdZ6Wdd6afFOOdZ6afFOOfFOOdZOOfFQahVOOdZQahVTOg-UqilWhkRXdjJUqilXdjJVmhdLWjNMGkROCihLWjNOCihNShdQmjdQqmFSCmBQmjdSCmBS8jd', 'ptB4CKBGI4I0ptB4I4I0k7I0M4K4M0QyftR0M4K4ftR0fxK8ddp3aZqxttq-ddp3ttq-txk7ddp3txk7i3k3I0qxVOqVa7olI0qxa7oldNmVdNmVfhjxiRexdNmViRexjxYRdNmVjxYRjxT8I4bVKubVImZ3MGVaOuXxP4UWU8UWUKXhWhVaaFZ7Y3blbVbtbVghY3h3aFjhWtn3UKktTuoJP4oJOuktMKn3ImjVKehJI4hJImjVI4hJI0qxI4T4I4bVImZ3I4T4ImZ3MGVaI4T4MGVaP4UWI4T4P4UWU8UWMKn3ImjVI0qxjxT8I4T4U8UWjxT8U8UWWhVajxT8WhVaaFZ7jxT8aFZ7bVbtjxT8bVbtbVghjxT8bVghaFjhP4oJMKn3I0qxdNmVjxT8aFjhdNmVaFjhWtn3dNmVWtn3TuoJTuoJP4oJI0qxTuoJI0qxdNmV', '54bp4mghFehVFehVFmrRI4tFFehVI4tFYFrpYFrpaZtFvNslYFrpvNslvNiJYFrpvNiJjVhlYFrpjVhllxahYFrplxahmBSeYFrpmBSeiBQiYFrpiBQiiBKOiBKOmRIyrhCiiBKOrhCirh9eiBKOrh9eAq9KiBKOAq9KAmDCiBKOAmDCGaJmiBKOGaJmJmKOiBKOJmKOJmQiiBKOJmQiFmSeiBKOFmSeFmbBFmbB54bpFehVFmbBFehVYFrpFmbBYFrpiBKO'
ICON_DATA.flame.tg, ICON_DATA.flame.tb, ICON_DATA.flame.te = 'HWgdHaohPighHWgdPighPqbFPqbFSidhY7YFPqbFY7YFNCLuNCLuN0RSOGTyOGTyLWVOLSaVGCUCIyQyIuLqGCUCIuLqAWTuGCUCAWTuAWZhGCUCAWZhHWgdPqbFNCLuOGTyPqbFOGTyLSaVLSaVGCUCHWgdLSaVHWgdPqbF', 'ptB4C4BGHqI0ptB4HqI0k7I0ftK4OKKGUKR0ftK4UKR0fxQyedo3a3qxttq-edo3ttq-txk7edo3txk7hpk3RmhRIKq-UOqlRmhRUOqlY7plRmhRY7plctm-RmhRctm-fxjhRmhRfxjhiBfhRmhRiBfhjxYxRmhRjxYxjxT8jxT8WJT4alYRjxT8alYRSugJSugJRmfxRmhRSugJRmhRjxT8', 'FGhdGqslvhsRFGhdvhsRvNiJFGhdvNiJjhhhFGhdjhhhmBSeFGhdmBSeiBQiFGhdiBQiiBKOiBKOldJmsBBiiBKOsBBirN9KiBKOrN9KAG9eiBKOAG9eAGCiiBKOAGCiGyKGiBKOGyKG8mSOiBKO8mSO8GaBiBKO8GaBFGhd'
ICON_DATA.mortar.tg, ICON_DATA.mortar.tb, ICON_DATA.mortar.te = 'F0fRJ4q-MCqhF0fRMCqhPyfRF0fRPyfRLyTCF0fRLyTCLyP8LyP8OyMCOuH4LyP8OuH4G0H8LyP8G0H8G0MCLyP8G0MCJ0P8LyP8J0P8J0TCLyP8J0TCF0fR', 'ptB4C4BGFKF0ptB4FKF0QuFGptB4QuFGR4I0ptB4R4I0k7I0O0PuO0QyftR0O0PuftR0fxK8fxK8R4K4R0MyfxK8R0MyO0Puedo3a3qxttq-edo3ttq-txk7edo3txk7hpk3S0fRO4q-Suq-S0fRSuq-Y7plS0fRY7plbtnlS0fRbtnlfBkhS0fRfBkhjBchS0fRjBchjxYxS0fRjxYxjtT4S0fRjtT4O4T4', 'CmfxHaslvhsRCmfxvhsRvNiJCmfxvNiJjhhhCmfxjhhhmBSeCmfxmBSeiBQiCmfxiBQiiBKOiBKOldJmsBBiiBKOsBBirN9KiBKOrN9KAG9eiBKOAG9eAGCiiBKOAGCiDmGeiBKODmGeDmMiiBKODmMiGmQ8iBKOGmQ8Cmfx'
ICON_DATA.ems.tg, ICON_DATA.ems.tb, ICON_DATA.ems.te = '7GeREepBCyg77GeRCyg7IifdIifdB4UeD0dxIifdD0dx7GeRG4i3K4t-MytxG4i3MytxQyiBMyRuPyOyPuK4MyRuPuK4H0K8MyRuH0K8H0OyMyRuH0OyK0RuMyRuK0RuK0WRMyRuK0WRIGbRMyRuIGbRMihpMihpG4i3QyiBMihpQyiBMyWRMihpMyWRMyRu', 'ptE4C4EGFKI0ptE4FKI0S8I0ptE4S8I0SKL0ptE4SKL0k7L0P0SuP0TyftU0P0SuftU0fxN8fxN8S4N4S0PyfxN8S0PyP0SudtrpaJtxttt-dtrpttt-txn7dtrptxn7i3n3T0hNPKt-XtslT0hNXtslcNqFT0hNcNqFfRnBT0hNfRnBjBfRT0hNjBfRjxbRT0hNjxbRjtW3T0hNjtW3PGW7', '50exCWqRGSqpGSqpK4wFvNvlGSqpvNvlvNlJGSqpvNlJjVklGSqpjVklmBVeGSqpmBVeiBTiGSqpiBTiiBNOiBNOlxMSrhFiiBNOrhFirhCeiBNOrhCeAaCKiBNOAaCK9mEiiBNO9mEiEmK8iBNOEmK8EmPSiBNOEmPSHmSuiBNOHmSuGWYVGWYVCeSq9aSqGWYV9aSqACblACbl5qcJ50exACbl50exGSqpACblGSqpiBNOACbliBNOGWYV'
ICON_DATA.tesla.tg, ICON_DATA.tesla.tb, ICON_DATA.tesla.te = 'M0N8M4e-OyexM0N8OyexP4R0M0N8P4R0T0R8T0R8T0VCV0X7V0X7V0axWta-V0X7Wta-WxX7V0X7WxX7YxVCV0X7YxVCYxR8ctR0c-exfxexctR0fxexfxN8ctR0fxN8itHqctR0itHqeZGKctR0eZGKWNK4ctR0WNK4NOGKctR0NOGKJGHuctR0JGHuM0N8ctR0M0N8T0R8T0R8V0X7YxR8T0R8YxR8ctR0Q4kFWttxV0m3Q4kFV0m3ZtlpZtlpT4c7Uyj-ZtlpUyj-Q4kF', '444440DiDaI04444DaI0N8E04444N8E0WNI04444WNI0f7E0f7E0oNI0xxDif7E0xxDixx48f7E0xx484444', 'JmfRRGaVRSWpSmZxRGaVJmfRSmZxJmfROuhFSmZxOuhFRWfNSmZxRWfNS0hhS0hhOaiJNmkhS0hhNmkhV0vRS0hhV0vRYNvlS0hhYNvlXxoNS0hhXxoNcBmRS0hhcBmRWldVWldVZBbRZBY7alWtbFgRhNglalWthNgliBNealWtiBNekpJGkpJGpNK0zhFCkpJGzhFCzh2ekpJGzh2e2a2KkpJG2a2K2GFC2GFCCaK0HGJ8JmNeJmfRRSWpSmZxS0hhWldVSmZxWldVZBY7SmZxZBY7alWtSmZxalWtkpJGkpJG2GFCHGJ8kpJGHGJ8JmNekpJGJmNeRSWpkpJGRSWpSmZx'
ICON_DATA.dog.tg, ICON_DATA.dog.tb, ICON_DATA.dog.te = '80XBCyLyD4I0CyLy80XBCyRyCyLyCyRyD4O0CyLyD4O0P8OmCyXx80XBCqexCyXxCqexCyb7CyXxCyb7Fua-Fua-I4g-MCghFua-MCghO4a-R0b7R8exVyXBR0b7VyXBVyHOR0b7VyHOR8B8R0b7R8B8R0EyO4F4Lu94Hm9OO4F4Hm9OFuF4CyEyCqB880IOCyEy80IO80XBCyEy80XBD4I0CyEyD4I0P8ImP8LKCyLyP8OmP8LKP8OmQmPuCyRy80XBCyXxCyRyCyXxD4U0CyRyD4U0P8UmP8XJCyXxFua-P8XJFua-O4a-P8XJO4a-R0b7FuF4CyEyP8ImQmJuP8LKQmPuP8RKCyRyP8UmP8RKP8UmQmVuQmVuP8XJR0b7QmVuR0b7R0EyO4F4FuF4P8ImO4F4P8ImQmJuQmPuP8RKQmVuQmPuQmVuR0EyR0EyO4F4QmJuR0EyQmJuQmPu', 'c-c7d3f-gxfxc-c7gxfxgtc3S0gtS4jxW3f-W3f-axfxb3Z-itZ-i-fxntf-itZ-ntf-rxjtitZ-rxjtrxKuitZ-rxKuo7H4itZ-o7H4X-H8itZ-X-H8X-XhX-XhS0gtW3f-X-XhW3f-b3Z-X-Xhb3Z-itZ-S0mtS0qxrtq-S0mtrtq-rxmtS0mtrxmtn7i3S0mtn7i3Wpi3', 'R4s-tNslthJOR4s-thJOo7EqR4s-o7EqX3F4R4s-X3F4Se9KR4s-Se9KOmAGR4s-OmAGLu6qLu6qGa7KFCAGFCAGBK9K5mHuFCAG5mHu5mXhFCAG5mXhB0gRFCAGB0gRFCfpFCAGFCfpGailFCAGGailLujFFCAGLujFOyfpOyfpR4s-Lu6qOyfpLu6qFCAG'
ICON_DATA.rover.tg, ICON_DATA.rover.tb, ICON_DATA.rover.te = 'MWUiNyTyO4S0RuU4NyTyMWUiH8U480U880aBH8U480aBDiXtH8U4DiXtGeVGH8U4GeVGHmWhEqZJDiXt80aB80aBCuhxCye780aBCye7Fud-Fud-I4j-MCjhFud-MCjhO4d-R0e7R8hxVyaBR0e7VyaBVyKOVyKOR8E8R0HyVyKOR0HyO4I4O4I4LuC4HmCOO4I4HmCOFuI4CyHyCqE880LOCyHy80LOIyL8CyHyIyL8KuL080LODiOCEqMmMCPOHmPOGeQqGeQqDiOC80LOGeQq80LO84S0GeQq84S0H8S0GeQqH8S0IKQWGeQqIKQWKeQ0N0SOMWUiO4S0IKVaH8U4HmWhIKVaHmWhMCWhEqZJ80aBFud-EqZJFud-O4d-O4d-R0e7VyKOVyKOO4I4FuI4VyKOFuI4CyHyVyKOCyHyKuL0IyL880LOEqMmIyL8EqMmHmPOMCPOGeQqKeQ0MCPOKeQ0N0SOMCPON0SOO4S0KeW3IKVaMCWhKeW3MCWhNKVGHmWhEqZJIyX7HmWhIyX7KuW-J4b3IyX7EqZJJ4b3EqZJO4d-J4P4IyL8HmPOJ4P4HmPOMCPONKQqMCPOO4S0NKQqO4S0S0S8MWUiKeW3NKVGMCWhHmWhKuW-MCWhKuW-L0axL0axJ4b3O4d-L0OyJ4P4MCPOL0OyMCPOP8MmQGOCNKQqS0S8RuU4MWUiNKVGRuU4NKVGQGXtP8ZJMCWhL0axP8ZJL0axO4d-KuL0L0OyP8MmQGXtP8ZJO4d-VyKOKuL0P8MmVyKOP8MmQGOCVyKOQGOCS0S8VyKOS0S8RuU4RuU4QGXtO4d-RuU4O4d-VyKO', 'c-f7d3i-gxixc-f7gxixgtf3S0jtS4mxW3i-W3i-axixb3c-itc-i-ixnti-itc-nti-rxmtitc-rxmtrxNuitc-rxNuo7K4itc-o7K4X-K8itc-X-K8X-ahX-ahS0jtW3i-X-ahW3i-b3c-X-ahb3c-itc-S0ptS0txrtt-S0ptrtt-rxptS0ptrxptn7l3S0ptn7l3Wpl3', 'R4v-tNvlthMOR4v-thMOo7HqR4v-o7HqX3I4R4v-X3I4SeCKR4v-SeCKOmDGR4v-OmDGLu9qLu9qGaAKFCDGFCDGBKCK5mKuFCDG5mKu5mahFCDG5mahB0jRFCDGB0jRFCipFCDGFCipGallFCDGGallLumFFCDGLumFOyipOyipR4v-Lu9qOyipLu9qFCDG'
ICON_DATA.k9.tg, ICON_DATA.k9.tb, ICON_DATA.k9.te = 'DWR0JSQiI0KGQmV8KqVaMSb-DWR08GahCmhxDWR0CmhxD4eFDWR0D4eFGGedDWR0GGedI4kVDWR0I4kVLykBDWR0LykBNqeFR0eNRCiBVyaRR0eNVyaRVyLuR0eNVyLuRCE8R0eNRCE8R0HyNqI4LuC4I0C8NqI4I0C8G8I4CyHyCmEO8GLeCyHy8GLe8GahCyHy8GahDWR0CyHyDWR0I0KGMSb-DWR0NqeFMSb-NqeFR0eNG8I4CyHyI0KGQmV8MSb-R0eNQmV8R0eNR0HyQmV8R0HyNqI4NqI4G8I4I0KGNqI4I0KGQmV8', 'c-fNdJjFgxjBc-fNgxjBgtf3S0k7S4nBWJjFWJjFaxjBbJc-itdFi-jBntjFitdFntjFrxn7itdFrxn7rxNOitdFrxNOntJKitdFntJKXlJOitdFXlJOXlaxXlaxS0k7WJjFXlaxWJjFbJc-XlaxbJc-itdFS0q7S0txrtt-S0q7rtt-rxq7S0q7rxq7n7lJS0q7n7lJX3lJ', 'R4v-tNvlthLuR4v-thLuntH4R4v-ntH4W0HmR4v-W0HmSeCKR4v-SeCKOmDWR4v-OmDWLu9qLu9qGaAKFCDWFCDWBKCa60L8FCDW60L860bBFCDW60bBAmjBFCDWAmjBF8i-FCDWF8i-GamFFCDWGamFLemlFCDWLemlOyipOyipR4v-Lu9qOyipLu9qFCDW'
ICON_DATA.frv.tg, ICON_DATA.frv.tb, ICON_DATA.frv.te = 'WlYdWpilZxihWlYdZxiha3fFWlYda3fFdVfNdVfNdZilgxihdVfNgxihgtYZdVfNgtYZWlYdL0YdL4ilOCihL0YdOCihOKfFL0YdOKfFRmfNRmfNRqilVCihRmfNVCihV8YZRmfNV8YZL0YdQqkJQmuRTyuRQqkJTyuRU4q-QqkJU4q-XNq-XNq-XZuVb7uVXNq-b7uVbBkNXNq-bBkNQqkJ', 'fFAOe-ByktC0fFAOktC0kxB8fFAOkxB8jN94fFAOjN94h38qHGAOH0ByMuC0HGAOMuC0MyB8HGAOMyB8LO94HGAOLO94J48qH4E4H0OCYtOGH4E4YtOGd3K0H4E4d3K0ktK0H4E4ktK0kxE8NKQ4NGTyROU0NKQ4ROU0SKT0NKQ4SKT0YtT0YtT0YxR8SKR4SKR4ROQ4NKQ4SKR4NKQ4YtT0', 'OWuxPqwVcdwFOWuxcdwFdRl7dRl7jBjBiNWpdRl7iNWpRWW3RWW3aNUmalPqRWW3alPqe3MGe3MGmhLSnBAee3MGnBAejt6qe3MGjt6qeJ7qe3MGeJ7qcdBqe3MGcdBqPKBqPKBqNy88Ku6aPKBqKu6aH47KPKBqH47KF09uPKBqF09uEmOiPKBqEmOiG4QGPKBqG4QGKuQWPKBqKuQWL0USPKBqL0USNCW3NCW3ImY7ImjBNCW3ImjBK4klNCW3K4klOWktOWktOWuxdRl7OWktdRl7RWW3RWW3e3MGPKBqRWW3PKBqNCW3RWW3NCW3OWkt'
ICON_DATA.pod.tg, ICON_DATA.pod.tb, ICON_DATA.pod.te = 'Wp9aWVDSkNDWWp9akNDWkh9uZpEaZVIChNIWZpEahNIWhREegtVaf3WRp7WVgtVap7WVpBSugtVapBSujZSqWZJaWVWRc7WFWZJac7WFgdUGWZJagdUGjxPyWZJajxPykhJu', 'MW9OKmDiUODmMW9OUODmUS78MW9OUS78X76KMW9OX76KV854MW9OV854QK5aFGfhFqhlghhhFGfhghhhhNZJFGfhhNZJV4ZJFGfhV4ZJUSYhFGfhUSYhUOGqFGfhUOGqJ4GqFGfhJ4GqIGHuFGfhIGHuFGVeD0ntD0txIet-Iet-Jaw-dNw-Iet-dNw-eJt-eJt-jNt-jxtReJt-jxtRjxo7eJt-jxo7fxnheJt-fxnhgdkpeJt-gdkpG4kpeJt-G4kpGenpeJt-GenpD0nteJt-D0ntIet-', 'AmnNBavlGewFAmnNGewFJazFAmnNJazFdNzFAmnNdNzFg3wFAmnNg3wFlhuxAmnNlhuxmBndAmnNmBndiRjhAmnNiRjhjhYtjhYtq7YVrRWxjhYtrRWxrRSOjhYtrRSOmBQSjhYtmBQSmxJOjhYtmxJOjhHCjhHCmxDilt7qjhHClt7qZJ7KZJ7KY744RK2qZJ7KRK2qKm7uZJ7KKm7uDmQ8ZJ7KDmQ8D0gBZJ7KD0gBEGjhEGjhAmnNjhYtEGjhjhYtjhHCEGjhjhHCZJ7K'
ICON_DATA.gasmortar.tg, ICON_DATA.gasmortar.tb, ICON_DATA.gasmortar.te = '7mhBAChBACddBacVEKd-GqcVIehJAChB7mhBIehJ7mhB90hNIehJ90hN9mjxIehJ9mjxB4lFIehJB4lFDamFIehJDamFH8llIehJH8llJSjhIehJJSjhJyhNIehJJyhNLChBIehJLChBLCcdIOX-JiZBKSXtIOX-KSXtGyUOIOX-GyUOFqVKIOX-FqVKHCWpIOX-HCWpGSXlGSXlE4WpCKXpBiWtCyVOBqUaBiWtBqUa8KY3BiWt8KY39GZBBiWt9GZBAaX-BiWtAaX-BWYxBWYx7mcd7mhBBWYx7mhBACddBWYxACddBacVBWYxBacVGqcVBWYxGqcVImdNImdNIehJLCcdImdNLCcdHSYxHSYxIOX-GSXlHSYxGSXlCKXpCKXpBiWtBWYxCKXpBWYxImdNCKXpImdNHSYxHmn7J4q-LyqxLyOuOyLyOuH4LyOuOuH4G0H8LyOuG0H8G0LyLyOuG0LyJ0OuLyOuJ0OuImTyMmXtL4aFMmbtMmihLaipKmkhKmkhHmn7LyqxLyTSLyOuImTyLyTSImTyMmXtMmihKmkhLyqxMmihLyqxPyfBPyfBLyTSMmXtPyfBMmXtMmbtPyfBMmbtMmih', 'phB8CGBSFKF0phB8FKF0QuF0phB8QuF0R4I0phB8R4I0jtI0O0PuO0QyftR0O0PuftR0fxK8fxK8R4K4R0MyfxK8R0MyO0PudtopaJqxttq-dtopttq-txk7dtoptxk7iJk3S0eNOKq-Seq-S0eNSeq-XtplS0eNXtplcNnFS0eNcNnFfBkhS0eNfBkhhxghS0eNhxghjRchS0eNjRchjtT4S0eNjtT4OGT8', '5Whh8GlxFioJFioJJ4tFvNslFioJvNslvNiJFioJvNiJjxhhFioJjxhhlxbxFioJlxbxmBSeFioJmBSeiBQiFioJiBQiiBKOiBKOmxICrRCyiBKOrRCyrR9eiBKOrR9eAq9KiBKOAq9KA0ByiBKOA0ByDmGeiBKODmGeDmMiiBKODmMiGmSCiBKOGmSCESTWESTWAqSK60XNESTW60XN5WhhESTW5WhhFioJESTWFioJiBKO'

-- ======================================================================================================
-- Targeting laser (drawn only on your screen). (5.0, my colors) red from the gun to the enemy it is firing at,
-- amber while it is locked on but not firing yet (lining up, turning), flashing green to the enemy it is being kept
-- off because a friendly (you, a teammate, a sentry, a SEAF soldier or civilian) is in the way, gray when it lost
-- sight of its target. Uses the engine's own line drawing; if that is not
-- available in this game build, the laser simply stays off and the log says why.
-- ======================================================================================================
-- the laser is switched on by the optional 'Targeting laser' part of the mod (a tiny second addon that sets
-- this flag); it is read every frame, so load order does not matter
-- ((5.0 Test 13) the drawing runs for the Targeting Laser or the Targeting Marker option: the two are separate options, see
-- laser.step in engine_main.lua for what each keeps)
local function laser_wanted() return rawget(_G, 'SmarterGuardDogsLaser') == true or rawget(_G, 'SmarterGuardDogsMarker') == true end
local RED_SECONDS = 0.6         -- how long the red warning stays up after the safety steps in
-- (4.0: colors about 25% dimmer than before, a tester's call; the sentries' rings are a little brighter, see
-- engine_sentry.lua)
-- (5.0) the beam's meaning (each table is the key the drawing looks its look up by; alpha, red, green, blue)
local FIRE = { 255, 220, 16, 12 }     -- firing at an enemy: red
local FRIEND = { 255, 0, 200, 20 }    -- held off an enemy because a friendly is in the way: green (flashing)
-- ((5.1.0 Test 1, my ask: "make the laser inversion an option. Put it back to how I had it, and make it an option I can
-- change" - "suboptions under targeting laser") the '... green while firing' choices under Targeting Laser set this flag:
-- firing green and the safety's flashing beam red, as before 5.0. The tables above stay the keys; only the look swaps)
local LOST = { 255, 150, 150, 150 }   -- a shot stopped because the target went out of sight (cover or smoke): gray
local LOCK = { 255, 230, 140, 0 }     -- locked on, not firing yet (lining up, turning onto it): amber
local LASER_RISE = 0.0               -- meters above the drone's center where the beam starts
local LASER_FORWARD = 0.45           -- meters out from the drone's center toward its target (its front face)
local AIM_RISE = 0.5                 -- meters above an enemy's base when not following a barrel (low: most bugs are small);
                                     -- a dog can set its own (the Guard Dog's shots land ~1.2-1.4 m up, measured in game)
local ATTACK_STEPS = { [6] = true, [7] = true }   -- the dog's AI steps for lining up a shot and firing
local FIRE_STEP = 7                               -- the step where it is actually shooting (6: lining it up)
local FLASH_HZ = 6

local laser = { state = 'not started', worlds = {},
  -- (4.6.7 Test 1, my note: the Rover's laser shook while it aimed) seconds: how quickly a dog's beam end catches up
  -- with where it should point (as BEAM_SMOOTH does for the sentries since 5.0 Test 14; the dogs had none)
  dog_smooth = 0.1, dog_beam = {} }
-- ((5.0 Test 9, my note: the markers "need to move more in real time like actual pings"; the laser "sometimes floating
-- in front of the enemies") an enemy's place as the game draws it this frame - its unit's root - instead of the copy in
-- the gun's perception record, which the AI refreshes only ~6 times a second (the Test 8 probe: a gunship's place held
-- still every other sample). The perception copy when the unit can't be read
laser.live = function(c)
  local e = c and c.ent
  if e then
    local p = unit_position(u32(e, 12))
    if p then return p end
  end
  return c and c.pos
end
-- ((5.0 Test 9) how far into the enemy a beam fixed on a barrel runs past the point nearest its centre: the line is
-- depth-tested, so its visible end is where it meets the enemy's body)
laser.INTO = 0.4
-- ((5.1.5 Test 22, my note: "some enemies I've seen the laser above their heads") the beam runs along the barrel, and a
-- barrel pitched up for a long shot - or a short enemy under the beam's usual height - had it pass over the enemy's
-- head. When the beam's end is beside the enemy (within its width) but above its top, the end comes down onto its upper
-- body; a beam off to the side stays as it is. Tops (meters above the feet) by enemy name, 2 m when unknown; 0 = flying
-- or huge, left alone (laser.kind_name is set by the sentry code, which knows the armor table)
local LASER_TOPS = {
  { 'Bile Titan', 9 }, { 'Factory Strider', 12 }, { 'War Strider', 6 }, { 'Scout Strider', 4.2 }, { 'Harvester', 7 },
  { 'Tank', 3.2 }, { 'Hulk', 3.4 }, { 'Charger', 3.0 }, { 'Impaler', 3.5 }, { 'Spewer', 2.6 }, { 'Commander', 2.4 },
  { 'Hive Guard', 1.8 }, { 'Warrior', 1.6 }, { 'Hunter', 1.1 }, { 'Scavenger', 0.8 }, { 'Pouncer', 1.0 }, { 'Stalker', 2.8 },
  { 'Berserker', 2.4 }, { 'Devastator', 2.6 }, { 'Overseer', 2.6 }, { 'Fleshmob', 2.8 }, { 'Crescent', 2.6 },
  { 'Voteless', 1.8 }, { 'Gatekeeper', 3.2 }, { 'Veracitor', 3.5 }, { 'Emplacement', 2.5 },
  { 'Gunship', 0 }, { 'Dropship', 0 }, { 'Stingray', 0 }, { 'Warp Ship', 0 }, { 'Leviathan', 0 }, { 'Watcher', 0 },
  { 'Elevated', 0 }, { 'Shrieker', 0 }, { 'Dragonroach', 0 }, { 'Hive Lord', 0 }, { 'Vox Engine', 0 },
}
local LASER_TOP = { n = 0 }
laser.top_of = function(kind)
  if not kind then return 2.0 end
  local v = LASER_TOP[kind]
  if v then return v end
  v = 2.0
  local nm = laser.kind_name and laser.kind_name(kind)
  if nm then for _, e in ipairs(LASER_TOPS) do if nm:find(e[1], 1, true) then v = e[2]; break end end end
  if LASER_TOP.n < 500 then LASER_TOP[kind], LASER_TOP.n = v, LASER_TOP.n + 1 end
  return v
end
laser.fit_end = function(e, c)
  local p = e and c and c.pos and laser.live(c)
  if not p then return e end
  local T = laser.top_of(c.kind)
  if T <= 0 or e[3] <= p[3] + T then return e end
  local dx, dy, w = e[1] - p[1], e[2] - p[2], math.max(1.2, 0.4 * T)
  if dx * dx + dy * dy > w * w then return e end
  return { e[1], e[2], p[3] + T * 0.6 }
end
laser.MARK_SETTLE = 0.25   -- ((5.1.0 Test 1) seconds a dog keeps a target before its marker shows over it
-- (4.5.3) Laser Brightness (the option's sub-options, or Bingus' Mod Options Menu): a multiplier on every beam's and ring's
-- color - the lines' red, green and blue (the engine ignores their transparency), the glow's transparency. 1 = as
-- before; read every frame
-- (5.0 Test 15, my ask: "add targeting marker opacity as well, in case people want to tune how it appears") the Marker
-- Opacity option (its sub-options, or the Mod Options Menu): a multiplier on the markers' transparency. 1 = as designed
laser.marker_opacity = function()
  local o = rawget(_G, 'SmarterGuardDogsMarkerOpacity')
  if type(o) ~= 'number' or o ~= o then return 1 end
  return math.max(0.1, math.min(1, o))
end
-- (5.1.0 Test 1, my ask: "Add an option in the options menu to adjust the size of the targeting marker") the Marker
-- Size option (its sub-options, or the Mod Options Menu): a multiplier on the markers' size. 1 = as designed
laser.marker_size = function()
  local o = rawget(_G, 'SmarterGuardDogsMarkerSize')
  if type(o) ~= 'number' or o ~= o then return 1 end
  return math.max(0.25, math.min(3, o))
end
laser.inverted = function() return rawget(_G, 'SmarterGuardDogsLaserInvert') == true end
laser.brightness = function()
  local b = rawget(_G, 'SmarterGuardDogsLaserBrightness')
  if type(b) ~= 'number' or b ~= b then return 1 end
  return math.max(0.1, math.min(3, b))
end
local SR = rawget(_G, 'stingray')

-- (4.0.1) how a beam looks. The engine draws 1-pixel lines, ignores their transparency and renders their colors
-- far brighter than given (Test 2 and 4 screenshots: every green came out as pure neon green), so a beam is a thin core
-- line with a strand 4 mm to either side of it: a real beam's width, which perspective makes about 3 pixels up close
-- and a single pixel far away. (Test 1-4 kept the width constant on screen from an estimate of the camera's position;
-- with you far from the sentry, e.g. dead, that estimate put the strands centimeters apart and the beam split in two.)
-- (4.5) One solid color from end to end (the 4.0.1-4.0.6 fade toward the far end is gone, a tester's call), and the
-- green is a neon laser-pointer green, (0,200,20). A beam on a target ends in a small cross just in front of the
-- enemy. The line object is depth-tested: walls and terrain hide the beam like a real one.
do
  -- (5.0 Test 5, my note: Test 4's thick beam "looks super cartoony") a laser's look: one hot core line inside four
  -- strands 3 mm out in the beam's own color (no darker edge: the engine draws lines solid, so a dim edge only made a
  -- dark outline), ending in a small bright cross on the enemy. Only firing and safety holds have a beam; locked on
  -- (about to fire) and target lost are a marker over the enemy instead, like the game's ping. Every beam and marker
  -- fades with its distance from you (FADE: full up to 'near' m, down to 'low' at 'far' m and beyond)
  -- (5.0 Test 6, my ask: "less intense", like a real laser - a thin line with a soft glow and a bright point where
  -- it leaves the gun) the strands are dimmer than the core, the core is only lightly whitened, and a small star
  -- marks the emitter. The marker is the gun's own stratagem icon ("I won't know what sentry/dog it is"), facing you
  -- and kept about the same size on screen at any distance, over a small chevron pointing at the enemy
  local BEAM = {
    inner = 0.003, strands = 0,   -- ((5.0 Test 8) no strands: lines 3 mm apart broke the beam into dashes on screen)
    dot = 0.035, dot_back = 0.08,   -- the cross on the target: its half-size, and how far in front of the end
    flare = 0.045, flare_v = 0.028,  -- the star at the emitter: its half-width and half-height (meters)
    mark_up = 1.0,                   -- the chevron's point, over the enemy's aim point (meters)
    icon_per_m = 0.05, icon_min = 0.5, icon_max = 7.0,   -- ((5.1.5 Test 30: "the mortar marker still sometimes doesnt show at range") was 3.5: past 70 m the marker shrank (17 px at a mortar's 125 m); the same size on screen now to 140 m
      -- ((5.0 Test 8) about 40 px at 1080p, was 30)   -- the icon's height: this much per meter from you, within these
    icon_scale = 0.75,               -- ((5.2, my ask: "make the default size of the in-game markers 25% smaller") about 30 px at 1080p; Marker Size multiplies this
  }
  local FADE = { near = 25, far = 70, low = 0.45, steps = 4 }
  laser.fade_of = function(from)
    local me = laser.me
    if not me then return 1 end
    local d = math.sqrt((from[1] - me[1]) ^ 2 + (from[2] - me[2]) ^ 2 + (from[3] - me[3]) ^ 2)
    if d <= FADE.near then return 1 end
    local f = math.max(FADE.low, 1 - (1 - FADE.low) * (d - FADE.near) / (FADE.far - FADE.near))
    return math.floor(f * FADE.steps + 0.5) / FADE.steps   -- (a few levels only: each is a color made once)
  end
  -- colors (alpha, red, green, blue; the engine ignores the alpha) by the beam's base color: core, side strands,
  -- the cross on the target
  -- (4.5: green is (0,200,20) throughout, a tester's pick, shown as neon green in game; red and yellow keep
  -- the color-chart shades a tester picked in 4.0.1: core post 9, sides post 8, cross post 10)
  -- core, inner strands, outer (soft edge) strands, the ring and dot on the target
  local function shade(c, k) return { c[1], math.floor(c[2] * k + 0.5), math.floor(c[3] * k + 0.5), math.floor(c[4] * k + 0.5) } end
  -- (the core whitened a little: a laser's hottest line; the strands dimmer, the glow round it. Test 6: less whitening
  -- (35% before) and dimmer strands (the pure color before) - "the lasers should be less intense". 'body': the icon's
  -- sentry or backpack, half as bright as its weapon glyph, the HUD icon's two tones)
  local function look(c, k)
    local a = shade(c, k)
    local w = { a[1], math.floor(a[2] + (255 - a[2]) * 0.12), math.floor(a[3] + (255 - a[3]) * 0.12), math.floor(a[4] + (255 - a[4]) * 0.12) }
    return { core = w, side = shade(c, k * 0.72), dot = w, body = shade(c, k * 0.5) }
  end
  local STYLE = {
    [FIRE] = look(FIRE, 0.9), [FRIEND] = look(FRIEND, 0.9),
    [LOST] = look(LOST, 0.8), [LOCK] = look(LOCK, 1),
  }
  -- ((5.1.0 Test 1) the swapped colors: firing in the safety's green, the safety's beam in the firing red)
  local STYLE_INV = { [FIRE] = STYLE[FRIEND], [FRIEND] = STYLE[FIRE], [LOST] = STYLE[LOST], [LOCK] = STYLE[LOCK] }
  -- the icons (icon_data.lua), unpacked once: per icon its glyph and body as flat lists of (height, left, right),
  -- the height 0..1 from the bottom and the sides -0.5..0.5 across
  local ICONS = {}
  do
    local val = {}
    for k = 1, #ICON_DATA.abc do val[ICON_DATA.abc:sub(k, k)] = k - 1 end
    local R, C = ICON_DATA.rows, ICON_DATA.cols
    local function unpack_runs(str)
      local out = {}
      for k = 1, #str - 2, 3 do
        out[#out + 1] = (val[str:sub(k, k)] + 0.5) / R
        out[#out + 1] = val[str:sub(k + 1, k + 1)] / C - 0.5
        out[#out + 1] = val[str:sub(k + 2, k + 2)] / C - 0.5
      end
      return out
    end
    -- ((5.1.0 Test 1, my ask: "clean up the marker a bit, its kind of low-resolution") the icons as filled shapes
    -- (tools/icons_vec.py): triangles traced from the 256-pixel HUD icons, smooth edges at any size, and a rounded dark
    -- edge. Each triangle six numbers (across, up), turned counterclockwise as the band quads are)
    local vval = {}
    if ICON_DATA.vabc then for k = 1, #ICON_DATA.vabc do vval[ICON_DATA.vabc:sub(k, k)] = k - 1 end end
    -- ((5.1.0 release review) each corner once - the triangles share most of them - and the triangles as three corner
    -- numbers: { v = { across, up, ... }, i = { corner, corner, corner, ... } })
    local function unpack_tris(str)
      if not str then return nil end
      local v, idx, at = {}, {}, {}
      local function corner(k)
        local key = str:sub(k, k + 3)
        local n = at[key]
        if not n then
          n = #v / 2 + 1; at[key] = n
          v[#v + 1] = (vval[str:sub(k, k)] * 64 + vval[str:sub(k + 1, k + 1)]) / 4095 - 0.5
          v[#v + 1] = (vval[str:sub(k + 2, k + 2)] * 64 + vval[str:sub(k + 3, k + 3)]) / 4095
        end
        return n
      end
      for k = 1, #str - 11, 12 do
        local a, b, c = corner(k), corner(k + 4), corner(k + 8)
        local ax, ay, bx, by, cx, cy = v[a * 2 - 1], v[a * 2], v[b * 2 - 1], v[b * 2], v[c * 2 - 1], v[c * 2]
        if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0 then b, c = c, b end
        idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
      end
      return { v = v, i = idx }
    end
    for name, d in pairs(ICON_DATA) do
      if type(d) == 'table' then
        local ic = { g = unpack_runs(d.g), b = unpack_runs(d.b), rows = R, tg = unpack_tris(d.tg), tb = unpack_tris(d.tb), te = unpack_tris(d.te) }
        -- ((5.0 Test 8) per band, its leftmost to rightmost run: the dark edge behind the GUI marker, one quad a band)
        local span, sh = {}, {}
        for _, L in ipairs({ ic.g, ic.b }) do
          for k = 1, #L, 3 do
            local h = L[k]
            local sp = span[h]
            if not sp then span[h] = { L[k + 1], L[k + 2] } else sp[1], sp[2] = math.min(sp[1], L[k + 1]), math.max(sp[2], L[k + 2]) end
          end
        end
        for h, sp in pairs(span) do sh[#sh + 1] = h; sh[#sh + 1] = sp[1]; sh[#sh + 1] = sp[2] end
        ic.sh = sh
        ICONS[name] = ic
      end
    end
  end
  -- which icon each gun shows (by its name in DEFS/DOGS); ((5.1.5 Test 7, my ask: "It should use the Booster icon")
  -- the pod gun shows the Armed Resupply Pods booster's pod and gun (it ran the Gatling's)
  local ICON_OF = {
    ['Machine Gun Sentry'] = 'mg', ['Gatling Sentry'] = 'gatling', ['Autocannon Sentry'] = 'ac', ['Rocket Sentry'] = 'rocket',
    ['Laser Sentry'] = 'laser', ['Flame Sentry'] = 'flame', ['Tesla Tower'] = 'tesla', ['Mortar Sentry'] = 'mortar',
    ['EMS Mortar Sentry'] = 'ems', ['Gas Mortar Sentry'] = 'gasmortar',   -- ((5.1.5 Test 12) its own icon, from the wiki's (the game's is out of reach)
    ['Resupply Pod Gun'] = 'pod', ['Supply FRV Gun'] = 'frv',
    ['Guard Dog'] = 'dog', ['Rover'] = 'rover', ['K-9'] = 'k9',
  }
  -- the strands' directions round the beam, and the ring's, worked out once
  local SC, SS = {}, {}
  for k = 1, BEAM.strands do local a = 2 * math.pi * (k - 0.5) / BEAM.strands; SC[k], SS[k] = math.cos(a), math.sin(a) end

  local sqrt = math.sqrt
  -- two unit vectors at right angles to the unit vector d and to each other (the first one level)
  local function perp(dx, dy, dz)
    local ux, uy = -dy, dx
    local l = sqrt(ux * ux + uy * uy)
    if l < 1e-4 then ux, uy, l = 1, 0, 1 end
    ux, uy = ux / l, uy / l
    return ux, uy, 0, -dz * uy, dz * ux, dx * uy - dy * ux
  end
  laser.styled = function(b) return STYLE[b.argb] ~= nil end
  -- the marker over an enemy: line(color, fade, ...) as for the beams. The gun's icon stands upright facing you (its
  -- lines run across your view, so the bands read as a filled shape), about 30 pixels tall at any distance; a small
  -- chevron under it points at the enemy
  -- where a marker goes: its icon, the chevron's point (x, y, z), your right (rx, ry), its size and the chevron's
  -- half-width. ((5.0 Test 8) several guns on one enemy: their icons side by side - b.slot of b.slots, set by
  -- laser.prepare)
  -- ((5.0 Test 15, my ask: "the marker only appears vertically up and down, it should display to you the same whether
  -- you are flat on the ground or looking down from the top of a skyscraper") the marker faces your eyes, tilted as
  -- well as turned: its right stays level, its 'up' (ux, uy, uz) leans back as you look down on it. Your eyes: 1.7 m
  -- over your helldiver (the camera is close to that). Straight down on it, the last right is kept
  local EYE_UP = 1.7
  laser.mark_right = { 1, 0 }
  laser.marker_geom = function(b)
    local t = b.to
    local me = laser.me
    local x, y, z = t[1], t[2], t[3] + BEAM.mark_up
    local rx, ry, dist = laser.mark_right[1], laser.mark_right[2], 20
    local ux, uy, uz = 0, 0, 1
    if me then
      local fx, fy, fz = x - me[1], y - me[2], z - (me[3] + EYE_UP)
      dist = sqrt(fx * fx + fy * fy + fz * fz)
      local l = sqrt(fx * fx + fy * fy)
      if l > 0.05 * dist and l > 0.05 then rx, ry = fy / l, -fx / l; laser.mark_right[1], laser.mark_right[2] = rx, ry end   -- (your right, looking at it)
      if dist > 0.1 then
        fx, fy, fz = fx / dist, fy / dist, fz / dist
        -- up = right x forward (right is level: its z is 0)
        ux, uy, uz = ry * fz, -rx * fz, rx * fy - ry * fx
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        if ul > 1e-3 then ux, uy, uz = ux / ul, uy / ul, uz / ul else ux, uy, uz = 0, 0, 1 end
      end
    end
    local sz = math.min(BEAM.icon_max, math.max(BEAM.icon_min, dist * BEAM.icon_per_m)) * BEAM.icon_scale * laser.marker_size()
    local n = b.slots or 1
    if n > 1 then
      local o = ((b.slot or 1) - (n + 1) / 2) * sz * 1.1
      x, y = x + rx * o, y + ry * o
    end
    local ic = ICONS[ICON_OF[b.icon or ''] or ''] or ICONS.mg   -- (b.icon: the gun's name)
    return ic, x, y, z, rx, ry, sz, sz * 0.12, ux, uy, uz
  end
  -- the marker as lines (when the game build has no world GUI): line(color, fade, ...) as for the beams. The gun's icon
  -- stands upright facing you, about 30 pixels tall at any distance; a small chevron under it points at the enemy
  -- ((5.1.3, my ask: "being able to hide the markers ... behind walls") the game's lines are the only drawing
  -- walls hide (the world GUI can't be depth tested from a mod), so Behind walls draws the marker with them: the traced
  -- icon (edge, body, glyph) cut into rows, one line per row and color - lines a pixel or so apart, so it reads as filled
  -- - with a row's pieces never overlapping (lines in one plane would fight). Each icon is cut once into 96 rows
  -- (0.3-1.8 ms; warmed one icon a frame while Behind walls is on, see laser.warm_markers); smaller markers take every
  -- 2nd, 3rd or 4th row (48, 32, 24 rows), about one row per pixel of the marker's height on screen
  local BASE_ROWS = 96
  local MARK_LINES = 500   -- ((5.1.4) the most lines all Behind walls markers may use in a frame, the chevrons aside)
  local SCAN, CUT = {}, {}
  local function by_start(p, q) return p[1] < q[1] end
  local function cut_icon(ic)
    local base = CUT[ic]
    if base then return base end
    base = {}
    local layers = { ic.te, ic.tb, ic.tg }
    for r = 1, BASE_ROWS do
      local y = (r - 0.5) / BASE_ROWS
      local iv = {}
      for L = 1, 3 do
        local v, I = layers[L].v, layers[L].i
        local list = {}
        for k = 1, #I, 3 do
          local lo, hi
          for e = 0, 2 do
            local p, q = I[k + e], I[k + (e + 1) % 3]
            local px, py, qx, qy = v[p * 2 - 1], v[p * 2], v[q * 2 - 1], v[q * 2]
            if (py <= y and qy > y) or (qy <= y and py > y) then
              local x = px + (y - py) * (qx - px) / (qy - py)
              if not lo or x < lo then lo = x end
              if not hi or x > hi then hi = x end
            end
          end
          if lo and hi > lo then list[#list + 1] = { lo, hi } end
        end
        table.sort(list, by_start)
        local merged = {}
        for _, sg in ipairs(list) do
          local m = merged[#merged]
          if m and sg[1] <= m[2] + 1e-4 then if sg[2] > m[2] then m[2] = sg[2] end else merged[#merged + 1] = { sg[1], sg[2] } end
        end
        iv[L] = merged
      end
      -- the glyph on top, then the body outside it, then the edge outside both: { across from, across to, layer, ... }
      local row, covered = {}, {}
      for L = 3, 1, -1 do
        for _, sg in ipairs(iv[L]) do
          local pieces = { { sg[1], sg[2] } }
          for _, c in ipairs(covered) do
            local np = {}
            for _, pc in ipairs(pieces) do
              if c[2] <= pc[1] or c[1] >= pc[2] then np[#np + 1] = pc
              else
                if c[1] > pc[1] then np[#np + 1] = { pc[1], c[1] } end
                if c[2] < pc[2] then np[#np + 1] = { c[2], pc[2] } end
              end
            end
            pieces = np
          end
          for _, pc in ipairs(pieces) do
            if pc[2] - pc[1] > 1e-4 then row[#row + 1] = pc[1]; row[#row + 1] = pc[2]; row[#row + 1] = L end
          end
        end
        for _, sg in ipairs(iv[L]) do covered[#covered + 1] = sg end
      end
      base[r] = row
    end
    CUT[ic] = base
    return base
  end
  -- an icon in 'rows' rows (24, 32, 48 or 96): a flat list { up, across from, across to, layer, ... }
  local function scan_icon(ic, rows)
    local byrows = SCAN[ic]
    if not byrows then byrows = {}; SCAN[ic] = byrows end
    local out = byrows[rows]
    if out then return out end
    local base, k = cut_icon(ic), BASE_ROWS / rows
    out = {}
    for r = 1, rows do
      local row = base[(r - 1) * k + math.floor(k / 2) + 1]
      local y = (r - 0.5) / rows
      for j = 1, #row, 3 do out[#out + 1] = y; out[#out + 1] = row[j]; out[#out + 1] = row[j + 1]; out[#out + 1] = row[j + 2] end
    end
    byrows[rows] = out
    return out
  end
  -- (while Behind walls is on) one icon not cut yet, cut this frame: all of them ready in a dozen frames, before most
  -- markers are first needed - no frame cuts more than one unless a marker needs its icon at once
  laser.warm_markers = function()
    for _, ic in pairs(ICONS) do
      if ic.tg and not CUT[ic] then cut_icon(ic); return end
    end
    laser.markers_warm = true   -- ((release review) all cut: laser.step stops calling this
  end
  -- the solid colors (alpha ignored by the lines): the GUI marker's glyph and body; its see-through black edge as a dark shade
  local LMARK = {
    [LOCK] = { { 255, 40, 32, 8 }, { 255, 255, 214, 60 }, { 255, 255, 248, 170 } },
    [LOST] = { { 255, 40, 40, 40 }, { 255, 214, 214, 214 }, { 255, 250, 250, 250 } },
  }
  local function marker(b, S, line)
    local fd = b.fade or 1
    local ic, x, y, z, rx, ry, sz, cw, ux, uy, uz = laser.marker_geom(b)
    local C = LMARK[b.argb]
    if ic.tg and C then
      -- (the marker's own colors, not dimmed with distance or by Laser Brightness: the brightness is undone here)
      fd = 1 / laser.brightness()
      local me, t = laser.me, b.to
      local dist = me and sqrt((t[1] - me[1]) ^ 2 + (t[2] - me[2]) ^ 2 + (t[3] - me[3]) ^ 2) or 20
      local px = 40 * sz / (math.max(dist, 1) * BEAM.icon_per_m)   -- (its height in pixels, about)
      local rows = px <= 24 and 24 or px <= 32 and 32 or px <= 48 and 48 or 96
      local R = scan_icon(ic, rows)
      -- ((5.1.4, players: "the performance is much worse") the marker lines a frame are capped (MARK_LINES for all of
      -- them together): a lone close marker keeps every row, several at once step down in rows until they fit. A fixed
      -- cap per marker would have striped every nearby marker - 24 rows is already 60-110 lines)
      local used = laser.mark_lines or 0
      while rows > 24 and used + #R / 4 > MARK_LINES do
        rows = rows == 96 and 48 or rows == 48 and 32 or 24
        R = scan_icon(ic, rows)
      end
      laser.mark_lines = used + #R / 4
      local base = cw + sz * 0.1
      for k = 1, #R, 4 do
        local h, a, c = base + R[k] * sz, R[k + 1] * sz, R[k + 2] * sz
        line(C[R[k + 3]], fd, x + rx * a + ux * h, y + ry * a + uy * h, z + uz * h, x + rx * c + ux * h, y + ry * c + uy * h, z + uz * h)
      end
      -- the chevron: each bar a few lines across its thickness, the dark edge on either side
      local tk = sz * 0.035
      local n = math.max(1, math.floor(rows * 0.035 + 0.5))
      for side = -1, 1, 2 do
        for j = -n - 1, n + 1 do
          local o = tk * j / n
          local col = (j < -n or j > n) and C[1] or C[3]
          line(col, fd, x + rx * cw * side + ux * (cw + o), y + ry * cw * side + uy * (cw + o), z + uz * (cw + o), x + ux * o, y + uy * o, z + uz * o)
        end
      end
      return
    end
    -- (a point a along your right and h along the marker's up, from the chevron's tip)
    line(S.core, fd, x - rx * cw + ux * cw, y - ry * cw + uy * cw, z + uz * cw, x, y, z)
    line(S.core, fd, x + rx * cw + ux * cw, y + ry * cw + uy * cw, z + uz * cw, x, y, z)
    local base = cw + sz * 0.1
    for pass = 1, 2 do
      local L, col = pass == 1 and ic.b or ic.g, pass == 1 and S.body or S.core
      for k = 1, #L, 3 do
        local h, a, c = base + L[k] * sz, L[k + 1] * sz, L[k + 2] * sz
        line(col, fd, x + rx * a + ux * h, y + ry * a + uy * h, z + uz * h, x + rx * c + ux * h, y + ry * c + uy * h, z + uz * h)
      end
    end
  end
  -- adds one styled beam (or marker) as lines: line(color, fade, x1, y1, z1, x2, y2, z2) draws one line in a color dimmed
  -- by 'fade'. A beam: its strands, a small cross on the target, the star at the gun, and the core last, on top
  laser.draw_styled = function(b, line)
    local S = (laser.inv and STYLE_INV or STYLE)[b.argb]   -- ((release review) laser.inv: read once a frame, laser.step)
    if b.marker then return marker(b, S, line) end
    local f, t = b.from, b.to
    local dx, dy, dz = t[1] - f[1], t[2] - f[2], t[3] - f[3]
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.05 then return end
    dx, dy, dz = dx / len, dy / len, dz / len
    local ux, uy, uz, vx, vy, vz = perp(dx, dy, dz)
    local fd = b.fade or 1
    local w = BEAM.inner
    for k = 1, BEAM.strands do
      local cu, cv = SC[k] * w, SS[k] * w
      local ox, oy, oz = ux * cu + vx * cv, uy * cu + vy * cv, uz * cu + vz * cv
      line(S.side, fd, f[1] + ox, f[2] + oy, f[3] + oz, t[1] + ox, t[2] + oy, t[3] + oz)
    end
    if b.dot then
      -- a small bright cross where it hits, just in front of the end
      local back = math.min(BEAM.dot_back, len * 0.5)
      local qx, qy, qz = t[1] - dx * back, t[2] - dy * back, t[3] - dz * back
      local d = BEAM.dot
      line(S.dot, fd, qx - ux * d, qy - uy * d, qz - uz * d, qx + ux * d, qy + uy * d, qz + uz * d)
      line(S.dot, fd, qx - vx * d, qy - vy * d, qz - vz * d, qx + vx * d, qy + vy * d, qz + vz * d)
    end
    if not b.no_flare then
      -- ((5.0 Test 6) the star where it leaves the gun: a short level line and a shorter upright one, across the beam)
      local h, g = BEAM.flare, BEAM.flare_v
      line(S.core, fd, f[1] - ux * h, f[2] - uy * h, f[3] - uz * h, f[1] + ux * h, f[2] + uy * h, f[3] + uz * h)
      line(S.core, fd, f[1] - vx * g, f[2] - vy * g, f[3] - vz * g, f[1] + vx * g, f[2] + vy * g, f[3] + vz * g)
    end
    line(S.core, fd, f[1], f[2], f[3], t[1], t[2], t[3])
  end

end

-- every world the engine reports right now (re-read each frame, so a closed world is never touched again)
local ONE_WORLD = {}   -- ((4.6.4 review) the usual answer, one table kept: nothing is made on the frames it is asked)
local function live_worlds()
  local A = SR and SR.Application
  if type(A) ~= 'table' then return nil, 'no stingray.Application' end
  if type(A.main_world) == 'function' then
    local ok, w = pcall(A.main_world)
    if ok and w ~= nil then laser.world_source = 'main_world()'; ONE_WORLD[1] = w; return ONE_WORLD end
  end
  local list, seen = {}, {}
  local function add(w) if w ~= nil and not seen[w] then seen[w] = true; list[#list + 1] = w end end
  local src = {}
  if type(A.worlds) == 'function' then
    local ok, ws = pcall(A.worlds)
    if ok and type(ws) == 'table' then for _, w in pairs(ws) do add(w) end; src[#src + 1] = 'worlds()' end
  end
  for _, n in ipairs({ 'main_world', 'flow_callback_context_world' }) do
    if type(A[n]) == 'function' then local ok, w = pcall(A[n]); if ok and w ~= nil then add(w); src[#src + 1] = n .. '()' end end
  end
  laser.world_source = table.concat(src, ', ')
  if #list == 0 then return nil, 'no world available from stingray.Application' end
  return list
end

local function laser_ready()
  if laser.state == 'off' then return false end
  if laser.state == 'ready' then return true end
  local W, LO = SR and SR.World, SR and SR.LineObject
  if type(W) ~= 'table' or type(W.create_line_object) ~= 'function' or type(LO) ~= 'table'
    or type(LO.add_line) ~= 'function' or type(LO.dispatch) ~= 'function' or type(LO.reset) ~= 'function' then
    laser.state, laser.why = 'off', 'engine line drawing is not available in this game build'
    note('laser: off (' .. laser.why .. ')')
    return false
  end
  -- Vector3 and Color are callable in the engine but may be tables with a __call rather than functions
  local okv, v = pcall(SR.Vector3, 1, 2, 3)
  local okc, c = pcall(SR.Color, 255, 1, 2, 3)
  if not (okv and v ~= nil and okc and c ~= nil) then
    laser.state, laser.why = 'off', 'cannot build engine vectors/colors: ' .. tostring(okv and okc or (not okv and v) or c)
    note('laser: off (' .. laser.why .. ')')
    return false
  end
  laser.state = 'ready'
  -- (test builds: which of the engine's drawing and camera functions this game build offers, for future laser work)
  if TESTER then
    pcall(function()
      local function names(t, pat)
        local out = {}
        if type(t) == 'table' then for k in pairs(t) do if type(k) == 'string' and (not pat or k:lower():find(pat)) then out[#out + 1] = k end end end
        table.sort(out)
        return #out > 0 and table.concat(out, ' ') or '-'
      end
      note('laser (test): LineObject: ' .. names(SR.LineObject))
      note('laser (test): World (line/camera/viewport/debug): ' .. names(SR.World, 'line') .. ' | ' .. names(SR.World, 'camera') .. ' | ' .. names(SR.World, 'viewport') .. ' | ' .. names(SR.World, 'debug'))
      note('laser (test): Gui: ' .. names(SR.Gui) .. ' | World (gui): ' .. names(SR.World, 'gui') .. ' | Material: ' .. names(SR.Material))
      note('laser (test): Camera: ' .. names(SR.Camera) .. ' | Application (camera/viewport): ' .. names(SR.Application, 'camera') .. ' ' .. names(SR.Application, 'viewport'))
    end)
  end
  return true
end

local function laser_fail(err)
  laser.state, laser.why = 'off', tostring(err)
  -- ((5.1.2 review) the laser off after an error: what it drew last is taken off the screen first - a line object goes on
  -- showing its last dispatch, so a ring or beam stayed until the game restarted. Each object once, emptied, in a
  -- pcall of its own (they belong to worlds that were live last frame); the glow's retained triangles too)
  local LO = SR and SR.LineObject
  for _, objs in ipairs({ laser.worlds or {}, laser.ring_lo or {} }) do
    for w, lo in pairs(objs) do
      if LO then pcall(function() LO.reset(lo); LO.dispatch(w, lo) end) end
    end
  end
  if laser.glow and laser.glow.clear then pcall(laser.glow.clear) end
  laser.worlds, laser.ring_lo, laser.has, laser.ring_sig = {}, {}, false, nil
  note('laser: stopped after an error: ' .. laser.why)
  event('laser stopped: ' .. laser.why)
end

-- draw this frame's beams (a list of { from, to, argb }) in every live world; an empty list clears them
-- beams: this frame's beams (a list of { from, to, argb }); beams.rings: the sentries' rings, each a list of such segments
-- that a sentry builds once and reuses. (4.0.6) The rings go in a line object of their own that is rebuilt only when
-- the set of rings changes and otherwise just drawn again, instead of 40-80 lines rebuilt every frame. redraw: nothing
-- new this frame (the mod is checking only a few times a second, idle sentries): both line objects are drawn again as
-- they are. An empty list clears everything
-- ((4.6.4 review) the drawing in a named function, called through pcall: a new closure every frame before)
-- (5.0, my ask: "smoother motion") before a frame's beams are drawn: each styled beam gets its fade with distance from you,
-- and a beam that has a 'key' (whose it is: the dog, a sentry) and changed target ('tg') swings its end over to the
-- new target over SWITCH seconds (eased) instead of jumping there
local SWITCH = 0.14
local MARK_HOLD = 0.4
laser.ends = {}
laser.mark_last = {}
local function SLOT_ORDER(a, c) return a.sk < c.sk end
laser.prepare = function(beams)
  local t = os.clock()
  local E_ = laser.ends
  -- ((5.0 Test 8, my note: the marker is "not showing consistently") a locked-on marker missing for a frame or two
  -- (the gun's records between two states) stays up to MARK_HOLD s where it was, so it doesn't blink)
  local MH = laser.mark_last
  -- ((5.0 release review) the held entries are reused, not made anew each frame: m.f = the frame stamp it was last seen)
  laser.mark_frame = (laser.mark_frame or 0) + 1
  local fr = laser.mark_frame
  for _, b in ipairs(beams) do
    if b.marker and b.key then
      local m = MH[b.key]
      if m then m.b, m.t, m.f = b, t, fr else MH[b.key] = { b = b, t = t, f = fr } end
    end
  end
  for k, m in pairs(MH) do
    if m.f ~= fr then
      if t - m.t < MARK_HOLD then beams[#beams + 1] = m.b else MH[k] = nil end
    end
  end
  -- ((5.0 Test 8) markers on the same enemy (or the same spot) side by side)
  local groups
  for _, b in ipairs(beams) do
    if b.marker then
      local k = b.tg or string.format('%.0f/%.0f/%.0f', b.to[1] * 2, b.to[2] * 2, b.to[3] * 2)
      groups = groups or {}
      local g = groups[k]
      if not g then g = {}; groups[k] = g end
      g[#g + 1] = b
    end
  end
  -- ((5.0 Test 17, test builds; my note: with 3 or more guns on one enemy "it doesnt display more than 2, or at least the dog
  -- marker didnt show") how many markers stand on one enemy, and how often the dog's is up while it has a target
  if TESTER then
    local MS = laser.mstat or { n = 0, dog_t = 0, dog_m = 0, most = 0, three = 0, logged = 0 }
    laser.mstat = MS
    MS.n = MS.n + 1
    local top = 0
    for _, g in pairs(groups or {}) do if #g > top then top = #g end end
    if top > MS.most then MS.most = top end
    if top >= 3 then MS.three = MS.three + 1 end
    if laser.dog_target then MS.dog_t = MS.dog_t + 1; if MH.mdog and MH.mdog.f == fr then MS.dog_m = MS.dog_m + 1 end end
    if MS.n >= (rawget(_G, 'SGD_SIM_EVERY') or 1800) and MS.logged < 8 then   -- (the simulator logs sooner)
      MS.logged = MS.logged + 1
      event(string.format('markers (test): over %d frames the dog\'s marker was up on %d of its %d frames with a target; most markers on one enemy %d (3 or more on %d frames)',
        MS.n, MS.dog_m, MS.dog_t, MS.most, MS.three))
      MS.n, MS.dog_t, MS.dog_m, MS.most, MS.three = 0, 0, 0, 0, 0
    end
  end
  if groups then
    for _, g in pairs(groups) do
      if #g > 1 then
        for _, b in ipairs(g) do b.sk = tostring(b.icon) .. tostring(b.key) end   -- (the sort key made once, not per comparison)
        table.sort(g, SLOT_ORDER)
        for i, b in ipairs(g) do b.slot, b.slots = i, #g end
      else
        g[1].slot, g[1].slots = nil, nil   -- ((5.0 release review) a held marker left alone goes back over its enemy)
      end
    end
  end
  for _, b in ipairs(beams) do
    if laser.styled(b) then
      b.fade = laser.fade_of(b.from)
      local key = b.key
      if key then
        local E = E_[key]
        if E and t - E.t < 0.3 then
          -- ((5.0 Test 7) not a beam fixed on its gun's barrel: the barrel turning moves it, as a real one)
          if E.tg ~= b.tg and not b.fixed then E.sw_from, E.sw_t = E.to, t end
          if b.fixed then E.sw_t = nil end
          if E.sw_t then
            local x = (t - E.sw_t) / SWITCH
            if x >= 1 then E.sw_t = nil
            else
              local k = x * x * (3 - 2 * x)
              local a, e = E.sw_from, b.to
              b.to = { a[1] + (e[1] - a[1]) * k, a[2] + (e[2] - a[2]) * k, a[3] + (e[3] - a[3]) * k }
            end
          end
        else
          E = {}
          E_[key] = E
        end
        -- (Testers: how far each beam's end moves a frame while it stays on the same target - the dog's and the
        -- sentries' apart; one line each per 300 frames, up to 6 a session)
        if TESTER and E.to and E.tg == b.tg and not E.sw_t then
          local who = key == 'dog' and 'dog' or 'sentries'
          laser.st5 = laser.st5 or {}
          local S = laser.st5[who] or { n = 0, d = 0, logged = 0 }
          laser.st5[who] = S
          local o, e = E.to, b.to
          local d = math.sqrt((e[1] - o[1]) ^ 2 + (e[2] - o[2]) ^ 2 + (e[3] - o[3]) ^ 2)
          if d < 3 then S.n, S.d = S.n + 1, S.d + d end
          if S.n >= 300 and S.logged < 6 then
            S.logged = S.logged + 1
            event(string.format('laser steadiness (test): the %s beam end moved %.1f cm a frame on the same target (%d frames)', who, 100 * S.d / S.n, S.n))
            S.n, S.d = 0, 0
          end
        end
        E.to, E.tg, E.t = b.to, b.tg, t
      end
    end
  end
  -- (ends not drawn for a while are forgotten)
  if (laser.ends_clean or 0) < t then
    laser.ends_clean = t + 5
    for k, E in pairs(E_) do if t - E.t > 5 then E_[k] = nil end end
  end
end

local function laser_draw_body(beams, redraw)
    local worlds, why = live_worlds()
    if not worlds then
      if laser.wait_reason ~= why then laser.wait_reason = why; event('laser waiting: ' .. tostring(why)) end
      return
    end
    local rings = beams.rings
    if not redraw then laser.prepare(beams) end
    local LO, V = SR.LineObject, SR.Vector3
    local keep, keep_r = {}, {}
    -- (has the set of rings changed since they were last built?)
    local sig = laser.ring_sig or {}
    local same = not redraw and #(rings or sig) == #sig and (rings ~= nil) == (#sig > 0)
    -- (a new brightness rebuilds the rings too)
    local BR = laser.brightness()
    if not redraw and laser.ring_bright ~= BR then same = false; laser.ring_bright = BR end
    if same and rings then for i, r in ipairs(rings) do if sig[i] ~= r then same = false; break end end end
    for _, w in ipairs(worlds) do
      local lo = laser.worlds[w]
      if not lo and not redraw and (#beams > 0 or rings) then
        lo = SR.World.create_line_object(w, false)
        if not laser.announced then
          laser.announced = true
          note(string.format('laser: on (%d world(s) from %s)', #worlds, laser.world_source or '?'))
          event('laser: on')
        end
      end
      if lo then
        keep[w] = lo
        local colours = {}
        -- ((5.0) 'fd': the beam's fade with distance from you, a few levels; each color and level is made once a frame)
        local function colour(a, fd)
          fd = fd or 1
          local byf = colours[a]
          if not byf then byf = {}; colours[a] = byf end
          local c = byf[fd]
          if not c then
            local B2 = BR * fd
            if B2 == 1 then c = SR.Color(a[1], a[2], a[3], a[4])
            else
              -- (4.6.3 review) past full strength a channel can't go brighter (the neon green's 200 reached 255 at about
              -- 130%, so Bright and Brightest looked the same): what is left over whitens the color instead, as the
              -- glow does
              local r, g, b = a[2] * B2, a[3] * B2, a[4] * B2
              local m = math.max(r, g, b)
              if m > 255 then
                local w = math.min(0.6, (m - 255) / m)
                r, g, b = math.min(255, r), math.min(255, g), math.min(255, b)
                r, g, b = r + (255 - r) * w, g + (255 - g) * w, b + (255 - b) * w
              end
              c = SR.Color(a[1], math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
            end
            byf[fd] = c
          end
          return c
        end
        if not redraw then
          LO.reset(lo)
          -- (each color is built once per frame)
          local function line(a, fd, x1, y1, z1, x2, y2, z2) LO.add_line(lo, colour(a, fd), V(x1, y1, z1), V(x2, y2, z2)) end
          -- (4.5: with the glow chosen, the dogs' and sentries' beams are left to it)
          local lines = not (laser.glow and laser.glow.on())
          for _, b in ipairs(beams) do
            -- (the dogs' and sentries' beams: core, cross. (5.0 Test 8) markers are drawn by the world GUI - filled, and seen
            -- through walls like the game's own pings - and as lines only where the game build has none)
            -- ((5.1.3) and as lines - which walls hide - with Targeting Marker: Behind walls)
            if laser.styled(b) then if (b.marker and (laser.walls or not laser.glow.markers_ok())) or (lines and not b.marker) then laser.draw_styled(b, line) end
            else LO.add_line(lo, colour(b.argb), V(b.from[1], b.from[2], b.from[3]), V(b.to[1], b.to[2], b.to[3])) end   -- (any other line)
          end
        end
        LO.dispatch(w, lo)
        -- the rings: rebuilt when they change (a ring's segments share their end points: each point is made once)
        local rlo = laser.ring_lo and laser.ring_lo[w]
        local emptied = false   -- (4.6.8) reset this frame: sent once more, even empty, so the old rings go
        if not redraw and (not same or (rings and not rlo)) then
          if rings and not rlo then rlo = SR.World.create_line_object(w, false) end
          if rlo then
            LO.reset(rlo)
            laser.ring_has = rings ~= nil and #rings > 0   -- ((4.6.7 review) whether it holds anything to show)
            emptied = not laser.ring_has
            local points = {}
            for _, ring in ipairs(rings or {}) do
              for k = 1, #ring do
                local b = ring[k]
                local f, e = points[b.from], points[b.to]
                if not f then f = V(b.from[1], b.from[2], b.from[3]); points[b.from] = f end
                if not e then e = V(b.to[1], b.to[2], b.to[3]); points[b.to] = e end
                LO.add_line(rlo, colour(b.argb), f, e)
              end
            end
          end
        end
        -- ((4.6.7 review) an empty ring object isn't sent to the engine every frame. (4.6.8) But the engine keeps showing
        -- a line object's last dispatch until it is dispatched again: 4.6.7 never sent the emptied object, so the last
        -- rings (a Rocket Sentry's red minimum-range ring) stayed on screen for the rest of the session, ship and later
        -- missions included. The frame it is emptied, it is sent once, empty)
        if rlo then keep_r[w] = rlo; if laser.ring_has or emptied then LO.dispatch(w, rlo) end end
        if laser.glow then laser.glow.draw(w, beams, redraw) end
        if #beams > 0 or rings then stats.laser_frames = stats.laser_frames + 1 end
      end
    end
    if not redraw and not same then
      local copy = {}
      for i, r in ipairs(rings or {}) do copy[i] = r end
      laser.ring_sig = copy
    end
    laser.worlds, laser.ring_lo = keep, keep_r   -- line objects of worlds that went away are simply forgotten, never touched
    if not redraw then laser.has = #beams > 0 or rings ~= nil end
end
local function laser_draw(beams, redraw)
  if not laser_ready() then return end
  local ok, err = pcall(laser_draw_body, beams, redraw)
  if not ok then laser_fail(err) end
end

-- ((4.6.4 review) out of a mission: the line objects and world GUIs kept per world are dropped without being touched -
-- their worlds are gone, and a new mission's world could come back at the same address, where using a stale one would
-- crash the game)
laser.forget = function()
  laser.worlds, laser.ring_lo, laser.has, laser.ring_sig = {}, {}, false, nil
  laser.mark_last = {}
  if laser.glow then laser.glow.guis, laser.glow.ids, laser.glow.last = {}, {}, nil end
end

local function laser_clear()
  -- (4.6.3 review: only when something is on screen - before, every poll with nothing to show redrew empty line objects)
  if laser.state == 'ready' and laser.has and next(laser.worlds) then laser_draw({}) end
end
-- ((5.1.2) the mission ending: everything off the screen at once - the markers held up to MARK_HOLD s too, which an
-- ordinary clear still draws for a moment)
laser.clear_now = function()
  laser.mark_last = {}
  laser_clear()
end
-- (4.0.6) on the frames the mod doesn't look at the game (idle sentries, a few checks a second): the laser as it was
do
  local NO_BEAMS = {}
  laser.redraw = function()
    if laser.has and laser.state == 'ready' and next(laser.worlds) then laser_draw(NO_BEAMS, true) end
  end
end

-- (4.5) the glow, chosen under Targeting Laser ('Glow'; 'Line', the default, leaves the beams as the lines above): the
-- dogs' and sentries' beams drawn as see-through strips (triangles in a world GUI) instead of 1-pixel lines - a narrow
-- bright core inside a wide faint halo, each two crossed strips (one level, one standing up), fading out toward the far
-- end by transparency, with a small bright spot on the target. A tester's pick (4.0.6 Test 2), back as a choice: the
-- game's GUI draws on top of the world (its GUI code switches its gui:DEPTH_TEST_ENABLED flag off; Gui.rect_3d was no
-- different, 4.0.6 Test 10; no GUI material could switch it back on, Test 18), and HD2 has no Lua raycasts to hide it
-- where a wall is in the way, so the glow shows through walls - the options say so. The rings stay lines. If the world
-- GUI can't be made, the beams go back to the lines (noted once in the log)
do
  local G = { guis = {}, ids = {} }   -- per world: its GUI, and (retained GUI) the triangles drawn last frame
  laser.glow = G
  -- alpha, red, green, blue by the beam's color: the narrow core, the wide halo, the spot on the target
  local LOOK = {
    -- ((5.0) red firing, green held for a friendly, gray lost, amber locked on)
    [FIRE] = { core = { 210, 255, 110, 90 }, halo = { 55, 255, 40, 30 }, dot = { 230, 255, 170, 150 } },
    [FRIEND] = { core = { 210, 110, 255, 130 }, halo = { 55, 60, 255, 90 }, dot = { 230, 170, 255, 170 } },
    [LOST] = { core = { 160, 210, 210, 210 }, halo = { 40, 170, 170, 170 }, dot = { 180, 230, 230, 230 } },
    [LOCK] = { core = { 180, 255, 190, 70 }, halo = { 45, 255, 150, 20 }, dot = { 200, 255, 210, 120 } },
  }
  local WIDTH = { core = 0.006, halo = 0.03 }   -- half-widths in meters
  local FADE_TO, SPOT = 0.3, 0.03   -- alpha falls to this share at the far end; the spot's half-size
  -- ((5.1.4, players: "the performance is much worse") the pieces along each strip, each one a step of the fade: 4 for
  -- the faint halo and 6 for the core (10 each before, 86 triangles a beam; now 46, the same look in the preview)
  local PIECES = { halo = 4, core = 6 }
  local PARTS = { 'halo', 'core' }              -- (the core drawn last, on top)
  local LOOKS = {}
  for base, c in pairs(LOOK) do
    local S = { dot = c.dot }
    for _, part in ipairs(PARTS) do
      local steps = {}
      for k = 1, PIECES[part] do
        local f = 1 + (FADE_TO - 1) * (k - 0.5) / PIECES[part]
        steps[k] = { math.floor(c[part][1] * f + 0.5), c[part][2], c[part][3], c[part][4] }
      end
      S[part] = steps
    end
    LOOKS[base] = S
  end
  local LOOKS_INV = { [FIRE] = LOOKS[FRIEND], [FRIEND] = LOOKS[FIRE], [LOST] = LOOKS[LOST], [LOCK] = LOOKS[LOCK] }   -- ((5.1.0 Test 1) swapped)

  local function off(why)
    G.off = true
    note('laser: glow off, the beams are lines (' .. why .. ')'); event('laser: glow off: ' .. why)
  end
  -- whether this game build has what the glow needs (checked once; missing switches the glow off)
  local function usable()
    if G.usable == nil then
      local W, Gui, M = SR and SR.World, SR and SR.Gui, SR and SR.Matrix4x4
      G.usable = type(W) == 'table' and type(W.create_world_gui) == 'function' and type(Gui) == 'table'
        and type(Gui.triangle) == 'function' and type(M) == 'table' and type(M.identity) == 'function'
      if not G.usable then off('no world GUI in this game build') end
    end
    return G.usable
  end
  -- true when the beams are the glow's (chosen, and it works)
  G.on = function() return rawget(_G, 'SmarterGuardDogsGlow') == true and not G.off and usable() end
  -- ((5.0 Test 8) the markers are always the world GUI's when it works, Line or Glow)
  G.markers_ok = function() return not G.off and usable() end
  -- the marker's colors (alpha, red, green, blue): the weapon glyph solid, the sentry/backpack body see-through, the
  -- chevron as the glyph. Locked on: the game's ping yellow; lost: gray
  -- ((5.0 Test 8, my ask: "marker is pretty rough") a pale yellow weapon glyph on a deeper yellow body, both over a
  -- dark see-through edge so it reads on sky, snow or smoke)
  -- ((5.0 Test 14, my note: the markers "sometimes get really dark and hard to see") lighter all round: the dark edge at
  -- about half its strength (a thin shadow, not a dark plate), the body more solid, the target-lost gray near white;
  -- and the markers are no longer dimmed by Laser Brightness (they are their own option now)
  local MARK = {
    [LOCK] = { glyph = { 255, 255, 248, 170 }, body = { 225, 255, 214, 60 }, edge = { 85, 0, 0, 0 } },
    [LOST] = { glyph = { 255, 250, 250, 250 }, body = { 215, 214, 214, 214 }, edge = { 75, 0, 0, 0 } },
  }
  for _, M in pairs(MARK) do M.glyph.mark, M.body.mark, M.edge.mark = true, true, true end

  local sqrt = math.sqrt
  local function perp(dx, dy, dz)
    local ux, uy = -dy, dx
    local l = sqrt(ux * ux + uy * uy)
    if l < 1e-4 then ux, uy, l = 1, 0, 1 end
    ux, uy = ux / l, uy / l
    return ux, uy, 0, -dz * uy, dz * ux, dx * uy - dy * ux
  end
  local A3 = { {}, {}, {} }   -- (the spot's three axes, reused)

  -- this frame's glow in world w (inside laser_draw's protection; its own errors switch only the glow off)
  local function draw(w, beams)
    local Gui, V = SR.Gui, SR.Vector3
    local g = G.guis[w]
    if not g then
      local W, M = SR.World, SR.Matrix4x4
      local errs = {}
      for _, flags in ipairs({ { 'immediate' }, {} }) do
        local okc, r = pcall(W.create_world_gui, w, M.identity(), 1, 1, unpack(flags))
        if okc and r ~= nil then g, G.immediate = r, flags[1] == 'immediate'; break end
        errs[#errs + 1] = (flags[1] or 'no flags') .. ': ' .. tostring(r)
      end
      if not g then return off('create_world_gui failed: ' .. table.concat(errs, '; ')) end
      G.guis[w] = g   -- (a world that went away takes its GUI with it: never touched again)
      note('laser: glow on (' .. (G.immediate and 'immediate' or 'retained') .. ' world GUI)')
    end
    -- a retained GUI keeps what was drawn: last frame's pieces go first
    local ids = G.ids[w]
    if not G.immediate and ids and #ids > 0 then
      for _, id in ipairs(ids) do pcall(Gui.destroy_triangle, g, id) end
      ids = nil
    end
    if not G.immediate then ids = {}; G.ids[w] = ids end
    if #beams == 0 then return end
    local colours = {}
    local layered = G.layered
    local keep = ids
    local tri_fn = Gui.triangle
    local BR = laser.brightness()
    local OP = laser.marker_opacity()
    local function tri(p0, p1, p2, a)
      local c = colours[a]
      if not c and a.mark then c = SR.Color(math.floor(a[1] * OP + 0.5), a[2], a[3], a[4]); colours[a] = c end   -- (a marker: its own opacity, no brightness)
      if not c then
        -- (4.5.3 Test 11) brightness on the glow: its transparency alone hardly showed (a tester: the setting didn't
        -- change it - the core is nearly solid already), so dimmer also darkens its color and brighter whitens it
        -- toward its hottest; the strips are widened too (WIDTH below)
        local r, gg, bb = a[2], a[3], a[4]
        if BR < 1 then r, gg, bb = r * BR, gg * BR, bb * BR
        elseif BR > 1 then local w = math.min(0.6, (BR - 1) * 0.4); r, gg, bb = r + (255 - r) * w, gg + (255 - gg) * w, bb + (255 - bb) * w end
        c = SR.Color(math.min(255, math.floor(a[1] * BR + 0.5)), math.floor(r + 0.5), math.floor(gg + 0.5), math.floor(bb + 0.5)); colours[a] = c
      end
      local id
      if layered then id = tri_fn(g, p0, p1, p2, 1, c)
      elseif layered == false then id = tri_fn(g, p0, p1, p2, c)
      else
        -- (the first triangle: with the layer argument, or without it)
        local ok1, r1 = pcall(tri_fn, g, p0, p1, p2, 1, c)
        if ok1 then layered, id = true, r1
        else
          local ok2, r2 = pcall(tri_fn, g, p0, p1, p2, c)
          if not ok2 then error('Gui.triangle failed: ' .. tostring(r1) .. ' / without the layer: ' .. tostring(r2)) end
          layered, id = false, r2
        end
        G.layered = layered
      end
      if keep and id ~= nil then keep[#keep + 1] = id end
    end
    -- ((5.0 Test 8) the markers: each run of the icon a filled quad, upright, facing you; no gaps between the bands)
    local glow = G.on()
    -- ((5.0 Test 15) facing your eyes: a along your right, h along the marker's up, from the chevron's tip) ((5.0 release
    -- review) one function for every marker, reading the marker being drawn from these locals - not one made per marker)
    local x, y, z, rx, ry, ux, uy, uz
    local function P(a, h) return V(x + rx * a + ux * h, y + ry * a + uy * h, z + uz * h) end
    local PV = G.pv or {}; G.pv = PV   -- ((5.1.0 release review) a marker's corners, reused)
    for _, b in ipairs(beams) do
      local M = b.marker and not laser.walls and MARK[b.argb]   -- ((5.1.3) Behind walls: lines instead
      if M then
        local ic, sz, cw
        ic, x, y, z, rx, ry, sz, cw, ux, uy, uz = laser.marker_geom(b)
        local hb = sz / ic.rows * 0.5 + 0.0005   -- (half a band, a hair over so the bands meet)
        local base = cw + sz * 0.1
        local e = sz * 0.05                      -- (the dark edge's width)
        if ic.tg then
          -- ((5.1.0 Test 1) the traced shapes: edge, body, glyph; (release review) each corner placed once, PV reused)
          for pass = 1, 3 do
            local T = pass == 1 and ic.te or pass == 2 and ic.tb or ic.tg
            local col = pass == 1 and M.edge or pass == 2 and M.body or M.glyph
            local v, I = T.v, T.i
            for k = 1, #v, 2 do PV[(k + 1) / 2] = P(v[k] * sz, base + v[k + 1] * sz) end
            for k = 1, #I, 3 do tri(PV[I[k]], PV[I[k + 1]], PV[I[k + 2]], col) end
          end
        else
        for pass = 1, 3 do
          local L = pass == 1 and ic.sh or pass == 2 and ic.b or ic.g
          local col = pass == 1 and M.edge or pass == 2 and M.body or M.glyph
          local ex = pass == 1 and e or 0
          for k = 1, #L, 3 do
            local h, a, c = base + L[k] * sz, L[k + 1] * sz - ex, L[k + 2] * sz + ex
            local p1, p2 = P(a, h - hb - ex), P(c, h - hb - ex)
            local p3, p4 = P(c, h + hb + ex), P(a, h + hb + ex)
            tri(p1, p2, p3, col); tri(p1, p3, p4, col)
          end
        end
        end
        -- the chevron: two short bars meeting at the point
        for pass = 1, 2 do
          local tk = sz * 0.035 + (pass == 1 and e or 0)
          local col = pass == 1 and M.edge or M.glyph
          for side = -1, 1, 2 do
            local q1, q2 = P(cw * side, cw + tk), P(cw * side, cw - tk)
            local q3, q4 = P(0, -tk), P(0, tk)
            tri(q1, q2, q3, col); tri(q1, q3, q4, col)
          end
        end
      end
    end
    for _, b in ipairs(beams) do
      local S = glow and not b.marker and laser.styled(b) and (laser.inv and LOOKS_INV or LOOKS)[b.argb]
      local f, e = b.from, b.to
      local dx, dy, dz = e[1] - f[1], e[2] - f[2], e[3] - f[3]
      local len = S and sqrt(dx * dx + dy * dy + dz * dz) or 0
      if len >= 0.05 then
        dx, dy, dz = dx / len, dy / len, dz / len
        local ux, uy, uz, vx, vy, vz = perp(dx, dy, dz)
        for _, part in ipairs(PARTS) do
          local wd, steps = WIDTH[part] * (BR > 1 and 1 + (BR - 1) * 0.5 or 1), S[part]
          for pass = 1, 2 do   -- a strip lying level, then one standing up
            local ax, ay, az = ux * wd, uy * wd, uz * wd
            if pass == 2 then ax, ay, az = vx * wd, vy * wd, vz * wd end
            local pa, pb = V(f[1] + ax, f[2] + ay, f[3] + az), V(f[1] - ax, f[2] - ay, f[3] - az)
            local n = PIECES[part]
            for k = 1, n do
              local s = len * k / n
              local x, y, z = f[1] + dx * s, f[2] + dy * s, f[3] + dz * s
              local na, nb = V(x + ax, y + ay, z + az), V(x - ax, y - ay, z - az)
              local col = steps[k]
              tri(pa, na, nb, col); tri(pa, nb, pb, col)
              pa, pb = na, nb
            end
          end
        end
        if b.dot then
          -- a small bright spot just in front of the target: three crossed squares
          local back = math.min(0.3, len * 0.5)
          local qx, qy, qz = e[1] - dx * back, e[2] - dy * back, e[3] - dz * back
          A3[1][1], A3[1][2], A3[1][3] = dx * SPOT, dy * SPOT, dz * SPOT
          A3[2][1], A3[2][2], A3[2][3] = ux * SPOT, uy * SPOT, uz * SPOT
          A3[3][1], A3[3][2], A3[3][3] = vx * SPOT, vy * SPOT, vz * SPOT
          for i = 1, 3 do
            local p, q = A3[i], A3[i % 3 + 1]
            local c1 = V(qx - p[1] - q[1], qy - p[2] - q[2], qz - p[3] - q[3])
            local c2 = V(qx + p[1] - q[1], qy + p[2] - q[2], qz + p[3] - q[3])
            local c3 = V(qx + p[1] + q[1], qy + p[2] + q[2], qz + p[3] + q[3])
            local c4 = V(qx - p[1] + q[1], qy - p[2] + q[2], qz - p[3] + q[3])
            tri(c1, c2, c3, S.dot); tri(c1, c3, c4, S.dot)
          end
        end
      end
    end
  end
  -- redraw: a frame the mod skipped (idle sentries) - the last frame's beams again (an immediate GUI draws only what it
  -- is given each frame)
  -- ((4.6.4 review) a retained GUI keeps its last triangles: with the glow off they go now, not left on screen)
  G.clear = function()
    if G.immediate then return end
    for w, ids in pairs(G.ids) do
      local g = G.guis[w]
      if g then for _, id in ipairs(ids) do pcall(SR.Gui.destroy_triangle, g, id) end end
      G.ids[w] = {}
    end
  end
  G.draw = function(w, beams, redraw)
    -- ((5.0 Test 8) also with the Glow off when there are markers to draw)
    local any = G.on()
    if not any and G.markers_ok() then
      for _, b in ipairs(redraw and (G.last or beams) or beams) do if b.marker and not laser.walls then any = true; break end end
    end
    if not any then if next(G.ids) then G.clear() end; G.last = nil; return end
    -- (a retained GUI still holds the last frame's triangles: nothing to do on a redraw)
    if redraw and G.guis[w] and not G.immediate then return end
    if redraw then beams = G.last or beams else G.last = beams end
    local ok, err = pcall(draw, w, beams)
    if not ok then off(tostring(err)) end
  end
  -- ((5.1.5 Test 20) all calls into the game's GUI: not for the compiler, see engine_main.lua)
  local j = rawget(_G, 'jit')
  if type(j) == 'table' and type(j.off) == 'function' then pcall(j.off, draw, true) end
end

-- ------------------------------------------------------------------------------------------------------
-- Where the gun actually points. The drone's parts (body, yaw ring, pitch arm, gun mount) each have a
-- world pose right after the drone's own in the engine's pose array. While the dog fires at an enemy
-- in plain view, every part's axes are scored against the direction to that enemy; the part and axis
-- that track it best is the barrel. From then on the laser follows the barrel, so it ends exactly where
-- the gun is aimed, and falls back to "drone to enemy" until then or if the barrel can't be read.
-- ------------------------------------------------------------------------------------------------------
-- min_cos: how closely a part must track the enemy to count as the barrel (0.997 = within ~4 degrees on
-- average); keep_cos: below this, while firing at an enemy in plain view, the part is dropped and the search
-- starts again; off: the laser end may sit at most this far (meters, or this share of the distance) from the
-- enemy, otherwise it falls back to pointing straight at it
local GUN = { nodes = 40, reach = 2.5, frames = 24, min_cos = 0.997, keep_cos = 0.985, min_range = 8, off = 1.5, off_share = 0.06,
  fire_cos = 0.95, fire_keep = 0.9, tries = 6 }
-- (4.5.3 Test 9) fire_cos / fire_keep: on the game's own fire node (the muzzle) only its three axes are tried, so a
-- barrel that lags its aim a little still counts; the wrong axes point well away
local gun = {}     -- per dog name: { sums = {}, n = 0, node, axis, sign, tries }

local function parse_node(m, o, root)
  local x, y, z = f32(m, o + 48), f32(m, o + 52), f32(m, o + 56)
  if not (x == x and y == y and z == z and (x - root[1]) ^ 2 + (y - root[2]) ^ 2 + (z - root[3]) ^ 2 < GUN.reach ^ 2) then return nil end
  local axes = {}
  for r = 0, 2 do
    local a = { f32(m, o + r * 16), f32(m, o + r * 16 + 4), f32(m, o + r * 16 + 8) }
    local len = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    if not (len > 0.5 and len < 2) then return nil end
    axes[r + 1] = { a[1] / len, a[2] / len, a[3] / len }
  end
  return { pos = { x, y, z }, axes = axes }
end

-- every part's pose while learning which one is the barrel; afterwards just the barrel's (one small read)
local function read_nodes(pose, root, only)
  if only then
    local m = read(pose + 64 * only, 64)
    local nd = m and parse_node(m, 0, root)
    return nd and { [only] = nd } or nil
  end
  local n, m = GUN.nodes, nil
  while n >= 8 and not m do m = read(pose, 64 * n); if not m then n = n - 8 end end
  if not m then return nil end
  local nodes = {}
  for i = 0, n - 1 do nodes[i] = parse_node(m, 64 * i, root) end
  return nodes
end

local function gun_learn(g, nodes, aim)
  for i, nd in pairs(nodes) do
    local v = { aim[1] - nd.pos[1], aim[2] - nd.pos[2], aim[3] - nd.pos[3] }
    local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    for r = 1, 3 do
      local a = nd.axes[r]
      local cos = (a[1] * v[1] + a[2] * v[2] + a[3] * v[3]) / len
      local k = i * 6 + (r - 1) * 2
      g.sums[k] = (g.sums[k] or 0) + cos
      g.sums[k + 1] = (g.sums[k + 1] or 0) - cos
    end
  end
  g.n = g.n + 1
  if g.n < GUN.frames then return end
  local best, bk
  for k, sum in pairs(g.sums) do if not best or sum > best then best, bk = sum, k end end
  g.tries = (g.tries or 0) + 1
  if not best then
    if g.tries <= 3 then note('laser: no barrel found for ' .. g.name .. ' yet (no readable parts)') end
    g.sums, g.n = {}, 0
    return
  end
  local mean = best / g.n
  if mean >= (g.fire and GUN.fire_cos or GUN.min_cos) then
    g.node, g.axis, g.sign = math.floor(bk / 6), math.floor((bk % 6) / 2) + 1, bk % 2 == 0 and 1 or -1
    note(string.format('laser: barrel found for %s (part %d, axis %d%s, match %.3f)', g.name, g.node, g.axis, g.sign > 0 and '+' or '-', mean))
    event('laser: following the barrel of the ' .. g.name)
  elseif g.tries <= 3 then
    note(string.format('laser: no barrel found for %s yet (best match %.3f)', g.name, mean))
  end
  g.sums, g.n = {}, 0
end

-- (4.5.3 Test 12) from the muzzle toward the game's own aim point when it is near the enemy (as far as the enemy),
-- else straight at the enemy: the Rover's and K-9's beam, and anyone's until its barrel axis is known. (On the laser
-- table, built once: 4.6.0 review)
laser.straight = function(st, to, from)
  local A = st.aim
  if A and A[1] == A[1] and (A[1] - to[1]) ^ 2 + (A[2] - to[2]) ^ 2 + (A[3] - to[3]) ^ 2 < 9 then
    local ax, ay, az = A[1] - from[1], A[2] - from[2], A[3] - from[3]
    local al = math.sqrt(ax * ax + ay * ay + az * az)
    local tl = math.sqrt((to[1] - from[1]) ^ 2 + (to[2] - from[2]) ^ 2 + (to[3] - from[3]) ^ 2)
    if al > 0.5 then return { from[1] + ax / al * tl, from[2] + ay / al * tl, from[3] + az / al * tl }, from, true end
  end
  return to, from, true
end

-- the point the barrel is aimed at, level with the enemy (nil if unknown); also where the beam starts and whether
-- its end is on the enemy (for the cross)
local function gun_point(st, to, learn)
  local D = st.drone_pos
  if not (D and D.pose) then return nil end
  local g = gun[st.dog.name]
  if not g then g = { name = st.dog.name, sums = {}, n = 0 }; gun[st.dog.name] = g end
  -- (4.5.3 Test 9) the game's own fire node (the muzzle) when its weapon record was found: the beam starts there,
  -- along the barrel once its axis is known and straight at the enemy until then. Otherwise the barrel part is
  -- guessed from all the drone's parts, as before
  local fn = st.fire_node
  if fn ~= g.fire then g.fire, g.node, g.sums, g.n, g.tries, g.check, g.check_n = fn, nil, {}, 0, 0, 0, 0 end
  local nd
  local straight = laser.straight
  if fn then
    local nodes = read_nodes(st.fire_pose or D.pose, D, fn)
    nd = nodes and nodes[fn]
    if not nd then return nil end
    -- ((5.0 Test 5) a dog with a set barrel axis (the Rover, the K-9): its muzzle part's axis, followed as it is - the beam
    -- goes where the gun points, as a laser mounted on it would, sweeping with it)
    local B = st.dog.barrel
    if B then
      local a = nd.axes and nd.axes[B[1]]
      if not a then return straight(st, to, nd.pos) end
      local dir = { a[1] * B[2], a[2] * B[2], a[3] * B[2] }
      local v = { to[1] - nd.pos[1], to[2] - nd.pos[2], to[3] - nd.pos[3] }
      local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
      -- ((5.0 Test 7, my ask: "like a fixed laser") along the barrel however far off the enemy it points - before, a
      -- barrel more than 60 degrees off fell back to pointing at the enemy)
      if len < 1 then return straight(st, to, nd.pos) end
      -- ((5.0 Test 9) as far as the point on the barrel's line nearest the enemy, and into it: the beam meets the
      -- enemy's body instead of stopping in front of it)
      local sp = v[1] * dir[1] + v[2] * dir[2] + v[3] * dir[3]
      if sp > 1 then len = sp + laser.INTO end
      local p = { nd.pos[1] + dir[1] * len, nd.pos[2] + dir[2] * len, nd.pos[3] + dir[3] * len }
      local off = math.sqrt((p[1] - to[1]) ^ 2 + (p[2] - to[2]) ^ 2 + (p[3] - to[3]) ^ 2)
      return p, nd.pos, off <= math.max(GUN.off, GUN.off_share * len), true
    end
    if not g.node then
      if learn and (g.tries or 0) < GUN.tries then gun_learn(g, nodes, to) end
      if g.node ~= fn then g.node = nil; return straight(st, to, nd.pos) end
    end
  else
    if not g.node and (g.tries or 0) >= GUN.tries then return nil end
    local nodes = read_nodes(D.pose, D, g.node)
    if not nodes then return nil end
    if not g.node then
      if learn then gun_learn(g, nodes, to) end
      return nil
    end
    nd = nodes[g.node]
    if not nd then return nil end
  end
  local a = nd.axes[g.axis]
  local dir = { a[1] * g.sign, a[2] * g.sign, a[3] * g.sign }
  local v = { to[1] - nd.pos[1], to[2] - nd.pos[2], to[3] - nd.pos[3] }
  local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  local s = v[1] * dir[1] + v[2] * dir[2] + v[3] * dir[3]
  if learn and len > 0 then
    -- keep checking the choice while the dog fires at enemies in plain view; a part that only roughly
    -- follows the aim (a body or mount rather than the barrel) is dropped and the search starts over
    g.check, g.check_n = (g.check or 0) + s / len, (g.check_n or 0) + 1
    if g.check_n >= GUN.frames then
      local mean = g.check / g.check_n
      g.check, g.check_n = 0, 0
      if mean < (g.fire and GUN.fire_keep or GUN.keep_cos) then
        note(string.format('laser: part %d of the %s stopped matching its aim (%.3f), looking again', g.node, g.name, mean))
        g.node = nil
        if g.fire then return straight(st, to, nd.pos) end
        return nil
      end
    end
  end
  -- ((5.0 Test 7) a barrel turned well away still carries its laser; only one pointing back behind the drone doesn't)
  if s < -0.5 * len then
    if g.fire then return straight(st, to, nd.pos) end
    return nil
  end
  -- (4.5.3, a tester's call: the laser comes out of the barrel and runs along it, as far as the enemy, wherever the
  -- barrel points; before, it fell back to pointing at the enemy when the barrel was off. Also returned: where the
  -- beam starts (the barrel part) and whether its end is on the enemy, for the cross)
  if s > 1 then len = s + laser.INTO end   -- ((5.0 Test 9) into the enemy, as above)
  local p = { nd.pos[1] + dir[1] * len, nd.pos[2] + dir[2] * len, nd.pos[3] + dir[3] * len }
  local off = math.sqrt((p[1] - to[1]) ^ 2 + (p[2] - to[2]) ^ 2 + (p[3] - to[3]) ^ 2)
  return p, nd.pos, off <= math.max(GUN.off, GUN.off_share * len) + laser.INTO, true
end

-- what to show for this frame
local DOCKED = 1.2   -- meters (level) between the drone and you: it has flown back to the backpack to reload

-- adds the dog's beam (if any) to 'beams'; the main loop draws the dog's and the sentries' beams together
local function laser_frame(st, beams, safety_t, safety_enemy, safety_step, cover_t, cover_enemy, cover_step)
  local D = st.drone_pos
  if not D then return end
  -- no laser at all while the drone sits on your back reloading
  local me = st.player_pos
  if me and (D[1] - me[1]) ^ 2 + (D[2] - me[2]) ^ 2 < DOCKED ^ 2 then return end
  -- (an enemy by id, looked up only when a beam is drawn)
  local function by_id(id) for _, c in ipairs(st.candidates) do if c.id == id then return c end end end
  -- ((5.0 Test 9) its aim spot where the enemy is drawn this frame)
  local function spot(c) local p = laser.live(c); return { p[1], p[2], p[3] + (st.dog.aim_rise or AIM_RISE) } end
  local t = os.clock()
  -- the beam leaves its barrel when that is known (from: the barrel part; on: its end is on the enemy, for the cross),
  -- otherwise the front of the drone, facing whatever it points at
  local function beam(to, argb, from, on, at, fixed)
    -- (4.6.7 Test 1) the firing beam's end is smoothed over about a tenth of a second, so the game's aim point
    -- wandering over the enemy doesn't shake it; a new target (or a gap) starts it afresh. What is smoothed is where
    -- the end sits on the enemy (at: the enemy's aim spot), so it never trails behind a running enemy. The start
    -- stays on the muzzle, so the beam never leaves the drone
    -- ((4.6.7 review) the offset kept as plain numbers - no tables a frame but the smoothed end - and skipped with no
    -- aim spot: smoothed in world space instead, the end would trail a running enemy)
    if (argb == FIRE or argb == LOCK) and at and not fixed then
      local B = laser.dog_beam
      local raw = to
      local ox, oy, oz = raw[1] - at[1], raw[2] - at[2], raw[3] - at[3]
      if B.ox and B.dog == st.dog.name and B.target == st.target and t - B.t < 0.25 then
        local k = laser.dog_smooth > 0 and 1 - math.exp(-(t - B.t) / laser.dog_smooth) or 1
        ox, oy, oz = B.ox + (ox - B.ox) * k, B.oy + (oy - B.oy) * k, B.oz + (oz - B.oz) * k
        to = { at[1] + ox, at[2] + oy, at[3] + oz }
        -- (Tester: how much the end moves a frame before and after, and the start; one line per dog every 200 frames,
        -- up to 6 a session)
        if TESTER and B.raw and B.from and from then
          local L = laser.steady or {}
          laser.steady = L
          local S = L[st.dog.name] or { n = 0, raw = 0, out = 0, from = 0, logged = 0 }
          L[st.dog.name] = S
          local dr = math.sqrt((raw[1] - B.raw[1]) ^ 2 + (raw[2] - B.raw[2]) ^ 2 + (raw[3] - B.raw[3]) ^ 2)
          local d1 = math.sqrt((to[1] - B.to[1]) ^ 2 + (to[2] - B.to[2]) ^ 2 + (to[3] - B.to[3]) ^ 2)
          local df = math.sqrt((from[1] - B.from[1]) ^ 2 + (from[2] - B.from[2]) ^ 2 + (from[3] - B.from[3]) ^ 2)
          if dr < 3 and df < 1 then S.n, S.raw, S.out, S.from = S.n + 1, S.raw + dr, S.out + d1, S.from + df end
          if S.n >= 200 and S.logged < 6 then
            S.logged = S.logged + 1
            event(string.format('laser steadiness (test): %s beam end moved %.1f cm a frame before smoothing, %.1f cm after; its start %.1f cm (%d frames)',
              st.dog.name, 100 * S.raw / S.n, 100 * S.out / S.n, 100 * S.from / S.n, S.n))
            S.n, S.raw, S.out, S.from = 0, 0, 0, 0
          end
        end
      end
      B.ox, B.oy, B.oz, B.dog, B.target, B.t = ox, oy, oz, st.dog.name, st.target, t
      if TESTER then B.to, B.raw, B.from = to, raw, from end   -- (the steadiness stat's only)
    end
    -- ((5.0 Test 7) a beam fixed on the barrel: its direction lightly smoothed (half the last frame's), as the sentries',
    -- so the muzzle part's shake doesn't shake it; it still turns with the gun)
    if fixed and from then
      local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
      local len = math.sqrt(dx * dx + dy * dy + dz * dz)
      local P = laser.dog_dir
      if len > 0.1 then
        dx, dy, dz = dx / len, dy / len, dz / len
        if P and P.dog == st.dog.name and t - P.t < 0.25 then
          local x, y, z = P[1] + dx, P[2] + dy, P[3] + dz
          local l = math.sqrt(x * x + y * y + z * z)
          if l > 1e-3 then dx, dy, dz = x / l, y / l, z / l end
        end
        laser.dog_dir = { dx, dy, dz, dog = st.dog.name, t = t }
        to = { from[1] + dx * len, from[2] + dy * len, from[3] + dz * len }
      end
    end
    -- ((5.0) the firing and locked-on beams are the dog's ('key'), on its target ('tg'): a new target swings the end over)
    local mine = argb == FIRE or argb == LOCK
    if from then
      beams[#beams + 1] = { from = from, to = to, argb = argb, dot = mine and on ~= false, key = mine and 'dog' or nil, tg = st.target, fixed = fixed }
      return
    end
    local dx, dy, dz = to[1] - D[1], to[2] - D[2], to[3] - (D[3] + LASER_RISE)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < LASER_FORWARD + 0.5 then return end
    local k = LASER_FORWARD / len
    -- (a dot where it hits: only on the enemy it is firing at)
    beams[#beams + 1] = { from = { D[1] + dx * k, D[2] + dy * k, D[3] + LASER_RISE + dz * k }, to = to, argb = argb, dot = mine, key = mine and 'dog' or nil, tg = st.target }
  end
  -- ((5.0 Test 5) locked on / target lost: a marker over the enemy, no beam)
  -- ((5.0 Test 10, my note: no marker "unless it can actually harm them... if it is outside of their range" - the Guard
  -- Dog marked bots at 35-40 m it never fired at) only on an enemy within the dog's range that it can hurt
  local function can_mark(c)
    local r = st.dog.range
    if r and not (c.d2 and c.d2 <= r * r) then return false end
    return not (laser.cannot_hurt and laser.cannot_hurt(st.dog, c, st.drone_pos, st.dog.name, c.id == st.target and st.aim or nil))
  end
  local function mark(to, argb, c)
    if c and not can_mark(c) then return end
    -- ((5.0 release review) grouped by the enemy it is over: a lost marker is over the old enemy, not the dog's new target)
    beams[#beams + 1] = { from = to, to = to, argb = argb, marker = true, key = argb == LOCK and 'mdog' or nil, tg = c and c.id or st.target,
      icon = st.dog and st.dog.name }
  end
  -- red only for a shot the safety actually stopped (it stepped in while the dog was lining up or firing),
  -- and not once the dog has gone on to something else such as reloading
  local warn = safety_t and t - safety_t < RED_SECONDS and ATTACK_STEPS[safety_step]
    and (ATTACK_STEPS[st.node] or st.target == 0)
  if warn then
    -- ((5.0 Test 7, my ask: "the color of the laser will change to green if a safety stops it") its laser, along the
    -- barrel, turned green. ((5.0 Test 20, my ask: "the safety laser should still flash green, not solid green") flashing)
    local e = by_id(safety_enemy)
    local lit = math.floor(t * FLASH_HZ * 2) % 2 == 0   -- ((5.0 release review) an even blink: safety_t is renewed with each hold)
    if e and e.pos and lit then
      local to = spot(e)
      local gp, gfrom, _, along = gun_point(st, to, false)
      gp = laser.fit_end(gp, e)
      beam(gp or to, FRIEND, gp and gfrom, nil, nil, along)
    end
  elseif cover_t and t - cover_t < RED_SECONDS and ATTACK_STEPS[cover_step] and (ATTACK_STEPS[st.node] or st.target == 0)
    and st.target ~= cover_enemy then
    -- flashing yellow toward the enemy it just stopped shooting at because it dropped out of sight (behind cover
    -- or in smoke: the game doesn't tell the two apart), until the dog is busy with its next target. (4.0.6 Test 6
    -- tried flashing green: it blended in with the firing beam, a tester's call)
    local e = by_id(cover_enemy)
    local on = math.floor((t - cover_t) * FLASH_HZ * 2) % 2 == 0
    -- (4.5.3 Test 9: these leave the barrel too)
    if e and e.pos and on and st.node ~= FIRE_STEP then
      mark(spot(e), LOST, e)
    end
    if st.target ~= 0 and st.node == FIRE_STEP then
      local e2 = by_id(st.target)
      if e2 and e2.pos then
        local to = spot(e2)
        local gp, gfrom, gon, along = gun_point(st, to, false)
        gp = laser.fit_end(gp, e2)
        beam(gp or to, FIRE, gp and gfrom, gon, to, along)
      end
    end
  elseif st.target ~= 0 and st.node == FIRE_STEP then   -- green only while it is actually firing
    local e = by_id(st.target)
    if e and e.pos then
      local to = spot(e)
      local far = e.d2 and e.d2 > GUN.min_range ^ 2
      local gp, gfrom, gon, along = gun_point(st, to, e.visible and far)
      gp = laser.fit_end(gp, e)
      laser.last_gun, laser.last_to = gp, to     -- (the research log compares the two)
      -- (4.5.3 Test 12, test builds) how far the beam points from where the game aims the gun (its targeting state's
      -- aim point): the angle between the two from the muzzle, and how far apart they pass at the aim point. Logged
      -- every 40 samples, up to 8 times a session
      local A = st.aim
      if TESTER and gp and gfrom and A and A[1] == A[1] then
        local bx, by, bz = gp[1] - gfrom[1], gp[2] - gfrom[2], gp[3] - gfrom[3]
        local ax, ay, az = A[1] - gfrom[1], A[2] - gfrom[2], A[3] - gfrom[3]
        local bl, al = math.sqrt(bx * bx + by * by + bz * bz), math.sqrt(ax * ax + ay * ay + az * az)
        if bl > 1 and al > 1 and al < 200 then
          local cos = math.max(-1, math.min(1, (bx * ax + by * ay + bz * az) / (bl * al)))
          local deg = math.deg(math.acos(cos))
          -- (per dog: 4.5.3 Test 18 - one dog used up the eight lines in a tester's Test 17 log)
          laser.align = laser.align or {}
          local L = laser.align[st.dog.name] or { n = 0, sum = 0, max = 0, gap = 0, logged = 0 }
          laser.align[st.dog.name] = L
          L.n, L.sum, L.max, L.gap = L.n + 1, L.sum + deg, math.max(L.max, deg), L.gap + al * math.sin(math.rad(deg))
          if L.n >= 40 and L.logged < 8 then
            L.logged = L.logged + 1
            event(string.format('laser alignment (test): %s beam vs the game\'s aim: %.2f degrees on average (most %.2f), %.2f m apart at the aim point, over %d samples',
              st.dog.name, L.sum / L.n, L.max, L.gap / L.n, L.n))
            L.n, L.sum, L.max, L.gap = 0, 0, 0, 0
          end
        end
      end
      beam(gp or to, FIRE, gp and gfrom, gon, to, along)
    end
  end
  -- ((5.0 Test 17, my ask: "Guard dog marker seems a little inconsistent") its icon over its target the whole time it has
  -- one - lining up, firing, held by the safety, moving to a better spot, after a target went out of sight - like the
  -- sentries' (before, only while lining up or firing: the icon blinked out whenever the dog did anything else)
  local Dp, Pp = st.drone_pos, st.player_pos
  local docked = Dp and Pp and ((Dp[1] - Pp[1]) ^ 2 + (Dp[2] - Pp[2]) ^ 2) < 1.2 ^ 2   -- (on your back, reloading)
  laser.dog_target = st.target ~= 0 and not docked   -- (the test builds' marker count)
  -- ((5.1.0 Test 1, my ask: "the marker with the guard dog rover and guard dog would constantly flick around to
  -- enemies it cant reach still") not over a target the mod is hiding from it this frame (out of range, a friendly in
  -- the way, out of sight, no shot, armor it can't hurt): the game kept picking those and the mod kept taking them away,
  -- so the icon jumped between them. And only once it has kept the same target for MARK_SETTLE seconds
  if st.target ~= laser.dog_mark_tg then laser.dog_mark_tg, laser.dog_mark_t = st.target, t end
  local H = st.hidden
  if st.target ~= 0 and not docked and not (H and H[st.target]) and t - laser.dog_mark_t >= laser.MARK_SETTLE then
    local e = by_id(st.target)
    if e and e.pos then mark(spot(e), LOCK, e) end
  end
end

-- ======================================================================================================
-- Research recorder (1.5 test builds): writes SmarterGuardDogsAndSentries-research.log next to the
-- status log (%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs) with what the
-- dog targets, each enemy's unit type and the raw fields of its perception entry, so line-of-sight and
-- armor rules can be worked out from real missions. Reads only. Press F8 in game to drop a marker line
-- ("MARK") at a moment worth looking at, e.g. the dog shooting through a wall or at a Hulk.
-- ======================================================================================================
local RESEARCH = false
local hexr, check_marker, research_frame, research_close
-- (its helpers live inside a function of their own, to leave room among the main chunk's locals)
;(function()
local RESEARCH_MAX_BYTES = 4 * 1024 * 1024
local SAMPLE_SECONDS = 0.25     -- the dog's current target while it is lining up or firing
local LIST_SECONDS = 2.0        -- the whole enemy list
local research = { f = nil, bytes = 0, full = false, types = {}, next_sample = 0, next_list = 0, t0 = os.clock(),
  last_target = nil, key = nil, key_down = false, key_state = 'not checked', marks = 0 }

local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
local function type_of(c)
  -- entity rows start with the unit type hash (stored byte-reversed); shown the way Filediver names units
  return c.ent and hex(c.ent:sub(1, 8):reverse()) or '-'
end

local function rwrite(line)
  if not RESEARCH or research.full or not LOGDIR then return end
  if not research.f then
    research.f = io.open(LOGDIR .. '\\SmarterGuardDogsAndSentries-research.log', 'w')
    if not research.f then research.full = true; return end
    research.f:write('Smarter Guard Dogs & Sentries ' .. VERSION .. ' research log. t = seconds since start. F8 = MARK.\n')
    research.f:write('S = sample of the dog\'s target: t dog step target type group flags score dist_dog dist_you synced raw16_67 dock(drone to you, level m) barrel_off(up, sideways m)\n')
    research.f:write('L = enemy list: t dog [id:type:group:flags:score:dist_you:eligible:alive:visible:memory:hidden ...]\n')
    research.f:write('V = line of sight changed: t dog id type now_visible hidden_by_us\n')
  end
  research.bytes = research.bytes + #line + 1
  if research.bytes > RESEARCH_MAX_BYTES then
    research.f:write('-- size limit reached, recording stopped --\n'); research.f:close(); research.f = nil; research.full = true
    return
  end
  research.f:write(line, '\n')
end

-- F8 marker (only if the engine's keyboard functions are available): notes in the status log what the dog is
-- aiming at right now and which enemy types are around, so a player can point out an enemy for a bug report
-- ((5.1.5 Test 19) remembered per string, and no new function each time: the logs ask for the same few enemy types
-- over and over, and making a function per call stopped LuaJIT compiling every path that named an enemy)
do
  local HEXR, n = {}, 0
  local function hexr_byte(c) return string.format('%02x', c:byte()) end
  function hexr(s)
    local h = HEXR[s]
    if h then return h end
    h = (s:reverse():gsub('.', hexr_byte))
    if n < 2000 then HEXR[s], n = h, n + 1 end
    return h
  end
end

-- ((5.1.5 Test 19, test builds) where LuaJIT gives up compiling this mod's code: every trace started in this file,
-- counted by the line it started on - compiled or given up, and why. The summary lists the lines that keep failing
-- (the loader's log only names the file). Trace events are rare once the game is warmed up; the counting is a few
-- table updates per event
if TESTER then
  pcall(function()
    local jit_ = rawget(_G, 'jit') or require('jit')
    local util = require('jit.util')
    local okv, vmdef = pcall(require, 'jit.vmdef')
    local own = debug.getinfo(1, 'S').source
    local J = { ok = {}, bad = {}, why = {}, starts = 0, aborts = 0, stops = 0, flushes = 0 }
    session.jitw = J
    local start_line, events, watcher = nil, 0, nil
    -- ((5.1.5 Test 20) it lets go after 3,000 trace events - plenty for the list, and then nothing of mine sits in
    -- the compiler's way: the loader keeps its own watcher on it)
    watcher = function(what, tr, func, pc, otr, oex)
      events = events + 1
      if events >= 3000 then J.stopped = true; pcall(jit_.attach, watcher); return end
      if what == 'flush' then J.flushes = J.flushes + 1; return end
      if what == 'start' then
        local fi = util.funcinfo(func, pc)
        start_line = (fi and fi.source == own) and fi.currentline or nil
        if start_line then J.starts = J.starts + 1 end
        return
      end
      if not start_line then return end
      if what == 'stop' then J.stops = J.stops + 1; J.ok[start_line] = (J.ok[start_line] or 0) + 1
      elseif what == 'abort' then
        J.aborts = J.aborts + 1
        J.bad[start_line] = (J.bad[start_line] or 0) + 1
        if not J.why[start_line] then
          local msg = otr
          if type(otr) == 'number' and okv and vmdef.traceerr[otr] then
            local info = oex
            if type(info) == 'function' then local f2 = util.funcinfo(info); info = f2 and (f2.source .. ':' .. (f2.linedefined or 0)) or '?' end
            local fmt = vmdef.traceerr[otr]
            if fmt == 'NYI: bytecode %s' and type(oex) == 'number' then info = vmdef.bcnames:sub(6 * oex + 1, 6 * oex + 6) end
            local okf, m = pcall(string.format, fmt, info)
            msg = okf and m or fmt
          end
          local fe = util.funcinfo(func, pc)
          J.why[start_line] = tostring(msg) .. ((fe and fe.source == own) and (' at line ' .. (fe.currentline or 0)) or '')
        end
      end
    end
    jit_.attach(watcher, 'trace')
  end)
end
function check_marker(st)
  local KB = SR and SR.Keyboard
  if research.key == nil then
    research.key = false
    if type(KB) == 'table' and type(KB.button_index) == 'function' and type(KB.pressed) == 'function' then
      local ok, idx = pcall(KB.button_index, 'f8')
      if ok and idx then research.key = idx; research.key_state = 'F8 marker ready' else research.key_state = 'F8 marker unavailable' end
    else
      research.key_state = 'F8 marker unavailable (no keyboard functions)'
    end
    note(research.key_state)
  end
  if not research.key then return end
  local ok, down = pcall(KB.pressed, research.key)
  if not (ok and down) then return end
  research.marks = research.marks + 1
  rwrite(string.format('MARK %d at %.2f', research.marks, os.clock() - research.t0))
  local cur, near = nil, {}
  local me = st and st.player_pos
  for _, c in ipairs(st and st.candidates or {}) do
    if c.id == st.target then cur = c end
    if c.kind and c.alive and c.pos and me and (c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 < 60 ^ 2 then
      local k = hexr(c.kind) .. (LABELS[c.kind] and ('(' .. LABELS[c.kind] .. ')') or ''); near[k] = (near[k] or 0) + 1
    end
  end
  local list = {}
  for k, n in pairs(near) do list[#list + 1] = k .. 'x' .. n end
  table.sort(list)
  local msg = string.format('%8.1fs  marker %d: %s', os.clock() - T0, research.marks, st and st.dog.name or ('no dog out (' .. tostring(SGD.status) .. ')'))
  if cur and cur.kind then
    msg = msg .. string.format(' aiming at type %s%s (%.0f m, AI step %d)', hexr(cur.kind), LABELS[cur.kind] and (' ' .. LABELS[cur.kind]) or '', cur.d2 and math.sqrt(cur.d2) or -1, st.node)
  else msg = msg .. ' not aiming at anything' end
  msg = msg .. '; enemies within 60 m: ' .. (#list > 0 and table.concat(list, ' ') or 'none')
  -- details (test builds): what the dog is doing, then each enemy near you, nearest first
  if st then
    local D = st.drone_pos
    msg = msg .. string.format('\n      dog: AI step %d, target %d for %.1fs, lined up %.1fs on it without firing, timer %.2fs, %.1f m from you (level)',
      st.node, st.target, st.target_for or 0, st.lineup_acc or 0, math.max(0, (st.deadline or 0) - (st.now or 0)) / 1e6,
      (me and D) and math.sqrt((D[1] - me[1]) ^ 2 + (D[2] - me[2]) ^ 2) or -1)
    -- ((5.1.5 Test 5) its target's health as the game holds it)
    if st.target ~= 0 then
      local hp, mx = HEALTH.of(st.target)
      msg = msg .. (hp and string.format(', target health %d of %d%s', hp, mx, HEALTH.proven and '' or ' (damage check not armed yet)') or ', target health record not found')
    end
    local tm = {}
    for _, m in ipairs(st.mates or {}) do
      tm[#tm + 1] = me and string.format('%.1f m', math.sqrt((m[1] - me[1]) ^ 2 + (m[2] - me[2]) ^ 2 + (m[3] - me[3]) ^ 2)) or '?'
    end
    msg = msg .. string.format('\n      teammates: %d%s', #tm, #tm > 0 and (' (' .. table.concat(tm, ', ') .. ' from you)') or '')
    if #team.rows > 0 then msg = msg .. '\n      teammate rows: ' .. team_detail(me) end
    msg = msg .. '\n      id type             from you  height  from dog  sight memory  score pickable  hidden by the mod'
    local rows = {}
    for _, c in ipairs(st.candidates or {}) do
      if c.pos and me then
        local dz = c.pos[3] - me[3]
        local d = math.sqrt((c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + dz ^ 2)
        if d < 60 then rows[#rows + 1] = { c = c, d = d, dz = dz } end
      end
    end
    table.sort(rows, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#rows, 16) do
      local c, why = rows[i].c, {}
      for _, k in ipairs({ 'unsafe', 'cover', 'armor', 'range', 'no_shot', 'closer_threat', 'focus' }) do
        if st.hide_sets and st.hide_sets[k] and st.hide_sets[k][c.id] then
          why[#why + 1] = (k == 'unsafe' and st.unsafe_why and (st.unsafe_why[c.id] or ''):find('teammate')) and 'unsafe(teammate)' or k
        end
      end
      if #why == 0 and c.mask == '    ' then why[1] = 'held' end
      msg = msg .. string.format('\n      %d %s %5.1f m %+6.1f m %6.1f m  %-5s %5.2f %6.2f %-8s  %s%s', c.id, c.kind and hexr(c.kind) or '-',
        rows[i].d, rows[i].dz, c.d2 and math.sqrt(c.d2) or -1, c.visible and 'yes' or 'no', c.memory or -1, c.score or -1,
        c.eligible and 'yes' or (c.alive and 'no' or 'dead'), #why > 0 and table.concat(why, ',') or '-', (c.kind and LABELS[c.kind] and ('  ' .. LABELS[c.kind]) or '') .. (c.id == st.target and '  <- target' or ''))
    end
    if #rows > 16 then msg = msg .. string.format('\n      (+%d more)', #rows - 16) end
  end
  -- (4.0) what each of your sentries is doing
  if sentry_marker_text then
    local ok, lines = pcall(sentry_marker_text, me)
    if ok and lines and #lines > 0 then msg = msg .. '\n      sentry ' .. table.concat(lines, '\n      sentry ') end
  end
  local m = session.markers
  m[#m + 1] = msg
  if #m > 30 then table.remove(m, 1) end
  event('F8 marker ' .. research.marks)
end

local function dist(a, b)
  if not (a and b) then return -1 end
  return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

function research_frame(st)
  if not RESEARCH or research.full then return end
  local t = os.clock()
  local me, D = st.player_pos, st.drone_pos
  for _, c in ipairs(st.candidates) do
    local ty = type_of(c)
    if ty ~= '-' and not research.types[ty] then
      research.types[ty] = true
      rwrite(string.format('T %.2f new unit type %s (first seen as %d, group %s)', t - research.t0, ty, c.id, c.group or '?'))
    end
  end
  research.vis = research.vis or {}
  local seen = {}
  for _, c in ipairs(st.candidates) do
    seen[c.id] = true
    local was = research.vis[c.id]
    if was ~= nil and was ~= c.visible then
      rwrite(string.format('V %.2f %s %d %s %d %d', t - research.t0, st.dog.name, c.id, type_of(c), c.visible and 1 or 0, c.mask == '    ' and 1 or 0))
    end
    research.vis[c.id] = c.visible
  end
  for id in pairs(research.vis) do if not seen[id] then research.vis[id] = nil end end
  local cur
  for _, c in ipairs(st.candidates) do if c.id == st.target then cur = c end end
  if st.target ~= research.last_target then
    research.last_target = st.target
    rwrite(string.format('C %.2f %s target -> %d type %s step %d', t - research.t0, st.dog.name, st.target, cur and type_of(cur) or '-', st.node))
  end
  if t >= research.next_sample and st.target ~= 0 and (st.node == 6 or st.node == 7) then
    research.next_sample = t + SAMPLE_SECONDS
    if cur then
      rwrite(string.format('S %.2f %s %d %d %s %s %08x %.3f %.1f %.1f %s %s', t - research.t0, st.dog.name, st.node, st.target,
        type_of(cur), cur.group or '?', cur.flags or 0, cur.score or 0, dist(cur.pos, D), dist(cur.pos, me),
        st.synced and 1 or 0, hex(read(cur.entry + 16, 52) or '')) .. string.format(' dock %.1f', (me and D) and math.sqrt((D[1] - me[1]) ^ 2 + (D[2] - me[2]) ^ 2) or -1)
        .. ((laser.last_gun and laser.last_to) and string.format(' barrel_off %.2f %.2f', laser.last_gun[3] - laser.last_to[3],
          math.sqrt((laser.last_gun[1] - laser.last_to[1]) ^ 2 + (laser.last_gun[2] - laser.last_to[2]) ^ 2)) or ''))
    else
      rwrite(string.format('S %.2f %s %d %d not-in-list', t - research.t0, st.dog.name, st.node, st.target))
    end
  end
  if t >= research.next_list then
    research.next_list = t + LIST_SECONDS
    local parts = {}
    for _, c in ipairs(st.candidates) do
      parts[#parts + 1] = string.format('%d:%s:%s:%x:%.2f:%.0f:%d:%d:%d:%.2f:%d', c.id, type_of(c), c.group or '?', c.flags or 0,
        c.score or 0, dist(c.pos, me), c.eligible and 1 or 0, c.alive and 1 or 0, c.visible and 1 or 0, c.memory or -1,
        c.mask == '    ' and 1 or 0)
    end
    rwrite(string.format('L %.2f %s %s', t - research.t0, st.dog.name, table.concat(parts, ' ')))
    if research.f then research.f:flush() end
  end
end

function research_close()
  if research.f then pcall(function() research.f:close() end); research.f = nil end
end
end)()

-- ======================================================================================================
-- Armor: enemies a dog cannot hurt. The game keys every enemy by a type hash (the first 8 bytes of its
-- entity row, byte-reversed). Each listed enemy has the armor where the dogs' shots land (the middle of
-- the body; for the Scout Strider that is the Medium-armored crotch, not the Heavy front plate), from the
-- Helldivers wiki. Shots bounce off armor above a dog's penetration: Rover Light (2) - its beam must
-- connect to set anything on fire - Guard Dog Medium (3), K-9 Anti-Tank (7). Unlisted enemies are never
-- skipped, so an unknown or new enemy type is simply treated the way the game treats it.
-- ======================================================================================================
local ARMOR = {}
local function armor(hash, av, name, extra)
  local e = extra or {}
  e.av, e.name = av, name
  ARMOR[type_hash(hash)] = e
end
-- Terminids
armor('1a7fcdff98c664b0', 4, 'Charger')
armor('3aff5fd7d5450b99', 4, 'Charger Behemoth')
armor('6b202392f4ab605e', 4, 'Spore Charger')
armor('0ab7b92b131c228c', 4, 'Rupture Charger')
armor('dcf8e74212fbee3b', 4, 'Impaler')
armor('960b48a421a3faaa', 4, 'Dragonroach')
armor('d465d9c7f77a07cb', 5, 'Hive Lord')
-- Bile Titan (4.0, by file name: fac_bugs/cha_strider): Heavy carapace; the dogs never pick it anyway, but the sentries
-- rank it (the rocket and autocannon sentries go for it first, the machine gun and Gatling sentries leave it alone)
armor('9e2e17f2ccccafdd', 4, 'Bile Titan')
armor('ef04cb84d097a497', 4, 'Spore Burst Bile Titan')
-- the game files its bug types by tier too ("cha_charger_tier2" is the Charger seen in game); the other tiers
-- and sub-types follow the same pattern (a name that doesn't exist simply never matches)
armor('b69a85547b03e00b', 4, 'Charger (tier1)')
armor('a05bd1ec67b3ac4c', 4, 'Charger')
armor('c9a50ad41ba6e366', 4, 'Charger (tier3)')
armor('2ee35a025f7be547', 4, 'Charger (tier 1)')
armor('1cc0cbc3c8c203e6', 4, 'Charger (tier 2)')
armor('81cfb7520c2fd4ea', 4, 'Charger (tier 3)')
armor('ff922fb58cf3c898', 4, 'Charger (gloom)')
armor('1d7c1121d14d4640', 4, 'Charger (predator)')
armor('82d7dbf36df2cd5d', 4, 'Charger Behemoth (tier1)')
armor('cb0ac45550e3fa08', 4, 'Charger Behemoth (tier2)')
armor('a268efcfd5960e5b', 4, 'Charger Behemoth (tier3)')
armor('a9825f1cf370258d', 4, 'Charger Behemoth (tier 1)')
armor('5618ff7dcba169de', 4, 'Charger Behemoth (tier 2)')
armor('712123d7050156ce', 4, 'Charger Behemoth (tier 3)')
armor('3552e6e38336b99d', 4, 'Charger Behemoth (gloom)')
armor('e3c3cba17ecc82bb', 4, 'Charger Behemoth (predator)')
armor('097150e4fba7baaf', 4, 'Spore Charger (tier1)')
armor('d627f630fb6cad19', 4, 'Spore Charger (tier2)')
armor('6acb7837c592b516', 4, 'Spore Charger (tier3)')
armor('f8fd2aad1cff629f', 4, 'Spore Charger (tier 1)')
armor('6dd3c4f82f64f81d', 4, 'Spore Charger (tier 2)')
armor('b51014ff0536c61d', 4, 'Spore Charger (tier 3)')
armor('ded63b68585fa88e', 4, 'Spore Charger (gloom)')
armor('95782440f640c3b4', 4, 'Spore Charger (predator)')
armor('cbf1826547aa60ec', 4, 'Rupture Charger (tier1)')
armor('848e53715479be04', 4, 'Rupture Charger (tier2)')
armor('fd2e34a1b1c6a4d3', 4, 'Rupture Charger (tier3)')
armor('ef3129d9dbef6503', 4, 'Rupture Charger (tier 1)')
armor('18a07ac28c3b8258', 4, 'Rupture Charger (tier 2)')
armor('db6181255b9b4497', 4, 'Rupture Charger (tier 3)')
armor('725647c42e84de3d', 4, 'Rupture Charger (gloom)')
armor('1e6a385598cba826', 4, 'Rupture Charger (predator)')
armor('8396bcd1003b7f46', 4, 'Impaler (tier1)')
armor('b7c25339a05a04c4', 4, 'Impaler (tier2)')
armor('2683800ebc99c5be', 4, 'Impaler (tier3)')
armor('446825542ef85f41', 4, 'Impaler (tier 1)')
armor('d26d4b7d4166dbe1', 4, 'Impaler (tier 2)')
armor('ee74e10e8693a124', 4, 'Impaler (tier 3)')
armor('65a81640a158d4a0', 4, 'Impaler (gloom)')
armor('184ad328cc8c6010', 4, 'Impaler (predator)')
armor('aa4668216fb9dc7e', 4, 'Dragonroach (tier1)')
armor('2f3ecea87263f777', 4, 'Dragonroach (tier2)')
armor('50d9042eea9da250', 4, 'Dragonroach (tier3)')
armor('6bd57fd70a200f03', 4, 'Dragonroach (tier 1)')
armor('8f0f553c0726adbe', 4, 'Dragonroach (tier 2)')
armor('8628b0f6e5129d2d', 4, 'Dragonroach (tier 3)')
armor('6728b887e4a17d0d', 4, 'Dragonroach (gloom)')
armor('6127e8bb9026de42', 4, 'Dragonroach (predator)')
armor('555069735072f167', 5, 'Hive Lord (tier1)')
armor('a25f9da353c6b87d', 5, 'Hive Lord (tier2)')
armor('150ffdb619e0060d', 5, 'Hive Lord (tier3)')
armor('d44584b9b341f2dd', 5, 'Hive Lord (tier 1)')
armor('7ab2961e1725be57', 5, 'Hive Lord (tier 2)')
armor('5b89ba8c3a303363', 5, 'Hive Lord (tier 3)')
armor('fa91c6c1d9d68536', 5, 'Hive Lord (gloom)')
armor('846fc796b658993d', 5, 'Hive Lord (predator)')
-- Automatons
armor('f8131632aa867107', 3, 'Scout Strider')   -- (Codex: Waist and Turret System AV3 where shots land; its Front Plate and HMG are separate parts, AV4)
armor('ae63e525853d7044', 2, 'Devastator')
armor('b92435fbf60f0748', 4, 'Heavy Devastator', { legs = 2, burst = true })
armor('db7139323c40ae6f', 2, 'Rocket Devastator')
armor('3d9c95bd03c0c7cf', 4, 'Heavy Devastator', { legs = 2, burst = true })   -- soldier_heavy_weapon
armor('c626d2bb495a202d', 2, 'Devastator (Iron Fleet)')
-- Devastators: listed at their Light legs, so every dog shoots them (the Rover burns their legs).
-- Heavy Devastators: their Heavy shield faces the dog. The Rover still burns their Light legs; the Guard Dog
-- fires only short suppressing bursts at them (see BURST in engine_logic.lua) instead of emptying its magazine.
-- Devastators of the Automaton sub-factions (Ivory Legion ones confirmed in game)
armor('57eed0eac346cd9d', 2, 'Devastator (Ivory Legion)')
armor('387d5f34dee8ed58', 2, 'Devastator (Jet Brigade)')
armor('fd7cb6955092ded7', 2, 'Devastator (Incineration Corps)')
armor('793d676154cce8f9', 4, 'Heavy Devastator (Iron Fleet)', { legs = 2, burst = true })
armor('58b2b86c11369241', 5, 'Incendiary MG Devastator', { legs = 2, burst = true })   -- ((5.1) the asset index: cha_soldier_mg_ivory_legion; Codex: its shield is AV5)
armor('b8a9c5e5ca2bed52', 4, 'Heavy Devastator (Jet Brigade)', { legs = 2, burst = true })
armor('9b9e22b1fbf4aead', 4, 'Heavy Devastator (Incineration Corps)', { legs = 2, burst = true })
armor('01ecb61cfba04732', 2, 'Rocket Devastator (Iron Fleet)')
armor('0c95f5e9fbda85a5', 2, 'Rocket Devastator (Ivory Legion)')
armor('be8fe6b6d1f66828', 2, 'Rocket Devastator (Jet Brigade)')
armor('fa7a1664fbc642bd', 2, 'Rocket Devastator (Incineration Corps)')
armor('ed1b320d618b35a2', 2, 'Devastator (shotgun)')
armor('3045ad506156c217', 2, 'Devastator (shotgun) (Iron Fleet)')
armor('e0353177f1329573', 4, 'Conflagration Devastator', { legs = 2, burst = true })   -- ((5.1) the asset index: cha_soldier_shotgun_ivory_legion, the Conflagration Devastator; Codex: a Shield AV4)
armor('0acde1a3ae2eb027', 2, 'Devastator (shotgun) (Jet Brigade)')
armor('4daec072f9395162', 2, 'Devastator (shotgun) (Incineration Corps)')
armor('f4ceeaf35ee84f15', 2, 'Devastator (heavy weapon) (Iron Fleet)')
armor('d6ad92ab466a4014', 2, 'Devastator (heavy weapon) (Ivory Legion)')
armor('651f72844a012959', 2, 'Devastator (heavy weapon) (Jet Brigade)')
armor('03ed7c9298237257', 2, 'Devastator (heavy weapon) (Incineration Corps)')
armor('282eb766c1ffa6a1', 3, 'Gunship')
-- Hulks: the game files them as "lieutenants" (their saw, cannon and launcher arms are lieutenant_* weapons).
-- Confirmed in game: the Scorcher, the Bruiser and the Firebomber (filed as the Ivory Legion lieutenant); the rest are the same names with the other
-- sub-faction endings the game uses (a name that doesn't exist simply never matches)
armor('3e0537d606438fea', 4, 'Hulk Scorcher')
armor('6dab2eadf5d8b692', 4, 'Hulk Firebomber')
armor('137988cea16458f7', 4, 'Hulk Bruiser')
armor('846bc06c6b213a06', 4, 'Hulk')
armor('b16493b009eec762', 4, 'Hulk Scorcher')
armor('68d696b3ddc8efa0', 4, 'Hulk (Iron Fleet)')
armor('92674f050150fa24', 4, 'Hulk (Jet Brigade)')
armor('b96035bf3708da51', 4, 'Hulk (Incineration Corps)')
armor('5581097fe8bad0cf', 4, 'Hulk Scorcher (Iron Fleet)')
armor('970810405c11ea79', 4, 'Hulk Scorcher (Ivory Legion)')
armor('64d3a01db1863ccb', 4, 'Hulk Scorcher (Jet Brigade)')
armor('f93ec7e4b88037b1', 4, 'Hulk Scorcher (Incineration Corps)')
-- emplacements (Mortar confirmed in game; the machine-gun one turned up as its file name, so the heavy
-- machine-gun one is taken from its file name too)
armor('ff5cc825b9571052', 4, 'Mortar Emplacement')
armor('a98f8b559c7993d8', 3, 'Automaton HMG Emplacement')   -- file name says heavy MG emplacement; seen in game as an armored strider
armor('aeaef7a1851e6c9d', 4, 'Anti-Air Emplacement')   -- confirmed in game (F8 markers)
armor('ef570293245a17c2', 4, 'War Strider')
-- (4.0) a separate part of the War Strider that the Gatling Sentry kept firing at (a tester's F8 marker; its file
-- name isn't in the game's unit list): Heavy like the rest of it
armor('390e6b3d2f26bd70', 3, 'Factory Strider (Fusion Gatling Gun)')   -- ((5.1) the asset index: an entity on cyborg_top_turret named Factory Strider - its gatling gun, Codex AV3)
-- (4.5, Codex check) its two fusion cannons are units of their own (Codex: left and right fusion cannon, AV4)
armor('8372619b2702d743', 4, 'War Strider (left fusion cannon)')
armor('9ab036439f74c115', 4, 'War Strider (right fusion cannon)')
armor('00bcf8247a544cdc', 5, 'Tank hull')
-- tank variants (Shredder confirmed in game with an F8 marker; the others by file name)
armor('c6449ffd9ea3779c', 5, 'Shredder Tank')   -- confirmed in game (F8 marker)
armor('63df3d07b7424588', 5, 'Barrager Tank')   -- seen in game logs
armor('f75a20ca493f7407', 5, 'Annihilator Tank')   -- guess by file name (cyborg_tank_cannon): never seen in game
-- the enemy the Guard Dog kept firing at while a tester marked it shooting an Annihilator Tank (RC 14, bots); its name is
-- not in the game's file list, so identified from that log rather than by name
armor('36390775d61159eb', 5, 'Annihilator Tank')
armor('0de06d0359ce6b1c', 5, 'Tank (mortar)')
armor('b64245d92dd8fa1a', 5, 'Tank (machine gun)')
-- tank turrets and hull gun can be picked on their own (the rocket turret was, in game)
armor('5d142c3a73ebc634', 5, 'Barrager Tank turret')
armor('49674794a165eda8', 5, 'Shredder Tank')
armor('cecd6979cf7bb0f2', 5, 'Annihilator Tank turret')
armor('6293d7ab6e681855', 4, 'Mortar Emplacement (gun)')   -- (Codex: the mortar of the Mortar Emplacement, stored with the tank turrets; Main AV4)
armor('16023e554fee830e', 5, 'Tank hull machine gun')
-- (bc242702fb46b7e7 was listed as the Factory Strider until Filediver showed it is cyborg_siege_engine: the Vox Engine)
armor('bc242702fb46b7e7', 5, 'Vox Engine')
-- the big walkers' guns are separate targets. The miniguns are the same part on the Factory Strider (its front
-- Fusion Gatling Guns) and the Vox Engine (its side Plasma Duster miniguns): wiki 300 health, Medium (AV3) on both.
-- But the dogs aim low, so their shots land on the armored body around them (Heavy/Tank, AV4-5) and are wasted:
-- listed at AV5. The two minigun ids were identified by where they sat in a Vox Engine F8 marker (not by name);
-- the upper pair is cyborg_siege_engine_turret (Vox cannons or launchers), and the Factory Strider's cannon turret
-- is cyborg_big_walker_turret_cannon (Tank I, AV5); both names confirmed by hash
-- ((5.1) the asset index: both are entities on cyborg_top_turret named Vox Engine (its miniguns), like the Factory Strider's
-- gatling guns. Listed at their own armor (Codex AV3) now that a gun is judged by where the game aims it)
armor('f2881f5807348116', 3, 'Vox Engine (minigun)')
armor('356de4a7808ef3e3', 3, 'Vox Engine (minigun)')
armor('1c6981ca2fb69508', 3, 'Factory Strider (Fusion Gatling Gun)')
armor('3aafba89b53b0f63', 3, 'Factory Strider (Fusion Gatling Gun)')
armor('6a7a54d5fb3a6d17', 3, 'Factory Strider (Fusion Gatling Gun)')
armor('611ba777783b08a2', 5, 'Vox Engine turret')
armor('843d18d4b5512b63', 5, 'Factory Strider cannon turret')
armor('8093204aea733daa', 4, 'Factory Strider')   -- guess: cyborg_big_walker (the Factory Strider's own id is not confirmed)
-- dropships (4.0): every sentry leaves them alone - they only waste ammo and time on them (a tester's call)
armor('db90077e76faa025', 5, 'Dropship', { sentries_skip = true })   -- fac_cyborgs/vehicles/cyborg_dropship
-- bunker turrets (3.0): the tower turret on Automaton bunkers, confirmed in game with F8 markers (a tester: the Guard Dog
-- can't damage it; it sits ~11 m up); its file name isn't in the game's unit list. The command bunker's machine-gun
-- turret is added by file name (not yet seen in game). Both left alone by the Rover and Guard Dog (the K-9 still shoots them)
armor('9926876b2375a1bb', 4, 'Bunker Turret')   -- confirmed in game (F8 markers); Codex: Main AV4, Heatsink AV3
armor('cd28a27a79be53d5', 5, 'Command Bunker MG turret')     -- fac_cyborgs/turrets/cyborg_turret_command_bunker_hmg
-- Illuminate
armor('19e18b46ec55d94a', 3, 'Stingray')
armor('965eae5a51acdd4a', 4, 'Harvester')
armor('f22d027b37bef107', 4, 'Leviathan')
armor('74e2285c01da4f71', 5, 'Warp Ship', { sentries_skip = true })   -- fac_illuminate/vehicles/illuminate_dropship

-- from the HD2 Enemy Codex (2026-09-28): every enemy model with armor Light (2) or more that wasn't listed above,
-- at its wiki armor value (the body's armor, where shots land); parts that attach to a bigger enemy (guns, plates,
-- packs) carry that enemy's rule. Names as checked by a tester in the Codex. Gatekeepers and Veracitors were left off the
-- list on purpose (their pilots are Light and their shields can be brought down; (5.1) they are listed now, judged only
-- by their part model, and shot at as before when it can't be read); anything under Light is not armor
-- What counts is the armor where the shots land: Hive Guards (armored front, the rest of the body exposed) and the
-- Spewers (a little face armor, and only on higher difficulties) are hit mostly where they are unarmored, and Alpha
-- and Brood Commanders are only lightly armored, so they are left off (named in LABELS instead)
armor('56b7f620948be11e', 4, 'Anti-Air Emplacement')   -- cyborg_turret_aa_base
armor('9b6c199030d86085', 4, 'Emplacement base')   -- (4.5, Codex check) env_cyborg/cyborg_turret_base: the base under the Anti-Air and Mortar Emplacements and the Bunker Turret, AV4
armor('2c1a7790c435fd67', 2, 'Automaton MG Emplacement')   -- cyborg_emplacement_mg
armor('dfb610642eff47d7', 4, 'Conflagration Devastator (scattergun)', { legs = 2, burst = true })   -- soldier_riotgun (Codex: a Shield AV4 like the Heavy Devastator's)
armor('070bc8d3e18bb8f9', 2, 'Devastator (cannon)')   -- soldier_standard_rifle
armor('48c91e42b9f16512', 3, 'Factory Strider (Fusion Gatling Gun)')   -- cyborg_top_turret (Codex AV3)
armor('d37e8d120d2836e3', 4, 'Factory Strider')   -- cyborg_spawner
armor('2ed3696e12a14d4c', 4, 'Heavy Devastator (fusion repeater)', { legs = 2, burst = true })   -- soldier_machinegun
armor('f96257fcae258caa', 4, 'Heavy Devastator (shield)', { legs = 2, burst = true })   -- soldier_shield
armor('feb484ee972469f7', 5, 'Incendiary MG Devastator (shield)', { legs = 2, burst = true })   -- soldier_shield_ivory_legion (Codex 4.5: its shield is AV5)
-- ((5.1) 9647b00cc3a9d36f was listed as the Heavy Devastator's shield (likely); the asset index shows it is the Rocket
-- Devastator's entity (cha_soldier_rpg, on the cha_soldier_rocket unit): Light like the other Devastators)
armor('9647b00cc3a9d36f', 2, 'Rocket Devastator')
armor('c9bcccb0a54a82a4', 2, 'Rocket Devastator (Ivory Legion)')   -- cha_soldier_rpg_ivory_legion
armor('4d61156dd350a82b', 4, 'Hulk (autocannon arm)')   -- lieutenant_cannon
armor('7b5c9bdd385d0516', 4, 'Hulk (rocket arm)')   -- lieutenant_launcher
armor('8fc2784308e9ba99', 4, 'Hulk (flag)')   -- lieutenant_flag
armor('b940c889d77f8219', 4, 'Hulk (jetpack)')   -- lieutenant_jetpack
armor('bb37f12d0f46690f', 4, 'Hulk (buzzsaw arm)')   -- lieutenant_saw_ivory_legion
armor('c89ed7ac3e425b25', 4, 'Hulk (buzzsaw arm)')   -- lieutenant_saw
armor('33b3e0ce8d179eec', 2, 'Jet Brigade Devastator (jump pack)')   -- soldier_jumppack
armor('d3cd6f0ca83bb51e', 4, 'Reinforced Scout Strider (cabin)')   -- (Codex: Faceplate AV4)
armor('e5b14182b25f7f7d', 2, 'Reinforced Scout Strider (rocket rack)')   -- (Codex: Rocket Rails and Rockets AV2)
armor('2a346bf4552997e2', 4, 'Scout Strider (heavy machine gun)')   -- (Codex: HMG AV4)
armor('ee00bfe8ff769f70', 4, 'Scout Strider (front plate)')   -- (Codex: Front Plate AV4)
armor('8612789d750e8d92', 5, 'Vox Engine (gun turret)')
armor('abdc3c3c4eb8e1ee', 5, 'Vox Engine (sarcophagus)')   -- cyborg_siege_engine_sarcophagus
armor('0bd274fdd3b20e90', 10, 'Illuminate Overship', { sentries_skip = true })
armor('e7074f10233cd0b8', 10, 'Illuminate Overship', { sentries_skip = true })
armor('4e342031a9d5c4f9', 4, 'Leviathan (cannon turret)')   -- illuminate_turret_wm_cannon
armor('f735a51a991e4bda', 5, 'Warp Ship', { sentries_skip = true })
armor('019610dfe2e4ab79', 5, 'Hive Lord (shard f 02)')   -- cha_hive_lord_shard_f_02
armor('09cd7fc0ba3ffcf4', 6, 'Hive Lord (r mandible)')   -- cha_hive_lord_r_mandible
armor('0a2bbb5dd1dc065f', 5, 'Hive Lord (r leg)')   -- cha_hive_lord_r_leg
armor('1614f01ade1aac64', 5, 'Hive Lord (shard b 03)')   -- cha_hive_lord_shard_b_03
armor('3d75b189bf969ec0', 5, 'Hive Lord (shard f 03)')   -- cha_hive_lord_shard_f_03
armor('86f2a2d347c70074', 6, 'Hive Lord (l mandible)')   -- cha_hive_lord_l_mandible
armor('909bffb60c2236f0', 5, 'Hive Lord (shard f 01)')   -- cha_hive_lord_shard_f_01
armor('a5b106ba5d813094', 5, 'Hive Lord (l leg)')   -- cha_hive_lord_l_leg
armor('cbddb06fa202b2a4', 5, 'Hive Lord (shard b 02)')   -- cha_hive_lord_shard_b_02
armor('fecada76a501af4c', 5, 'Hive Lord (shard b 01)')   -- cha_hive_lord_shard_b_01

-- (5.1 Test 1) the asset index's entities on the enemies that now have part models, that weren't listed: their armor
-- is their Codex main armor; the part model decides where the shots land (engine_armor PARTS below)
armor('f8b5a81a86d5d4eb', 4, 'Heavy Devastator', { legs = 2, burst = true })   -- cha_soldier_mg_assassinate
armor('53d8919d7b8abd67', 5, 'Annihilator Tank')            -- cyborg_tank_heavycannon (on the cyborg_tank hull)
armor('31bae74d2f064d8d', 5, 'Annihilator Tank')            -- cyborg_tank_base
armor('8fb47dd28b398cf7', 5, 'Annihilator Tank turret')     -- cyborg_tank_turret_heavycannon
armor('30f2dee2333f227a', 4, 'Factory Strider')             -- cyborg_spawner_jammer
armor('9076eeed17fcee35', 3, 'Reinforced Scout Strider')    -- (on the cyborg_walker_scout unit)
armor('d63fcbff0851b7af', 4, 'Harvester')                   -- cha_tripod_tier_2
armor('453fe22c634eb30f', 4, 'Gatekeeper', { open = true })  -- cha_exomech_ranged
armor('20b9c7734daead65', 3, 'Veracitor', { open = true })   -- cha_exomech_melee (Main AV3: only the Rover looks at its parts)

-- (5.1.3; a player: the Machine Gun Sentry tried to kill a Jet Brigade Hulk by shooting its head) entities on the
-- units of listed enemies that weren't listed - an unlisted kind counts as unarmored, so every gun fired on it where the
-- game aims (a Hulk's head). Found by checking every entity in the asset index whose unit is a listed enemy's; the ones
-- without a file name are most likely the sub-faction versions (Jet Brigade, Incineration Corps). Armor as their listed
-- kin; the Hulks and the Behemoth get their part models by name, the others below by type id
armor('32cdeada234fb8df', 4, 'Hulk Bruiser')                -- (on cha_lieutenant; no file name)
armor('e44ec9f9b3fe1d2a', 4, 'Hulk Scorcher')               -- (on cha_lieutenant_assault; no file name)
armor('1e66ee1f6f7fd00e', 4, 'Hulk Obliterator')            -- cha_lieutenant_artillery
armor('96ba14c9ebb49ce1', 4, 'Hulk')                        -- cha_lieutenant_base
armor('1897bdd32105d2dc', 4, 'Hulk Scorcher')               -- cha_lieutenant_ivory_legion_assault
armor('fd5247653c897803', 4, 'Charger Behemoth')            -- (on cha_charger_bull; no file name)
armor('91ebd77931110afc', 4, 'Heavy Devastator', { legs = 2, burst = true })   -- (on cha_soldier_heavy_weapon; no file name)
armor('fc8dec78be8ab47d', 2, 'Devastator')                  -- (on cha_soldier; no file name)
armor('be743b2faa3a6e26', 2, 'Devastator (jump pack)')      -- cha_soldier_jumppack
armor('f66d0bad8693779a', 2, 'Rocket Devastator')           -- cha_soldier_rpg_assassinate
armor('98152772a72f7838', 5, 'Dropship', { sentries_skip = true })   -- (on cyborg_dropship; no file name)
armor('2cf3488c4845f8bd', 5, 'Cannon Turret')               -- cyborg_turret_heavycannon (the Annihilator turret's unit)
armor('abdb2e2a0479d8ca', 5, 'Cannon Turret')               -- cyborg_turret_base
armor('b8580cac32214fc0', 5, 'Annihilator Tank turret')     -- cyborg_tank_turret_base
armor('96110f9d6b010e02', 4, 'Leviathan (cannon turret)')   -- (on illuminate_turret_wm_cannon; no file name)
armor('f196069e7e14c497', 4, 'Leviathan (cannon turret)')   -- illuminate_turret_wm_cannon_head_l
armor('7acb4bd753b71de0', 4, 'Leviathan (cannon turret)')   -- illuminate_turret_wm_cannon_head_r
armor('397fb7e4883af100', 2, 'Reinforced Scout Strider (rocket rack)')   -- (on its rocket rack unit; no file name)
armor('a8173fba5dec35c3', 2, 'Reinforced Scout Strider (rocket rack)')   -- (on its rocket rack unit; no file name)

-- the highest armor each dog can hurt (its armor penetration)
local PEN = { ['Rover'] = 2, ['Guard Dog'] = 3, ['K-9'] = 7 }
-- (sentries carry their own 'pen' in SENTRIES: machine gun and Gatling 3, Laser 4 (Heavy), Autocannon and Rocket 5
-- ((5.1.5 Test 10) were 'shoot everything'); those without one - the mortars, the Tesla Tower, the Flame Sentry - shoot
-- everything)

-- ======================================================================================================
-- (5.0 Test 12) Part armor. My ask: "see if the sentries and guard dogs can read what part they are aiming at and
-- determine what Armor rating it is, before firing on it, instead of blacklisting a whole enemy", and "add a fallback
-- so if it cant determine what part an enemy is, it goes off of the old version and blacklists an enemy based on what
-- armor rating it is".
-- (5.1 Test 1) my ask: "Let's add all of those functionalities. It should only worry about shooting parts of an
-- enemy it can actually hit, Sentries and guard dogs only aim at a specific point on an enemy": part models for the
-- Heavy Devastators' shields, the Impaler, the Bile Titans, the Dragonroach, the tanks and their turrets, the
-- emplacements and the Bunker Turret, the Factory Strider, the Vox Engine, the War Strider, the Scout Striders, the
-- Harvester, the Gatekeeper and the Veracitor.
-- For an enemy with a part model, the line from the gun to where it aims is followed into the enemy: the first part
-- it meets decides, by that part's armor (Codex). A Hulk facing away shows its Heatsink (AV1); a Charger facing away
-- its Butt (AV0); a tank turret its heatsink (AV3); a Heavy Devastator's body only where its shield isn't in the way.
-- Anything that can't be worked out - no model for that enemy, its bones can't be read or don't match a known
-- skeleton, the line meets none of the parts - falls back to the whole enemy's armor rules (as before).
-- A model: boxes in a bone's own axes (the frame bone; the game's pose matrices: rows = the bone's axes in the world,
-- then its place), from the game's own models (Filediver glb, bind pose: each visibility group's bounds in the frame
-- bone's axes). A few boxes ride a second bone (f = 2: a Heavy Devastator's shield on its hand, the Barrager's launch
-- tubes on their pitch bone). Each box has an armor value, and a face can have its own (the Hulk's back face is its
-- heatsink). The skeleton is checked before use: child bones whose origins sit at fixed places in the frame bone's
-- axes (they rotate, they don't move) must be where the model says, to within 10 cm; this also catches a variant
-- whose bones are numbered differently.
-- ======================================================================================================
local PARTS
do
  -- box: { x0, x1, y0, y1, z0, z1, armor, part name, f = frame (1 if left out), faces = { ['y-'] = { armor, name }, ... } } (meters)
  -- model: name, aim (where to look when the game's own aim point isn't known: frame 1), back (for the log's angle),
  -- checks (the check bones' places in frame 1), nf (frames used)
  local function mirror(list)   -- each box given for the +x side, and its mirror image on the -x side
    local out = {}
    for _, b in ipairs(list) do
      out[#out + 1] = b
      -- ((5.1.0 release review) a face on the x sides swaps with it)
      local fc = b.faces
      if fc and (fc['x-'] or fc['x+']) then
        local sw = {}
        for k, v in pairs(fc) do sw[k == 'x-' and 'x+' or k == 'x+' and 'x-' or k] = v end
        fc = sw
      end
      local m = { -b[2], -b[1], b[3], b[4], b[5], b[6], b[7], b[8], f = b.f, faces = fc }
      out[#out + 1] = m
    end
    return out
  end
  local function join(a, b) for _, x in ipairs(b) do a[#a + 1] = x end; return a end
  local HULK = { name = 'Hulk', back = { 0, -1, 0 }, aim = { 0, 0, 0 },
    -- frame bone spine2 (+x up, -y back, z sideways); its aim_root sits on it (the game aims at the chest)
    boxes = {
      { -0.25, 1.45, -1.10, 0.85, -0.75, 0.75, 4, 'Main', faces = { ['y-'] = { 1, 'Heatsink' } } },   -- upper body: the back is the heatsink
      { -1.05, -0.25, -0.90, 0.75, -0.72, 0.72, 4, 'Main' },                                            -- lower body
      { 0.16, 1.05, -0.60, 0.16, 0.39, 1.66, 4, 'Shoulder' },
      { 0.16, 1.05, -0.60, 0.16, -1.66, -0.39, 4, 'Shoulder' },
    },
    checks = { { 0.691, 0.532, 0 }, { 0.9, -0.9, 0 } } }   -- head, backpack_damage
  local CHARGER = { name = 'Charger', back = { -1, 0, 0 }, aim = { 0, 0, 0 },
    -- frame bone boss (+x forward, z up); the abdomen runs back to x -3.5
    boxes = {
      { -1.50, 0.85, -1.37, 1.37, -0.60, 1.70, 4, 'Torso Armor', faces = { ['z-'] = { 2, 'Underside' } } },
      { 0.75, 2.60, -0.90, 0.90, -1.00, 1.00, 4, 'Head' },                    -- (the Behemoth's bigger head)
      -- ((5.0 Test 16, Test 14 log on bugs: the answer from 15-30 deg behind flipped between Butt and the plates every few
      -- tenths of a second) the plates' box no longer reaches past the butt's at the back or sides, and starts a little
      -- higher: from behind, a sentry's line meets the butt; only a line coming down on it meets the plates
      { -3.30, -1.10, -0.80, 0.80, 0.95, 1.85, 4, 'Rear Armor Plates' },     -- the plates over the abdomen
      { -3.30, -1.10, -0.80, 0.80, -0.45, 0.95, 0, 'Butt' },                 -- the abdomen under them
    },
    checks = { { 0.669, 0, 0.228 }, { -1.087, 0, 0.238 } } }   -- neck1, spine1
  -- (5.1 Test 1) the Heavy Devastators: frame bone boss (+y forward, z up, -x its left), the shield on the bone its left
  -- hand holds it by (frame 2: the shield's own axes; the plate runs across y and z, 35 cm thick along x). The game
  -- aims at aim_root (the chest). Shield AV4 (the Incendiary MG Devastator's AV5)
  local function devastator(name, shield)
    return { name = name, back = { 0, -1, 0 }, aim = { 0, 0.119, 0.266 }, nf = 2,
      boxes = join({
        { -0.22, 0.22, 0.10, 0.55, 0.50, 0.85, 1, 'Head' },
        { -0.45, 0.45, -0.25, 0.45, 0.00, 0.60, 3, 'Torso' },
        { -0.38, 0.38, -0.20, 0.35, -0.35, 0.00, 1, 'Stomach' },
        { -0.42, 0.42, -0.25, 0.35, -0.65, -0.35, 2, 'Pelvis' },
        { -0.60, 0.60, -0.30, 0.40, -1.48, -0.65, 2, 'Legs' },
        { -0.36, 0.36, -0.70, -0.25, -0.12, 0.70, 2, 'Backpack' },
        { -0.36, 0.02, -0.55, 0.55, -1.22, 0.50, shield, 'Shield', f = 2 },
      }, mirror({ { 0.45, 0.80, -0.25, 0.40, 0.25, 0.75, 2, 'Shoulder' } })),
      checks = { { 0, -0.011, 0.251 }, { 0, 0, 0 } } }   -- chest, pelvis
  end
  -- Impaler: frame bone boss (+x forward, +y its left, z up), like the Charger's; its face (AV1) hangs in front and below
  -- (frame 2: headplate1, the crest over its head - its head and crest move with it: +x its right, +y forward, z up)
  local IMPALER = { name = 'Impaler', back = { -1, 0, 0 }, aim = { 0, 0, 0 }, nf = 2,
    boxes = {
      { -2.29, 1.82, -1.63, 1.66, -1.60, 1.26, 4, 'Torso Armor', faces = { ['z-'] = { 2, 'Underside' } } },
      { -1.39, 1.28, -1.08, 1.39, -2.42, 0.52, 1, 'Head', f = 2 },
      { -2.41, 2.41, -2.90, -0.24, -0.29, 3.21, 4, 'Crest Armor', f = 2 },
      { -4.91, -2.29, -1.72, 1.72, 1.10, 2.68, 4, 'Rear Armor Plates' },
      { -4.91, -2.29, -1.60, 1.60, -0.28, 1.10, 1, 'Butt' },
    },
    checks = { { 0.981, 0, 0.334 }, { -1.132, 0, 0.824 } } }   -- neck1, spine1
  -- Bile Titan: frame bone boss (+x forward, z up, about 9 m above its feet); the game aims at its target_node, 1.4 m
  -- below it. Its belly (Underside AV2) and the sac under its abdomen (AV0) face the ground
  local TITAN = { name = 'Bile Titan', back = { -1, 0, 0 }, aim = { 0, 0, -1.4 },
    boxes = {
      { -2.20, 2.10, -1.80, 1.80, -2.45, 0.85, 4, 'Torso Armor', faces = { ['z-'] = { 2, 'Underside' } } },
      { 2.10, 3.48, -0.98, 0.99, -1.65, 1.43, 4, 'Head' },
      { -7.18, -2.20, -1.45, 1.45, -4.20, -0.97, 4, 'Butt Armor', faces = { ['z-'] = { 0, 'Sac' } } },
    },
    checks = { { 1.135, 0, 0 }, { -1.566, 0, -0.793 } } }   -- spine_upper_1, spine_lower_1
  -- Dragonroach: frame bone boss (+y forward, z up); carapace on top, its sacs underneath (AV0), four wings (AV0)
  local DRAGON = { name = 'Dragonroach', back = { 0, -1, 0 }, aim = { 0, 0, 0 },
    boxes = join({
      { -1.20, 1.20, -1.97, 1.86, 0.00, 2.44, 4, 'Carapace' },
      { -1.44, 1.44, -2.34, 2.03, -1.73, 0.00, 4, 'Thorax Innards', faces = { ['z-'] = { 0, 'Sacs' } } },
      { -0.63, 0.63, 2.03, 3.27, -1.52, 0.48, 4, 'Head' },
      { -1.40, 1.40, 1.86, 2.45, -0.47, 1.26, 4, 'Neck' },
      { -1.00, 1.00, -5.40, -2.34, -5.06, 0.45, 4, 'Abdomen Armor' },
    }, mirror({
      { 1.30, 17.50, -0.80, 7.36, 0.20, 4.05, 0, 'Wing' },
      { 1.30, 12.30, -5.80, -0.59, -0.24, 1.48, 0, 'Wing' },
    })),
    checks = { { 0, 1.002, -0.069 }, { 0, -1.087, 0.064 } } }   -- spine, hips
  -- tank hull (every tank): frame bone boss (+y forward, z up); the engine bay (AV4) at the back, the tracks (AV3) low on
  -- the sides; the turret (a target of its own) sits on top. The game aims at aim_root, 0.5 m up
  local TANK = { name = 'Tank', back = { 0, -1, 0 }, aim = { 0, 0, 0.5 },
    boxes = join({
      { -1.49, 1.49, -2.06, 5.22, -1.32, 0.90, 5, 'Hull Main', faces = { ['y+'] = { 5, 'Hull Front' } } },
      { -1.49, 1.49, -3.89, -2.06, -1.16, 0.84, 4, 'Engine Bay' },
      { -2.34, 2.34, -2.03, 2.20, 0.90, 1.90, 5, 'Turret' },
    }, mirror({
      { 1.49, 3.14, -3.64, 4.88, -1.10, 0.89, 5, 'Hull Sides' },
      { 1.51, 2.60, -4.33, 5.01, -1.77, -1.10, 3, 'Tracks' },
    })),
    checks = { { -2, -3.584, -0.226 }, { 2, -3.584, -0.226 } } }   -- l_backwheel_rotation, r_backwheel_rotation
  -- turrets: frame bone yaw (it turns with the turret: +y the way the gun points, z up); the back is the heatsink (AV3;
  -- the game's damage effects for it sit there)
  local CANNON_TURRET = { name = 'Tank turret', back = { 0, -1, 0 }, aim = { 0, 0, 0.5 },
    boxes = {
      { -2.34, 2.34, -2.03, 2.20, -0.06, 0.98, 5, 'Turret Main', faces = { ['y-'] = { 3, 'Turret Heatsink' } } },
      { -0.45, 0.45, 2.20, 5.16, 0.15, 0.85, 5, 'Cannon' },
    },
    checks = { { 0, 0.849, 0.468 }, { -1.4, -2.0, 0.3 } } }   -- pitch, fx_damage_l
  local function autocannon_turret(name, av)   -- the Shredder Tank's turret (AV5) and the Anti-Air Emplacement (AV4)
    return { name = name, back = { 0, -1, 0 }, aim = { 0, 0, 0.7 },
      boxes = {
        { -1.42, 1.42, -1.28, 1.60, 0.03, 1.45, av, 'Turret Main', faces = { ['y-'] = { 3, 'Heatsink' } } },
        { -1.00, 1.00, 1.60, 4.16, 0.40, 1.30, av, 'Cannons' },
      },
      checks = { { 0, 0.734, 1.424 }, { -0.69, -1.2, 0.7 } } }   -- upper_plate, fx_damage_l
  end
  local MORTAR = { name = 'Mortar Emplacement', back = { 0, -1, 0 }, aim = { 0, 0, 0.7 },
    boxes = {
      { -1.42, 1.42, -1.31, 1.50, 0.00, 1.44, 4, 'Main', faces = { ['y-'] = { 3, 'Heatsink' } } },
      { -0.60, 0.60, 1.50, 2.98, 0.30, 1.40, 4, 'Mortar' },
    },
    checks = { { 0, 0.734, 1.424 }, { -0.69, -1.2, 0.7 } } }   -- upper_plate, fx_damage_l
  -- the Barrager's turret: its launch tubes (AV3) ride the pitch bone (frame 2) on both sides
  local BARRAGER = { name = 'Barrager turret', back = { 0, -1, 0 }, aim = { 0, 0, 0.8 }, nf = 2,
    boxes = join({
      { -1.75, 1.75, -2.92, 1.75, -0.13, 0.60, 5, 'Turret Main' },
      { -0.90, 0.90, -0.13, 6.22, -0.40, 1.19, 5, 'Turret Main', f = 2 },
    }, mirror({ { 0.90, 2.04, -0.13, 6.22, -0.40, 1.19, 3, 'Launch Tubes', f = 2 } })),
    checks = { { 0, -2.653, 0.67 }, { 0, 0, 0 } } }   -- pitch, boss
  local BUNKER = { name = 'Bunker Turret', back = { 0, -1, 0 }, aim = { 0, 0, 0.5 },
    boxes = {
      { -0.98, 0.98, -0.90, 1.30, 0.02, 1.03, 4, 'Main', faces = { ['y-'] = { 3, 'Heatsink' } } },
      { -0.40, 0.40, 1.30, 2.83, 0.30, 0.90, 4, 'Cannons' },
    },
    checks = { { 0, 0.677, 0.601 }, { -0.69, -1.2, 0.7 } } }   -- pitch, fx_damage_l
  -- Factory Strider: frame bone boss (+y forward, z up, 7 m above its feet); the game aims at aim_root, under the
  -- front of its neck. The belly panels (AV3) are the underside of its body, the rear engine weakspot (AV3) the back of
  -- the engine on top, the stratagem scrambler (AV0) on top behind it; the rest is AV4-5
  local FACTORY = { name = 'Factory Strider', back = { 0, -1, 0 }, aim = { 0, 5.99, -0.99 },
    boxes = {
      { -1.40, 1.40, 5.89, 8.87, -0.98, 1.70, 5, 'Head Armor' },
      { -1.31, 1.31, 3.97, 5.89, -0.89, 1.99, 5, 'Neck Armor' },
      { -2.18, 2.18, 2.08, 3.97, -1.60, 3.20, 5, 'Front Armor' },
      { -2.81, 2.81, -3.36, 2.08, -1.79, 2.43, 5, 'Side Armor', faces = { ['z-'] = { 3, 'Belly Panels' } } },
      { -2.50, 2.50, -0.35, 2.08, 2.43, 3.60, 5, 'Front Top Armor' },
      { -2.41, 2.41, -6.57, -3.36, -1.55, 2.41, 5, 'Rear Armor' },
      { -2.24, 2.24, -6.22, -0.35, 2.43, 3.22, 5, 'Rear Engine Armor', faces = { ['y-'] = { 3, 'Rear Engine Weakspot' } } },
      { -0.60, 0.60, -3.60, -2.40, 3.22, 4.20, 0, 'Stratagem Scrambler' },
      { -1.18, 1.18, -3.92, 2.80, -3.22, -1.79, 4, 'Main' },                  -- the cage under its belly
    },
    checks = { { 0, 4.349, 0.965 }, { 0, -3.021, 2.754 } } }   -- neck, jammer
  -- Vox Engine: frame bone boss (+y forward, z up, 4.7 m above its tracks); vents (AV1) under it, a hatch (AV0) at the
  -- back, flaps, missile launchers and speakers (AV3) on its torso, tracks (AV4); the rest AV5
  local VOX = { name = 'Vox Engine', back = { 0, -1, 0 }, aim = { 0, 0, 0.5 },
    boxes = join({
      { -2.40, 2.40, -3.40, 3.60, -1.60, 1.01, 5, 'Undercarriage' },
      { -2.40, 2.40, 0.63, 3.57, -2.83, -1.60, 5, 'Undercarriage' },
      { -1.10, 1.10, -0.86, 0.86, -1.75, -1.60, 1, 'Vents' },
      { -0.86, 0.86, -3.45, -1.74, -0.36, 0.52, 0, 'Hatch' },
      { -2.79, 2.79, -3.85, 3.13, 1.01, 6.39, 5, 'Torso' },
    }, mirror({
      { 2.79, 3.48, -1.82, 1.47, 0.84, 2.05, 3, 'Torso Flap' },
      { 2.79, 3.85, -3.76, -2.25, 2.51, 4.82, 3, 'Missile Launcher' },
      { 1.62, 2.85, 0.99, 2.45, 6.39, 6.71, 3, 'Speaker' },
      { 1.69, 5.50, 2.19, 6.84, -5.02, -0.35, 4, 'Tracks' },
      { 1.69, 5.50, -7.24, -2.54, -5.02, -0.35, 4, 'Tracks' },
    })),
    checks = { { 0, 0, 1.36 }, { 0.001, -1.897, 0.262 } } }   -- head_yaw, boss_lid
  -- War Strider: frame bone boss (+y forward, z up, 3.3 m above its feet); its hip joints (AV3) behind the platform
  local WAR_STRIDER = { name = 'War Strider', back = { 0, -1, 0 }, aim = { 0, 0, 0 },
    boxes = join({
      { -0.83, 0.83, -1.69, 1.19, -0.81, 0.39, 4, 'Crotch' },
      { -1.15, 1.15, -2.12, 1.66, 0.39, 1.87, 4, 'Torso' },
    }, mirror({
      { 0.83, 1.25, -1.50, -0.50, -0.70, 0.20, 3, 'Hip Joint' },
      { 0.70, 1.83, -1.98, 1.41, -3.34, -0.70, 4, 'Leg' },
    })),
    checks = { { 0, -0.226, 0.227 }, { -0.645, -1.02, -0.242 } } }   -- turret_compression, l_hip_rotator
  -- Scout Striders (they matter to the Rover only): frame bone boss (+y forward, z up); legs AV2, the pilot (AV0)
  -- behind the front plate (AV4); the Reinforced one's pilot sits in an armored cabin
  local function scout(name, pilot, pname)
    return { name = name, back = { 0, -1, 0 }, aim = { 0, 0, 0 },
      boxes = join({
        { -0.36, 0.36, -1.04, 0.52, -0.34, 0.10, 3, 'Waist' },
        { -0.30, 0.30, -0.75, 0.00, 0.10, 0.95, pilot, pname },
        { -0.45, 0.45, 0.00, 0.55, 0.10, 1.00, 4, 'Front Plate' },
      }, mirror({ { 0.36, 0.70, -1.18, 0.38, -1.76, -0.06, 2, 'Leg' } })),
      checks = { { 0, -0.106, 0.168 }, { -0.395, -0.666, -0.066 } } }   -- turret_compression, l_hip
  end
  -- Harvester: frame bone boss (+y forward, z up, 9.6 m above its feet); its eye (AV2) in front, hip joints (AV3). Its
  -- shield isn't modeled: the body is judged as if the shield were down (as the whole-enemy rule did)
  -- ((5.1.0 Test 1 log: the game aims a Rover at 0, -1.25, 0 in this frame - its Bone_459bb7fc - every time))
  local HARVESTER = { name = 'Harvester', back = { 0, -1, 0 }, aim = { 0, -1.25, 0 },
    boxes = join({
      { -1.34, 1.34, -2.39, 0.16, -0.80, 1.30, 4, 'Chassis' },
      { -0.73, 0.73, 0.16, 1.35, -0.71, 0.72, 2, 'Eye' },
      { -0.33, 0.33, -3.41, -1.86, -1.74, -0.88, 3, 'Hip Joint' },
    }, mirror({ { 1.74, 2.39, -1.66, -0.59, -1.37, -0.57, 3, 'Hip Joint' } })),
    checks = { { -0.539, -0.003, -0.427 }, { 0, -0.292, -0.789 } } }   -- l_leg1, b_leg1
  -- Gatekeeper and Veracitor (the same frame: boss, +y forward, z up): the cockpit below, its energy shield in front of it
  local GATEKEEPER = { name = 'Gatekeeper', back = { 0, -1, 0 }, aim = { 0, 0, 0 },
    boxes = join({
      { -1.00, 1.00, -2.56, 0.72, 0.71, 2.06, 4, 'Carapace' },
      { -0.95, 0.95, -1.50, 1.00, -0.60, 0.71, 4, 'Chassis', faces = { ['y-'] = { 1, 'Rear Weakspot' } } },
      { -0.58, 0.58, -4.45, -1.50, -4.41, 1.02, 3, 'Rear Hip' },
      { -0.73, 0.73, -1.14, 1.41, -3.09, -0.60, 4, 'Cockpit' },
      { -0.96, 0.96, 0.09, 1.50, -2.75, -0.62, 2, 'Shield' },
    }, mirror({
      { 0.15, 2.06, 0.55, 1.78, -0.03, 1.14, 4, 'Shoulder Armor' },
      { 1.37, 2.23, 0.11, 1.35, -1.15, -0.03, 3, 'Arm' },
      { 1.44, 2.77, 1.35, 4.43, -2.77, -1.37, 4, 'Gun' },
      { 0.95, 3.21, -1.99, -0.19, -1.14, 0.93, 3, 'Hip' },
      { 2.35, 3.36, -2.02, 1.36, -4.93, -1.14, 4, 'Leg Armor' },
    })),
    checks = { { 0.605, 1.359, 0.281 }, { -0.018, -1.286, 0.131 } } }   -- collar_right, hip_back
  local VERACITOR = { name = 'Veracitor', back = { 0, -1, 0 }, aim = { 0, 0, 0 },
    boxes = join({
      { -1.11, 1.11, -2.95, 0.80, 0.69, 2.33, 3, 'Carapace' },
      { -0.95, 0.95, -1.50, 0.80, -0.60, 0.69, 3, 'Chassis' },
      { -0.52, 0.52, -4.56, -1.50, -4.93, 1.00, 3, 'Rear Leg' },
      { -0.73, 0.73, -1.14, 1.41, -3.09, -0.60, 3, 'Cockpit' },
      { -0.96, 0.96, 0.09, 1.50, -2.75, -0.62, 2, 'Shield' },
    }, mirror({
      { 0.15, 2.34, 0.50, 1.81, -0.62, 1.17, 2, 'Shoulder' },
      { 1.44, 2.23, 0.16, 1.22, -1.17, -0.62, 2, 'Upper Arm' },
      { 0.85, 2.75, 1.22, 5.90, -2.93, -1.15, 3, 'Lower Arm' },
      { 0.95, 3.25, -2.20, -0.31, -1.09, 1.07, 2, 'Hip' },
      { 2.38, 3.18, -2.11, 1.37, -4.95, -1.09, 3, 'Lower Leg' },
    })),
    checks = { { 0.605, 1.359, 0.281 }, { -0.018, -1.286, 0.131 } } }
  -- skeletons: the frame bones (f) and the check bones (c) by node number (asset index bone_names; node k = bone k)
  local HULK_S = { { f = { 79 }, c = { 120, 135 } }, { f = { 79 }, c = { 120, 138 } } }                     -- cha_lieutenant, cha_lieutenant_assault
  local CHARGER_S = { { f = { 61 }, c = { 62, 79 } }, { f = { 72 }, c = { 73, 90 } }, { f = { 62 }, c = { 63, 80 } } }   -- cha_charger(_bull), _acid, _burrower
  local DEV_S = { { f = { 57, 145 }, c = { 58, 109 } }, { f = { 56, 87 }, c = { 57, 108 } } }               -- cha_soldier_heavy_weapon (boss, attach_shield), cha_soldier (boss, attach_l_hand)
  local DEV_S2 = { DEV_S[2], DEV_S[1] }
  local KNOWN = {   -- units the asset index names: their own skeleton first
    ['846bc06c6b213a06'] = HULK_S[1], ['b16493b009eec762'] = HULK_S[2],
    ['32cdeada234fb8df'] = HULK_S[1], ['1e66ee1f6f7fd00e'] = HULK_S[1], ['96ba14c9ebb49ce1'] = HULK_S[1], ['1897bdd32105d2dc'] = HULK_S[1],
    ['e44ec9f9b3fe1d2a'] = HULK_S[2], ['fd5247653c897803'] = CHARGER_S[1],
    ['1a7fcdff98c664b0'] = CHARGER_S[1], ['3aff5fd7d5450b99'] = CHARGER_S[1], ['6b202392f4ab605e'] = CHARGER_S[2], ['0ab7b92b131c228c'] = CHARGER_S[3],
  }
  -- (5.1 Test 1) the other models by type id (the game's entity or unit ids; the asset index gives each entity's unit)
  local BY_KIND = {}
  local function give(model, skels, ...) for _, h in ipairs({ ... }) do BY_KIND[h] = { model, skels } end end
  give(devastator('Heavy Devastator', 4), DEV_S, 'b92435fbf60f0748', '3d9c95bd03c0c7cf', 'f8b5a81a86d5d4eb', '793d676154cce8f9', 'b8a9c5e5ca2bed52', '9b9e22b1fbf4aead', '91ebd77931110afc')
  give(devastator('Incendiary MG Devastator', 5), DEV_S, '58b2b86c11369241')
  give(devastator('Conflagration Devastator', 4), DEV_S2, 'e0353177f1329573')
  give(IMPALER, { { f = { 65, 110 }, c = { 87, 120 } } }, 'dcf8e74212fbee3b')
  give(TITAN, { { f = { 93 }, c = { 134, 121 } } }, '9e2e17f2ccccafdd', 'ef04cb84d097a497')
  give(DRAGON, { { f = { 84 }, c = { 121, 115 } } }, '960b48a421a3faaa')
  give(TANK, { { f = { 25 }, c = { 35, 36 } } }, '00bcf8247a544cdc', 'c6449ffd9ea3779c', '63df3d07b7424588', '53d8919d7b8abd67', '31bae74d2f064d8d')
  give(CANNON_TURRET, { { f = { 17 }, c = { 20, 33 } } }, 'cecd6979cf7bb0f2', '8fb47dd28b398cf7', '2cf3488c4845f8bd', 'abdb2e2a0479d8ca', 'b8580cac32214fc0')
  give(autocannon_turret('Shredder turret', 5), { { f = { 16 }, c = { 17, 33 } } }, '49674794a165eda8')
  give(autocannon_turret('Anti-Air Emplacement', 4), { { f = { 16 }, c = { 17, 33 } } }, 'aeaef7a1851e6c9d')
  give(MORTAR, { { f = { 17 }, c = { 18, 28 } } }, '6293d7ab6e681855', 'ff5cc825b9571052')
  give(BARRAGER, { { f = { 16, 17 }, c = { 17, 15 } } }, '5d142c3a73ebc634')
  give(BUNKER, { { f = { 12 }, c = { 13, 18 } } }, '9926876b2375a1bb')
  give(FACTORY, { { f = { 90 }, c = { 156, 204 } } }, 'd37e8d120d2836e3', '30f2dee2333f227a', '8093204aea733daa')
  give(VOX, { { f = { 57 }, c = { 58, 87 } } }, 'bc242702fb46b7e7')
  give(WAR_STRIDER, { { f = { 38 }, c = { 63, 39 } } }, 'ef570293245a17c2')
  give(scout('Scout Strider', 0, 'Pilot'), { { f = { 35 }, c = { 36, 47 } } }, 'f8131632aa867107')
  give(scout('Reinforced Scout Strider', 4, 'Cabin'), { { f = { 35 }, c = { 36, 47 } } }, '9076eeed17fcee35')
  give(HARVESTER, { { f = { 85 }, c = { 86, 98 } } }, '965eae5a51acdd4a', 'd63fcbff0851b7af')
  give(GATEKEEPER, { { f = { 110 }, c = { 168, 142 } } }, '453fe22c634eb30f')
  give(VERACITOR, { { f = { 111 }, c = { 169, 143 } } }, '20b9c7734daead65')
  PARTS = { kinds = {}, units = {}, frames = {}, verdict = {}, lines = 0, bad = {}, aims = 0 }
  -- every listed Hulk and Charger (sub-faction and tier variants too: their skeleton is found by the checks); not the
  -- Hulks' arms, flag and jetpack, which are units of their own; then the other models by type id
  for k, a in pairs(ARMOR) do
    local n = a.name
    local model = (n:find('^Hulk') and not n:find('arm%)') and not n:find('flag') and not n:find('jetpack') and HULK)
      or (n:find('Charger') and CHARGER) or nil
    if model then
      local list = {}
      local own = KNOWN[hexr(k)]
      if own then list[1] = own end
      for _, s in ipairs(model == HULK and HULK_S or CHARGER_S) do if s ~= own then list[#list + 1] = s end end
      PARTS.kinds[k] = { model = model, skel = list }
    end
  end
  for h, m in pairs(BY_KIND) do PARTS.kinds[type_hash(h)] = { model = m[1], skel = m[2] } end
  local function now() return os.clock() end
  -- a bone's world place (or, with whole = true, its axes too) from the unit's pose array
  -- ((5.1.0 release review) 'into': a frame table to fill in place - the frames read every 30 ms reuse theirs)
  local function bone(pose, i, whole, into)
    local m = read(pose + 64 * i, 64)
    if not m then return nil end
    local x, y, z = f32(m, 48), f32(m, 52), f32(m, 56)
    if not (x == x and y == y and z == z and math.abs(x) < 1e6 and math.abs(y) < 1e6 and math.abs(z) < 1e6) then return nil end
    if not whole then return { x, y, z } end
    local B = into or { rows = { {}, {}, {} } }
    for r = 0, 2 do
      local a, b, c = f32(m, r * 16), f32(m, r * 16 + 4), f32(m, r * 16 + 8)
      local len = math.sqrt(a * a + b * b + c * c)
      if not (len > 0.5 and len < 2) then return nil end
      local R = B.rows[r + 1]
      R[1], R[2], R[3] = a / len, b / len, c / len
    end
    B[1], B[2], B[3] = x, y, z
    return B
  end
  local function loc(F, p)
    local dx, dy, dz = p[1] - F[1], p[2] - F[2], p[3] - F[3]
    local R = F.rows
    return dx * R[1][1] + dy * R[1][2] + dz * R[1][3], dx * R[2][1] + dy * R[2][2] + dz * R[2][3], dx * R[3][1] + dy * R[3][2] + dz * R[3][3]
  end
  -- (5.1 Test 1) a point given in a frame's axes, in the world
  local WP = { 0, 0, 0 }
  local function world(F, x, y, z)
    local R = F.rows
    WP[1] = F[1] + x * R[1][1] + y * R[2][1] + z * R[3][1]
    WP[2] = F[2] + x * R[1][2] + y * R[2][2] + z * R[3][2]
    WP[3] = F[3] + x * R[1][3] + y * R[2][3] + z * R[3][3]
    return WP
  end
  -- which skeleton this unit has (checked once per unit): the first whose check bones sit where the model says
  local function skeleton(unit, kind, pose)
    local u = PARTS.units[unit]
    if u and u.kind == kind and not (u.retry and now() >= u.retry) then u.seen = now(); return u.skel end
    local K = PARTS.kinds[kind]
    local found, unread = false, false
    for _, s in ipairs(K.skel) do
      local F = bone(pose, s.f[1], true)
      if not F then unread = true end
      if F then
        local ok = true
        for ci = 1, 2 do
          local q = bone(pose, s.c[ci])
          local e = K.model.checks[ci]
          if not q then ok = false; unread = true; break end
          local x, y, z = loc(F, q)
          if (x - e[1]) ^ 2 + (y - e[2]) ^ 2 + (z - e[3]) ^ 2 > 0.01 then ok = false; break end
        end
        if ok then found = s; break end
      end
    end
    -- ((5.0 release review) a bone that couldn't be read (a unit just spawned, its pose not filled in yet) is not an
    -- answer: main armor for now, and the skeleton is looked at again in a second)
    if not found and unread then
      PARTS.units[unit] = { kind = kind, skel = false, retry = now() + 1, unit_tries = u and u.unit_tries, seen = now() }
      return false
    end
    -- ((5.1.0 Test 1, my logs: "Harvester ... match no known skeleton" every Illuminate mission, while other
    -- Harvesters were judged by their parts fine - most likely one seen while it was still warping in, its bones not yet
    -- where they settle) a mismatch is looked at again 2 s later, 4 times, before the unit is judged by main armor for good.
    -- Test builds write where the check bones were (each kind once)
    if not found then
      local tries = ((u and u.unit_tries) or 0) + 1
      if TESTER and not (PARTS.bad_seen or {})[kind] then
        PARTS.bad_seen = PARTS.bad_seen or {}; PARTS.bad_seen[kind] = true
        local s = K.skel[1]
        local F = bone(pose, s.f[1], true)
        local got = {}
        for ci = 1, 2 do
          local q = F and bone(pose, s.c[ci])
          if q then local x, y, z = loc(F, q); got[#got + 1] = string.format('%.2f %.2f %.2f (model %.2f %.2f %.2f)', x, y, z, K.model.checks[ci][1], K.model.checks[ci][2], K.model.checks[ci][3]) end
        end
        event('part armor (test): ' .. K.model.name .. ' ' .. hexr(kind) .. ' check bones at ' .. (#got > 0 and table.concat(got, '; ') or 'unreadable') .. ' (first look)')
      end
      if tries < 5 then
        PARTS.units[unit] = { kind = kind, skel = false, retry = now() + 2, unit_tries = tries, seen = now() }
        return false
      end
    end
    PARTS.units[unit] = { kind = kind, skel = found, seen = now() }
    if not found and not PARTS.bad[kind] then
      PARTS.bad[kind] = true
      note('part armor: ' .. K.model.name .. ' type ' .. hexr(kind) .. ' - its bones match no known skeleton, so it is judged by its main armor')
    end
    return found
  end
  -- the frame bones of an enemy this frame (read at most every 30 ms per unit): a list, frame 1 first
  local function frame(c)
    local unit = c.ent and u32(c.ent, 12)
    if not unit or unit == 0 then return nil end
    local t = now()
    local F = PARTS.frames[unit]
    if F and F.kind == c.kind and t - F.t < 0.03 then return F.F end
    -- ((5.1.0 release review) a unit judged by its main armor for good, or waiting for its next look: nothing read)
    local u = PARTS.units[unit]
    if u and u.kind == c.kind and u.skel == false and not (u.retry and t >= u.retry) then u.seen = t; return nil end
    local root = unit_position(unit)
    if not (root and root.pose) then return nil end
    local s = skeleton(unit, c.kind, root.pose)
    -- ((5.1.0 release review) one table per unit, its frames filled in place)
    if not F then F = { bufs = {}, list = {} }; PARTS.frames[unit] = F end
    F.kind, F.t = c.kind, t
    local B
    if s then
      B = F.list
      for i, b in ipairs(s.f) do
        local buf = F.bufs[i]
        if not buf then buf = { rows = { {}, {}, {} } }; F.bufs[i] = buf end
        if not bone(root.pose, b, true, buf) then B = nil; break end
        B[i] = buf
      end
    end
    F.F = B
    return B
  end
  -- ((5.1.0 release review) old entries are dropped by age, every 20000 answers (decide and exposed together): what a
  -- gun has said about an enemy, units and frames, not looked at for 30 s)
  local function sweep(t)
    for g, W2 in pairs(PARTS.verdict) do
      for k2, V2 in pairs(W2) do if t - (V2.seen or 0) > 30 then W2[k2] = nil end end
      if next(W2) == nil then PARTS.verdict[g] = nil end
    end
    for g, E2 in pairs(PARTS.exp) do
      for k2, X2 in pairs(E2) do if t - (X2.seen or 0) > 30 then E2[k2] = nil end end
      if next(E2) == nil then PARTS.exp[g] = nil end
    end
    for k2, F2 in pairs(PARTS.frames) do if t - F2.t > 30 then PARTS.frames[k2] = nil end end
    for k2, U2 in pairs(PARTS.units) do if t - (U2.seen or 0) > 30 then PARTS.units[k2] = nil end end
  end
  local function tick_sweep(t)
    PARTS.n = (PARTS.n or 0) + 1
    if PARTS.n > 20000 then PARTS.n = 0; sweep(t) end
  end
  -- slab test of the segment a -> b (local coordinates) against a box: where it enters, and through which face
  -- ((5.0 release review) the face names made once, not a table and a string per axis per box per call)
  local FACE = { { 'x-', 'x+' }, { 'y-', 'y+' }, { 'z-', 'z+' } }
  local function enter(a, d, b)
    local t0, t1, face = 0, 1, nil
    for ax = 1, 3 do
      local lo, hi = b[ax * 2 - 1], b[ax * 2]
      if math.abs(d[ax]) < 1e-9 then
        if a[ax] < lo or a[ax] > hi then return nil end
      else
        local ta, tb = (lo - a[ax]) / d[ax], (hi - a[ax]) / d[ax]
        local side = 1
        if ta > tb then ta, tb, side = tb, ta, 2 end
        if ta > t0 then t0, face = ta, FACE[ax][side] end
        if tb < t1 then t1 = tb end
        if t0 > t1 then return nil end
      end
    end
    if not face then return nil end   -- (it starts inside the box)
    return t0, face
  end
  -- the first part the segment from the gun toward a world point meets: its armor and name ((5.0 release review) one
  -- function and reused tables instead of a closure and tables per call; (5.1) the segment is put in each frame's axes)
  local SA, SD = { { 0, 0, 0 }, { 0, 0, 0 } }, { { 0, 0, 0 }, { 0, 0, 0 } }
  local function try_meet(M, FR, from, p)
    for f = 1, M.nf or 1 do
      local A, D = SA[f], SD[f]
      A[1], A[2], A[3] = loc(FR[f], from)
      local px, py, pz = loc(FR[f], p)
      -- (the segment runs 1.5 times past the aim point: a shot doesn't stop where it was aimed)
      D[1], D[2], D[3] = (px - A[1]) * 1.5, (py - A[2]) * 1.5, (pz - A[3]) * 1.5
    end
    local best, bf, bb
    for _, b in ipairs(M.boxes) do
      local f = b.f or 1
      local tt, face = enter(SA[f], SD[f], b)
      if tt and (not best or tt < best) then best, bf, bb = tt, face, b end
    end
    if not best then return nil end
    local fc = bb.faces and bb.faces[bf]
    if fc then return fc[1], fc[2] end
    return bb[7], bb[8]
  end
  -- the part the line from 'from' toward 'aim' meets first: armor, part name, angle from behind (degrees); nil if
  -- it can't be worked out
  PARTS.meet = function(c, from, aim, want_angle)
    local K = PARTS.kinds[c.kind]
    local FR = frame(c)
    if not FR then return nil end
    local M = K.model
    local av, part
    -- ((5.1 Test 1) the game's aim point only when it is a real point near this enemy - within 15 m of its frame bone)
    if aim and aim[1] == aim[1] and aim[2] == aim[2] and aim[3] == aim[3]
      and (aim[1] - FR[1][1]) ^ 2 + (aim[2] - FR[1][2]) ^ 2 + (aim[3] - FR[1][3]) ^ 2 < 225 then
      av, part = try_meet(M, FR, from, aim)
    end
    if not av then
      local p = world(FR[1], M.aim[1], M.aim[2], M.aim[3])
      av, part = try_meet(M, FR, from, p)
    end
    if not av then return nil end
    if not want_angle then return av, part end
    -- angle between the gun's direction and straight behind (for the test builds' log)
    local ax, ay, az = loc(FR[1], from)
    local bk, h = M.back, math.sqrt(ax * ax + ay * ay + az * az)
    local ang = h > 0.01 and math.deg(math.acos(math.max(-1, math.min(1, (ax * bk[1] + ay * bk[2] + az * bk[3]) / h)))) or 0
    return av, part, ang
  end
  -- a short hold: a gun that could hurt an enemy keeps that answer for PARTS.HOLD (0.6 s) after its line last met a part it can hurt,
  -- so an enemy turning back and forth on the edge doesn't flip it every frame
  -- ((5.0 Test 21, my note: sentries "dont seem to consistently aim at the rear of chargers" - Test 20 log: guns 8-15 m up,
  -- coming down on a Charger's back, the answer flipped Butt <-> Rear Armor Plates 123 times) 0.6 s, was 0.25 s
  PARTS.HOLD = 0.6
  -- true: the line meets a part it can't hurt (skip); false: one it can (fire); nil: it can't be worked out (the
  -- whole-enemy rules decide, in cannot_hurt)
  PARTS.decide = function(dog, c, from, who, aim, pen)
    -- ((5.0 release review) the same gun asks about the same enemy several times a frame (its target pick, the no-shot
    -- list, the marker, the priority rules): the first answer this frame is kept, one for a look along its aim and one
    -- without. Answers are kept per gun, then per enemy - no key string made per call)
    local W = PARTS.verdict[who or dog.name]
    if not W then W = {}; PARTS.verdict[who or dog.name] = W end
    local V = W[c.id]
    if not V then V = {}; W[c.id] = V end
    if aim then
      if V.fa == FRAME then return V.ra end
    elseif V.fn == FRAME then return V.rn end
    local av, part, ang = PARTS.meet(c, from, aim, TESTER)
    V.seen = now()
    local K = PARTS.kinds[c.kind]
    -- ((5.0 Test 16, test builds) where the game really aims a gun at a modeled enemy, in the enemy's frame (frame bone
    -- axes): at most every 2 s per model and 6 lines per model, 60 in all ((5.1) every model, was Hulks and Chargers)
    if TESTER and aim and PARTS.aims < 60 then
      local tk = (PARTS.aim_t or {})[K.model.name]
      local tn = now()
      PARTS.aim_n = PARTS.aim_n or {}
      if (not tk or tn - tk > 2) and (PARTS.aim_n[K.model.name] or 0) < 6 then
        local FR = frame(c)
        if FR then
          PARTS.aim_t = PARTS.aim_t or {}; PARTS.aim_t[K.model.name] = tn
          PARTS.aim_n[K.model.name] = (PARTS.aim_n[K.model.name] or 0) + 1
          PARTS.aims = PARTS.aims + 1
          local x, y, z = loc(FR[1], aim)
          local gx, gy, gz = loc(FR[1], from)
          event(string.format('part aim (test): %s on %s %d: the game aims at %.2f %.2f %.2f in its frame, the gun at %.1f %.1f %.1f; the line meets %s',
            dog.name, K.model.name, c.id, x, y, z, gx, gy, gz, part and (part .. ' AV' .. av) or 'nothing'))
        end
      end
    end
    local t = now()
    local can
    if av then can = av <= pen end
    if can then
      V.last_can = t
    elseif V.last_can and t - V.last_can < PARTS.HOLD then
      can = true
    end
    local r
    if can == nil then
      r = nil   -- (not worked out, and no recent 'it can': the whole-enemy rules)
    else
      r = not can
      -- a change of answer is counted (and in test builds written out, at most 60); not the first look that says
      -- skip - that is what every gun says of every armored enemy facing it
      local first = V.can == nil
      if V.can ~= can and not (first and not can) then
        V.can = can
        local say = (av and (part .. ' AV' .. av) or 'part not found (held)') .. (can and ': fires' or ': skips')
        local name = (ARMOR[c.kind] and ARMOR[c.kind].name) or K.model.name
        bump(session.parts, string.format('%s on %s: %s', dog.name, name, say))
        if TESTER and PARTS.lines < 60 then
          PARTS.lines = PARTS.lines + 1
          local gl = ''
          if aim then
            local FR = frame(c)
            if FR then local x, y, z = loc(FR[1], aim); gl = string.format(', the game aims at %.2f %.2f %.2f in its frame', x, y, z) end
          end
          event(string.format('part check: %s on %s %d: %s%s%s', who and tostring(who) ~= dog.name and (dog.name .. ' ' .. tostring(who)) or dog.name,
            name, c.id, say, ang and string.format(' (%.0f deg from straight behind)', ang) or '', gl))
        end
      end
      if first then V.can = can end
    end
    tick_sweep(t)   -- (old answers are dropped now and then: the tables must not grow all session)
    if aim then V.fa, V.ra = FRAME, r else V.fn, V.rn = FRAME, r end
    return r
  end
  -- ((5.1.0 Test 1) Heavy Devastators: is the gun's line on its body rather than its shield? true while the line meets
  -- any part but the Shield, and for PARTS.HOLD after (so it doesn't flip between bursts and full auto as it turns);
  -- false when the shield is in the way or it can't be worked out (short bursts, as before). The first answer each frame
  -- is kept per gun and enemy; a change is counted (and written out in test builds, with the part checks' limit)
  PARTS.exp = {}
  PARTS.exposed = function(dog, c, from, who, aim)
    if not (from and c.kind and PARTS.kinds[c.kind]) then return false end
    local key = who or dog.name
    local E = PARTS.exp[key]
    if not E then E = {}; PARTS.exp[key] = E end
    local X = E[c.id]
    if not X then X = {}; E[c.id] = X end
    if X.f == FRAME then return X.r end
    local ok, av, part = pcall(PARTS.meet, c, from, aim)
    local t = now()
    X.seen = t
    if ok and av and part ~= 'Shield' then X.last = t end
    local r = X.last ~= nil and t - X.last < PARTS.HOLD
    if r ~= X.was then
      if X.was ~= nil or r then
        bump(session.parts, string.format('%s on %s: %s', dog.name, (ARMOR[c.kind] and ARMOR[c.kind].name) or '?', r and 'body open: full auto' or 'shield in the way: short bursts'))
        if TESTER and PARTS.lines < 60 then
          PARTS.lines = PARTS.lines + 1
          event(string.format('part check: %s on %s %d: %s (%s)', who and tostring(who) ~= dog.name and (dog.name .. ' ' .. tostring(who)) or dog.name,
            (ARMOR[c.kind] and ARMOR[c.kind].name) or '?', c.id, r and 'body open: full auto' or 'shield in the way: short bursts',
            ok and av and (part .. ' AV' .. av) or 'part not found'))
        end
      end
      X.was = r
    end
    X.f, X.r = FRAME, r
    tick_sweep(t)
    return r
  end
end

-- switched on by the optional 'Armor skipping' part of the mod (a tiny second addon that sets this flag); read
-- every frame, so load order does not matter
-- ((5.0 Test 12) from = the gun's muzzle (or the dog), who = which gun (a sentry's id; a dog's name), aim = where the
-- game is aiming it now, if this enemy is its target: with them, an enemy with a part model is judged by the part the
-- line of fire meets; without them, or when that can't be worked out, by the whole-enemy rules as before)
-- ((5.1 Test 1) the part answer comes first; the whole-enemy rules (the main armor) are the fallback when the part can't be
-- worked out. Heavy Devastators are never skipped: see a.burst below)
local armor_state
local function cannot_hurt(dog, c, from, who, aim)
  local on = rawget(_G, 'SmarterGuardDogsArmor') == true
  if on ~= armor_state then armor_state = on; note('armor intelligence: ' .. (on and 'on' or 'off (option not installed)')) end
  if not on or not c.kind then return false end
  local a = ARMOR[c.kind]
  if not a then return false end
  if a.sentries_skip and dog.sentry then return true end         -- dropships: no sentry shoots them
  -- ((5.1.0 Test 1, my ask: "guard dog should still fire short bursts at the heavy devastator, the point is
  -- suppression"; "dont have any of the sentries hold fire on the heavy devastators, it should fire short bursts to keep
  -- them surpressed and then if its turned around it should go full auto") no gun skips a Heavy Devastator: the guns
  -- that fire short bursts (the Guard Dog, the machine gun and Gatling sentries) burst while its shield is in the way and
  -- go full auto while its back is turned (PARTS.exposed); the rest fire on it as before
  if a.burst then return false end
  local pen = dog.pen or PEN[dog.name] or 99
  if a.av <= pen then return false end
  if from and PARTS.kinds[c.kind] then
    local ok, r = pcall(PARTS.decide, dog, c, from, who, aim, pen)
    if ok then
      if r ~= nil then return r end
    else
      if not PARTS.failed then PARTS.failed = true; note('part armor stopped (error): ' .. tostring(r)) end
      PARTS.kinds = {}   -- (back to the whole-enemy rules for every enemy)
    end
  end
  if a.open then return false end                                 -- (5.1) Gatekeeper, Veracitor: shot at as before
  if a.legs and a.legs <= pen then return false end
  return true
end
laser.cannot_hurt = cannot_hurt   -- ((5.0 Test 10) for the dogs' markers (engine_laser.lua comes first)
-- ((5.1.0 Test 1) short bursts while the shield is in the way (or the part can't be worked out); full auto while its
-- line meets the body - turned around, or the shield held aside: see PARTS.exposed)
local function burst_only(dog, c, from, aim)
  local a = c.kind and rawget(_G, 'SmarterGuardDogsArmor') == true and ARMOR[c.kind]
  if not (a and a.burst and dog.name == 'Guard Dog') then return false end
  return not PARTS.exposed(dog, c, from, dog.name, aim)
end
-- (4.0.6) a Heavy Devastator shows up in the target list as more than one entry - its body and its shield (and the
-- variants' parts) - and the game can pick any of them. Resting only the entry that was just fired at let the dog (or
-- a sentry) switch to the shield or body of the same Devastator and keep firing, so the short bursts turned into
-- continuous fire. So a rest covers every short-burst entry within 3 m of the one fired at: the whole Devastator.
local function rest_parts(rest, candidates, current, until_t)
  rest[current.id] = until_t
  local p = current.pos
  if not p then return 0 end
  local n = 0
  for _, c in ipairs(candidates) do
    local q = c.pos
    if c ~= current and q and c.kind and (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2 < 9 then
      local a = ARMOR[c.kind]
      if a and a.burst then rest[c.id] = until_t; n = n + 1 end
    end
  end
  return n
end

-- ======================================================================================================
-- Deciding: fast switching (Rover) and player safety (all dogs)
-- ======================================================================================================
-- (4.6.3) the names other files use are declared here; the rest of this file sits in a do-block so its own
-- helpers stop counting toward Lua's 200 locals of the main chunk once the file ends
local SAFE, dot3, segment_distance, M, TEAM, P, PRIORITY, union, plan, BLANK, hidden, hider_restore, hider_apply, restore, apply, steer
do
local FAST = { fire = 0.5, lock = 0.5, recent = 8, recent_seconds = 3.0, near = 20, reach = 35 }
-- (4.6.7 Test 2, my note: the Rover hesitated) fire 0.15 -> 0.5 s, as the Laser Sentry's: each switch costs it a
-- fresh line-up (about half a second), so after only 0.15 s of beam it spent about half its time lining up (sim: firing
-- 48% -> 67% of the time in a fight, 36% -> 57% surrounded). 'lock' is now checked against P.fire_step, its time in
-- its firing step whether or not in step with its aim (P.lock, which still counts its line-up too, is for the no-shot
-- rule): counted from the start of the line-up, a line-up over 0.5 s was cut short before the first shot and it never
-- fired. 'switch_after_lock' now means it fired 0.5 s without being in step with its aim
-- The Rover spreads its fire: once an enemy is alight it moves on to one within 'reach' meters that it hasn't
-- set alight in the last 'recent_seconds' (it remembers its last 'recent' targets). Only when there is no such
-- enemy (the last one nearby, or every other one already burning) does it keep firing at the one it is on.
SAFE = { body_bottom = 0.2, body_top = 1.75, aim_heights = { 0.0, 0.5 } }

local function sub3(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function dot3(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
-- shortest distance between segments p1-q1 and p2-q2 (plain numbers throughout: it runs for every enemy and every
-- protected body each frame, so it makes no tables)
local mmin, mmax = math.min, math.max
function segment_distance(p1, q1, p2, q2)
  local d1x, d1y, d1z = q1[1] - p1[1], q1[2] - p1[2], q1[3] - p1[3]
  local d2x, d2y, d2z = q2[1] - p2[1], q2[2] - p2[2], q2[3] - p2[3]
  local rx, ry, rz = p1[1] - p2[1], p1[2] - p2[2], p1[3] - p2[3]
  local a = d1x * d1x + d1y * d1y + d1z * d1z
  local e = d2x * d2x + d2y * d2y + d2z * d2z
  local f = d2x * rx + d2y * ry + d2z * rz
  -- ((5.1.5 Test 19) the clamps as min/max, not a little function or branches: LuaJIT kept starting traces in the old
  -- clamp function and giving up (1,234 times in a 6 s big-fight sim, by the new compile counter), and the branches
  -- written out gave it side exits it couldn't compile either; min/max compile to plain instructions
  local s, t
  if a <= 1e-9 and e <= 1e-9 then s, t = 0, 0
  elseif a <= 1e-9 then s, t = 0, mmax(0, mmin(1, f / e))
  else
    local c = d1x * rx + d1y * ry + d1z * rz
    if e <= 1e-9 then s, t = mmax(0, mmin(1, -c / a)), 0
    else
      local b = d1x * d2x + d1y * d2y + d1z * d2z
      local den = a * e - b * b
      s = den ~= 0 and mmax(0, mmin(1, (b * f - c * e) / den)) or 0
      t = (b * s + f) / e
      if t < 0 then t, s = 0, mmax(0, mmin(1, -c / a)) elseif t > 1 then t, s = 1, mmax(0, mmin(1, (b - c) / a)) end
    end
  end
  local x = (p1[1] + d1x * s) - (p2[1] + d2x * t)
  local y = (p1[2] + d1y * s) - (p2[2] + d2y * t)
  local z = (p1[3] + d1z * s) - (p2[3] + d2z * t)
  return math.sqrt(x * x + y * y + z * z)
end

-- ------------------------------------------------------------------------------------------------------
-- Where the dog will be a moment from now. It flies to a fixed spot beside you (learned here in your own
-- frame), so when you spin quickly its spot swings around and the dog follows it: every point along that
-- swing is checked, not just where the dog is at this instant.
-- ------------------------------------------------------------------------------------------------------
-- the look-ahead only kicks in for genuinely fast turns (about 85+ degrees a second): during ordinary movement
-- the dog repositions a lot, and checking its whole path then flagged enemies that were never in the way
local MOTION = { steady_turn = 0.6, steady_move = 1.5, fast_turn = 1.5, fast_keep = 0.6, spin_min = 1.5,
  lookahead = { 0.12 }, arc = { 0.25, 0.5, 0.75, 1.0 }, ahead_after = 0.5, arc_max = 1.0 }
M = {}
local TAU = 2 * math.pi
local function wrap(a) a = (a + math.pi) % TAU; return a - math.pi end
local function heading(v) return math.atan2(v[2], v[1]) end
local function axes_heading(axes)
  for _, ax in ipairs(axes) do if ax[1] * ax[1] + ax[2] * ax[2] > 0.5 then return heading(ax) end end
end
local function around(P, angle, radius, height) return { P[1] + radius * math.cos(angle), P[2] + radius * math.sin(angle), P[3] + height } end

local function dog_positions(st)
  local P, D = st.player_pos, st.drone_pos
  local out = { D }
  local t = os.clock()
  if st.key ~= M.key then M = { key = st.key, turn = 0, spin = 0 } end
  local o = sub3(D, P)
  local ang, yaw = heading(o), P.axes and axes_heading(P.axes)
  local dt = M.t and t - M.t or 0
  local rel_speed = 0
  if dt > 0.001 and dt < 0.5 then
    M.spin = 0.5 * M.spin + 0.5 * wrap(ang - M.ang) / dt
    if yaw and M.yaw then M.turn = 0.5 * M.turn + 0.5 * wrap(yaw - M.yaw) / dt end
    local d = sub3(o, M.o); rel_speed = math.sqrt(dot3(d, d)) / dt
  end
  M.t, M.ang, M.yaw, M.o = t, ang, yaw, o
  local r0 = math.sqrt(o[1] * o[1] + o[2] * o[2])
  -- (4.5.3 Test 9) a slow dog (Guard Dog, K-9) gets the look-ahead at all times except the early part of its line-up
  -- (4.6.3 review: the comment said only late line-up and firing; the code, tested in game, also keeps it while it has
  -- no target or is in any other step): early in its line-up it isn't about to shoot, and checked then it hid nearly every enemy whenever you
  -- turned, each hide restarting its slow line-up (a tester's log: the Guard Dog fired 7% of the time it had a
  -- target, every hold in its lining-up step). Left off for the whole line-up, it fired through you more in the
  -- simulator (it starts firing while still swinging round). Its line from where it is now is always checked, and the
  -- Rover, which fires as it turns, keeps the look-ahead throughout
  local ahead = st.dog.fast or st.node ~= 6 or (st.lineup_acc or 0) >= (st.dog.ahead_after or MOTION.ahead_after)
  -- 1) the spot it is flying to, and the swing from here to there
  if P.axes then
    local ax = P.axes
    local here = { dot3(o, ax[1]), dot3(o, ax[2]), dot3(o, ax[3]) }
    if math.abs(M.turn) < MOTION.steady_turn and rel_speed < MOTION.steady_move then
      if M.spot then for i = 1, 3 do M.spot[i] = M.spot[i] * 0.9 + here[i] * 0.1 end else M.spot = here end
    end
    if math.abs(M.turn) > MOTION.fast_turn then M.fast_until = t + (st.dog.safety_keep or MOTION.fast_keep) end
    local L = M.spot
    local size = L and math.sqrt(dot3(L, L)) or 0
    if ahead and size > 1 and size < 10 and t < (M.fast_until or 0) then
      local S = { P[1] + ax[1][1] * L[1] + ax[2][1] * L[2] + ax[3][1] * L[3],
                  P[2] + ax[1][2] * L[1] + ax[2][2] * L[2] + ax[3][2] * L[3],
                  P[3] + ax[1][3] * L[1] + ax[2][3] * L[2] + ax[3][3] * L[3] }
      local gap = sub3(S, D)
      if dot3(gap, gap) > 0.25 then
        local so = sub3(S, P)
        local a1, r1 = heading(so), math.sqrt(so[1] * so[1] + so[2] * so[2])
        local da = wrap(a1 - ang)
        -- (4.5.3 Test 15) only the first arc_max radians (about 57 degrees) of its swing around you: 0.7 let it fire through
        -- you on a 180-degree flick in the simulator (2-3 frames), 1.0 doesn't:
        -- the whole way round to its spot took in points well behind you, from where an enemy straight ahead lined up
        -- through you - a tester's Guard Dog held fire on an enemy in front of them while it was on their right
        local fmax = math.abs(da) > MOTION.arc_max and MOTION.arc_max / math.abs(da) or 1
        for _, f in ipairs(MOTION.arc) do
          local g = f * fmax
          out[#out + 1] = around(P, ang + da * g, r0 + (r1 - r0) * g, o[3] + (so[3] - o[3]) * g)
        end
        if fmax == 1 then out[#out + 1] = { (D[1] + S[1]) / 2, (D[2] + S[2]) / 2, (D[3] + S[3]) / 2 } end   -- in case it cuts straight across
      end
    end
  end
  -- 2) wherever its current swing carries it next
  if ahead and math.abs(M.spin) > MOTION.spin_min then
    for _, dt2 in ipairs(MOTION.lookahead) do
      local turn = math.max(-math.pi, math.min(math.pi, M.spin * dt2))
      out[#out + 1] = around(P, ang + turn, r0, o[3])
    end
  end
  return out
end

-- teammates (version 3): the same body check against the other players' helldivers. Their positions arrive
-- over the network a little late, so their body is a bit wider and also checked where they are heading.
TEAM = { margin = 0.1, lead = 0.2, reach = 90 }

-- the bodies to keep out of the line of fire: you, then each teammate near enough to matter
-- (Testers, 5.0 Test 9, my ask: "rover and seaf troops is better, but not 100%") while the dog fires, any SEAF soldier
-- or civilian within 0.6 m of its line to its target is logged (at most once a second, 15 a session): how close, how far
-- from the dog, whether the mod was hiding that target from it and the dog's AI step - to see what still gets through
SGD.dog_seaf_check = function(st, req, t)
  if st.node ~= 7 or st.target == 0 or not TEAM.seaf_bodies then return end
  local S = session.team
  if (S.seaf_close_notes or 0) >= 15 or t < (S.seaf_close_next or 0) then return end
  local D, to = st.drone_pos, nil
  for _, c in ipairs(st.candidates) do if c.id == st.target and c.pos then to = { c.pos[1], c.pos[2], c.pos[3] + 0.5 } end end
  local fb = to and D and TEAM.seaf_bodies(os.clock(), st.player_pos)
  if not fb then return end
  for _, b in ipairs(fb) do
    if not b.lead then
      local d = segment_distance(D, to, b.lo, b.hi)
      if d < 0.6 then
        S.seaf_close_notes, S.seaf_close_next = (S.seaf_close_notes or 0) + 1, t + 1
        local a = b.at
        event(string.format('dog SEAF (test): %s firing at %d with %s %.2f m from its line, %.1f m from the dog, %.1f m from the enemy; hidden from it: %s',
          st.dog.name, st.target, b.civ and 'a civilian' or 'a SEAF soldier', d, math.sqrt((a[1] - D[1]) ^ 2 + (a[2] - D[2]) ^ 2 + (a[3] - D[3]) ^ 2),
          math.sqrt((a[1] - to[1]) ^ 2 + (a[2] - to[2]) ^ 2), (req and req.block and req.block[st.target]) and 'yes (the game kept firing)' or 'no'))
        return
      end
    end
  end
end
local function bodies_of(st)
  local me = st.player_pos
  -- (you only with the Safety option on; teammates with the Teammate safety option on)
  local out = {}
  if OPT.safety() then out[1] = { lo = { me[1], me[2], me[3] + SAFE.body_bottom }, hi = { me[1], me[2], me[3] + SAFE.body_top }, at = me, extra = 0 } end
  local D = st.drone_pos
  -- (4.7.0 SEAF Safety, my note: the guard dogs too) the SEAF soldiers and civilians the sentry code keeps track of
  -- (TEAM.seaf_bodies, set there: their places read twenty times a second (Test 9; ten before), with a look-ahead when they move). Only those
  -- within the dog's reach of it; the option off or none around: nil
  local fb = TEAM.seaf_bodies and TEAM.seaf_bodies(os.clock(), me)
  if fb then
    for _, b in ipairs(fb) do
      local a = b.at
      if (a[1] - D[1]) ^ 2 + (a[2] - D[2]) ^ 2 < TEAM.reach ^ 2 then out[#out + 1] = b end
    end
  end
  for _, m in ipairs(st.mates or {}) do
    if (m[1] - D[1]) ^ 2 + (m[2] - D[2]) ^ 2 < TEAM.reach ^ 2 then
      out[#out + 1] = { lo = { m[1], m[2], m[3] + SAFE.body_bottom }, hi = { m[1], m[2], m[3] + SAFE.body_top }, at = m, extra = TEAM.margin, mate = true }
      local v = m.vel
      if v and v[1] * v[1] + v[2] * v[2] > 1 then
        local a = { m[1] + v[1] * TEAM.lead, m[2] + v[2] * TEAM.lead, m[3] + v[3] * TEAM.lead }
        out[#out + 1] = { lo = { a[1], a[2], a[3] + SAFE.body_bottom }, hi = { a[1], a[2], a[3] + SAFE.body_top }, at = a, extra = TEAM.margin, mate = true }
      end
    end
  end
  return out
end

-- enemies the dog must not shoot right now because you (or a teammate) are in the way, now or in a moment
-- ((4.6.4 review) the aim points at each height are set once per enemy into tables kept for good: they were made
-- anew inside the loop over dog positions x bodies x heights, thousands of tables a frame in a big fight)
local AIM_PTS = {}
local function unsafe_enemies(st)
  local U, count = {}, 0
  st.unsafe_why, st.safe_gap = {}, {}
  local me, dog = st.player_pos, st.dog
  if not (me and st.drone_pos) then return U, 0 end
  local spots = dog_positions(st)
  local bodies = bodies_of(st)
  local radius = dog.radius or 0.4
  local D0 = st.drone_pos
  for _, c in ipairs(st.candidates) do
    local p = c.pos
    -- (only enemies the dog could pick: dead ones and entries of no interest are skipped, saving most of the work)
    if p and (c.alive or c.mask == '    ' or c.id == st.target) then
      local closest, why = math.huge, nil
      -- a teammate farther from the dog than the enemy (plus the dog's swing and a body height) can't be in between
      local reach2 = (math.sqrt((p[1] - D0[1]) ^ 2 + (p[2] - D0[2]) ^ 2 + (p[3] - D0[3]) ^ 2) + 8) ^ 2
      local heights = SAFE.aim_heights
      for k = 1, #heights do
        local q = AIM_PTS[k]
        if not q then q = {}; AIM_PTS[k] = q end
        q[1], q[2], q[3] = p[1], p[2], p[3] + heights[k]
      end
      for bi, b in ipairs(bodies) do
        local a = b.at
        if not (b.mate or b.seaf) or (a[1] - D0[1]) ^ 2 + (a[2] - D0[2]) ^ 2 + (a[3] - D0[3]) ^ 2 < reach2 then
          for i, D in ipairs(spots) do
            for k = 1, #heights do
              local d = segment_distance(D, AIM_PTS[k], b.lo, b.hi) - b.extra
              if d < closest then closest = d end
            end
            if dog.chain then
              -- arcs jump onward from the target: unsafe if someone stands just past it, as seen from the dog
              local vx, vy = p[1] - D[1], p[2] - D[2]
              local wx, wy, wz = a[1] - p[1], a[2] - p[2], a[3] + 1.0 - p[3]
              if vx * wx + vy * wy > 0 and math.sqrt(wx * wx + wy * wy + wz * wz) < dog.chain then
                closest = 0; why = why or ('arc would chain to ' .. (b.civ and 'a civilian' or b.seaf and 'a SEAF soldier' or b.mate and 'a teammate' or 'you'))
              end
            end
            if closest < radius then
              if TESTER and i > 1 and not why then st.unsafe_from = st.unsafe_from or {}; st.unsafe_from[c.id] = D end
              local who = b.civ and 'a civilian' or b.seaf and 'a SEAF soldier' or b.mate and 'a teammate'
              why = why or (i == 1 and (who and (who .. ' is in its line of fire') or 'you are in its line of fire')
                or (who and (who .. ' would be in its line after the turn') or 'you would be in its line after the turn'))
              break
            end
          end
          if closest < radius then break end
        end
      end
      st.safe_gap[c.id] = closest
      if closest < radius then U[c.id] = true; count = count + 1; st.unsafe_why[c.id] = why end
    end
  end
  return U, count
end

P = {}   -- per-dog policy memory
local stuck_logged
local function reset_policy(key) P = { key = key, target = 0, fire = 0, lock = 0, last = nil, recent = {}, hold = nil, kicked = nil, ignored = 0, stuck = {},
  lineup = {}, noshot = {} } end
reset_policy(nil)

local function remember(id, t)
  for i = #P.recent, 1, -1 do if P.recent[i].id == id then table.remove(P.recent, i) end end
  P.recent[#P.recent + 1] = { id = id, t = t }
  while #P.recent > FAST.recent do table.remove(P.recent, 1) end
end
local function recently(id, t)
  for _, r in ipairs(P.recent) do if r.id == id and t - r.t < FAST.recent_seconds then return r.t end end
  return nil
end

-- best other enemy to switch to (nil if none)
local function pick_other(st, U, t, from)
  local pool = {}
  for _, c in ipairs(st.candidates) do
    if c.eligible and c.id ~= st.target and not U[c.id] then pool[#pool + 1] = c end
  end
  if #pool == 0 then return nil end
  -- prefer enemies near the dog when the one it is leaving was far away
  if from and from.d2 and from.d2 > FAST.near ^ 2 then
    local near = {}
    for _, c in ipairs(pool) do if c.d2 and c.d2 <= FAST.near ^ 2 then near[#near + 1] = c end end
    if #near > 0 then pool = near end
  end
  -- skip enemies hit in the last few seconds while others are available (their burn is still ticking)
  local fresh = {}
  for _, c in ipairs(pool) do if not recently(c.id, t) then fresh[#fresh + 1] = c end end
  if #fresh > 0 then pool = fresh end
  local best, bestd
  local me = st.player_pos
  for _, c in ipairs(pool) do
    local d
    if st.dog.fast and me and c.pos then
      -- the Rover lights the unlit enemies closest to you first
      d = (c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + (c.pos[3] - me[3]) ^ 2
    elseif from and from.pos and c.pos then d = (c.pos[1] - from.pos[1]) ^ 2 + (c.pos[2] - from.pos[2]) ^ 2 + (c.pos[3] - from.pos[3]) ^ 2
    else d = c.d2 or math.huge end
    if #fresh == 0 then d = (recently(c.id, t) or 0) * 1e9 + d end   -- all recent: oldest first
    if not best or d < bestd then best, bestd = c, d end
  end
  return best
end

PRIORITY = { range = 25, band = 3, linger = 0.4, urgent = 10 }   -- meters from you / extra meters / seconds /
-- while the dog is already shooting, it is only pulled off for a closer enemy that is within 'urgent' meters of you;
-- otherwise it finishes its burst and its next pick (within a second) is the closer one
local COVER = true            -- hide enemies the dog has lost sight of
local BURST = { fire = 1.0, rest = 3.0 }   -- Guard Dog vs Heavy Devastators: fire this long, then leave it this long
local RANGE_SLACK = 2         -- meters past a dog's range before an enemy counts as out of range
local COVER_GRACE = 0.6       -- ...but its current target only once it has been out of sight ~0.4 s (the game's
                              -- memory of it runs from 1 down to 0 in about a second), so an enemy that just
                              -- passes behind something for a moment doesn't make the dog start over
local CALM_SECONDS = 0.5      -- at most one optional redirect (closer threat, out of sight) per this long
local UNSAFE_LINGER = 0.4     -- an enemy stays hidden this long after it was last in line with you
local ENGAGE = { every = 0.25, tries = 3, pause = 1.0 }   -- 3.0: no target but something shootable in sight: pick now
local HOLD_SECONDS = 0.25     -- how long a forced re-selection may take before we try again
local BACKOFF_SECONDS = 1.0   -- slow down after the dog ignores two redirects in a row
-- closest first, but never at the cost of not shooting at all: after it is pulled to a closer enemy, the next
-- such pull waits until it has fired at its target for 'burst' seconds (or that target is gone, or 'timeout'
-- passes); and if it has not fired for 'after' seconds it is left to finish lining up on its current target.
-- It then goes back to closest first and catches up with the closer enemies.
local COMMIT = { after = 1.0, burst = 0.6, timeout = 4.0 }
-- ((5.1.5 Test 5) the damage check: seconds of firing without its target's health going down (the Rover's beam hurts at
-- once), and how long that enemy is then left alone (longer the second time)
local DOG_NODMG = { wait = 1.0, rover = 0.8, hide = 4.0, hide2 = 10.0, notes = 0 }
-- no shot: an enemy the dog keeps lining up without ever firing at (the game still lists it, but the dog can't
-- get a shot: e.g. an enemy stuck under the map). Line-up time on it adds up over repeated picks; once it passes
-- the limit the enemy rests hidden for a while so the dog moves on. The Guard Dog and K-9 get longer (a Guard
-- Dog was seen lining up a Berserker for ~3 s before firing normally).
-- (beyond 'far_m' from the dog the Guard Dog and K-9 get the short limit too: far line-ups rarely end in a shot)
-- line-up time without a shot before an enemy is set aside (3.0: shortened on a tester's call, for fewer pauses on
-- enemies it can't reach): Rover 1 s; Guard Dog/K-9 1 s beyond 25 m and 2 s closer (they line up slower); and the
-- current pick must have had at least 'fair' seconds of it in one go (so line-ups cut short by the mod's own
-- switching don't add up to setting everything aside)
local NOSHOT = { rover = 1.0, far = 1.0, other = 2.0, fair = 0.6, far_m = 25, rest = 4.0, forget = 5.0,
  -- ((5.0 Test 17, my note: the Rover "didnt properly prioritize enemies closer to me, and was actually avoiding one for a
  -- while" - a Test 16 log: a Bile Warrior 9 m from him set aside for 4 s after a 1 s line-up) an enemy within 'near_m' of
  -- you is a threat: it gets 'near' seconds of line-up before it is set aside, and then only for 'near_rest'
  near_m = 15, near = 2.0, near_rest = 1.5,
  -- (an enemy set aside again within 'again' seconds gets the full rest: one it truly can't reach - stuck under the map
  -- right next to you - must not hold the dog for good)
  again = 15 }

-- ((4.6.4 review) without packing the sets into a table first: one less table per call, several per frame)
function union(...)
  local out = {}
  for i = 1, select('#', ...) do
    local set = select(i, ...)
    if set then for id in pairs(set) do out[id] = true end end
  end
  return out
end

-- first few target losses go to the log with the dog's AI step, to confirm what the game does on a kill
local lost_logged = 0
local function note_lost(st, how)
  if lost_logged >= 6 then return end
  lost_logged = lost_logged + 1
  event(string.format('target lost: %s, %s (AI step %d, %.2fs left on its timer)', st.dog.name, how, st.node,
    math.max(0, st.deadline - st.now) / 1e6))
end

-- the first target changes of each dog also go to the log, with what had become of the old target
local change_logged = {}
local function note_change(st, old, held)
  local n = change_logged[st.dog.name] or 0
  if old == 0 or n >= 8 then return end
  change_logged[st.dog.name] = n + 1
  local c
  for _, x in ipairs(st.candidates) do if x.id == old then c = x end end
  local what = not c and 'gone from its list' or string.format('%s, %s, score %.2f',
    c.alive and 'valid' or 'not valid', c.eligible and 'pickable' or 'not pickable', c.score or -1)
  event(string.format('target change: %s %d -> %d after %.1fs; old target %s; AI step %d; %.2fs left on timer',
    st.dog.name, old, st.target, held or 0, what, st.node, (st.deadline - st.now) / 1e6))
end

-- the enemies the Rover hit in the last few seconds (their burn is still ticking)
local function recent_set(t)
  local set = {}
  for _, r in ipairs(P.recent) do if t - r.t < FAST.recent_seconds then set[r.id] = true end end
  return set
end
-- ((4.6.7 review) out of plan(): a closure made every frame kept LuaJIT from compiling plan()
local function dog_kick(st, t, hide, block, reason)
  -- a repeat for the same target means the dog ignored the last redirect
  -- (a nudge after a kill, with no target set, doesn't count: there is nothing to have ignored)
  -- ((4.6.6 review) the same ask again: another reason starts the count over, and a safety stop never backs off - it
  -- is asked again every HOLD_SECONDS while the target is unsafe, as a back-off left the dog free to fire through you)
  if st.target ~= 0 and P.kicked == st.target and P.kick_reason == reason then P.ignored = P.ignored + 1 else P.kicked, P.ignored, P.kick_reason = st.target, 0, reason end
  if P.ignored >= 2 and not reason:find('^safety') then
    -- it keeps ignoring us: keep the enemies hidden but stop forcing re-selection for a while
    P.kicked, P.ignored = nil, 0
    if reason == 'cannot_hurt' then
      -- some enemies (seen with armored striders) stay the dog's target however often we hide them; pulling
      -- it off again and again only makes it start over each time, so stop redirecting it off that one (it
      -- stays hidden, so the dog still drops it whenever the game lets it)
      P.stuck[st.target] = true
      local c
      for _, x in ipairs(st.candidates) do if x.id == st.target then c = x end end
      local k = c and c.kind and hexr(c.kind) or '?'
      stuck_logged = stuck_logged or {}
      if not stuck_logged[k] then
        stuck_logged[k] = true
        local a = c and c.kind and ARMOR[c.kind]
        event(string.format('cannot steer: the %s keeps returning to %s (type %s); left to the game', st.dog.name, a and a.name or '?', k))
      end
      return { block = hide, kick = false, reason = reason }
    end
    P.hold = { target = st.target, block = block, until_t = t + BACKOFF_SECONDS, reason = reason }
    stats.ignored_redirects = stats.ignored_redirects + 1
    bump(session.actions, 'backing_off')
    if stats.ignored_redirects <= 20 then event(string.format('backing off: %s ignored two redirects (target %d)', st.dog.name, st.target)) end   -- ((4.6.7 review) capped)
    return { block = union(block, hide), kick = false, reason = reason }
  end
  P.hold = { target = st.target, block = block, until_t = t + HOLD_SECONDS, reason = reason }
  P.last_kick_t = t
  if reason == 'out_of_sight' then P.cover_t, P.cover_enemy, P.cover_step = t, st.target, st.node end
  if reason:find('^safety') then P.safety_t, P.safety_enemy, P.safety_step, P.safety_now = t, st.target, st.node, (st.unsafe_why[st.target] or ''):find('after the turn') == nil end
  return { block = union(block, hide), kick = true, reason = reason }
end

-- returns { block = set of enemy ids to hide from the dog, kick = force a re-selection now, reason = text }
function plan(st)
  local t = os.clock()
  if st.key ~= P.key then reset_policy(st.key) end
  local dt = P.last and math.min(math.max(t - P.last, 0), 0.25) or 0
  P.last = t
  if st.target ~= P.target then
    note_change(st, P.target, P.target_since and t - P.target_since)
    for _, c in ipairs(st.candidates) do
      if TESTER and c.id == st.target and c.kind then
        local k = hexr(c.kind) .. (LABELS[c.kind] and (' ' .. LABELS[c.kind]) or '')
        if session.types[k] or next(session.types) == nil or #session.type_list < 40 then
          if not session.types[k] then session.type_list[#session.type_list + 1] = k end
          session.types[k] = (session.types[k] or 0) + 1
        end
      end
    end
    -- (Tester: how long each line-up takes to the first shot, and how many end before one)
    if TESTER then
      local d = session.dog_time[st.dog.name]
      if d and P.lu_t and P.target ~= 0 then d.lu_cut = (d.lu_cut or 0) + 1 end
      P.lu_t = st.target ~= 0 and t or nil
    end
    P.target, P.fire, P.lock, P.target_since, P.fire_step = st.target, 0, 0, t, 0
  end
  local attacking = st.target ~= 0 and (st.node == 6 or st.node == 7)
  -- ((4.6.7 review) an ask it obeyed is not counted as ignored when it later comes back to that enemy)
  if P.kicked and st.target ~= 0 and st.target ~= P.kicked then P.kicked, P.ignored = nil, 0 end
  if attacking then P.lock = P.lock + dt end
  if attacking and st.node == 7 then P.fire_step = (P.fire_step or 0) + dt end
  if TESTER and P.lu_t and st.node == 7 then
    local d = session.dog_time[st.dog.name]
    if d then local lu = t - P.lu_t; d.lu_n, d.lu_sum = (d.lu_n or 0) + 1, (d.lu_sum or 0) + lu; if lu > (d.lu_max or 0) then d.lu_max = lu end end
    P.lu_t = nil
  end
  if st.node == 7 and st.synced then P.fire = P.fire + dt; P.last_fire_t = t end
  -- (4.6.3 review) measured from when it last had no target: before, time spent idle counted too, so the first enemy
  -- it picked after a quiet spell was committed to at once and a closer threat couldn't pull it during its line-up
  if st.target == 0 or not P.out_since then P.out_since = t end
  if st.target ~= 0 and P.commit ~= st.target and st.node == 6 and t - math.max(P.last_fire_t or -99, P.out_since) >= COMMIT.after then
    P.commit = st.target   -- it has gone too long without a shot: let it finish this one
  end
  if P.commit and (P.commit ~= st.target or P.fire >= COMMIT.burst) then P.commit = nil end
  -- (counted on the enemy it was pulled to, not the one it was pulled from)
  if P.need_fire and ((st.target ~= P.need_fire_from and (P.fire >= COMMIT.burst or st.target == 0)) or t - P.need_fire >= COMMIT.timeout) then P.need_fire = nil end
  -- (4.6.3 review: and only once it is on another enemy - while the game hadn't yet answered the pull it was still on
  -- the one it was pulled from, so 'focus' hid every other enemy, the closer one too, and the dog sat with nothing)
  local committed = not st.dog.fast and ((P.commit ~= nil and P.commit == st.target) or (P.need_fire ~= nil and st.target ~= 0 and st.target ~= P.need_fire_from))
  -- line-up time without a shot, per enemy (kept across re-picks, reset as soon as the dog fires at it)
  if st.target ~= 0 then
    local L = P.lineup[st.target] or { acc = 0 }
    -- ((5.0 Test 17) not while the safety is what keeps it from firing - you in its line, or about to be: that is not the
    -- dog being unable to get a shot, and setting the enemy aside for it left a close one alone for seconds)
    local held = P.unsafe_seen and P.unsafe_seen[st.target] and t - P.unsafe_seen[st.target] < 1.0
    if st.node == 6 and not held then L.acc = L.acc + dt elseif st.node == 7 and st.synced then L.acc = 0 end
    L.t = t; P.lineup[st.target] = L
  end
  for id, L in pairs(P.lineup) do if t - L.t > NOSHOT.forget then P.lineup[id] = nil end end
  if P.noshot_last then for id, tl in pairs(P.noshot_last) do if t - tl > NOSHOT.again then P.noshot_last[id] = nil end end end
  local tgt_c
  for _, c in ipairs(st.candidates) do if c.id == st.target then tgt_c = c end end
  local noshot_limit = st.dog.fast and NOSHOT.rover or ((tgt_c and tgt_c.d2 and tgt_c.d2 > NOSHOT.far_m ^ 2) and NOSHOT.far or NOSHOT.other)
  local mp = st.player_pos
  local near = tgt_c and tgt_c.pos and mp and (tgt_c.pos[1] - mp[1]) ^ 2 + (tgt_c.pos[2] - mp[2]) ^ 2 + (tgt_c.pos[3] - mp[3]) ^ 2 < NOSHOT.near_m ^ 2
  if near then noshot_limit = math.max(noshot_limit, NOSHOT.near) end
  local L_now = st.target ~= 0 and P.lineup[st.target]
  if L_now and L_now.acc >= noshot_limit and P.fire == 0 and P.lock >= math.min(noshot_limit, NOSHOT.fair) then
    P.noshot_last = P.noshot_last or {}
    local before = P.noshot_last[st.target]
    local rest = (near and not (before and t - before < NOSHOT.again)) and NOSHOT.near_rest or NOSHOT.rest
    P.noshot_last[st.target] = t
    P.noshot[st.target] = t + rest
    st.noshot_new, st.noshot_acc, st.noshot_rest = st.target, L_now.acc, rest
    L_now.acc = 0
  end
  st.lineup_acc = L_now and L_now.acc or 0
  st.target_for = P.target_since and t - P.target_since or 0

  local U_now, unsafe_count = unsafe_enemies(st)
  -- what stays hidden: enemies the dog could pick that were unsafe within the last moment (so a hidden enemy
  -- is not un-hidden and re-hidden every time you shift a little), plus whatever it is aiming at right now
  P.unsafe_seen = P.unsafe_seen or {}
  for id in pairs(U_now) do P.unsafe_seen[id] = t end
  local U = {}
  for _, c in ipairs(st.candidates) do
    local seen = P.unsafe_seen[c.id]
    -- (an enemy we already hid reads as not pickable, so it counts too)
    -- (only while its line still passes close to you: once you are clearly out of the way it comes back at once)
    local near_line = (st.safe_gap[c.id] or 0) < (st.dog.radius or 0.4) + 0.3
    if seen and t - seen < (st.dog.linger or UNSAFE_LINGER) and near_line and (c.eligible or c.mask == '    ' or c.id == st.target) then U[c.id] = true end
  end
  for id, seen in pairs(P.unsafe_seen) do if t - seen >= (st.dog.linger or UNSAFE_LINGER) then P.unsafe_seen[id] = nil end end

  -- enemies it cannot hurt (too heavily armored) and enemies it cannot see (behind cover): hidden while they
  -- are, so the dog spends its ammo on what it can actually hit. The game refreshes line of sight about
  -- twice a second, so an enemy stepping out of cover comes back within half a second.
  local N, C = {}, {}
  for _, c in ipairs(st.candidates) do
    -- (every live one, not just those the dog rates worth shooting right now: it still picks those now and then)
    if c.alive or c.mask == '    ' or c.id == st.target then
      -- ((5.1 Test 1) with the game's aim point for its target: the part model follows the line to where it really aims)
      if cannot_hurt(st.dog, c, st.drone_pos, st.dog.name, c.id == st.target and st.aim or nil) then N[c.id] = true
      -- (its current target gets a short grace while it is lining up, but none while it is firing: the moment an
      -- enemy it is shooting at drops out of sight it stops, the same as when its target dies)
      elseif COVER and not c.visible and (c.id ~= st.target or (c.memory or 0) <= COVER_GRACE or st.node == 7) then C[c.id] = true end
    end
  end
  st.armored, st.covered = N, C
  -- short bursts (Guard Dog vs Heavy Devastators): after a burst the enemy rests hidden for a while
  P.rest = P.rest or {}
  for _, c in ipairs(st.candidates) do
    -- ((5.1.0 Test 1) a Heavy Devastator that has turned its back comes back at once: full auto)
    if P.rest[c.id] and t < P.rest[c.id] and (c.alive or c.mask == '    ' or c.id == st.target)
      and burst_only(st.dog, c, st.drone_pos, c.id == st.target and st.aim or nil) then N[c.id] = true end
  end
  for id, until_t in pairs(P.rest) do if t >= until_t then P.rest[id] = nil end end
  -- ((5.1.5 Test 5) the damage check (HEALTH, engine_state.lua): it has fired a while at its target and the target's
  -- health hasn't gone down - a wall, a rock or armor in the way: that enemy is left alone for a while and it picks again
  -- (not a Heavy Devastator behind its shield: the Guard Dog's short bursts there are meant to keep it down)
  local ND = {}
  P.nd = P.nd or {}
  if st.target ~= 0 and st.node == 7 and st.synced and tgt_c and tgt_c.alive and not P.nd[st.target] then
    local a = tgt_c.kind and ARMOR[tgt_c.kind]
    -- ((5.1.5 review) nor a shielded enemy: its shield takes the hits first, HEALTH.shielded)
    if not (a and a.burst) and not HEALTH.shielded[tgt_c.kind] and not (a and a.av >= 5) then   -- ((5.1.5 Test 16) nor AV5+: see nodmg_set
      P.dw = P.dw or {}
      local secs = HEALTH.watch(P.dw, st.target, P.fire, t, st.dog.name)
      if secs and secs >= (st.dog.fast and DOG_NODMG.rover or DOG_NODMG.wait) then
        P.nd_n = P.nd_n or {}
        local n = (P.nd_n[st.target] or 0) + 1
        P.nd_n[st.target] = n
        P.nd[st.target] = t + (n == 1 and DOG_NODMG.hide or DOG_NODMG.hide2)
        if P.dw.e then P.dw.e[st.target] = nil end
        bump(session.actions, 'dog_no_damage')
        if TESTER then
          local seen = P.unsafe_seen and P.unsafe_seen[st.target]
          HEALTH.track_new(st.dog.name, st.dog.name, st.target, st.dog.fast and DOG_NODMG.rover or DOG_NODMG.wait,
            { t = t, hp = P.dw.hp, hold = P.nd[st.target] - t, meter = nil, unseen = not tgt_c.visible, mate = seen and t - seen < 1.5 })
        end
        if TESTER and DOG_NODMG.notes < 80 then
          DOG_NODMG.notes = DOG_NODMG.notes + 1
          local nm = a and a.name or (tgt_c.kind and LABELS[tgt_c.kind])
          event(string.format('no damage (test): %s fired %.1f s at %d (%s%s) and its health stayed at %d of %d: left alone %.0f s', st.dog.name, secs, st.target,
            tgt_c.kind and hexr(tgt_c.kind) or '-', nm and (' ' .. nm) or '', P.dw.hp or -1, P.dw.mx or -1, P.nd[st.target] - t))
        end
      end
    end
  end
  for id, u in pairs(P.nd) do if t >= u then P.nd[id] = nil else ND[id] = true end end
  if TESTER and #HEALTH.open > 0 then HEALTH.track_step(st.dog.name, st.target, P.fire, t) end
  local S = {}
  for _, c in ipairs(st.candidates) do
    if P.noshot[c.id] and t < P.noshot[c.id] and (c.alive or c.mask == '    ' or c.id == st.target) then S[c.id] = true end
  end
  for id, until_t in pairs(P.noshot) do if t >= until_t then P.noshot[id] = nil end end
  -- (never at the cost of not shooting at all: when every enemy it could pick is set aside, they all come back)
  if next(S) then
    local other = false
    for _, c in ipairs(st.candidates) do
      if not S[c.id] and not U[c.id] and (c.eligible or (c.mask == '    ' and c.alive and (c.score or 0) > 0)) then other = true; break end
    end
    if not other then S = {} end
  end
  -- out of range: the Guard Dog only opens fire within ~32 m of itself (the Rover reliably within ~35 m), but both
  -- happily pick enemies farther out and then wait, "lining up", until they come closer. While anything is in
  -- range, hide what isn't.
  local R = {}
  local range = st.dog.range
  local in_range_alt = false
  if range then
    local any
    for _, c in ipairs(st.candidates) do
      -- (only enemies it could actually shoot right now count: one hidden because you are in the way or because it
      -- can't get a shot at it must not keep the farther ones hidden too, or the dog is left with nothing at all)
      local open = c.eligible or (c.mask == '    ' and c.alive and (c.score or 0) > 0)
      if open and not N[c.id] and not C[c.id] and not U[c.id] and not S[c.id] and c.d2 and c.d2 <= range ^ 2 then any = true; break end
    end
    in_range_alt = any and true or false
    if any or st.dog.hard_range then
      for _, c in ipairs(st.candidates) do
        -- (a Rover already firing at a far enemy is hitting it: leave that one alone, its fire spreading moves it on)
        local firing_at = st.dog.fast and c.id == st.target and st.node == 7 and st.synced
        if (c.eligible or c.mask == '    ' or c.id == st.target) and c.d2 and c.d2 > (range + RANGE_SLACK) ^ 2 and not firing_at then R[c.id] = true end
      end
    end
  end
  -- priority: when an enemy is close to you, hide the ones clearly farther from you than it, so the dog
  -- deals with the nearest threat first (enemies already hidden by us count as pickable here). With the Target
  -- Prioritization option (Intelligence) only.
  local F = {}
  P.far_seen = P.far_seen or {}
  local me = st.player_pos
  if me and OPT.priority() then
    local best
    for _, c in ipairs(st.candidates) do
      c.dp = nil
      if c.pos and (c.eligible or c.mask == '    ') and not U[c.id] and not N[c.id] and not C[c.id] and not R[c.id] and not S[c.id] then
        local dx, dy, dz = c.pos[1] - me[1], c.pos[2] - me[2], c.pos[3] - me[3]
        c.dp = math.sqrt(dx * dx + dy * dy + dz * dz)
        -- (for the Rover, enemies it has already set alight don't count as the close threat: once the close
        -- ones are burning it spreads its fire to the next ones out instead of staying on them)
        local lit = st.dog.fast and (recently(c.id, t) or (c.id == st.target and P.fire >= FAST.fire))
        -- (nor do enemies it has already spent a while lining up without a shot: they may be unreachable)
        local doubtful = P.lineup[c.id] and P.lineup[c.id].acc >= 0.5 * noshot_limit
        if (not best or c.dp < best) and not lit and not doubtful then best = c.dp end
      end
    end
    if best and best < PRIORITY.range then
      for _, c in ipairs(st.candidates) do
        if c.dp and c.dp > best + (st.dog.band or PRIORITY.band) then P.far_seen[c.id] = t end
      end
    end
    -- keep hiding for a moment after an enemy stops being "far" (no flicker), but only while it is still nearly
    -- as far; when the close threat dies or you move, the others come back straight away
    for _, c in ipairs(st.candidates) do
      local seen = P.far_seen[c.id]
      if seen and t - seen < PRIORITY.linger and best and best < PRIORITY.range and c.dp and c.dp > best + (st.dog.band or PRIORITY.band) - 1.5
        and (c.eligible or c.mask == '    ' or (c.id == st.target and (st.node ~= 7 or best <= PRIORITY.urgent))) then F[c.id] = true end
    end
  end
  for id, seen in pairs(P.far_seen) do if t - seen >= PRIORITY.linger then P.far_seen[id] = nil end end
  -- right after a redirect, leave the new target alone for a moment (it is not hidden, so it is not dropped
  -- without being asked to choose again)
  local calm = t - (P.last_kick_t or -1) < CALM_SECONDS
  if calm and st.target ~= 0 then
    if st.node ~= 7 then C[st.target] = nil end
    F[st.target], R[st.target] = nil, nil
  end
  if committed then F[st.target] = nil end
  -- focus: while committed (and its target is one it may shoot), keep the other enemies hidden so the game's own
  -- once-a-second re-pick doesn't move it on before it has fired its burst either
  local focus = {}
  if committed and st.target ~= 0 and P.fire < COMMIT.burst and not (U[st.target] or N[st.target] or C[st.target] or S[st.target] or R[st.target] or ND[st.target]) then
    for _, c in ipairs(st.candidates) do if c.id ~= st.target and (c.eligible or c.mask == '    ') then focus[c.id] = true end end
  end
  local hide = union(U, F, N, C, R, S, focus, ND)
  st.hidden = hide   -- ((5.1.0 Test 1) for the dog's marker: none over a target the mod is taking away from it)
  if TESTER then st.hide_sets = { unsafe = U, closer_threat = F, armor = N, cover = C, range = R, no_shot = S, focus = focus, no_damage = ND } end   -- ((4.6.7 review) the F8 marker's only)
  -- a re-selection we asked for is still pending: keep the same enemies hidden until the target changes
  -- (4.6.4 review: not while its target has become unsafe - a hold for another reason must never delay a safety stop)
  -- ((4.6.7 review) nor while its target is dead: a back-off hold on it kept the 'target lost' ask off for up to 1 s)
  if P.hold and st.target == P.hold.target and t < P.hold.until_t
     and not (U[st.target] and not tostring(P.hold.reason):find('^safety'))
     and not (st.target ~= 0 and not (tgt_c and tgt_c.alive)) then
    return { block = union(P.hold.block, hide), kick = false, reason = P.hold.reason }
  end
  P.hold = nil

  local current
  for _, c in ipairs(st.candidates) do if c.id == st.target then current = c end end

  -- 1) the dog's current target is on the other side of you: move it to a safe enemy, or make it stand down
  -- (only the target itself and the unsafe enemies are hidden; the dog picks freely among the rest)
  if st.target ~= 0 and U_now[st.target] and attacking then
    local other = pick_other(st, union(U, N, C, R, S), t, current)
    if other then return dog_kick(st, t, hide, { [st.target] = true }, 'safety_switch') end
    return dog_kick(st, t, hide, { [st.target] = true }, 'safety_hold')
  end
  -- 2) its target just died (or dropped out of sight): make it choose again now instead of shooting the
  --    body until its one-second selection timer runs out. Once per lost target, at most every 0.1 s.
  --    Seen two ways: the target is still set but no longer valid, or the game has already cleared it but the
  --    dog is still in its firing step with the old timer running (it keeps shooting where the enemy was).
  local prev = P.prev_target or 0
  P.prev_target = st.target
  if st.target ~= 0 and not (current and current.alive) and P.lost_target ~= st.target and t - (P.lost_t or 0) >= 0.1 then
    P.lost_target, P.lost_t, P.lost_tries = st.target, t, 0
    note_lost(st, 'target no longer valid')
    return dog_kick(st, t, hide, {}, 'target_lost')
  end
  if st.target == 0 and prev ~= 0 then P.lost_from, P.lost_tries = prev, 0 end
  -- (4.5.1) only when it has something it may pick: asked with nothing to choose, the game gives it a fresh timer in
  -- its firing step and it fires at nothing (seen on the Supply FRV gun, the same rule); left alone it stops when its
  -- old timer runs out
  if st.target == 0 and P.lost_from and st.node == 7 and st.deadline > st.now and (P.lost_tries or 0) < 2 and t - (P.lost_t or 0) >= 0.15 then
    local any = false
    for _, c in ipairs(st.candidates) do
      if (c.eligible or (c.mask == '    ' and c.alive and (c.score or 0) > 0)) and not hide[c.id] then any = true; break end
    end
    if any then
      P.lost_t, P.lost_tries = t, (P.lost_tries or 0) + 1
      if P.lost_tries == 1 then note_lost(st, 'target cleared, timer still running') end
      return dog_kick(st, t, hide, {}, 'target_lost')
    end
  end
  if st.target ~= 0 then P.lost_from = nil end
  -- 2b) it stood down for your safety and has no target: the moment something is safe to shoot again, make it
  --     choose right away instead of waiting out its selection timer (up to a second)
  if next(U) then P.safety_seen = t end
  if st.target == 0 and t - (P.safety_seen or -99) < 2.0 and t - (P.last_kick_t or -99) >= 0.1 then
    for _, c in ipairs(st.candidates) do
      if (c.eligible or (c.mask == '    ' and c.alive and (c.score or 0) > 0)) and not hide[c.id] then return dog_kick(st, t, hide, {}, 'resume') end
    end
  end
  -- 2c) engage (3.0): no target, yet an enemy it could shoot is in sight and in range: make it choose now instead
  --     of waiting out its selection timer (up to a second). Not while it is docked on your back (reloading); at
  --     most every 0.25 s, and after 3 tries without it picking anything it waits a second.
  if st.target ~= 0 then P.engage_tries = 0 end
  if st.target == 0 and st.deadline > st.now and t - (P.last_kick_t or -99) >= ENGAGE.every and t >= (P.engage_pause or 0) then
    local P2, D = st.player_pos, st.drone_pos
    local docked = P2 and D and ((D[1] - P2[1]) ^ 2 + (D[2] - P2[2]) ^ 2) < 1.2 ^ 2
    local reach = st.dog.range and (st.dog.range + 2) ^ 2
    if not docked then
      for _, c in ipairs(st.candidates) do
        if c.visible and (c.eligible or (c.mask == '    ' and c.alive and (c.score or 0) > 0)) and not hide[c.id]
          and (not reach or (c.d2 and c.d2 <= reach)) then
          P.engage_tries = (P.engage_tries or 0) + 1
          if P.engage_tries > ENGAGE.tries then P.engage_tries, P.engage_pause = 0, t + ENGAGE.pause; break end
          return dog_kick(st, t, hide, {}, 'engage')
        end
      end
    end
  end
  -- 3) it is shooting at something it cannot hurt, or at cover (it keeps firing at an enemy's last known
  --    spot for about a second after losing sight of it): make it choose again among what it can hit
  if st.target ~= 0 and attacking and ((N[st.target] and not P.stuck[st.target]) or (C[st.target] and (not calm or st.node == 7))) then
    return dog_kick(st, t, hide, { [st.target] = true }, N[st.target] and 'cannot_hurt' or 'out_of_sight')
  end
  -- (only redirected when there is something in range to go to: with nothing in range the far one just stays
  -- hidden, rather than asking the dog to choose again and again for nothing)
  if st.target ~= 0 and attacking and R[st.target] and not calm and in_range_alt then return dog_kick(st, t, hide, { [st.target] = true }, 'out_of_range') end
  if st.target ~= 0 and attacking and S[st.target] then return dog_kick(st, t, hide, { [st.target] = true }, 'no_shot') end
  -- ((5.1.5 Test 5) firing at it without hurting it)
  if st.target ~= 0 and attacking and ND[st.target] then return dog_kick(st, t, hide, { [st.target] = true }, 'no_damage') end
  if current and st.node == 7 and P.fire >= BURST.fire and burst_only(st.dog, current, st.drone_pos, st.aim) then
    -- (the whole Devastator rests: its body and its shield are separate entries, rest_parts in engine_armor.lua)
    local parts = rest_parts(P.rest, st.candidates, current, t + BURST.rest)
    if TESTER and (P.burst_notes or 0) < 12 then
      P.burst_notes = (P.burst_notes or 0) + 1
      local near = {}
      for _, c in ipairs(st.candidates) do
        if c ~= current and c.pos and current.pos and #near < 5 and (c.pos[1] - current.pos[1]) ^ 2 + (c.pos[2] - current.pos[2]) ^ 2 + (c.pos[3] - current.pos[3]) ^ 2 < 9 then
          near[#near + 1] = string.format('%d %s%s', c.id, c.kind and hexr(c.kind) or '-', P.rest[c.id] and ' (rested)' or '')
        end
      end
      event(string.format('burst done: %s on %d %s; rested with it: %d; within 3 m: %s', st.dog.name, current.id,
        current.kind and hexr(current.kind) or '-', parts, #near > 0 and table.concat(near, ', ') or 'nothing'))
    end
    return dog_kick(st, t, hide, { [st.target] = true }, 'burst_done')
  end
  -- 4) it is busy with an enemy well behind a closer one: switch to the closer threat
  if st.target ~= 0 and F[st.target] and not calm and not committed then
    local closer = false
    for _, c in ipairs(st.candidates) do if c.eligible and not hide[c.id] then closer = true; break end end
    if closer then P.need_fire, P.need_fire_from = t, st.target; return dog_kick(st, t, hide, { [st.target] = true }, 'closer_threat') end
  end
  -- 5) fast switching (Rover): move on once the burn has been applied
  if st.dog.fast and attacking and (P.fire >= FAST.fire or (P.fire_step or 0) >= FAST.lock) then
    local other = pick_other(st, union(U, N, C, R, S), t, current)
    if other and not (other.d2 and other.d2 <= FAST.reach ^ 2 and not recently(other.id, t)) then other = nil end
    if other then
      remember(st.target, t)
      -- hide the one it just burned and the other recently burned ones, as long as something is left to pick
      local block = recent_set(t)
      local left = false
      for _, c in ipairs(st.candidates) do if c.eligible and not block[c.id] and not hide[c.id] then left = true; break end end
      if not left then block = {} end
      block[st.target] = true
      -- (a line-up cut short by this switch counts half towards the no-shot rule: the mod moved it on, the enemy
      -- wasn't necessarily out of reach)
      if P.fire < FAST.fire and P.lineup[st.target] then P.lineup[st.target].acc = math.max(0, P.lineup[st.target].acc - 0.5 * P.lock) end
      return dog_kick(st, t, hide, block, P.fire >= FAST.fire and 'switch_after_burn' or 'switch_after_lock')
    end
  end
  -- 6) otherwise just keep unsafe (and, near a close threat, far-away) enemies hidden
  return { block = hide, kick = false, reason = unsafe_count > 0 and 'guarding' or nil }
end

-- ======================================================================================================
-- Steering: hide enemies from the dog by blanking their faction mask in its perception record, and
-- expire its target-selection timer when it has to choose again. Every blanked mask is remembered with
-- its original value and put back as soon as it is no longer needed, when the dog changes, and at exit.
-- ======================================================================================================
BLANK = '    '
hidden = {}   -- mask address -> { id, entry, before }
local hidden_key = nil

local function unhide(addr, h)
  -- ((4.6.4 review) a record kept aside under a negative key - its entry was taken over by another enemy in the
  -- game's update, sentry_after - has no mask of its own to put back here; hider_apply adopts it where it moved to)
  if addr < 0 then return true end
  local id_now = read(h.entry, 4)
  if id_now and u32(id_now, 0) == h.id and read(addr, 4) == BLANK then
    if not write(addr, h.before) then stats.write_failures = stats.write_failures + 1; return false end
  end
  return true
end

-- (the same bookkeeping serves the dog and each sentry: H maps mask address -> { id, entry, before })
function hider_restore(H)
  local ok = true
  for addr, h in pairs(H) do
    if not unhide(addr, h) then ok = false end
    H[addr] = nil
  end
  return ok
end

-- Riders (4.0): entries that come with a bigger enemy and sit on it - the Scout Strider's pilot (fb9937035d652c43,
-- spawned with its Strider, never a target itself). The game can choose the Strider through its pilot, so a Strider
-- hidden on its own was chosen again and again (test logs: hidden Strider re-picked, its pilot shown next to it).
-- A rider within 3 m of an enemy being hidden is hidden with it.
-- (hider_apply: declared at the top of this file)
do
  local RIDERS = { [type_hash('fb9937035d652c43')] = true }
  local function with_riders(candidates, block)
    local out = block   -- (copied before the first change: the caller's set is left as it was)
    for _, r in ipairs(candidates) do
      if r.kind and RIDERS[r.kind] and r.pos and not block[r.id] then
        for _, v in ipairs(candidates) do
          if v ~= r and v.pos and block[v.id] and (v.pos[1] - r.pos[1]) ^ 2 + (v.pos[2] - r.pos[2]) ^ 2 + (v.pos[3] - r.pos[3]) ^ 2 < 9 then
            if out == block then out = {}; for id in pairs(block) do out[id] = true end end
            out[r.id] = true; break
          end
        end
      end
    end
    return out
  end
hider_apply = function(H, candidates, block)
  -- (nothing hidden and nothing to hide - most frames for an idle dog or sentry: nothing to do)
  if not next(block) and not next(H) then return 0 end
  if next(block) then block = with_riders(candidates, block) end
  local at = {}
  for _, c in ipairs(candidates) do at[c.mask_addr] = c end
  -- entries the game moved or dropped since the last poll
  local moved   -- (built only when something did move)
  for addr, h in pairs(H) do
    local c = at[addr]
    if not c or c.id ~= h.id then moved = moved or {}; moved[h.id] = h; H[addr] = nil end
  end
  if moved then
    for _, c in ipairs(candidates) do
      if c.mask == BLANK and not H[c.mask_addr] and moved[c.id] then
        H[c.mask_addr] = { id = c.id, entry = c.entry, before = moved[c.id].before }
      end
    end
  end
  -- put back what is no longer needed; note masks the game has refreshed on its own
  -- ((4.6.4) counted and returned: a sentry whose hidden entries the game keeps showing again)
  local back = 0
  for addr, h in pairs(H) do
    local c = at[addr]
    if c.mask ~= BLANK then h.before = c.mask; if block[h.id] then back = back + 1 end end
    if not block[h.id] then unhide(addr, h); H[addr] = nil end
  end
  -- hide what is needed
  for _, c in ipairs(candidates) do
    if block[c.id] and c.mask ~= BLANK then
      local id_now = read(c.entry, 4)
      if id_now and u32(id_now, 0) == c.id and read(c.mask_addr, 4) == c.mask then
        if write(c.mask_addr, BLANK) then H[c.mask_addr] = { id = c.id, entry = c.entry, before = c.mask }
        else stats.write_failures = stats.write_failures + 1 end
      end
    end
  end
  return back
end
  -- ((5.1.5 Test 22) the hide bookkeeping walks sets with pairs/next, which the game's LuaJIT (2.1.0-alpha) can't compile:
  -- my Test 19 log had it start and give up on hider_apply 531 times and with_riders 480. Not asked to any more (it ran
  -- uncompiled anyway; the loops in the functions it calls still compile)
  local j = rawget(_G, 'jit')
  if type(j) == 'table' and type(j.off) == 'function' then pcall(j.off, hider_apply); pcall(j.off, with_riders) end
end

function restore()
  local ok = hider_restore(hidden)
  hidden_key = nil
  return ok
end

function apply(st, block)
  if st.key ~= hidden_key then restore(); hidden_key = st.key end
  hider_apply(hidden, st.candidates, block)
end

local noted = {}
local safety_noted = { target = nil, t = -99 }   -- ((4.6.7 review) the last safety stop noted, see below)
local function note_action(st, req)
  local unsafe = 0
  for _ in pairs(req.block) do unsafe = unsafe + 1 end
  bump(session.actions, req.reason)
  if req.reason == 'no_shot' then
    noted.no_shot = (noted.no_shot or 0) + 1
    local c
    for _, x in ipairs(st.candidates) do if x.id == st.target then c = x end end
    if TESTER and c then
      local d = c.d2 and math.sqrt(c.d2) or -1
      local band = d < 15 and '0-15 m' or (d < 25 and '15-25 m' or (d < 35 and '25-35 m' or '35+ m'))
      bump(session.noshots, string.format('%s %s%s, %s', st.dog.name, c.kind and hexr(c.kind) or '?', c.kind and LABELS[c.kind] and (' ' .. LABELS[c.kind]) or '', band))
    end
    if noted.no_shot > 12 then return end
    local me = st.player_pos
    local where = ''
    if c and c.pos and me then
      local dz = c.pos[3] - me[3]
      where = string.format(', %.0f m from you, %.1f m %s you', math.sqrt((c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + dz ^ 2),
        math.abs(dz), dz < 0 and 'below' or 'above')
    end
    local nm = c and c.kind and ((ARMOR[c.kind] and ARMOR[c.kind].name) or LABELS[c.kind])
    event(string.format('%sno_shot: %s (target %d, type %s%s%s, %s, score %.2f; %s)',
      READ_ONLY and 'would ' or '', st.dog.name, st.target, c and c.kind and hexr(c.kind) or '?', nm and (' ' .. nm) or '', where,
      c and (c.visible and 'in sight' or 'out of sight') or '?', c and c.score or -1,
      st.noshot_new == st.target and string.format('lined up %.1fs without firing, hidden %.1fs', st.noshot_acc or 0, st.noshot_rest or NOSHOT.rest)
        or 'picked again while still set aside'))
    return
  end
  if req.reason == 'cannot_hurt' or req.reason == 'out_of_sight' or req.reason == 'out_of_range' or req.reason == 'closer_threat' or req.reason == 'no_damage' then
    -- the first few of each go to the log, with what the enemy was
    noted[req.reason] = (noted[req.reason] or 0) + 1
    if noted[req.reason] > 8 then return end
    local c
    for _, x in ipairs(st.candidates) do if x.id == st.target then c = x end end
    local a = c and c.kind and ARMOR[c.kind]
    event(string.format('%s%s: %s (target %d%s, AI step %d, on it %.1fs%s)', READ_ONLY and 'would ' or '', req.reason, st.dog.name, st.target,
      a and (', ' .. a.name .. ', armor ' .. a.av) or '', st.node, st.target_for or 0,
      c and c.pos and st.player_pos and string.format(', %.0f m from you', math.sqrt((c.pos[1] - st.player_pos[1]) ^ 2 + (c.pos[2] - st.player_pos[2]) ^ 2)) or ''))
    return
  end
  if not req.reason:find('^safety') then return end   -- target switches are too frequent to list one by one
  -- ((4.6.7 review) one stop is asked again every 0.25 s for as long as it lasts (4.6.6: a safety stop never backs
  -- off): noted and counted once, not on every ask - the repeats filled the log and rewrote it every 3 s)
  local now_t = os.clock()
  if safety_noted.target == st.target and now_t - safety_noted.t < 3 then safety_noted.t = now_t; return end
  safety_noted.target, safety_noted.t = st.target, now_t
  local w = st.unsafe_why and st.unsafe_why[st.target] or ''
  if w:find('teammate') then session.team.stops = session.team.stops + 1
  elseif w:find('SEAF') then session.team.seaf_stops = (session.team.seaf_stops or 0) + 1
  elseif w:find('civilian') then session.team.civ_stops = (session.team.civ_stops or 0) + 1 end
  local c
  for _, x in ipairs(st.candidates) do if x.id == st.target then c = x end end
  local me = st.player_pos
  local where = ''
  if c and c.pos and me then
    where = string.format(', %.1f m from you', math.sqrt((c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + (c.pos[3] - me[3]) ^ 2))
  end
  local gap = st.safe_gap and st.safe_gap[st.target]
  if gap and gap < 50 then where = where .. string.format(', line %.2f m from a body', math.max(gap, 0)) end
  -- (4.5.3 Test 15, test builds) for a look-ahead hold: where the dog was predicted to be, and where it was, in your
  -- own frame (right/left, ahead/behind of you)
  local F = TESTER and st.unsafe_from and st.unsafe_from[st.target]
  if F and me and me.axes and st.drone_pos then
    local function at(p)
      local d = { p[1] - me[1], p[2] - me[2], p[3] - me[3] }
      local r, f = d[1] * me.axes[1][1] + d[2] * me.axes[1][2] + d[3] * me.axes[1][3], d[1] * me.axes[2][1] + d[2] * me.axes[2][2] + d[3] * me.axes[2][3]
      return string.format('%.1f m %s, %.1f m %s', math.abs(r), r >= 0 and 'right' or 'left', math.abs(f), f >= 0 and 'ahead' or 'behind')
    end
    where = where .. ', predicted dog ' .. at(F) .. ' (now ' .. at(st.drone_pos) .. ')'
  end
  event(string.format('%s%s: %s (target %d, %s%s; AI step %d; %d enemies seen, %d hidden)', READ_ONLY and 'would ' or '', req.reason,
    st.dog.name, st.target, st.unsafe_why and st.unsafe_why[st.target] or '?', where, st.node, #st.candidates, unsafe))
end

function steer(st, req)
  if req.kick then note_action(st, req) end
  if READ_ONLY then
    if req.kick then last_reason = 'would ' .. req.reason end
    if next(req.block) then stats.guarded_polls = stats.guarded_polls + 1 end
    return
  end
  if read(st.rec_addr, 4) ~= st.rec_head then return end
  apply(st, req.block)
  if next(req.block) then stats.guarded_polls = stats.guarded_polls + 1 end
  -- (4.6.5, my note: no firing at the spot for a second after a target is lost) still in its firing step (7) with no
  -- target: its loss time is moved back, as for the sentries (loss_cut)
  if st.target == 0 and st.node == 7 then
    local age, raw = loss_cut(st.rec_addr, st.now)
    if age then
      stats.loss_cuts = (stats.loss_cuts or 0) + 1
      bump(session.actions, 'dog_loss_cut')   -- ((4.6.5 review) in the log's action counts, like the sentries' cuts)
      if TESTER and stats.loss_cuts <= 10 then event(string.format('loss cut (test): %s lost its target %.2f s ago, still firing: loss time moved back 1 s', st.dog.name, age)) end
    elseif TESTER and raw and (stats.loss_notes or 0) < 3 then
      stats.loss_notes = (stats.loss_notes or 0) + 1
      event(string.format('loss cut (test): %s in its firing step with no target, its +408 reads %.2f s ago - left alone', st.dog.name, raw / 1e6))
    end
  end
  if not req.kick then return end
  last_reason = req.reason
  -- make the dog choose again right away (only when its timer looks sane)
  if st.deadline > st.now and st.deadline - st.now <= 1000000 then
    if not write(st.rec_addr + 152, u64bytes(st.now)) then stats.write_failures = stats.write_failures + 1 end
  end
  local r = req.reason
  if r == 'safety_switch' then stats.safety_switches = stats.safety_switches + 1
  elseif r == 'safety_hold' then stats.holds = stats.holds + 1
  elseif r == 'target_lost' then stats.retargets = stats.retargets + 1
  elseif r == 'out_of_sight' then stats.cover_switches = stats.cover_switches + 1
  elseif r == 'cannot_hurt' then stats.armor_switches = stats.armor_switches + 1
  elseif r == 'no_shot' then stats.noshot_switches = stats.noshot_switches + 1
  else stats.switches = stats.switches + 1 end
end
end

-- ======================================================================================================
-- Sentries (4.0): your sentries get the same treatment as the dogs where it fits. They never fire through you or
-- (optionally) your teammates - including while they swing round to their next target - the mortars never pick an
-- enemy standing next to someone, the machine gun and Gatling sentries skip armor they can't hurt, and the
-- targeting laser shows what each one is aiming at. Like the dogs, a sentry is only ever steered by hiding enemies
-- from it (their faction mask in its own perception record) and by asking it to choose again (its selection
-- timer). Nothing else of the sentry is touched, so mods that change how sentries aim or fire keep working.
-- ======================================================================================================
-- (4.6.3) outside helpers the sentry code uses only now and then, in one table: the function below may only
-- reach 60 outside variables (LuaJIT), and this keeps plenty of room for new ones
local EXT = { PERC = PERC, teammates = teammates, GROUPS = GROUPS, SINGLES = SINGLES, find_player = find_player, read_candidates = read_candidates, in_mission = in_mission, laser_wanted = laser_wanted, RED_SECONDS = RED_SECONDS, FRIEND = FRIEND, FIRE = FIRE, FLASH_HZ = FLASH_HZ, cannot_hurt = cannot_hurt, rest_parts = rest_parts, parts_exposed = PARTS.exposed, hexr = hexr, is_local = is_local, team_wanted = team_wanted, hider_apply = hider_apply, loss_cut = loss_cut, type_hash = type_hash, LOCK = LOCK, LOST = LOST, me = nil, SGD = SGD }
-- (built inside a function of its own: its many helpers would not fit among the main chunk's locals)
local sentry_tick, sentry_restore, sentry_beams, sentry_after = (function()
  local sentry_tick, sentry_restore, sentry_beams, sentry_after
  local SCAN_SECONDS = 2.0          -- the game's list of AI agents is searched for sentries this often, and at once
                                    -- whenever the number of agents changes or one of ours drops out
  local HOLD, BACKOFF, LINGER = 0.25, 1.0, 0.3
  -- ((5.0 Test 12) part armor) whether a sentry cannot hurt an enemy: judged by the part its line of fire meets - from
  -- its muzzle, toward where the game is aiming it if this is its target - or by the enemy's main armor
  local function hurt_no(s, st, c)
    return EXT.cannot_hurt(s.def, c, st.muzzle, s.id, st.current == c and st.aim or nil)
  end
  local DEAD_HIDE = 1.5               -- (4.5.1) how long a killed enemy's entry stays hidden from the sentry that shot it (s)
  local BUSY_NODE = 10              -- an AI step in which sentries ignore being asked to choose again (test logs)
  -- (5.0) a sentry with 'laser_when_firing' (the Supply FRV's gun, stowed up on the roof until it swings down to
  -- fire, a tester's call) shows its laser only while firing, and this long after its last shot (seconds). (4.5, a
  -- tester's call: only while it fires - 0.6 -> 0.25, just enough to bridge single frames out of its firing step, and
  -- no longer kept on while it stays on the same target or after its target is gone: that looked janky)
  local LASER_FIRING_HOLD = 0.25
  local SALVO_GAP = 1.0           -- ((5.1.5 Test 32) the Autocannon still counts as firing this long after its firing step, on the same enemy (s)
  local SALVO_HOLD = 1.2           -- ((5.1.5 Test 25) the Autocannon's beam and marker after its AI clears the target mid-salvo (s)
  local BEAM_SMOOTH = 0.06           -- seconds: how quickly a sentry's laser end catches up with where it should point
  local FIRE_NODE = 12              -- the AI step in which most sentries fire (the Laser Sentry: its fire_node, 13)
  local AIM_UP = { 0.3, 1.0 }       -- where on an enemy the shots may land (meters above its base)
  local BODY_MID = 0.9              -- the middle of a body (meters above its feet): for explosions
  local UNSAFE_CLEAR = 1.0          -- ((5.1.5 Test 18) meters clear of a shot's line on the map that need no full check (the rules only care below 0.3)
  local MUZZLE_UP = 1.2             -- if the muzzle can't be read: this far above the sentry's base
  -- (turns under 10 degrees are left to the line check: a sentry's barrel wanders a few degrees around its aim
  -- while tracking, and counting that as a turn made the Laser Sentry drop enemies it was already on)
  local SWEEP = { min_deg = 10, reach = 45, both_ways_deg = 170 }
  -- which way the barrel points: known from testing for the machine gun, Gatling and Laser sentries ('barrel_axis');
  -- for other kinds whose turns are checked (the Flame Sentry) it is learned while it fires at enemies in plain view
  -- (the part's axis that tracks its aim point best); until then the turn check waits
  local BARREL = { frames = 30, min_cos = 0.97, tries = 4 }
  -- priority (Target Prioritization): by armor, the rocket and autocannon sentries go for armored (Heavy or more)
  -- enemies first, the machine gun, Gatling and Laser sentries for unarmored ones; by distance (4.6.1, prefer = 'near',
  -- the Flame Sentry), the closest first. Only enemies in sight within 'reach' meters count, and an enemy within
  -- 'near_you' meters of a helldiver is never pushed back (it is the threat right now).
  -- (4.6.4 wiki check: reach 80 -> 100, the Autocannon and Rocket sentries' range)
  local PRIORITY = { reach = 100, near_you = 8, calm = 0.5, closer = 3, closer_keep = 4, finish = 2.0, commit = 0.5, band = 25 }
  -- ((5.1.5 Test 24, my Test 23 game: "rocket sentries and autocannon sentries dont seem to properly prioritize enemies
  -- near them") 'band': the heavy-first guns (Rocket, Autocannon) take any enemy within this many meters of the sentry
  -- before anything farther out, heaviest first inside it (the Rocket from its 10 m minimum out). Gunships still first
  -- (4.6.1) prefer = 'near' (the Flame Sentry): no armor tiers - an enemy more than 'closer' m further from its muzzle
  -- than the closest one it can pick waits (its current target only past 'closer_keep' m, so it doesn't flick between two)
  -- (4.6.2, a tester: it still stayed on a burning enemy farther out while one walked in: 3 / 4 m, were 5 / 8)
  -- short bursts (machine gun and Gatling vs Heavy Devastators: their shield eats the ammo): fire this long at one,
  -- then leave it alone this long - the same as the Guard Dog
  local BURST_S = { fire = 1.0, rest = 3.0 }
  -- out of sight: an enemy the sentry has lost sight of is hidden; its current target only once the game's memory of
  -- it has faded to 'grace' (or at once while it is firing). Firing time (bursts, fire spreading) only counts while
  -- the barrel is within ~6 degrees of its aim ('aligned' = cosine)
  -- An enemy the game keeps choosing straight back although it is hidden as out of sight (a Scout Strider, whose own
  -- front plate seems to block the sentry's view of its body) is trusted as in sight for 'trust' seconds instead of
  -- being dropped over and over
  local COVER_S = { grace = 0.6, aligned = 0.995, trust = 5.0 }
  -- enemies still aboard a dropship: within 'reach' m of it sideways, from 'below' m under it to 'above' m over it,
  -- and at least 'above_sentry' m higher than the sentry (so troops it has already set down don't count)
  local DROPSHIP = { reach = 14, below = 12, above = 4, above_sentry = 5, near = 20, body_below = 4, air = 1.5, air_guess = 3, settle = 2.0 }   -- (near, body_below, air: the mortars, 5.1.5 Test 28)
  -- self-defense: enemies within 'reach' m of the sentry come before every priority rule (gunships included)
  local SELF = { reach = 8 }
  local RANGE_KEEP = 2                -- (4.5.2) a sentry with a 'range' keeps its current target until it is this much further out (m)
  -- fire spreading: once an enemy is burning it moves on to the unlit enemy nearest you within 'reach'; enemies lit in
  -- the last 'burn' seconds are left to burn while unlit ones are about. ((4.6.7 review) Two kinds use it now, the
  -- Laser Sentry (spreads_fire = true, the 'laser_*' values) and the Flame Sentry ('keep': 'fire' / 'lock' / 'near_you'
  -- below); the first rule, holding the beam once everything near is burning, no longer applies to either)
  -- (4.6.2) spreads_fire = 'keep' (the Flame Sentry, a tester's call): the same, but a burning enemy next to a
  -- helldiver is never left, it is left only for an unlit one at most PRIORITY.closer_keep m farther away (closer
  -- ones first), and when everything near is burning it keeps firing (no holding back)
  -- (4.6.6 Test 4, my note: the Laser Sentry redirected constantly and ignored enemies close by) the Laser Sentry
  -- ('laser_*'): half a second of beam (1 s on it; Test 5, my note: 1 s was too long) before it moves on, burning enemies within 'laser_near' m of you or
  -- of the sentry are never skipped, and when everything in reach is burning it keeps firing instead of holding
  local SPREAD = { fire = 0.3, lock = 1.0, burn = 3.0, reach = 50, near_you = 10, laser_fire = 0.5, laser_lock = 1.0, laser_near = 15 }
  -- Gunships come before everything else for the Gatling, autocannon, rocket and Laser sentries ('air_first')
  -- (Automaton Gunship; Illuminate Stingray)
  local AIR_FIRST = { [type_hash('282eb766c1ffa6a1')] = true, [type_hash('19e18b46ec55d94a')] = true }
  -- 1 = armored, 0 = unarmored; gunships rank above all ('air'). Every sentry has at least Medium penetration, so
  -- for them 'armored' means Heavy (AV4) or more: Light and Medium enemies count as unarmored
  local function armour_tier(c, heavy, air)
    if air and c.kind and AIR_FIRST[c.kind] then return heavy and 2 or -1 end
    local a = c.kind and ARMOR[c.kind]
    if a and not a.sentries_skip and a.av >= 4 then return 1 end
    return 0
  end
  -- (4.6.4, a tester's call: the hover rule is gone - the rocket sentry fires at gunships and at enemies aboard a dropship
  -- whether they move or hover. Its check watched how fast each one moved; in game it left a hovering dropship's
  -- riders hidden for half a minute and the sentry sat idle)
  -- overheating (Laser Sentry): stand it down at 'stop' of its heat capacity and let it cool to 'resume'. Its heat
  -- is estimated from how long it has had a target; once the game's own heat meter has been read, that is used, and
  -- then it may run hotter ('stop_measured'). (The share of time it can fire is set by the game's heating and
  -- cooling rates whatever the band; a narrower band just means shorter bursts and shorter pauses. The game warns
  -- at about 80% and burns out at 100%; the estimate assumes the slowest cooling, so it errs on the safe side.)
  -- (measured in game, Test 20-27 logs: it heats ~8.0 degrees a second while firing and cools ~5.05 a second at every
  -- heat level, so it can fire ~39% of the time whatever the band; after a stop it keeps heating for about a second,
  -- ~10 degrees. With the game's meter it runs 90% -> 70% (a tester's choice: short gaps), estimated 70% -> 60%)
  local HEAT = { stop = 0.70, stop_measured = 0.90, resume = 0.60, resume_measured = 0.70, probe_every = 0.25, fresh = 1.5 }
  local sentries = {}               -- by entity id: your sentries out right now
  if TESTER then SGD.sentries_dbg = sentries end   -- ((5.2 sim work) test builds: the replay sim reads why each enemy is hidden
  local type_ai = {}                -- entity type -> AI id, looked up once per kind (to report unknown sentries)
  local barrel = {}                 -- per sentry kind: { axis, sign } once learned, or sums while learning
  local next_scan, pl, pl_until, last_count, last_scan = 0, nil, 0, nil, nil
  -- what we know about a sentry is kept by its entity id for a while after we lose track of it: the game moves a
  -- sentry's records around now and then, and a Laser Sentry must not come back with its heat reset to zero
  -- (that let one burn out: it kept "restarting" cold)
  local remembered = {}              -- id -> { heat, heat_measured, P, t, name }
  local refound_notes = 0
  local not_steered = {}             -- id -> the reason last logged for a sentry that couldn't be steered
  local other_teslas = {}            -- another player's Tesla Towers already noted (4.5)
  local other_noted = {}             -- (test builds) sentries not run by this game already noted (4.5.3 Test 13)
  -- (4.6.5 Sentry Safety) every sentry out, whoever placed it - yours, one the mod leaves to the game, another player's:
  -- id -> { unit, def, sid, mine, body (its body, worked out at most once a second), next }
  local posts = {}
  -- (4.7.0 SEAF Safety, its own option) the SEAF soldiers and civilians in the game's list of AI agents:
  -- id -> { unit, civ, at, t, v }. Their types are every friendly NPC entity in the game data (the ones with a
  -- FriendlyNpc component, from the asset index): the 11 SEAF Soldier entities (cha_battlefront_seaf and its leader,
  -- medic and specialist variants; three seen in the 4.5.3 research log) and the 16 Civilian entities
  -- (cha_seaf_city_civ and 15 unnamed ones), plus cha_seaf_civ. They walk and run, so their places are read every
  -- 'every' seconds, with a short look-ahead along how they move, like a teammate's
  local SEAF = { troops = {}, every = 0.05, margin = 0.3, lead = 0.3, reach = 100, list = nil, t = -1, types = {} }
  for _, h in ipairs({ '75f7e96af7dcd303', '6b22ae8e5f669d4f', 'a00331f24deef2ee', '548136f66f5c9b5c', 'bcfc57848f206106',
    '78dabc7344e50234', '14453b8fcb040099', '6fb1e73e00a84329', 'c47287d738be91c3', 'bfb5c88d557595d8', 'a6dcc225e1263606' }) do
    SEAF.types[EXT.type_hash(h)] = 'soldier'
  end
  for _, h in ipairs({ '4abcf54464695efa', '021eaecf4ca267dc', '0e37a0fa0a978620', '111beed56922bf4c', '341af8820251a624',
    '353c5d1070126899', '4d19a06b81fa744a', '674fb0849f8a1140', '6b09879e8677752d', '8661ca5cf58d8162', '8d435a5c9a304215',
    '9402b0fc52136a70', 'c2d93163fdbb14a1', 'cc16ff3a5eeb6d83', 'd5a6aba03479cfb8', 'e515a723de95dc3d', 'f903a153f47ad10f' }) do
    SEAF.types[EXT.type_hash(h)] = 'civilian'
  end
  -- (4.5.3: declared here, defined further down - forget() calls it; before, it called an undefined global and a Tesla
  -- Tower the mod let go of kept its rewritten target list: switching it off mid-mission left it picking nothing new)
  local tesla_unfilter
  local records_current              -- ((4.6.6 review) declared here too: forget() checks it; defined further down)
  -- ((4.6.6 review) the hidden entries' bookkeeping, moved to where the game copied the record to (its swap-remove copies
  -- the record, hidden masks and all): each entry keeps its place in the record; hider_apply checks every one by its
  -- enemy id and adopts or drops the rest)
  local function shift_hidden(H, d)
    if d == 0 then return H end
    local out = {}
    for addr, h in pairs(H) do
      if addr < 0 then out[addr] = h else out[addr + d] = { id = h.id, entry = h.entry + d, before = h.before } end
    end
    return out
  end
  local function forget(id, s, why, force)
    s.spare_ids = nil
    -- ((4.6.6 review) its hidden entries are put back only while its records are still its own (or when the option is
    -- turned off): a record the game moved may now hold another agent, and a moved copy keeps the hidden masks, so
    -- the bookkeeping is kept for when the sentry is found again)
    local own = force
    if not own and not s.moved then local okc, cur = pcall(records_current, s); own = okc and cur end
    local keep
    if own then pcall(hider_restore, s.H) elseif next(s.H) then keep = s.H end
    pcall(tesla_unfilter, s)
    remembered[id] = { heat = s.heat, heat_measured = s.heat_measured, meter_ok_t = s.meter_ok_t, P = s.P, tag = s.tag, t = os.clock(), name = s.def.name, unit = s.unit, why = why,
      H = keep, pbase = s.pbase }
    sentries[id] = nil
  end
  local function carry_over(ns, old, t)
    -- (an old record of the same sentry: its heat, cooled down for the time we lost it, and its policy)
    local h = ns.def.heat
    local gone = math.max(0, t - (old.t or t))
    -- (it may have kept firing while we couldn't see it: short gaps are not counted as cooling, and after a longer
    -- gap only the time beyond 5 s counts)
    ns.heat = h and math.max(0, (old.heat or 0) - h.cool * math.max(0, gone - 5)) or 0
    ns.heat_measured = gone < 1 and old.heat_measured or nil
    ns.meter_ok_t = ns.heat_measured and old.meter_ok_t or nil
    if old.P then ns.P = old.P; ns.P.hold = nil end
    ns.tag = old.tag
  end
  local noted_events = 0

  local function new_policy() return { unsafe_seen = {}, stuck = {}, sight_ok = {}, rest = {}, lit = {}, dead = {}, ignored = 0 } end
  -- a sentry's identity in its entity row: type, id, unit and the 'ours' flag (the rest of the row changes by itself)
  local function row_key(e) return e:sub(1, 16) .. string.char(bit.band(e:byte(21), 3)) end

  -- ------------------------------------------------------------------ finding your sentries
  local function build(f, targeting, behaviours, perception)
    need(map_lookup(targeting + 336, f.id, 16384) == f.slot, 'sentry targeting slot')
    local bi = map_lookup(behaviours + 64, f.id, 32768)
    if not bi then return nil, 'no AI record yet' end
    need(bi < 16384, 'sentry behavior index')
    need(rptr(rptr(behaviours + 88, 'behavior owners') + bi * 8, 'behavior owner') == f.ptr, 'sentry behavior owner')
    local rec_addr = rptr(behaviours + 96, 'behavior records') + bi * A.stride
    local rec = rd(rec_addr, 160, 'sentry behavior record')
    local ai = u32(rec, 0)
    if f.def.ai and ai ~= f.def.ai and not (f.def.ais and f.def.ais[ai]) then return nil, 'unexpected AI type ' .. ai end
    if u32(rec, 104) ~= f.id then return nil, 'perception owner' end
    local pi = map_lookup(perception + 48, f.id, 32768)
    if not pi then return nil, 'no perception yet' end
    need(pi < 16384, 'sentry perception index')
    need(rptr(rptr(perception + 72, 'perception owners') + pi * 8, 'perception owner') == f.ptr, 'sentry perception owner')
    local s = { def = f.def, id = f.id, unit = f.unit, row = f.row, ptr = f.ptr, ai = ai, rec_addr = rec_addr, bi = bi, pi = pi,
      pbase = rptr(perception + 80, 'perception records') + pi * 5112,
      tstate = rptr(targeting + 376, 'targeting states') + f.slot * 208, slot = f.slot, tstates = rptr(targeting + 376, 'targeting states'),
      H = {}, P = new_policy(), since = os.clock(), heat = 0,
      -- ((4.6.7 review) the two record arrays' own addresses, so records_current also catches the game moving a whole array)
      recs_base = rptr(behaviours + 96, 'behavior records'), perc_base = rptr(perception + 80, 'perception records') }
    -- the muzzle: the weapon's current fire node, a part in the sentry's pose array (optional)
    if A.g.weapons then
      pcall(function()
        local wm = rptr(A.g.weapons, 'weapons')
        local wi = map_lookup(wm + 48, f.id, 32768)
        if not wi or wi >= 16384 then return end
        if rptr(rptr(wm + 72, 'weapon owners') + wi * 8, 'weapon owner') ~= f.ptr then return end
        local wr_addr = rptr(wm + 88, 'weapon runtimes') + wi * 1008
        local wr = rd(wr_addr, 228, 'weapon runtime')
        s.wr_addr = wr_addr
        local count, index = u32(wr, 216), u32(wr, 220)
        if count > 0 and count <= 24 and index < count then
          local n = u32(wr, 120 + 4 * index)
          if n < 1024 then s.node = n end
          -- (the rocket sentry fires from several tubes in turn: the laser starts from their middle)
          s.nodes = {}
          for j = 0, count - 1 do
            local nj = u32(wr, 120 + 4 * j)
            if nj < 1024 then s.nodes[#s.nodes + 1] = nj end
          end
        end
      end)
    end
    -- (Laser Sentry) its heat meter: the game's own record of how hot it is and whether it has overheated
    if A.g.heatbar and f.def.heat then
      pcall(function()
        local hm = rptr(A.g.heatbar, 'heat meter')
        local hi = map_lookup(hm + 0x28, f.id, 32768)
        if hi and hi < 16384 and rptr(rptr(hm + 0x40, 'heat meter owners') + hi * 8, 'heat meter owner') == f.ptr then s.hb_mgr, s.hb_idx = hm, hi end
      end)
    end
    -- ((5.1.5 Test 6, test builds) the other sentries' ammo meter (the same records: +4 how much is used up), to see
    -- whether a sentry was really shooting while the damage check timed it. Read only. ((5.1.5 Test 13-15) I hoped the
    -- mortars had one too, to see each shell go; they don't, see the mortar marker in sentry_beams)
    if TESTER and A.g.heatbar and not f.def.heat then
      pcall(function()
        local hm = rptr(A.g.heatbar, 'heat meter')
        local hi = map_lookup(hm + 0x28, f.id, 32768)
        if hi and hi < 16384 and rptr(rptr(hm + 0x40, 'heat meter owners') + hi * 8, 'heat meter owner') == f.ptr then s.am_mgr, s.am_idx = hm, hi end
      end)
    end
    return s
  end

  -- are its records still where we found them? When the game removes an agent it moves the last record of each list
  -- into the freed place, and the old copy stays behind looking just like it (same AI, same owner) but no longer
  -- updated: a Laser Sentry read from such a copy showed 'no target' while it fired itself into overheating. So the
  -- lists' own index is checked every quarter second, and a sentry whose record moved is found again at once.
  local CHECK_EVERY = 0.25
  local MORTAR_EVERY = 0.05   -- ((5.1.5 Test 19) how often a busy mortar is read and steered
  -- (4.5: the lists' own addresses are looked up once a frame and shared by every sentry's check; after the game's
  -- update, sentry_after, afresh)
  local RC = { frame = -1 }
  -- ((4.6.7 review) the game's clock, read once a frame and shared by every sentry: it was read up to five times per
  -- sentry per frame)
  local CK = { frame = -1, v = 0 }
  local function clock_now()
    if CK.frame ~= FRAME then CK.v = u64(rd(rptr(A.g.clock, 'clock') + 24, 8, 'clock'), 0); CK.frame = FRAME end
    return CK.v
  end
  -- ((5.1.5 Test 19) a count that goes up whenever the game's agent lists change: the behavior list's count and records
  -- array, the perception list's owners and records arrays, and the targeting list's count (RC.tcount, read each frame
  -- by sentry_tick). Read once a frame (2 small reads); unreadable counts as changed
  RC.gen, RC.v = 0, {}
  RC.now = function()
    if RC.gen_f == FRAME then return RC.gen end
    RC.gen_f = FRAME
    local g, v = A.g, RC.v
    local bp = ptr_of(read(g.behaviours, 8), 0)
    local b = bp and read(bp + 32, 72)
    local pp = ptr_of(read(g.perception, 8), 0)
    local pr = pp and read(pp + 72, 16)
    if not (b and pr and RC.tcount) then RC.gen = RC.gen + 1; return RC.gen end
    local a1, a2, a3, a4, a5 = u32(b, 0), u64(b, 64), u64(pr, 0), u64(pr, 8), RC.tcount
    if a1 ~= v[1] or a2 ~= v[2] or a3 ~= v[3] or a4 ~= v[4] or a5 ~= v[5] then
      v[1], v[2], v[3], v[4], v[5] = a1, a2, a3, a4, a5
      RC.gen = RC.gen + 1
    end
    return RC.gen
  end
  records_current = function(s)
    local g = A.g
    if RC.frame ~= FRAME then
      RC.frame = -1
      RC.beh = rptr(g.behaviours, 'behaviours') + 64
      RC.perc = rptr(g.perception, 'perception') + 48
      RC.targ = rptr(g.targeting, 'targeting')
      RC.tstates = rptr(RC.targ + 376, 'targeting states')
      -- ((4.6.4 review) the maps' headers too, once a frame for every sentry: each look-up read its own before)
      RC.beh_h = rd(RC.beh, 20, 'map header')
      RC.perc_h = rd(RC.perc, 20, 'map header')
      RC.targ_h = rd(RC.targ + 336, 20, 'map header')
      RC.recs = rptr(RC.beh - 64 + 96, 'behavior records')
      RC.precs = rptr(RC.perc - 48 + 80, 'perception records')
      if RC.hb_h then for k in pairs(RC.hb_h) do RC.hb_h[k] = nil end else RC.hb_h = {} end
      RC.frame = FRAME
    end
    -- ((4.6.7 review) a whole array moved: every record in it is a stale copy now)
    if RC.recs ~= s.recs_base or RC.precs ~= s.perc_base then return false end
    if map_lookup(RC.beh, s.id, 32768, RC.beh_h) ~= s.bi then return false end
    if map_lookup(RC.perc, s.id, 32768, RC.perc_h) ~= s.pi then return false end
    if s.hb_mgr then
      local hh = RC.hb_h[s.hb_mgr]
      if not hh then hh = rd(s.hb_mgr + 0x28, 20, 'map header'); RC.hb_h[s.hb_mgr] = hh end
      if map_lookup(s.hb_mgr + 0x28, s.id, 32768, hh) ~= s.hb_idx then return false end
    end
    -- (5.0) its targeting state too: where it is aiming and whether that is in step with its AI. The Supply FRV's gun
    -- had it move (a Test 15 log: every poll 'not synced', so no laser); the old address then never matched again
    if s.slot and (map_lookup(RC.targ + 336, s.id, 16384, RC.targ_h) ~= s.slot or RC.tstates ~= s.tstates) then return false end
    return true
  end

  -- (4.5) Tesla Tower: it targets only what the mod has marked as an enemy. Hiding a helldiver's own entry wasn't
  -- enough: the game writes that entry afresh every frame, and test logs showed the tower picking you with your entry
  -- shown (7 times in one mission, once fatally). Taking the helldivers' faction off its list didn't work either: a
  -- Test 29 log showed its list is one faction (0) and helldivers and enemies carry the same bit (1). So its list is
  -- changed to one faction of the mod's own (MARK_ID, the count left as it is), and the entries of enemies in its
  -- list get that bit added to their masks. A helldiver's entry is never marked, so whatever the game writes into it,
  -- the tower can't pick it; if the game writes an enemy's entry afresh, that enemy is only passed over until it is
  -- marked again. The start of its perception record: a count at +0, then one faction id every 8 bytes from +8.
  -- All is put back when the tower is let go (only through records confirmed current: a record the game gave up may
  -- belong to another agent by now)
  local MARK_ID = 30
  local function count_action(k, n) session.actions[k] = (session.actions[k] or 0) + n end
  local MARK = bit.lshift(1, MARK_ID)
  local function pack32(v) return string.char(bit.band(v, 255), bit.band(bit.rshift(v, 8), 255), bit.band(bit.rshift(v, 16), 255), bit.band(bit.rshift(v, 24), 255)) end
  local function tesla_filter(s, st, bodies)
    local perc, P = st.perc, s.P
    if READ_ONLY or not perc then return end
    local n = u32(perc, 0)
    if n == 0 or n > 32 then return end
    -- its list: every place set to the mod's own faction
    local had = P.filter_orig ~= nil   -- ((4.6.7 review) taken before the loop: set in it, the first pass counted as a rewrite)
    local base, changed, rewritten = P.filter_orig, false, false
    if not base then
      base = {}
      local all = true
      for j = 0, n - 1 do base[j] = u32(perc, 8 + j * 8); if base[j] ~= MARK_ID then all = false end end
      -- ((4.6.7 review) its list already all the mod's faction with nothing saved - the saved list was lost, say after an
      -- error put the sentries back: the game's own list, faction 0 (Test 29 log), is taken as the original, so the
      -- tower is marked for and later put back instead of standing idle for the rest of the mission)
      if all then for j = 0, n - 1 do base[j] = 0 end; P.filter_orig = base end
    end
    for j = 0, n - 1 do
      local now = u32(perc, 8 + j * 8)
      if now ~= MARK_ID then
        if had then rewritten = true end
        P.filter_orig = base
        if write(s.pbase + 8 + j * 8, pack32(MARK_ID)) then changed = true else stats.write_failures = stats.write_failures + 1 end
      end
    end
    if not P.filter_orig then return end
    if changed and not P.factions_noted then
      P.factions_noted = true
      local l = {}; for j = 0, n - 1 do l[#l + 1] = tostring(base[j]) end
      event(string.format('sentry: %s now targets only enemies the mod has marked (its factions %s -> %d)', (s.tag or s.def.name), table.concat(l, ' '), MARK_ID))
    end
    if rewritten then
      P.filter_rewrites = (P.filter_rewrites or 0) + 1
      bump(session.actions, 'tesla_factions_rewritten')
      if P.filter_rewrites <= 5 then event(string.format('sentry: %s had its factions written back by the game: set again (checked every frame from now on)', (s.tag or s.def.name))) end
    end
    -- the enemies in its list marked: only entries of a known enemy type - never a helldiver, nor an entry whose type
    -- can't be read (a helldiver's can read as one for a moment). Hidden ones are marked in what they get back when
    -- they are shown again. Only entries just marked (or all of them, the frame its list is changed) have whether it
    -- may pick them worked out again: the others were read against its list as it is
    local marked = P.marked or {}
    P.marked = marked
    -- (its records moved: the copy carries the marks, at the same places in the new record)
    if P.marked_base and P.marked_base ~= s.pbase then
      local d, moved_marks = s.pbase - P.marked_base, {}
      for addr, m in pairs(marked) do moved_marks[addr + d] = { id = m.id, entry = m.entry + d, before = m.before } end
      marked = moved_marks; P.marked = marked
    end
    P.marked_base = s.pbase
    local lost = 0
    local NOMARK = bit.bnot(MARK)
    for _, c in ipairs(st.candidates) do
      local k = c.kind
      local addr = c.mask_addr
      local h = s.H[addr]
      if h and h.id ~= c.id then h = nil end
      if k and k ~= AVATAR_TYPE then
        local fresh = changed
        if c.mask == BLANK then
          -- (Test 34: never onto an unknown or blank saved mask - a Test 33 log had your entry carry the mark on a blank
          -- mask, 60202020, and the tower pick you 12 times)
          local hb = h and u32(h.before, 0)
          if hb and h.before ~= BLANK and bit.band(hb, 0x20202020) ~= 0x20202020 and bit.band(hb, MARK) == 0 then
            local orig = h.before
            h.before = pack32(bit.bor(hb, MARK))
            marked[addr] = { id = c.id, entry = c.entry, before = orig }
            fresh = true
          end
        else
          local v = u32(c.mask, 0)
          if bit.band(v, MARK) == 0 then
            -- (an entry it had marked, written afresh by the game: counted - if it happens a lot, the tower passes
            -- enemies over)
            local m0 = marked[addr]
            if m0 and m0.id == c.id then lost = lost + 1 end
            local m = pack32(bit.bor(v, MARK))
            if write(addr, m) then
              marked[addr] = { id = c.id, entry = c.entry, before = c.mask }
              c.mask = m
              fresh = true
            else stats.write_failures = stats.write_failures + 1 end
          end
        end
        if fresh then
          -- (a hidden entry with nothing saved for it - hidden by something else - counts as not pickable: a Test 37 review)
          local m = c.mask == BLANK and (h and h.before) or c.mask
          c.eligible = c.alive and bit.band(c.flags or 0, 1) ~= 0 and m and m ~= BLANK and bit.band(u32(m, 0), MARK) ~= 0 and (c.score or 0) > 0 or false
        end
      else
        -- a helldiver's entry, or one whose type can't be read (Test 34: never marked - a helldiver's entry can read as
        -- one for a moment): the mark taken off if it carries it, in its entry and in what it would get back
        if c.mask ~= BLANK and bit.band(u32(c.mask, 0), MARK) ~= 0 then
          local m = pack32(bit.band(u32(c.mask, 0), NOMARK))
          if write(addr, m) then c.mask = m; count_action(k == AVATAR_TYPE and 'tesla_mark_taken_off_helldiver' or 'tesla_mark_taken_off_unknown', 1) else stats.write_failures = stats.write_failures + 1 end
        end
        if h and bit.band(u32(h.before, 0), MARK) ~= 0 then h.before = pack32(bit.band(u32(h.before, 0), NOMARK)) end
        marked[addr] = nil
        c.eligible = false
      end
    end
    if lost > 0 then
      P.marks_lost = (P.marks_lost or 0) + lost
      count_action('tesla_mark_rewritten', lost)
      if not P.lost_noted and P.marks_lost >= 20 then
        P.lost_noted = true
        event(string.format('sentry: %s: the game has written enemies\' entries afresh %d times (each passed over until marked again)', (s.tag or s.def.name), P.marks_lost))
      end
    end
    -- (forget marks on entries now holding something else)
    if (P.mark_clean or 0) <= FRAME then
      P.mark_clean = FRAME + 60
      for addr, m in pairs(marked) do
        local id_now = read(m.entry, 4)
        if not (id_now and u32(id_now, 0) == m.id) then marked[addr] = nil end
      end
    end
    P.filter_on = true
    -- (the helldivers' entries are hidden from it as well, every frame: a Test 32 log had it pick you 25 times with the
    -- marking on, right after its records moved twice. The code that let a tower that is safe by its marking alone off
    -- that - 'faction_safe', Test 25-32 - is gone, a Test 37 review: it can come back once the marking has held in game)
  end
  -- (the list is kept as it was found until it has been written back: if the tower's records can't be confirmed now -
  -- moved, say - the original goes with what is remembered about the tower, for when it is found again). The marks
  -- are taken off the enemies' entries still holding them (after the hidden ones have been shown again)
  tesla_unfilter = function(s)
    local P = s.P
    local o = P and P.filter_orig
    if not o then return end
    if READ_ONLY then return end
    local okc, cur = pcall(records_current, s)
    if okc and cur and not s.moved then
      for j, f in pairs(o) do if not write(s.pbase + 8 + j * 8, pack32(f)) then stats.write_failures = stats.write_failures + 1 end end
      for addr, m in pairs(P.marked or {}) do
        local id_now = read(m.entry, 4)
        local now = id_now and u32(id_now, 0) == m.id and read(addr, 4)
        if now and bit.tobit(u32(now, 0)) == bit.bor(u32(m.before, 0), MARK) then   -- ((4.6.7 review) both signed: a mask with bit 31 set never matched)
          if not write(addr, m.before) then stats.write_failures = stats.write_failures + 1 end
        end
      end
      P.filter_orig, P.filter_on, P.marked, P.marked_base = nil, false, nil, nil
    end
  end

  -- ((4.6.4 review) 'from': only the rows from there on - the game appends new agents at the end of its list, so when
  -- the count rises (every enemy that spawns) only the new rows are read; the full scan, which also drops sentries
  -- that went, stays on its 2 s timer)
  -- ((4.7.0) 'seaf_only': with the Sentries option off, only the SEAF soldiers and civilians are kept, for the dog)
  local function scan(t, from, seaf_only)
    local g = A.g
    local targeting, behaviours, perception = rptr(g.targeting, 'targeting'), rptr(g.behaviours, 'behaviours'), rptr(g.perception, 'perception')
    local reg = rd(targeting + 308, 84, 'targeting registry')
    local tn, ta = u32(reg, 0), u32(reg, 12)
    need(ta <= tn and tn <= 8192, 'targeting registry')
    last_count = ta
    if from and (from >= ta or from < 0) then return end
    local i0 = from or 0
    local ptrs = ta > i0 and rd(rptr(targeting + 360, 'targeting entities') + 8 * i0, 8 * (ta - i0), 'targeting entities') or ''
    local seen, others, pseen, fseen = {}, 0, {}, {}
    local full = not from
    for i = i0, ta - 1 do
      local p = ptr_of(ptrs, (i - i0) * 8)
      local e = p and read(p, 24)
      if e then
        local ty = e:sub(1, 8)
        local def = not seaf_only and SENTRY_BY_TYPE[ty] or nil
        -- (4.7.0 SEAF Safety: every SEAF soldier and civilian, whoever's game runs them)
        if not def and SEAF.types[ty] then
          local id, unit = u32(e, 8), u32(e, 12)
          fseen[id] = true
          local q = SEAF.troops[id]
          if not q or q.unit ~= unit then SEAF.troops[id] = { unit = unit, civ = SEAF.types[ty] == 'civilian' } end
        end
        -- (4.6.5 Sentry Safety: every sentry out, whoever's; not the guns on a resupply pod or the Supply FRV)
        if def and not (def.vehicle or def.mount) then
          local id, unit = u32(e, 8), u32(e, 12)
          pseen[id] = true
          local q = posts[id]
          if not q or q.unit ~= unit or q.def ~= def then posts[id] = { unit = unit, def = def, sid = id, mine = EXT.is_local(e) } end
        end
        -- (the Tesla Tower is left to the game when the Sentries option is set to leave it out: it is simply not taken
        -- on, like another player's sentry)
        local skip = def and def.spares_helldivers and not OPT.tesla()
        if def and not skip then
          if EXT.is_local(e) then
            local id = u32(e, 8)
            seen[id] = true
            local s = sentries[id]
            if not (s and s.row == row_key(e) and s.ptr == p and not s.moved) then
              local ok, ns, why = pcall(build, { def = def, ptr = p, row = row_key(e), id = id, unit = u32(e, 12), slot = i }, targeting, behaviours, perception)
              if ok and ns then
                -- (the enemies hidden from it stay hidden: in its perception record, or (4.6.6 review) where the game
                -- copied that record to - before, they were put back through the old record, which may already hold
                -- another agent, and the copies were left blanked with nothing to put them back)
                local r = remembered[id]
                if s then ns.H = shift_hidden(s.H, ns.pbase - s.pbase)
                elseif r and r.H and r.name == def.name and r.unit == ns.unit then ns.H = shift_hidden(r.H, ns.pbase - r.pbase) end
                sentries[id] = ns
                local d = session.sentries[def.name] or { placed = 0, out = 0, targeted = 0, stops = 0, mate_stops = 0, armour = 0 }
                session.sentries[def.name] = d
                -- (4.6.4) how many of this kind are out at once (every sentry's cooldown is shorter than its lifetime, so
                -- two or more of a kind are common)
                local same = 0
                for _, o in pairs(sentries) do if o.def == def then same = same + 1 end end
                if same > (d.max_out or 0) then d.max_out = same end
                local old = s and { heat = s.heat, heat_measured = s.heat_measured, meter_ok_t = s.meter_ok_t, P = s.P, tag = s.tag, t = t } or (remembered[id] and remembered[id].name == def.name and remembered[id].unit == u32(e, 12) and t - remembered[id].t <= 120 and remembered[id])
                if old then
                  carry_over(ns, old, t)
                  if TESTER and refound_notes < 10 then
                    refound_notes = refound_notes + 1
                    event(string.format('sentry: %s found again (%s; heat kept at %.0f%%)', ns.tag or def.name,
                      s and (s.moved and ('its AI records moved' .. (s.moved_how and (', ' .. s.moved_how) or '')) or s.ptr ~= p and 'its record moved' or 'its record changed') or ('lost for ' .. string.format('%.1fs', t - old.t) .. ', ' .. tostring(old.why)),
                      def.heat and 100 * ns.heat / def.heat.cap or 0))
                  end
                else
                  d.placed = d.placed + 1
                  d.ai = ns.ai   -- ((5.1.5 Test 13) its AI id in the summary line too: the 'out' event can scroll out of the recent events
                  -- (4.6.4) numbered in the log (the n-th of its kind placed this session), so two out at once - two
                  -- Laser Sentries, say: one cools down faster than it lasts - can be told apart
                  ns.tag = def.name .. ' #' .. d.placed
                  -- ((5.1.5 Test 26, test builds) where it is, from you: my Test 23/24 games had a Gatling Sentry nobody
                  -- called show up 40-50 m from me ~30 s into the mission and fire at Troopers)
                  local where = ''
                  if TESTER then
                    local okp, bp = pcall(unit_position, ns.unit)
                    local me = EXT.me
                    if okp and bp then
                      where = string.format('; at %.1f %.1f %.1f', bp[1], bp[2], bp[3])
                      if me then where = where .. string.format(', %.0f m from you level, %+.1f m above you', math.sqrt((bp[1] - me[1]) ^ 2 + (bp[2] - me[2]) ^ 2), bp[3] - me[3]) end
                      ns.out_at = bp
                    end
                    where = where .. string.format(', entity %d unit %d row %d', id, ns.unit, i)
                  end
                  event(string.format('sentry: %s out (AI %d%s)%s', ns.tag, ns.ai, ns.node and (', muzzle part ' .. ns.node) or ', muzzle not found: using its position', where))
                  if TESTER then session.places = session.places or {}; if #session.places < 40 then session.places[#session.places + 1] = string.format('%.0fs %s out%s', t, ns.tag, where) end end
                end
                remembered[id] = nil
              else
                local why2 = ok and why or (type(ns) == 'table' and tostring(ns[2]) or tostring(ns))
                if s then forget(id, s, why2) end   -- (keeps its heat for when it is set up again)
                -- (once per sentry and reason: a sentry that can't be steered is tried again at every scan)
                if not remembered[id] and not_steered[id] ~= why2 then
                  not_steered[id] = why2
                  event(string.format('sentry: %s not steered (%s)', def.name, why2))
                end
              end
            end
          else
            others = others + 1
            -- (4.5.3 Test 13, test builds) what such a sentry is: a tester saw two in a solo game (Test 11 log), so
            -- either something in the mission uses a sentry's type or a sentry of yours was not taken as yours.
            -- Noted once each (up to 10): its kind, id, unit, the flag byte the mod reads and its AI
            if TESTER then
              local id = u32(e, 8)
              local N = other_noted
              if not N[id] and (N.count or 0) < 10 then
                N[id], N.count = true, (N.count or 0) + 1
                local bi = map_lookup(behaviours + 64, id, 32768)
                local ai = bi and bi < 16384 and read(rptr(behaviours + 96, 'behavior records') + bi * A.stride, 4)
                event(string.format('sentry (test): a %s not run by this game (id %d, unit %d, flag byte %d, AI %s)', def.name, id, u32(e, 12), e:byte(21),
                  ai and tostring(u32(ai, 0)) or 'none'))
              end
            end
            -- (4.5) another player's Tesla Tower: their game runs it, so this mod can't keep it off helldivers - noted
            -- once each, so a zap from one can be told apart from one by yours
            if def.spares_helldivers then
              local id = u32(e, 8)
              if not other_teslas[id] then other_teslas[id] = true; event('sentry: another player\'s Tesla Tower is out (run by their game: not steered by this mod)') end
            end
          end
        elseif not def and not seaf_only and EXT.is_local(e) and type_ai[ty] == nil then
          -- the first time a kind of agent shows up on your side: note it if it runs a sentry's AI but isn't known
          -- (that is how the Armed Resupply Pod's and the Supply FRV's guns were found, 4.0.6 Test 8)
          type_ai[ty] = false
          pcall(function()
            local bi = map_lookup(behaviours + 64, u32(e, 8), 32768)
            if not bi or bi >= 16384 then return end
            local ai = u32(rd(rptr(behaviours + 96, 'behavior records') + bi * A.stride, 4, 'behavior record'), 0)
            type_ai[ty] = ai
            if SENTRY_AI[ai] then event(string.format('unknown sentry-like agent on your side: type %s, AI %d (not steered)', EXT.hexr(ty), ai)) end
          end)
          -- (4.6.6 numbered Tester builds: every new kind of agent of yours, AI and perception record or not - to see
          -- whether a thrown Seeker grenade is one, and with what)
          if TESTER and TEST_BUILD then
            pcall(function()
              local id = u32(e, 8)
              local pi = map_lookup(perception + 48, id, 32768)
              event(string.format('agent (test): a new kind on your side: type %s, unit %d, AI %s, perception record %s', EXT.hexr(ty), u32(e, 12),
                type_ai[ty] and tostring(type_ai[ty]) or 'none', (pi and pi < 16384) and 'yes' or 'no'))
            end)
          end
        end
      end
    end
    if not full then return end
    for id in pairs(SEAF.troops) do if not fseen[id] then SEAF.troops[id] = nil end end
    if seaf_only then return end
    for id, s in pairs(sentries) do
      if not seen[id] then
        -- ((5.1.5 Test 26, test builds) where it was when it went, and whether it had moved since it came out)
        if TESTER and s.out_at and s.st and s.st.base then
          local b, o = s.st.base, s.out_at
          local line = string.format('%s gone, last at %.1f %.1f %.1f (moved %.1f m since it came out)', s.tag or s.def.name, b[1], b[2], b[3],
            math.sqrt((b[1] - o[1]) ^ 2 + (b[2] - o[2]) ^ 2 + (b[3] - o[3]) ^ 2))
          event('sentry: ' .. line)
          session.places = session.places or {}
          if #session.places < 40 then session.places[#session.places + 1] = string.format('%.0fs %s', t, line) end
        end
        forget(id, s, 'not in the list')
      end
    end
    for id in pairs(posts) do if not pseen[id] then posts[id] = nil end end
    for id, r in pairs(remembered) do if t - r.t > 120 then remembered[id] = nil end end
    if others > session.other_sentries then session.other_sentries = others end
  end

  -- ------------------------------------------------------------------ reading one sentry
  local function norm(v) local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]); if l < 1e-6 then return nil end return { v[1] / l, v[2] / l, v[3] / l }, l end
  local function finite3(x, y, z) return x == x and y == y and z == z and math.abs(x) < 1e6 and math.abs(y) < 1e6 and math.abs(z) < 1e6 end

  local FAR_ROW_EVERY = 0.25    -- ((5.1.5 review) how often a far target's registry row is looked up again (s)
  -- ((5.1.5 Test 31) an enemy the game has a sentry on that isn't in its own list (far off - my Test 30 log: mortars
  -- 1,296 frames, the Autocannon 139), from the registry. The marker and laser draw it, and it doesn't count as dead
  -- while the registry has it (before, the mod took it for a kill and asked the sentry to choose again). Its place: its
  -- unit's, else where its list last had it.
  -- ((5.1.5 review) its row four times a second, not every read (the map look-up and the row), and its health then: a
  -- dead enemy stays in the registry about a second, and its marker sat on the corpse that long, with the sentry left
  -- waiting to choose again. Health 0 = dead. Its place is still read every time, for drawing)
  local function far_entry(s, registry, id, t, M)
    local F = s.farc
    if not (F and F.id == id and t < F.t) then
      local okr, re = pcall(entity_row, registry, id)
      re = okr and re or nil
      if re then local hp = HEALTH.of(id); if hp and hp <= 0 then re = nil end end
      F = F or {}; s.farc = F
      F.id, F.re, F.t = id, re, t + FAR_ROW_EVERY
    end
    local re = F.re
    if not re then return nil end
    local p = unit_position(u32(re, 12)) or (s.tg_last and s.tg_last.id == id and s.tg_last.pos)
    if not p then return nil end
    s.far = s.far or {}
    local c = s.far
    c.id, c.ent, c.kind, c.alive, c.pos, c.live_f = id, re, re:sub(1, 8), true, p, nil
    c.d2 = (p[1] - M[1]) ^ 2 + (p[2] - M[2]) ^ 2 + (p[3] - M[3]) ^ 2
    return c
  end
  local function read_sentry(s, registry, t)
    local e = read(s.ptr, 24)
    if not e or row_key(e) ~= s.row then return nil, 'gone' end
    local rec = read(s.rec_addr, 160)
    if not (rec and u32(rec, 0) == s.ai and u32(rec, 104) == s.id) then return nil, 'gone' end
    local base = unit_position(s.unit)
    if not base then return nil, 'no position' end
    local muzzle, axes
    -- ((5.1.5 review) with a barrel part ('barrel_from', the Autocannon's) both parts come in one read: they sit
    -- (node - barrel_from) * 64 bytes apart in the pose array)
    local bf = s.def.barrel_from
    local lo = (bf and s.node == s.def.barrel_node and bf < s.node) and bf or s.node
    local mp, mo
    if s.node and base.pose then
      mp = read(base.pose + 64 * lo, 64 * (s.node - lo + 1))
      mo = 64 * (s.node - lo)
      local m = mp
      if m then
        local x, y, z = f32(m, mo + 48), f32(m, mo + 52), f32(m, mo + 56)
        if finite3(x, y, z) and (x - base[1]) ^ 2 + (y - base[2]) ^ 2 + (z - base[3]) ^ 2 < 16 then
          muzzle, axes = { x, y, z }, {}
          for r = 0, 2 do
            local a = norm({ f32(m, mo + r * 16), f32(m, mo + r * 16 + 4), f32(m, mo + r * 16 + 8) })
            if not a then axes = nil; break end
            axes[r + 1] = a
          end
        end
      end
    end
    -- the middle of all its fire points (several tubes or barrels): where the laser starts
    local centre = muzzle
    if muzzle and s.nodes and #s.nodes > 1 and EXT.laser_wanted() then
      local sx, sy, sz, n = 0, 0, 0, 0
      for _, nd in ipairs(s.nodes) do
        local m = read(base.pose + 64 * nd, 64)
        local x, y, z = m and f32(m, 48), m and f32(m, 52), m and f32(m, 56)
        if m and finite3(x, y, z) and (x - base[1]) ^ 2 + (y - base[2]) ^ 2 + (z - base[3]) ^ 2 < 16 then sx, sy, sz, n = sx + x, sy + y, sz + z, n + 1 end
      end
      if n > 0 then centre = { sx / n, sy / n, sz / n } end
    end
    local st = { base = base, muzzle = muzzle or { base[1], base[2], base[3] + (s.def.muzzle_up or MUZZLE_UP) }, axes = axes, has_muzzle = muzzle ~= nil }
    st.centre = centre or st.muzzle
    -- ((5.1.5 Test 29, my ask: "fix the laser on the autocannon sentry so it behaves as the other do") its barrel's
    -- direction from two of its parts: the gun housing and the muzzle at the barrel's end ('barrel_from', the housing's
    -- part number in the game model; the muzzle sits 'barrel_len' m out along the barrel from it) - so its laser runs
    -- along the barrel like every other sentry's, whatever the muzzle part's own axes say. Only while the two parts are
    -- that far apart (within 0.4 m)
    if muzzle and lo ~= s.node then
      local m = mp
      local x, y, z = f32(m, 48), f32(m, 52), f32(m, 56)
      if m and finite3(x, y, z) then
        local d, len = norm({ muzzle[1] - x, muzzle[2] - y, muzzle[3] - z })
        if d and math.abs(len - s.def.barrel_len) < 0.4 then st.bdir = d end
      end
    end
    s.cpool = s.cpool or {}
    st.candidates, st.perc = EXT.read_candidates(s.pbase, st.muzzle, registry, s.def.spares_helldivers, s.cpool, u32(rec, 24))
    st.target, st.node, st.rec_head = u32(rec, 24), u32(rec, 8), rec:sub(1, 4)
    st.deadline = u64(rec, 152)
    local ts = st.target ~= 0 and read(s.tstate, 32) or nil
    st.synced = st.target ~= 0 and ts ~= nil and u32(ts, 0) == st.target and rec:byte(121) == 1 and bit.band(u32(rec, 96), 1) ~= 0
    if st.synced then
      local x, y, z = f32(ts, 20), f32(ts, 24), f32(ts, 28)     -- where it is actually aiming (with lead)
      if finite3(x, y, z) and (x ~= 0 or y ~= 0 or z ~= 0) then st.aim = { x, y, z } end
    end
    for _, c in ipairs(st.candidates) do if c.id == st.target then st.current = c end end
    -- ((5.1.5 Test 31) its target from the registry when its list doesn't have it (far_entry); where its list last had it
    if st.current and st.current.pos then s.tg_last = s.tg_last or {}; s.tg_last.id, s.tg_last.pos = st.target, st.current.pos end
    if st.target ~= 0 and not st.current then st.far = far_entry(s, registry, st.target, t, st.muzzle) end
    -- ((5.1.5 review) the Autocannon's salvo hold (sentry_beams) on an enemy its AI has let go of and its list doesn't
    -- have either: from the registry too (before, the hold only looked in its list, and its marker went)
    local K = s.def.salvo and s.P and s.P.salvo_keep
    if st.target == 0 and K and K.firing and t - K.t < SALVO_HOLD then
      local inl = false
      for _, c in ipairs(st.candidates) do if c.id == K.id then inl = true; break end end
      if not inl then st.far_keep = far_entry(s, registry, K.id, t, st.muzzle) end
    end
    return st
  end

  -- which axis of the muzzle part is the barrel (per sentry kind, learned while it fires at enemies in view). (4.5)
  -- Decided only once it has aimed at least 30 degrees apart: aimed one way only, an axis that happens to point that
  -- way matches just as well as the barrel
  local BARREL_SPREAD = 0.87
  local function barrel_dir(s, st)
    local b = barrel[s.def.name]
    if not b then b = { sums = {}, n = 0, tries = 0 }; barrel[s.def.name] = b end
    if not st.axes then return nil end
    -- (kinds whose barrel axis is already known from testing don't need to learn it: axis 2+ for the machine gun,
    -- Gatling and Laser sentries and the pod and FRV guns; a Laser Sentry swung between targets a lot once failed to
    -- learn it, 0.905)
    if not b.axis and s.def.barrel_axis then b.axis, b.sign = s.def.barrel_axis, 1 end
    if b.axis then local a = st.axes[b.axis]; return { a[1] * b.sign, a[2] * b.sign, a[3] * b.sign } end
    if b.tries >= BARREL.tries or not s.def.sweep then return nil end   -- (only sentries whose turns are checked need it)
    local c = st.current
    if st.synced and st.aim and c and c.visible then
      local v, len = norm({ st.aim[1] - st.muzzle[1], st.aim[2] - st.muzzle[2], st.aim[3] - st.muzzle[3] })
      -- (only while its aim is steady: while it swings round, the barrel lags the aim)
      local p = s.last_aim_dir
      s.last_aim_dir = v
      if v and len > 5 and p and v[1] * p[1] + v[2] * p[2] + v[3] * p[3] > 0.9995 then
        for r = 1, 3 do
          local cos = dot3(st.axes[r], v)
          b.sums[2 * r - 1] = (b.sums[2 * r - 1] or 0) + cos
          b.sums[2 * r] = (b.sums[2 * r] or 0) - cos
        end
        b.n = b.n + 1
        if not b.d0 then b.d0 = v end
        b.spread = math.min(b.spread or 1, dot3(b.d0, v))
        if b.n >= BARREL.frames and b.spread <= BARREL_SPREAD then
          local best, bk
          for k, sum in pairs(b.sums) do if not best or sum > best then best, bk = sum, k end end
          b.tries = b.tries + 1
          local mean = best / b.n
          if mean >= (s.def.barrel_min or BARREL.min_cos) then
            b.axis, b.sign = math.floor((bk + 1) / 2), bk % 2 == 1 and 1 or -1
            note(string.format('%s: barrel found (axis %d%s, match %.3f)', s.def.name, b.axis, b.sign > 0 and '+' or '-', mean))
          elseif b.tries >= BARREL.tries then
            note(string.format('%s: barrel not found (best match %.3f, axis %d%s); its turns are not checked', s.def.name, mean, math.floor((bk + 1) / 2), bk % 2 == 1 and '+' or '-'))
          end
          b.sums, b.n, b.d0, b.spread = {}, 0, nil, nil
        end
      end
    end
    return nil
  end

  -- ------------------------------------------------------------------ who must not be hit
  local VEHICLE_BODY = { top = 3.8, extra = 1.0 }   -- (4.6.5: an exosuit is ~3.5 m tall and ~2 m across)
  local vehicle_notes = {}
  -- ((5.1.5 Test 22) the body-maker outside, not a new little function every call: making one stopped the game's LuaJIT
  -- (2.1.0-alpha) compiling all of bodies_for, which runs every frame while a sentry works)
  local function body_add(out, p, extra, mate)
    out[#out + 1] = { lo = { p[1], p[2], p[3] + SAFE.body_bottom }, hi = { p[1], p[2], p[3] + SAFE.body_top }, at = p, extra = extra, mate = mate }
  end
  local function bodies_for(me, mates)
    local out = {}
    if me and OPT.safety() then
      -- ((4.6.5) piloting a vehicle - an exosuit, say: a larger body round it, its height and width)
      if me.vehicle then out[#out + 1] = { lo = { me[1], me[2], me[3] }, hi = { me[1], me[2], me[3] + VEHICLE_BODY.top }, at = me, extra = VEHICLE_BODY.extra, mate = false, piloting = true }
      else body_add(out, me, 0, false) end   -- (you: with the Safety option on)
    end
    if mates then
      for _, m in ipairs(mates) do
        body_add(out, m, TEAM.margin, true)
        local v = m.vel
        if v and v[1] * v[1] + v[2] * v[2] > 1 then body_add(out, { m[1] + v[1] * TEAM.lead, m[2] + v[2] * TEAM.lead, m[3] + v[3] * TEAM.lead }, TEAM.margin, true); out[#out].lead = true end
      end
    end
    return out
  end

  -- (4.6.5, my note: Sentry Safety, its own option) every sentry out - yours, a teammate's, one the mod leaves to the game -
  -- is a body your sentries don't fire through, swing their fire across or blast (each sentry leaves out its own body;
  -- the Tesla Tower's arc spares sentries, 'spares_sentries'). Its place is read at most once a second (a sentry
  -- stands still once its pod has landed); the list is made at most four times a second
  -- ((4.6.5 review) 'kh': each kind's height learned from your own sentries - their muzzle's height above their base
  -- plus 0.3 m, never below the kind's set height or 1.8 m - so another player's Rocket or Autocannon Sentry is as tall
  -- as yours)
  local POST = { bottom = 0.3, top = 1.8, extra = 0.5, every = 1.0, list = nil, t = -1, kh = {} }
  local function post_bodies(t)
    if not next(posts) or not OPT.sentry_safety() then return nil end
    if POST.list and t < POST.t then return POST.list end
    POST.t = t + 0.25
    local out = {}
    for id, q in pairs(posts) do
      if t >= (q.next or 0) then
        q.next = t + POST.every
        local p = unit_position(q.unit)
        if p then
          local b = q.body
          local h = math.max(q.def.height or POST.top, POST.kh[q.def.name] or 0)
          if not (b and b.at[1] == p[1] and b.at[2] == p[2] and b.at[3] == p[3] and b.h == h) then
            q.body = { lo = { p[1], p[2], p[3] + POST.bottom }, hi = { p[1], p[2], p[3] + h }, at = { p[1], p[2], p[3] }, extra = POST.extra, sentry = true, sid = id, h = h }
          end
        else q.body = nil end
      end
      if q.body then out[#out + 1] = q.body end
    end
    -- (Testers: how many it guards, whose, and how many it could not place - each time that changes, first 10)
    if TESTER and (POST.notes or 0) < 10 then
      local mine, n = 0, 0
      for _, q in pairs(posts) do n = n + 1; if q.body and q.mine then mine = mine + 1 end end
      local key = n .. '/' .. #out .. '/' .. mine
      if key ~= POST.key then
        POST.key, POST.notes = key, (POST.notes or 0) + 1
        event(string.format('sentry safety (test): %d sentries out, %d guarded (%d yours, %d another player\'s)%s', n, #out, mine, #out - mine,
          n > #out and string.format(', %d with no position yet', n - #out) or ''))
      end
    end
    POST.list = out
    return out
  end

  -- (4.7.0 SEAF Safety) the SEAF soldiers' and civilians' bodies: as tall as a helldiver, a little wider (their places are read ten
  -- times a second), and a second body where a running one will be a moment later; only soldiers within 'reach' of you
  -- (your sentries stand near you; a squad across the map would only cost time). Nil with the option off or none around
  local function seaf_bodies(t, me)
    if not next(SEAF.troops) or not OPT.seaf_safety() then return nil end
    if SEAF.list and t < SEAF.t then return SEAF.list end
    SEAF.t = t + SEAF.every
    local out = {}
    for _, q in pairs(SEAF.troops) do
      local p = unit_position(q.unit)
      if p and me and (p[1] - me[1]) ^ 2 + (p[2] - me[2]) ^ 2 > SEAF.reach ^ 2 then p, q.at = nil, nil end
      if p then
        local dt = t - (q.t or -99)
        if q.at and dt > 0.02 and dt < 0.5 then
          q.v = { (p[1] - q.at[1]) / dt, (p[2] - q.at[2]) / dt, (p[3] - q.at[3]) / dt }
        elseif not (q.at and dt <= 0.02) then q.v = nil end
        q.at, q.t = p, t
        out[#out + 1] = { lo = { p[1], p[2], p[3] + SAFE.body_bottom }, hi = { p[1], p[2], p[3] + SAFE.body_top }, at = p, extra = SEAF.margin, seaf = true, civ = q.civ }
        local v = q.v
        if v and v[1] * v[1] + v[2] * v[2] > 0.25 and v[1] * v[1] + v[2] * v[2] < 144 then
          local a = { p[1] + v[1] * SEAF.lead, p[2] + v[2] * SEAF.lead, p[3] }
          out[#out + 1] = { lo = { a[1], a[2], a[3] + SAFE.body_bottom }, hi = { a[1], a[2], a[3] + SAFE.body_top }, at = a, extra = SEAF.margin, seaf = true, civ = q.civ, lead = true }
        end
      end
    end
    -- (Testers: how many it guards - each time that changes, first 10)
    if TESTER and (SEAF.notes or 0) < 10 then
      local n, nc = 0, 0
      for _, q in pairs(SEAF.troops) do if q.civ then nc = nc + 1 else n = n + 1 end end
      local key = n .. '/' .. nc .. '/' .. #out
      if key ~= SEAF.key then
        SEAF.key, SEAF.notes = key, (SEAF.notes or 0) + 1
        event(string.format('SEAF safety (test): %d SEAF soldiers and %d civilians in the agent list, %d bodies guarded (with look-ahead)', n, nc, #out))
      end
    end
    SEAF.list = out
    return out
  end
  TEAM.seaf_bodies = seaf_bodies   -- ((4.7.0) the guard dog's safety uses them too: bodies_of, engine_logic.lua)

  -- does turning the barrel from 'f' onto 'aim' carry its line over the body? (the turn follows the shortest way
  -- round; when the enemy is almost straight behind it, either way is possible and the whole height band counts)
  -- ((4.6.4 review) the same as before, worked in plain numbers: it made a handful of small tables per enemy, per body,
  -- per frame for every sentry whose turns are checked)
  local function nrm(x, y, z) local l = math.sqrt(x * x + y * y + z * z); if l < 1e-6 then return nil end; return x / l, y / l, z / l, l end
  local function cl1(x) return x < -1 and -1 or (x > 1 and 1 or x) end
  local function sweep_hits(M, f, aim, b, def)
    local dx, dy, dz, L = nrm(aim[1] - M[1], aim[2] - M[2], aim[3] - M[3])
    if not dx then return false end
    local f1, f2, f3 = f[1], f[2], f[3]
    local T = math.acos(cl1(f1 * dx + f2 * dy + f3 * dz))
    if T < math.rad(SWEEP.min_deg) then return false end
    local both = T > math.rad(SWEEP.both_ways_deg)
    local nx, ny, nz
    if not both then
      nx, ny, nz = nrm(f2 * dz - f3 * dy, f3 * dx - f1 * dz, f1 * dy - f2 * dx)
      if not nx then return false end
    end
    local lo, hi, at = b.lo[3], b.hi[3], b.at
    for k = 1, 3 do
      local z = k == 1 and lo or (k == 2 and (lo + hi) / 2 or hi)
      local vx, vy, vz, r = nrm(at[1] - M[1], at[2] - M[2], z - M[3])
      if vx and r > 0.3 and r < L + 1 and r < SWEEP.reach then
        local alpha = math.atan((def.line + def.spread * r + b.extra) / r)
        local off
        if both then
          local ev, ef, ed = math.asin(vz), math.asin(cl1(f3)), math.asin(dz)
          off = (ev >= math.min(ef, ed) - alpha and ev <= math.max(ef, ed) + alpha) and 0 or math.huge
        else
          local sn = vx * nx + vy * ny + vz * nz
          local px, py, pz = nrm(vx - nx * sn, vy - ny * sn, vz - nz * sn)
          if not px then off = math.pi / 2
          else
            local a1 = math.acos(cl1(f1 * px + f2 * py + f3 * pz))
            local a2 = math.acos(cl1(px * dx + py * dy + pz * dz))
            if math.abs(a1 + a2 - T) < 1e-3 then off = math.asin(math.min(1, math.abs(sn)))
            else off = math.min(math.acos(cl1(vx * f1 + vy * f2 + vz * f3)), math.acos(cl1(vx * dx + vy * dy + vz * dz))) end
          end
        end
        if off < alpha then return true end
      end
    end
    return false
  end

  -- (5.0 test builds) where a helldiver is relative to a vehicle's gun: position in the vehicle's own axes (from the
  -- vehicle's center; which axis is forward isn't known yet), the muzzle's height above their feet and, for a shot
  -- line, how high above their feet it passes them and how far from the muzzle. To tell the driver's seat, the other
  -- seats (people lean out of the windows to shoot) and people standing next to it apart before the safety treats
  -- riders differently. Up to 25 safety stops, and a sample every 3 s while someone is within 6 m (up to 25)
  local function rider_note(s, st, a, M, p, what)
    local V = unit_position(s.unit, true)
    local ax = V and V.axes
    local rel = { a[1] - st.base[1], a[2] - st.base[2], a[3] - st.base[3] }
    local loc = ax and string.format('%.2f %.2f %.2f', rel[1] * ax[1][1] + rel[2] * ax[1][2] + rel[3] * ax[1][3],
      rel[1] * ax[2][1] + rel[2] * ax[2][2] + rel[3] * ax[2][3], rel[1] * ax[3][1] + rel[2] * ax[3][2] + rel[3] * ax[3][3]) or '?'
    local line = ''
    if p then
      local h = math.sqrt((a[1] - M[1]) ^ 2 + (a[2] - M[2]) ^ 2)
      local H = math.sqrt((p[1] - M[1]) ^ 2 + (p[2] - M[2]) ^ 2)
      if H > 0.1 then line = string.format(', line passes %.2f m above your feet %.1f m from the muzzle', M[3] + (p[3] + AIM_UP[2] - M[3]) * math.min(1, h / H) - a[3], h) end
    end
    note(string.format('rider (test) at %.0fs: %s: %s; you in its axes %s (level %.1f m from its center), muzzle %.2f m above your feet%s',
      os.clock() - T0, s.def.name, what, loc, math.sqrt(rel[1] ^ 2 + rel[2] ^ 2), M[3] - a[3], line))
  end

  -- (5.0) someone sitting in the Supply FRV: its gun can't hit them (a tester's check in game) - only a passenger
  -- aiming out of a window, whose head, arms and gun are then outside the cab. Seats measured in game (Test 10
  -- riders log, in the FRV's own axes: side, fore-aft, up from its center): the front pair at (+-0.36, -1.51, -1.08),
  -- the back pair at (+-0.36, -0.70, -1.08); getting out showed (-1.76, ..., -1.45). Anyone inside that box is a
  -- rider. A rider counts as aiming out when any part of their body (the parts of their unit's pose) is more than
  -- 'window' meters to the side of the FRV's center on their side (the seats are 0.36 m out; the value is a first
  -- guess, the test builds log each rider's reach to tune it). Seated: left out of this gun's safety altogether.
  -- Aiming out: their usual body, plus one around the parts outside the cab. Anyone outside the box: as always
  -- (4.5, a tester: the safety still stopped the gun now and then while he sat in it. Seated reaches of up to 0.93 m
  -- were logged, aiming out 1.44 m and more: 'window' 0.95 -> 1.15. And the driver - the front seat on the +x side,
  -- where a tester always sat driving alone - can't aim out of the window at all: always seated)
  local RIDE = { side = 0.9, fore = { -2.3, 0.1 }, up = { -1.4, -0.7 }, window = 1.15, parts = 96, driver_fore = -1.1 }
  -- how far (meters, sideways from the FRV's center, on the seat's side) the rider's body reaches, and the parts that
  -- stick out of the cab (a vertical segment around them), or nil if their pose can't be read
  local function reach_out(a, V, ax, side_sign)
    local pose = a.pose
    if not pose and a.unit then local q = unit_position(a.unit); pose = q and q.pose end
    if not pose then return nil end
    local n, m = RIDE.parts, nil
    while n >= 16 and not m do m = read(pose, 64 * n); if not m then n = n - 32 end end
    if not m then return nil end
    local best, lo, hi, sx, sy, k = -99, nil, nil, 0, 0, 0
    for i = 0, n - 1 do
      local x, y, z = f32(m, 64 * i + 48), f32(m, 64 * i + 52), f32(m, 64 * i + 56)
      if x == x and y == y and z == z and (x - a[1]) ^ 2 + (y - a[2]) ^ 2 + (z - a[3]) ^ 2 < 2.5 ^ 2 then
        local r1, r2, r3 = x - V[1], y - V[2], z - V[3]
        local sd = (r1 * ax[1][1] + r2 * ax[1][2] + r3 * ax[1][3]) * side_sign
        if sd > best then best = sd end
        if sd > RIDE.window then
          lo, hi = math.min(lo or z, z), math.max(hi or z, z)
          sx, sy, k = sx + x, sy + y, k + 1
        end
      end
    end
    if best == -99 then return nil end
    local outside = k > 0 and { lo = { sx / k, sy / k, lo - 0.1 }, hi = { sx / k, sy / k, hi + 0.1 }, at = { sx / k, sy / k, lo - 0.1 }, extra = 0 } or nil
    return best, outside
  end
  local function riders(s, st, bodies, def)
    -- (nobody within 3 m of it, level: nothing to work out, and the FRV's axes aren't read)
    local B, near = st.base, false
    for _, b in ipairs(bodies) do
      local a = b.at
      if (a[1] - B[1]) ^ 2 + (a[2] - B[2]) ^ 2 < 9 then near = true; break end
    end
    if not near then return bodies end
    local V = unit_position(s.unit, true)
    local ax = V and V.axes
    if not ax then return bodies end
    local out, changed, last = {}, false, nil
    for _, b in ipairs(bodies) do
      local a = b.at
      local r1, r2, r3 = a[1] - V[1], a[2] - V[2], a[3] - V[3]
      local x = r1 * ax[1][1] + r2 * ax[1][2] + r3 * ax[1][3]
      local y = r1 * ax[2][1] + r2 * ax[2][2] + r3 * ax[2][3]
      local z = r1 * ax[3][1] + r2 * ax[3][2] + r3 * ax[3][3]
      local seated = math.abs(x) <= RIDE.side and y >= RIDE.fore[1] and y <= RIDE.fore[2] and z >= RIDE.up[1] and z <= RIDE.up[2]
      if b.lead then
        -- (a moving teammate's look-ahead body: while they ride, they are where the FRV is)
        if last == 'seated' then changed = true
        elseif last == 'leaning' then changed = true; out[#out + 1] = out[#out]
        else out[#out + 1] = b end
      elseif seated then
        changed = true
        -- (how far a seated rider reaches is read at most every 0.1 s; someone aiming out is read every frame, so
        -- the body parts outside the cab follow them)
        s.reach_seen = s.reach_seen or {}
        local key = a.pose or a.unit or 0
        local seen = s.reach_seen[key]
        local reach, outside
        if x > 0 and y < RIDE.driver_fore then reach = nil   -- (the driver: never read, see below)
        elseif seen and seen.t > os.clock() - 0.1 and seen.reach <= RIDE.window then reach = seen.reach
        else
          reach, outside = reach_out(a, V, ax, x < 0 and -1 or 1)
          if reach then
            if not s.reach_seen[key] then
              s.reach_n = (s.reach_n or 0) + 1
              if s.reach_n > 32 then s.reach_seen, s.reach_n = {}, 1 end   -- (old riders' entries don't pile up)
            end
            s.reach_seen[key] = { t = os.clock(), reach = reach }
          end
        end
        a.reach = reach
        -- (a pose that can't be read: treated as aiming out, the safe side; the driver is always seated)
        local driver = x > 0 and y < RIDE.driver_fore
        if driver or (reach and reach <= RIDE.window) then a.ride, last = driver and 'driving' or 'seated', 'seated'
        else
          a.ride, last = 'aiming out', 'leaning'
          out[#out + 1] = b
          if outside then outside.mate = b.mate; out[#out + 1] = outside end
        end
      else
        out[#out + 1] = b; last = nil
      end
    end
    return changed and out or bodies
  end

  -- enemies this sentry must not shoot right now (id -> true), why, and how close each came (for the linger rule)
  local AIM_LO, AIM_HI = { 0, 0, 0 }, { 0, 0, 0 }
  local BODY_SKIP, BODY_DM = {}, {}   -- ((4.6.7 review) per-body scratch for unsafe_for, reused every call)
  local WHY = {
    { blast = 'you would be inside the blast', line = 'you are in its line of fire', splash = 'you would be caught in the explosion', sweep = 'it would swing its fire across you' },
    { blast = 'a teammate would be inside the blast', line = 'a teammate is in its line of fire', splash = 'a teammate would be caught in the explosion', sweep = 'it would swing its fire across a teammate' },
    { blast = 'a sentry would be inside the blast', line = 'a sentry is in its line of fire', splash = 'a sentry would be caught in the explosion', sweep = 'it would swing its fire across a sentry' },
    { blast = 'a SEAF soldier would be inside the blast', line = 'a SEAF soldier is in its line of fire', splash = 'a SEAF soldier would be caught in the explosion', sweep = 'it would swing its fire across a SEAF soldier' },
    { blast = 'a civilian would be inside the blast', line = 'a civilian is in its line of fire', splash = 'a civilian would be caught in the explosion', sweep = 'it would swing its fire across a civilian' },
  }
  -- ((5.1.5 Test 19) 'only': just that enemy (its current target, checked every frame between full plans)
  -- ((5.1.5 Test 19) its three result tables reused, not made anew each call: two sets taken in turn by the full plans
  -- (the last one is kept for the frames in between, sentry_light), and one for the in-between checks)
  -- ((5.1.5 Test 20) cleared through the list of ids put in them (B[4]): my Test 19 log showed the game's LuaJIT
  -- (2.1.0-alpha) giving up on the pairs loop that cleared them about 1,900 times - it can't compile pairs)
  local function ub_take(B)
    local U, why, gap, K = B[1], B[2], B[3], B[4]
    for i = #K, 1, -1 do local id = K[i]; U[id], why[id], gap[id], K[i] = nil, nil, nil, nil end
    return U, why, gap, K
  end
  local function unsafe_for(s, st, bodies, pb, only)
    local U, why, gap, K
    if only then
      s.ub_l = s.ub_l or { {}, {}, {}, {} }
      U, why, gap, K = ub_take(s.ub_l)
    else
      s.ub = s.ub or { { {}, {}, {}, {} }, { {}, {}, {}, {} }, k = 1 }
      s.ub.k = 3 - s.ub.k
      U, why, gap, K = ub_take(s.ub[s.ub.k])
    end
    local def, M, fwd = s.def, st.muzzle, st.fwd
    local all = bodies
    if def.vehicle then bodies = riders(s, st, bodies, def) end
    if TESTER and def.vehicle and (s.rider_samples or 0) < 25 and os.clock() >= (s.rider_next or 0) then
      for _, b in ipairs(all) do
        local a = b.at
        if (a[1] - st.base[1]) ^ 2 + (a[2] - st.base[2]) ^ 2 < 36 then
          s.rider_samples, s.rider_next = (s.rider_samples or 0) + 1, os.clock() + 3
          pcall(rider_note, s, st, a, M, nil, (b.mate and 'a teammate nearby' or 'you nearby') .. (a.ride and (' (' .. a.ride .. (a.reach and string.format(', reaching %.2f m out', a.reach) or '') .. ')') or ''))
          session.dirty = true
          break
        end
      end
    end
    -- (4.6.5 Sentry Safety: the sentries' bodies after the helldivers'; each sentry leaves out its own)
    local nb, sid = #bodies, s.id
    local P = s.P
    local firing = st.target ~= 0 and P.on_target == st.target and (P.on_fire or 0) > 0
    local nall = nb + ((pb and not def.spares_sentries) and #pb or 0)
    -- ((4.6.7 review) what depends on the body alone, worked out once per body instead of once per enemy and body:
    -- whether it is left out, and its distance from the muzzle)
    for i = 1, nall do
      local b = i <= nb and bodies[i] or pb[i - nb]
      local a = b.at
      -- ((4.6.5 review) a gun on a vehicle - the Supply FRV's - leaves out a piloting body within 4 m of it: should
      -- driving it ever count as piloting, that body is the FRV itself, round its own barrel)
      BODY_SKIP[i] = b.sid == sid or (b.piloting and def.vehicle and (a[1] - st.base[1]) ^ 2 + (a[2] - st.base[2]) ^ 2 < 16) or false
      BODY_DM[i] = math.sqrt((a[1] - M[1]) ^ 2 + (a[2] - M[2]) ^ 2 + (a[3] + BODY_MID - M[3]) ^ 2)
    end
    local need_near = def.blast or def.splash
    for _, c in ipairs(st.candidates) do
      local p = c.pos
      -- (only enemies it could pick: ones its own scoring rates 0 are skipped, which saves most of the work)
      if p and (only == nil or c.id == only) and (c.eligible or c.mask == BLANK or c.id == st.target) then
        local closest, reason = math.huge, nil
        local dM = math.sqrt((p[1] - M[1]) ^ 2 + (p[2] - M[2]) ^ 2 + (p[3] - M[3]) ^ 2)
        -- ((5.1.5 Test 34, my Test 33 game: an Autocannon Sentry "avoid shooting a hulk that was approaching" - it held
        -- fire 3 times for a sentry in the explosion) a heavy (AV4 and up) close to one of the sentries is fired on all
        -- the same ('splash_heavy'): it is about to wreck that sentry anyway, and the shell does at most 150 of its 400-600)
        local ca = def.splash_heavy and c.kind and ARMOR[c.kind]
        local spare_heavy = ca and ca.av >= 4
        for i = 1, nall do
          local b = i <= nb and bodies[i] or pb[i - nb]
          if not BODY_SKIP[i] then
          local W = WHY[b.sentry and 3 or (b.civ and 5) or (b.seaf and 4) or (b.mate and 2 or 1)]
          local a = b.at
          -- (only the mortars and splash guns need the body's distance from the enemy)
          local near = need_near and (math.sqrt((a[1] - p[1]) ^ 2 + (a[2] - p[2]) ^ 2 + (a[3] + BODY_MID - p[3]) ^ 2) - b.extra)
          if def.blast then
            local m = near - (b.sentry and def.sentry_blast or def.blast)
            if m < closest then closest = m end
            if m < 0 then reason = reason or W.blast end
          else
            local dB = BODY_DM[i]
            if dB < dM + 3 then
              local r = def.line + def.spread * dB + b.extra
              -- ((5.1.5 Test 18, my "performance can be a bit rough" with lots of enemies) seen from above first: a gap in
              -- 3D is never smaller than the same gap on the map, so a body standing UNSAFE_CLEAR m or more clear of the
              -- shot's line on the map can't be in it, and the full check is skipped. In my Test 17 fight (8 sentries,
              -- ~40 enemies) this check was half the mod's time; nearly every body is far off the line. Not for its own
              -- target (its aim point can sit off the enemy) or a body that isn't upright (a vehicle's rider)
              local m
              local lo, hi = b.lo, b.hi
              if c.id ~= st.target and lo[1] == hi[1] and lo[2] == hi[2] then
                local ex, ey, wx, wy = p[1] - M[1], p[2] - M[2], lo[1] - M[1], lo[2] - M[2]
                local L2 = ex * ex + ey * ey
                local k = L2 > 1e-9 and (wx * ex + wy * ey) / L2 or 0
                k = k < 0 and 0 or (k > 1 and 1 or k)
                local qx, qy = wx - ex * k, wy - ey * k
                local d = math.sqrt(qx * qx + qy * qy) - r
                if d >= UNSAFE_CLEAR then m = d end
              end
              if not m then
                -- (the two heights its shots may land at, and its actual aim point: reused scratch points, no new tables)
                AIM_LO[1], AIM_LO[2], AIM_LO[3] = p[1], p[2], p[3] + AIM_UP[1]
                AIM_HI[1], AIM_HI[2], AIM_HI[3] = p[1], p[2], p[3] + AIM_UP[2]
                m = math.min(segment_distance(M, AIM_LO, lo, hi), segment_distance(M, AIM_HI, lo, hi))
                if c.id == st.target and st.aim then m = math.min(m, segment_distance(M, st.aim, lo, hi)) end
                m = m - r
              end
              if m < closest then closest = m end
              if closest < 0 then reason = reason or W.line end
            end
            if def.splash and near < def.splash and not (spare_heavy and b.sentry) then
              closest = math.min(closest, near - def.splash)
              reason = reason or W.splash
            end
            -- (a sentry with a firing step - the Laser Sentry - only sweeps its beam across someone while it is firing:
            -- while it turns onto a target with the beam off it can't hit anyone)
            -- ((4.6.5) for a sentry's body only while it is firing at its target: an idle gun, or one still turning
            -- onto a new target, isn't firing, and one left pointing at a sentry next to it was never let turn at all)
            if def.sweep and fwd and not reason and dB < dM + 1 and (not def.fire_node or st.node == def.fire_node) and (firing or not b.sentry) then
              local q = (c.id == st.target and st.aim) or AIM_HI
              if q == AIM_HI then AIM_HI[1], AIM_HI[2], AIM_HI[3] = p[1], p[2], p[3] + AIM_UP[2] end
              if sweep_hits(M, fwd, q, b, def) then
                closest = math.min(closest, 0)
                reason = W.sweep
              end
            end
          end
          if reason then
            if TESTER and def.vehicle and (s.rider_stops or 0) < 25 and os.clock() >= (s.rider_stop_next or 0) then
              s.rider_stops, s.rider_stop_next = (s.rider_stops or 0) + 1, os.clock() + 1   -- (one a second at most)
              session.dirty = true
              pcall(rider_note, s, st, a, M, p, reason .. (a.ride and (' (' .. a.ride .. (a.reach and string.format(', reaching %.2f m out', a.reach) or '') .. ')') or ''))
            end
            break
          end
          end
        end
        gap[c.id] = closest; K[#K + 1] = c.id
        if reason then U[c.id] = true; why[c.id] = reason end
      end
    end
    -- ((4.6.7 review) its target when the enemy itself couldn't be checked - gone from its list (a body) or without a
    -- position: the line to where the sentry aims (for the mortars, the blast there), so a sentry still on it is never
    -- left unchecked)
    local tg = st.target
    if tg ~= 0 and gap[tg] == nil and st.aim and st.aim[1] == st.aim[1] then
      local q = st.aim
      for i = 1, nall do
        local b = i <= nb and bodies[i] or pb[i - nb]
        if not BODY_SKIP[i] then
          local a, m = b.at, nil
          local W = WHY[b.sentry and 3 or (b.civ and 5) or (b.seaf and 4) or (b.mate and 2 or 1)]
          if def.blast then
            m = math.sqrt((a[1] - q[1]) ^ 2 + (a[2] - q[2]) ^ 2 + (a[3] + BODY_MID - q[3]) ^ 2) - b.extra - (b.sentry and def.sentry_blast or def.blast)
          else
            m = segment_distance(M, q, b.lo, b.hi) - (def.line + def.spread * BODY_DM[i] + b.extra)
          end
          if m < 0 then U[tg], why[tg], gap[tg] = true, def.blast and W.blast or W.line, m; K[#K + 1] = tg; break end
        end
      end
    end
    return U, why, gap
  end

  -- ------------------------------------------------------------------ overheating (Laser Sentry)
  -- the heat meter record: +4 = heat so far, +8 = overheated. Its unit is learned: degrees (it rises about as fast
  -- as the wiki's rate) or a share of the capacity; the capacity is taken from the value at which it overheats.
  local meter = {}   -- per sentry kind: { scale = capacity in the meter's unit }
  local function meter_read(s)
    if not s.hb_mgr then return nil end
    local owners = ptr_of(read(s.hb_mgr + 0x40, 8), 0)
    local own = owners and ptr_of(read(owners + s.hb_idx * 8, 8), 0)
    if own ~= s.ptr then return nil end
    local arr = ptr_of(read(s.hb_mgr + 0x58, 8), 0)
    local r = arr and read(arr + s.hb_idx * 12, 12)
    if not r then return nil end
    local v = f32(r, 4)
    if v ~= v or v < 0 or v > 100000 then return nil end
    return v, r:byte(9) ~= 0
  end
  -- ((5.1.5 Test 6) the meter's value for any sentry: the heat meter's, else the ammo meter's (nil when not readable)
  local function any_meter(s)
    if s.hb_mgr then return (meter_read(s)) end
    if not s.am_mgr then return nil end
    local owners = ptr_of(read(s.am_mgr + 0x40, 8), 0)
    local own = owners and ptr_of(read(owners + s.am_idx * 8, 8), 0)
    if own ~= s.ptr then return nil end
    local arr = ptr_of(read(s.am_mgr + 0x58, 8), 0)
    local r = arr and read(arr + s.am_idx * 12, 12)
    if not r then return nil end
    local v = f32(r, 4)
    if v ~= v or v < -1 or v > 1e7 then return nil end
    return v
  end
  local function heat_probe(s, st, t)
    local def = s.def
    if s.hb_mgr then
      if t < (s.probe_next or 0) then return end
      s.probe_next = t + HEAT.probe_every
      local v, over = meter_read(s)
      -- ((4.6.4 release review) the overheated flag holds the stand-down until it clears (Laser Sentry Cooldown); with
      -- the meter unreadable for 2 s it is let go, so a lost meter can't keep the sentry stood down for good)
      if not v then
        if s.was_over and t - (s.meter_ok_t or t) >= 2 then s.was_over = nil end
        return
      end
      s.meter_ok_t = t
      local m = meter[def.name] or {}
      meter[def.name] = m
      -- the unit: from how fast it climbs while firing
      if not m.scale then
        local p = s.meter_prev
        if p and st.target ~= 0 and p.target ~= 0 and t > p.t and v > p.v then
          local r = (v - p.v) / (t - p.t)
          m.n, m.sum = (m.n or 0) + 1, (m.sum or 0) + r
          if m.n >= 8 then
            local rate = m.sum / m.n
            if rate > 2 and rate < 40 then m.scale = def.heat.cap elseif rate > 0.008 and rate < 0.16 then m.scale = 1 end
            if m.scale then note(string.format('%s: heat meter read (%s, rising %.3g a second while firing)', def.name, m.scale == 1 and 'share of capacity' or 'degrees', rate)) end
          end
        end
        s.meter_prev = { v = v, t = t, target = st.target }
      end
      -- it overheated: the meter's value now is its true capacity
      if over and not s.was_over then
        m.scale = math.max(v, 1e-6)
        event(string.format('%s OVERHEATED (heat meter %.3g; the mod had it at %.0f%%)%s', s.tag or def.name, v, 100 * (s.heat_measured or (s.heat / def.heat.cap)),
          rawget(_G, 'LaserSentryCooldownInstalled') and ' - Laser Sentry Cooldown is installed: it cools down and comes back' or ''))
      end
      s.was_over = over
      if m.scale then s.heat_measured = v / m.scale end
      -- ((4.6.7 review) only while it has a target or is still warm: idle samples filled the log's recent events)
      if TESTER and t >= (s.sample_next or 0) and (s.samples or 0) < 45 and (st.target ~= 0 or v > 0) then
        s.sample_next, s.samples = t + 2, (s.samples or 0) + 1
        event(string.format('heat sample: %s meter %.3g%s, estimate %.0f%%, %s, AI step %d', s.tag or def.name, v, over and ' OVERHEATED' or '',
          100 * s.heat / def.heat.cap, st.target ~= 0 and 'on a target' or 'no target', st.node))
      end
      return
    end
  end
  local function heat_update(s, st, t, dt)
    local h = s.def.heat
    if not h then return end
    if st.target ~= 0 then s.heat = math.min(h.cap, s.heat + h.rate * dt) else s.heat = math.max(0, s.heat - h.cool * dt) end
    pcall(heat_probe, s, st, t)
    -- ((4.6.7 review) the meter's reading only while it is fresh: if the meter stopped reading - lost after the sentry's
    -- records moved, say - a value kept for good held the sentry stood down for good, or never let it cool)
    local fresh = s.heat_measured and t - (s.meter_ok_t or -99) < HEAT.fresh
    st.heat = fresh and s.heat_measured or (s.heat / h.cap)
    st.heat_from = fresh and 'measured' or 'estimated'
  end

  -- ------------------------------------------------------------------ deciding and steering
  -- (helpers for plan_sentry, built once rather than every frame)
  local NONE = {}   -- an empty set shared by every set nothing was put in (never written to: see 'put')
  local function put(set, id) if set == NONE then set = {} end set[id] = true; return set end
  -- could the sentry pick it (its own scoring doesn't rate it 0), is it in play, and is it fair game right now
  local function pickable(c, st) return c.eligible or c.mask == BLANK or c.id == st.target end
  local function in_play(c, st) return c.alive or c.mask == BLANK or c.id == st.target end
  local function open(c) return c.eligible or (c.mask == BLANK and c.alive and (c.score or 0) > 0) end
  local function near_body(bodies, p, r2)
    if not p then return false end
    for _, b in ipairs(bodies) do
      if (b.at[1] - p[1]) ^ 2 + (b.at[2] - p[2]) ^ 2 + (b.at[3] - p[3]) ^ 2 < r2 then return true end
    end
    return false
  end
  -- (4.5.3 Test 10) not one inside its minimum range (the Rocket Sentry's 10 m, wider than SELF.reach): it can't shoot
  -- that one, and treating it as the first to deal with left every enemy farther out hidden while it stood there
  local function near_sentry(s, st, c)
    if s.def.blast or not c.pos then return false end
    local d2 = (c.pos[1] - st.base[1]) ^ 2 + (c.pos[2] - st.base[2]) ^ 2 + (c.pos[3] - st.base[3]) ^ 2
    return d2 < SELF.reach ^ 2 and not (s.def.min_range and d2 < s.def.min_range ^ 2)
  end
  -- (test builds) other entries within 3 m of an enemy the sentry kept: parts or a pilot the game may be choosing it
  -- through (a Scout Strider was chosen again and again while hidden)
  local function near_note(st, c)
    if not (c and c.pos) then return '' end
    local out = {}
    for _, x in ipairs(st.candidates) do
      if x ~= c and x.pos and #out < 4 and (x.pos[1] - c.pos[1]) ^ 2 + (x.pos[2] - c.pos[2]) ^ 2 + (x.pos[3] - c.pos[3]) ^ 2 < 9 then
        out[#out + 1] = string.format('%d %s %s%s', x.id, x.kind and EXT.hexr(x.kind) or '-', x.mask == BLANK and 'hidden' or 'shown', x.visible and ' in sight' or '')
      end
    end
    return #out > 0 and ('; next to it: ' .. table.concat(out, ', ')) or ''
  end
  -- ask it to drop its target (with the hold and back-off rules)
  local function kick(s, st, t, hide, block, reason)
    local P = s.P
    -- ((4.6.6 review) an ask is counted as ignored only when the same ask for the same target comes again, and not in an
    -- AI step in which the game doesn't choose again (step 10, a salvo, the Tesla Tower's step 4). (4.6.7 review: what
    -- ended the safety back-offs is that a safety ask never backs off, below; this step rule only keeps the Tester's
    -- 'kept its target' notes honest, as other asks aren't made in those steps)
    local deaf = st.node == BUSY_NODE or (s.def.salvo_node ~= nil and st.node == s.def.salvo_node)
    if st.target ~= 0 and P.kicked == st.target and P.kick_reason == reason then
      if not deaf then P.ignored = P.ignored + 1 end
    else
      P.kicked, P.ignored, P.kick_reason = st.target, 0, reason
    end
    if TESTER and st.target ~= 0 and P.ignored > 0 and (P.ignore_notes or 0) < 12 then
      -- (test builds: why a sentry kept an enemy it was asked to drop)
      P.ignore_notes = (P.ignore_notes or 0) + 1
      local c = st.current
      local now = clock_now()
      event(string.format('sentry kept its target: %s target %d (%s) AI step %d, its mask %s, timer %.2fs, %s', (s.tag or s.def.name), st.target,
        c and c.kind and EXT.hexr(c.kind) or '?', st.node, c and (c.mask == BLANK and 'hidden' or 'shown') or 'not listed',
        (st.deadline - now) / 1e6, reason) .. near_note(st, c))
    end
    -- ((4.6.6 review) never for a safety stop: it is asked again every HOLD for as long as the target is unsafe - a
    -- back-off left the target only hidden for a second, which a sentry that keeps its target fires through)
    if P.ignored >= 2 and reason ~= 'sentry_safety' then
      P.kicked, P.ignored = nil, 0
      if reason == 'sentry_cannot_hurt' then P.stuck[st.target] = true; return { block = hide, kick = false, reason = reason } end
      if reason == 'sentry_out_of_sight' then
        -- (the game can see it after all: let it keep this one, shown again, for a while)
        P.sight_ok[st.target] = t + COVER_S.trust
        bump(session.actions, 'sentry_sight_trusted')
        local keep = {}
        for id in pairs(hide) do if id ~= st.target then keep[id] = true end end
        return { block = keep, kick = false, reason = reason }
      end
      P.hold = { target = st.target, block = block, until_t = t + BACKOFF, reason = reason }
      bump(session.actions, 'sentry_backing_off')
      return { block = union(block, hide), kick = false, reason = reason }
    end
    P.hold = { target = st.target, block = block, until_t = t + HOLD, reason = reason, deaf = deaf }
    P.last_kick_t = t
    if reason == 'sentry_safety' then P.safety_t, P.safety_enemy = t, st.target end
    return { block = union(block, hide), kick = true, reason = reason }
  end

  -- bodies: who must not be hit (follows the Safety option); people: where the helldivers are, you always included
  -- (for the rules about enemies near a helldiver: priority and fire spreading)
  -- (test builds, 4.5.1) what a sentry does in the 1.5 s after its target dies or is cleared, for the first 10 kills per
  -- sentry kind: its target (the dead one, none or a new one), whether that entry is alive (in the game's registry,
  -- flag 1), its AI step and selection timer. To see why a gun keeps shooting a body (a tester: the Supply FRV gun)
  local ktrace_count = {}
  local range_notes = {}   -- (test builds, 4.5.2) 'range (test)' notes so far, per sentry kind
  local function ktrace_state(s, st, id)
    local c = st.current
    local who = st.target == 0 and 'none' or (st.target == id and 'the old one' or ('new ' .. st.target))
    local life = st.target == 0 and '' or (not c and ' (not listed)' or string.format(' (%s, flag %d, %s)', c.alive and 'alive' or 'dead',
      bit.band(c.flags or 0, 1), c.ent and 'in registry' or 'gone from registry'))
    local now = clock_now()
    -- (4.6.2) and its targeting state's target and second id (+0, +4): 0 / 32767 once let go
    local ts = read(s.tstate, 8)
    local tss = ts and string.format(' ts %d/%d', u32(ts, 0), u32(ts, 4)) or ''
    -- (and how long ago its AI record says it lost its target, +408: it fires on at the spot for 1 s after)
    local lt = read(s.rec_addr + 408, 8)
    local lost = lt and string.format(' lost %.2fs ago', (now - u64(lt, 0)) / 1e6) or ''
    return string.format('%s%s step %d%s timer %.2f%s', who, life, st.node, tss, (st.deadline - now) / 1e6, lost)
  end
  -- (also, 'ask trace (test)': the same after the mod asks it to drop a target - safety, cover, armor, cooling... -
  -- with nothing else it may pick, first 10 per sentry kind: does it keep firing at nothing for a second?)
  local function kill_trace_start(s, st, t, why, label)
    label = label or 'kill trace'
    local k = s.def.name .. '/' .. label
    if (ktrace_count[k] or 0) >= 10 or (s.P.ktrace and t - s.P.ktrace.t0 < 0.3) then return end
    ktrace_count[k] = (ktrace_count[k] or 0) + 1
    local id = st.target ~= 0 and st.target or (s.P.lost_from or 0)
    local c = st.current
    s.P.ktrace = { id = id, t0 = t, why = why, label = label, kind = (st.target ~= 0 and c and c.kind) or s.P.prev_kind, parts = {}, last = nil }
  end
  local function kill_trace_step(s, st, t)
    local K = s.P.ktrace
    if not K then return end
    local ok, now = pcall(ktrace_state, s, st, K.id)
    now = ok and now or ('unreadable: ' .. tostring(now))
    local key = now:gsub(' timer %-?[%d%.]+.*$', '')
    if key ~= K.last then K.last = key; K.parts[#K.parts + 1] = string.format('+%.2f %s', t - K.t0, now) end
    if t - K.t0 >= 1.5 or #K.parts >= 12 then
      s.P.ktrace = nil
      event(string.format('%s (test): %s target %d (%s) %s: %s', K.label, (s.tag or s.def.name), K.id, K.kind and (LABELS[K.kind] or EXT.hexr(K.kind)) or 'type unknown', K.why, table.concat(K.parts, ' | ')))
    end
  end

  -- (test builds, 4.6.2) when a sentry's target dies or the game clears it in its firing step: what the mod decided
  -- and the other enemies it lists (nearest 8 within 60 m) - open to pick or not (flag, score) and what hid them.
  -- First 10 per sentry kind (a tester: the Supply FRV gun doesn't move on after a kill)
  local function kill_decision_note(s, st, target, cands, hide, any, what, yes, no, key)
    local k = s.def.name .. '/' .. (key or 'kill decision')
    if (ktrace_count[k] or 0) >= 10 then return end
    ktrace_count[k] = (ktrace_count[k] or 0) + 1
    local rows = {}
    for _, c in ipairs(cands) do if c.id ~= target and c.d2 and c.d2 < 3600 then rows[#rows + 1] = c end end
    table.sort(rows, function(x, y) return x.d2 < y.d2 end)
    local out = {}
    for i = 1, math.min(#rows, 8) do
      local c = rows[i]
      local why = {}
      for name, set in pairs(st.hide_sets or {}) do if set[c.id] then why[#why + 1] = name end end
      out[#out + 1] = string.format('%d %.0f m %s%s%s', c.id, math.sqrt(c.d2), c.alive and 'alive' or 'dead',
        c.eligible and ', open' or string.format(', not open (flag %d, score %s, %s)', bit.band(c.flags or 0, 1), tostring(c.score or 0),
          c.mask == BLANK and 'hidden by the mod' or 'shown'),
        #why > 0 and (', hidden: ' .. table.concat(why, '/')) or '')
    end
    event(string.format('%s (test): %s target %d %s, AI step %d: %s; %d others listed%s', key or 'kill decision', (s.tag or s.def.name), target, what, st.node,
      any and yes or no, #rows, #out > 0 and (': ' .. table.concat(out, '; ')) or ''))
  end

  -- (4.6.2) turn_hold (the Supply FRV gun and the Armed Resupply Pod gun, which runs the same AI): after a kill the game keeps it in its firing step while it swings to the
  -- next enemy, spraying the whole way (a tester: "wastes ammo moving from target to target"). True when every enemy
  -- it may pick next is more than def.turn_hold degrees off its barrel: then it isn't asked to switch at once but let
  -- go of (its loss time moved back), so it turns to the next one in its aiming step and fires once on it. Only after
  -- the game has cleared its target (the usual way for the FRV gun)
  local function turn_far(s, st, target, cands, hide)
    local deg = s.def.turn_hold
    if not deg or not st.fwd or not st.muzzle then return false end
    local m, f, lim = st.muzzle, st.fwd, math.cos(math.rad(deg))
    local seen = false
    for _, c in ipairs(cands) do
      if c.id ~= target and c.pos and open(c) and not hide[c.id] then
        local v = norm({ c.pos[1] - m[1], c.pos[2] - m[2], c.pos[3] + 1.0 - m[3] })
        if v then
          seen = true
          if dot3(v, f) >= lim then return false end
        end
      end
    end
    return seen
  end

  -- (4.5.2) dropping its target for any reason but safety: asked to choose again only when it has something else
  -- it may pick. Asked with nothing to pick, the game gives it a fresh second in its firing step and it fires at
  -- nothing (a tester's logs: the FRV gun, the Gatling, the Laser Sentry after setting its last enemy alight).
  -- Otherwise the target is only hidden (it is in 'hide' already) and it stops when its old timer runs out. Counted
  -- once per target and reason either way (a repeated ask is quiet). Safety stops still always ask (hidden only, it
  -- would keep firing at the target until its timer ran out)
  -- (Testers, (5.1.5 Test 17): each time a sentry leaves its target, why, what it was, its health and how long it had
  -- fired at it - to see what makes the Autocannon move on before a kill; 80 a session)
  local drop_notes = 0
  local function drop_note(s, st, t, reason)
    local P, target = s.P, st.target
    if not TESTER or target == 0 or (P.dn_tg == target and P.dn_reason == reason) then return end
    P.dn_tg, P.dn_reason = target, reason
    local c = st.current
    local a = c and c.kind and ARMOR[c.kind]
    -- ((5.1.5 Test 18) every drop counted for the whole session - by sentry, reason and enemy - in the log's summary:
    -- in Test 17 the Autocannon's three 'not hurting' drops had scrolled out of the last 60 events)
    local nm = a and a.name or (c and c.kind and (LABELS[c.kind] or EXT.hexr(c.kind))) or '?'
    session.drop_tally = session.drop_tally or {}
    local key = string.format('%s, %s: %s', s.def.name, (reason:gsub('^sentry_', '')), nm)
    session.drop_tally[key] = (session.drop_tally[key] or 0) + 1
    if drop_notes >= 80 then return end
    drop_notes = drop_notes + 1
    local hp, mx = HEALTH.of(target)
    local e = P.dw and P.dw.e and P.dw.e[target]
    event(string.format('drop (test): %s left %d (%s) for %s: health %s, fired %.1f s at it, last hurt %s, %.0f m', s.tag or s.def.name, target,
      a and (a.name .. ' AV' .. a.av) or (c and c.kind and (LABELS[c.kind] or EXT.hexr(c.kind))) or '?', reason,
      hp and string.format('%d of %d', hp, mx) or '-', P.on_target == target and (P.on_fire or 0) or 0,
      e and e.hurt_t and string.format('%.1f s ago', t - e.hurt_t) or 'never', c and c.d2 and math.sqrt(c.d2) or -1))
  end
  local function drop_target(s, st, t, hide, reason)
    drop_note(s, st, t, reason)
    local P, target = s.P, st.target
    local first = P.drop_target ~= target or P.drop_reason ~= reason
    P.drop_target, P.drop_reason = target, reason
    -- ((5.0) its laser flashes gray toward an enemy it dropped because it went out of sight, as the dog's does)
    -- ((5.0 release review) its own fields: P.lost_t is the kill logic's re-ask timer, and sharing it hid the marker after every kill)
    if reason == 'sentry_out_of_sight' and first then P.oos_t, P.oos_enemy = t, target end
    for _, c in ipairs(st.candidates) do
      if c.id ~= target and open(c) and not hide[c.id] then
        local r = kick(s, st, t, hide, { [target] = true }, reason)
        if r.kick and not first then r.quiet = true end
        return r
      end
    end
    return { block = hide, kick = false, reason = reason, count = first }
  end

  -- (4.6.6, a commenter: the Gatling Sentry fired at a Charger nonstop with Armor Intelligence on, 0 armor skips in
  -- the log) every build logs a target a sentry keeps firing at (1.5 s of fire) that the mod doesn't recognize - its
  -- type unreadable or not in the enemy list - or that Armor Intelligence should have skipped, with the entries
  -- next to it: once per sentry kind and target, 12 a session
  local target_notes = { n = 0, seen = {} }
  local function target_check(s, st, P)
    local target = st.target
    if target == 0 or (P.on_fire or 0) < 1.5 or target_notes.n >= 12 then return end
    -- ((4.6.7 review) each target looked at once: before, a key was built every frame after its first 1.5 s)
    if P.checked_target == target then return end
    P.checked_target = target
    local key = s.def.name .. ':' .. target
    if target_notes.seen[key] then return end
    local c = st.current
    local kind = c and c.kind
    local a = kind and ARMOR[kind]
    local why
    if not c then why = 'not in its list'
    elseif not kind then why = 'its type could not be read (' .. (c.alive and 'alive' or 'not alive') .. ')'
    elseif not a and not LABELS[kind] then
      -- ((4.6.6 review) once per unknown type, not per enemy: a common bug with no name filled the 12 lines)
      -- ((4.6.7 review) and nothing kept per enemy: after a patch adds a common enemy the mod doesn't know, a key per
      -- enemy grew all session)
      key = 'type:' .. kind
      if target_notes.seen[key] then return end
      why = 'type ' .. EXT.hexr(kind) .. ' is not in the mod\'s enemy list'
    elseif a and hurt_no(s, st, c) then
      why = string.format('%s (type %s, armor %d), which Armor Intelligence skips - %s from it', a.name, EXT.hexr(kind), a.av, c.mask == BLANK and 'hidden' or 'not hidden')
    end
    if not why then return end
    target_notes.seen[key], target_notes.n = true, target_notes.n + 1
    event(string.format('target check: %s fired %.1f s at target %d: %s%s', s.tag or s.def.name, P.on_fire, target, why, near_note(st, c)))
  end

  -- ------------------------------------------------------------------ ground in the way (5.1.5 Test 4)
  -- (my Test 3: the Rocket Sentry "firing into the ground" from high ground at enemies coming up its hill; the
  -- research probe (5.0 Test 19-21, 5.1.5 Test 2) found the ground 1.7-9 m above the Rocket and Autocannon Sentries' lines
  -- of fire then, and asked "All sentries"). HD2 has no Lua raycasts, but everything that walks shows where the ground is:
  -- every ground enemy's place (its feet) is kept as the lowest height seen in each 1 m square (counted once two samples
  -- agree within 0.3 m - something walked there, not leapt or fell through it; not the flying kinds, nor troops still
  -- aboard a dropship, nor your sentries' bases or you). A sentry's line from its muzzle to where the game aims is
  -- followed over those squares: ground GROUND.rise or more above it, at least near_gun m out and short of the blast at
  -- the target (its splash, at least near_target m), on 'confirm' checks in a row, and the target is hidden from it -
  -- it picks another, or with nothing else waits - until the line from its muzzle to the enemy is clear again (checked
  -- every 'recheck' s, held at least 'hold_min' s and at most 'hold_max' s). Not the mortars (they lob) or the Tesla Tower.
  -- ((5.1.5 Test 21) confirm 2 -> 3 checks in a row (a blip in one check no longer holds fire); rise_bullets, see ground_set)
  local GROUND = { cap = 60000, every = 0.1, rise = 0.5, rise_bullets = 1.0, near_gun = 2.0, near_target = 1.5, step = 0.5, check = 0.05, confirm = 3,
    recheck = 0.25, hold_min = 1.0, hold_max = 10.0, aim_lo = 0.5, aim_hi = 2.5 }
  local GMAP = { z = {}, n = {}, count = 0, next_t = 0, e = {} }
  local G_AIR = {}
  for _, h in ipairs({ '282eb766c1ffa6a1', '19e18b46ec55d94a', '64090088502435dd', 'db90077e76faa025', '74e2285c01da4f71', '98152772a72f7838' }) do G_AIR[type_hash(h)] = true end
  local function g_key(x, y) return (math.floor(x) + 30000) * 65536 + (math.floor(y) + 30000) end
  local G_NEAR = { -65537, -65536, -65535, -1, 1, 65535, 65536, 65537 }   -- (the eight squares round one, as key steps)
  -- ((5.1.5 Test 21, test builds) 'hd': a helldiver's footsteps; GMAP.e marks squares an enemy's path (or a sentry's
  -- base) showed, so a hold can say where its ground came from
  local function g_sample(x, y, z, hd)
    if not (x == x and y == y and z == z) then return end
    local k = g_key(x, y)
    if TESTER and not hd then GMAP.e[k] = true end
    local gz = GMAP.z[k]
    if gz then
      if z < gz - 0.3 then GMAP.z[k], GMAP.n[k] = z, 1
      elseif z <= gz + 0.3 then GMAP.n[k] = GMAP.n[k] + 1; if z < gz then GMAP.z[k] = z end end
    elseif GMAP.count < GROUND.cap then GMAP.z[k], GMAP.n[k] = z, 1; GMAP.count = GMAP.count + 1 end
  end
  -- ((5.1.5 Test 18, my ask after Test 17: "tweak the ground vision a bit more so it doesn't have to use the health as a
  -- fallback") every sentry's list, each 'every' s: before, only the first sentry's list was used, and each sentry
  -- lists only the enemies near it - with sentries spread out, the ground in front of the others went unmapped.
  -- An enemy seen in several lists is counted once a look ('seen')
  local function g_samples(s, cands, t)
    if t >= GMAP.next_t then GMAP.next_t, GMAP.tick, GMAP.seen = t + GROUND.every, (GMAP.tick or 0) + 1, {} end
    if s.g_tick == GMAP.tick then return end
    s.g_tick = GMAP.tick
    local ships, seen = nil, GMAP.seen
    for _, c in ipairs(cands) do if c.pos and c.kind and G_AIR[c.kind] then ships = ships or {}; ships[#ships + 1] = c.pos end end
    for _, c in ipairs(cands) do
      local p = c.pos
      if p and c.kind and c.alive and not G_AIR[c.kind] and c.kind ~= AVATAR_TYPE and not seen[c.id] then
        seen[c.id] = true
        local near = false
        if ships then
          for _, q in ipairs(ships) do
            local dz = p[3] - q[3]
            if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 <= 196 and dz >= -12 and dz <= 4 then near = true; break end
          end
        end
        if not near then g_sample(p[1], p[2], p[3]) end
      end
    end
  end
  -- ((5.1.5 Test 18) the ground where your sentries stand (set down on it) and where helldivers walk - you and your
  -- teammates walk round your sentries more than any enemy. A helldiver's square counts only after 3 places within
  -- 0.3 m of each other over at least half a second (not the top of a jump), and never while piloting something
  local HD_GROUND = { pend = {}, n = 0 }
  GMAP.people = function(list, t)
    if not list then HD_GROUND.pend, HD_GROUND.n, HD_GROUND.next_t = {}, 0, 0; return end   -- (a mission's end)
    if t < (HD_GROUND.next_t or 0) then return end
    HD_GROUND.next_t = t + GROUND.every
    for _, p in ipairs(list) do
      if p and not p.vehicle and p[1] == p[1] and p[2] == p[2] and p[3] == p[3] then
        local k = g_key(p[1], p[2])
        local q = HD_GROUND.pend[k]
        if q and math.abs(p[3] - q.z) <= 0.3 then
          q.n = q.n + 1
          -- ((5.1.5 Test 21, my note: the sentries "seemed a little like it was holding back") a full second in one place now
          -- (was half a second): standing a moment on a rock, a crate or the hellpod counted as ground too readily
          if q.n >= 3 and t - q.t0 >= 1.0 and not q.done then q.done = true; g_sample(p[1], p[2], q.z, true); g_sample(p[1], p[2], q.z, true) end
        else
          if not q then
            HD_GROUND.n = HD_GROUND.n + 1
            if HD_GROUND.n > 4000 then HD_GROUND.pend, HD_GROUND.n = {}, 1 end
            q = {}; HD_GROUND.pend[k] = q
          end
          q.z, q.t0, q.n, q.done = p[3], t, 1, false
        end
      end
    end
  end
  GMAP.base = function(s, st)
    if s.g_base or not st.base then return end
    s.g_base = true
    local b = st.base
    g_sample(b[1], b[2], b[3]); g_sample(b[1], b[2], b[3])
  end
  -- the ground in a square: its own (seen twice), or with nothing walked there, the lowest of the squares round it
  -- ((5.1.5 Test 18) when at least two of the eight have it - the lowest, so a gap is never filled in higher than its
  -- lowest side: an enemy's path that runs beside the line still shows a crest the line crosses)
  -- ((5.1.5 Test 21) at least three of the eight now (was two): two known neighbors could fill a dip the line passes over
  -- with its higher banks - the likeliest cause of sentries holding back on enemies they could hit, in my Test 19 game)
  local function g_at(key)
    local Z, N = GMAP.z, GMAP.n
    local gz = Z[key]
    if gz and N[key] >= 2 then return gz, true, key end
    local lo, m, lk = nil, 0, nil
    for _, o in ipairs(G_NEAR) do
      local k2 = key + o
      local z2 = Z[k2]
      if z2 and N[k2] >= 2 then m = m + 1; if not lo or z2 < lo then lo, lk = z2, k2 end end
    end
    if m >= 3 then return lo, false, lk end
    return nil
  end
  -- the highest ground above the line M -> A between 'from' m out and 'stop' m short of A (nil when none is 'rise' above it)
  -- ('rise': how far above the line counts, GROUND.rise unless given; also returns where the highest ground's height came
  -- from: 'enemy paths', 'your footsteps' or 'a filled gap')
  local function g_rise(M, A, stop, rise)
    local dx, dy, dz = A[1] - M[1], A[2] - M[2], A[3] - M[3]
    local D = math.sqrt(dx * dx + dy * dy)
    local last = D - stop
    local d = GROUND.near_gun
    if last < d then return nil end
    rise = rise or GROUND.rise
    local best, at, src = nil, nil, nil
    while d <= last do
      local k = d / D
      local x, y = M[1] + dx * k, M[2] + dy * k
      local gz, mine, gk = g_at(g_key(x, y))
      if gz then
        local over = gz - (M[3] + dz * k)
        if over >= rise and (not best or over > best) then best, at, src = over, d, (not mine and 'a filled gap') or ((GMAP.e[gk] or not TESTER) and 'enemy paths' or 'your footsteps') end
      end
      d = d + GROUND.step
    end
    return best, at, D, src
  end
  -- ((5.1.5 Test 18, test builds) how much of a line the map knows: the share of its steps with ground known (own
  -- square, from the squares round it), and the highest ground relative to the line (negative: all of it below)
  GMAP.cover = function(M, A, stop)
    local dx, dy, dz = A[1] - M[1], A[2] - M[2], A[3] - M[3]
    local D = math.sqrt(dx * dx + dy * dy)
    local last, d = D - stop, GROUND.near_gun
    local n, own, near, hi = 0, 0, 0, nil
    while d <= last do
      local k = d / D
      local gz, mine = g_at(g_key(M[1] + dx * k, M[2] + dy * k))
      n = n + 1
      if gz then
        if mine then own = own + 1 else near = near + 1 end
        local over = gz - (M[3] + dz * k)
        if not hi or over > hi then hi = over end
      end
      d = d + GROUND.step
    end
    return n, own, near, hi
  end
  local g_notes = 0
  -- the enemies hidden from this sentry for ground in its way (a set, or NONE)
  local function ground_set(s, st, t, firing)
    local def, P = s.def, s.P
    local cands, target = st.candidates, st.target
    -- ((5.1.5 Test 18) every sentry maps the ground, the mortars and the Tesla Tower too)
    g_samples(s, cands, t)
    GMAP.base(s, st)
    if def.blast or def.ring or not st.muzzle then return NONE end
    local stop = math.max(GROUND.near_target, def.splash or 0)
    -- ((5.1.5 Test 21) the guns that fire bullets in bursts - Machine Gun, Gatling, the pod and FRV guns - only for
    -- ground a meter or more above their line (was half a meter): their rounds clear the small bumps a rocket wouldn't)
    local rise = def.bursts and GROUND.rise_bullets or GROUND.rise
    local held = P.ground
    -- its target while it fires at it
    local c = st.current
    if target ~= 0 and firing and c and c.pos and st.aim and not (held and held[target]) and t >= (P.g_next or 0) then
      P.g_next = t + GROUND.check
      local over, at, D, src = g_rise(st.muzzle, st.aim, stop, rise)
      if over and P.g_on == target then P.g_hits = (P.g_hits or 0) + 1 else P.g_hits = over and 1 or 0 end
      P.g_on = target
      if P.g_hits >= GROUND.confirm then
        P.g_hits = 0
        if not held then held = {}; P.ground = held end
        local h = st.aim[3] - c.pos[3]
        held[target] = { t0 = t, next = t + GROUND.hold_min, h = math.max(GROUND.aim_lo, math.min(GROUND.aim_hi, h)) }
        bump(session.actions, 'sentry_behind_ground')
        -- ((5.1.5 Test 21, test builds) every hold counted: how far the ground was above the line, and where its height
        -- came from - to tell real cover from a map that guessed too high)
        if TESTER then
          local band = over < 1 and 'under 1 m' or over < 2 and '1-2 m' or over < 5 and '2-5 m' or '5 m or more'
          session.ground_tally = session.ground_tally or {}
          local gk = string.format('%s: %s above, from %s', def.name, band, src or '?')
          session.ground_tally[gk] = (session.ground_tally[gk] or 0) + 1
        end
        if TESTER and g_notes < 30 then
          g_notes = g_notes + 1
          event(string.format('ground (test): %s held fire on %d (%s): ground %.2f m above its line of fire %.1f m out of %.1f m; muzzle %.2f m above its feet, aim %.2f m',
            s.tag or def.name, target, c.kind and EXT.hexr(c.kind) or '-', over, at, D, st.muzzle[3] - c.pos[3], h))
        end
      end
    end
    if not held or not next(held) then return NONE end
    -- the held ones: hidden until the line to them is clear (or they are gone from its list)
    local G, listed = NONE, nil
    for _, e in ipairs(cands) do
      local g = held[e.id]
      if g then
        listed = listed or {}; listed[e.id] = true
        local keep = true
        if t - g.t0 >= GROUND.hold_max then keep = false
        elseif t >= g.next and e.pos then
          g.next = t + GROUND.recheck
          if not g_rise(st.muzzle, { e.pos[1], e.pos[2], e.pos[3] + g.h }, stop, rise) then keep = false end
        end
        if keep then G = put(G, e.id) else held[e.id] = nil end
      end
    end
    for id in pairs(held) do if not (listed and listed[id]) then held[id] = nil end end
    return G
  end

  -- ((5.1.5 Test 5) the damage check, see HEALTH in engine_state.lua) seconds of firing a kind waits for its target's
  -- health to go down before it counts as not hurting it (shells and rockets take a while to land at range), and how
  -- long such an enemy is then left alone by that sentry (longer the second time)
  -- ((5.1.5 Test 18) the Flame Sentry 1.2 -> 2.5 s: my Test 17 log had it drop six Troopers at full health after 1.2-1.7 s
  -- of fire 21-28 m out, and other guns hurt five of them while it left them alone - its flames take a while to get
  -- out there and catch)
  local NODMG = { wait = 1.0, hide = 4.0, hide2 = 10.0, notes = 0, shield = 4.0,   -- (shield: a shield bearer out of sight, 5.1.5 review)
    by = { ['Rocket Sentry'] = 2.5, ['Autocannon Sentry'] = 1.5, ['Laser Sentry'] = 0.8, ['Flame Sentry'] = 2.5 } }
  local function nodmg_set(s, st, t, firing, armour_on)
    local def, P = s.def, s.P
    if def.blast or def.ring then return NONE end
    local target, c = st.target, st.current
    local held = P.nd
    if target ~= 0 and firing and c and c.alive and not (held and held[target]) then
      -- (not while it fires short bursts at a Heavy Devastator's shield: those are meant to keep it down)
      local a = c.kind and ARMOR[c.kind]
      -- ((5.1.5 review) nor at a shielded enemy: its shield takes the hits first, HEALTH.shielded)
      -- ((5.1.5 Test 16) nor at AV5 and up (tanks, turrets, the Vox Engine, the Hive Lord): my Test 15 log had the
      -- Autocannon and Rocket Sentries drop Annihilator Tanks as 'not hurting' with their health at 300 of 300 - their
      -- hits go to the parts' own health, which this record doesn't show. Armor Intelligence decides for those)
      -- ((5.1.5 Test 32, my Test 31 game: the Laser Sentry "moving off" Heavy Devastators "as they were advancing" - their
      -- shields face the sentry as they come, and a shield's hits don't show in the body's health) nor at a shield
      -- bearer, for every sentry (it was only the short-burst guns)
      -- ((5.1.5 review) while it is in sight: out of sight - behind a wall, with Line of Sight off - it is let go after
      -- NODMG.shield s of fire without a change, as nothing else would ever take the sentry off it)
      local shield = a and a.burst
      if not (c.kind and HEALTH.shielded[c.kind]) and not (a and a.av >= 5) then
        P.dw = P.dw or {}
        -- ((5.1.5 Test 6, test builds) when its meter last changed, the last 20 times (was it shooting?)
        if TESTER and t >= (P.am_next or 0) then
          P.am_next = t + 0.1
          local okm, v = pcall(any_meter, s)
          if okm and v then
            P.am_known = true
            if P.am_v and v ~= P.am_v then P.am_hist = P.am_hist or {}; table.insert(P.am_hist, t); if #P.am_hist > 20 then table.remove(P.am_hist, 1) end end
            P.am_v = v
          end
        end
        local wait = shield and NODMG.shield or (NODMG.by[def.name] or NODMG.wait)
        local secs
        if shield and c.visible then
          -- (in sight: no health look-up, its count starts over - from the shots fired after it goes out of sight)
          local e = P.dw.e and P.dw.e[target]
          if e then e.f, e.acc, e.secs, e.next, e.t = P.on_fire or 0, 0, nil, 0, t end
        else
          secs = HEALTH.watch(P.dw, target, P.on_fire or 0, t, s.tag or def.name)
        end
        if secs and secs >= wait then
          P.nd_n = P.nd_n or {}
          local n = (P.nd_n[target] or 0) + 1
          P.nd_n[target] = n
          if not held then held = {}; P.nd = held end
          held[target] = { u = t + (n == 1 and NODMG.hide or NODMG.hide2) }
          if P.dw.e then P.dw.e[target] = nil end
          bump(session.actions, 'sentry_no_damage')
          if TESTER then
            -- ((5.1.5 Test 6) what it was shooting into, and how the drop turns out (HEALTH.track_*))
            local moved
            if P.am_known then
              moved = 0
              for _, ht in ipairs(P.am_hist or {}) do if ht >= t - secs then moved = moved + 1 end end
            end
            local seen = P.unsafe_seen and P.unsafe_seen[target]
            local mate = seen and t - seen < 1.5
            local rise = st.aim and st.muzzle and g_rise(st.muzzle, st.aim, math.max(GROUND.near_target, def.splash or 0))
            -- ((5.1.5 Test 18) how much of its line the ground map knew, to tell ground the map missed from other causes:
            -- tallied by sentry kind in the summary, and in the event)
            local cn, co, cne, chi
            if st.aim and st.muzzle then cn, co, cne, chi = GMAP.cover(st.muzzle, st.aim, math.max(GROUND.near_target, def.splash or 0)) end
            local known = cn and cn > 0 and (co + cne) / cn or nil
            local class = not known and 'its line unknown (no aim)' or (rise and 'ground over its line')
              or (chi and chi > -0.5 and 'ground just under its line') or (known < 0.5 and 'line mostly unmapped') or 'line mapped and clear'
            session.nd_ground = session.nd_ground or {}
            local gk = def.name .. ': ' .. class
            session.nd_ground[gk] = (session.nd_ground[gk] or 0) + 1
            HEALTH.track_new(s, def.name, target, wait, { t = t, hp = P.dw.hp, hold = held[target].u - t,
              meter = moved and moved >= 2 or (moved and false), unseen = not c.visible, mate = mate, rise = rise ~= nil })
            if NODMG.notes < 150 then
              NODMG.notes = NODMG.notes + 1
              local nm = a and a.name or (c.kind and LABELS[c.kind])
              event(string.format('no damage (test): %s fired %.1f s at %d (%s%s, %.0f m) and its health stayed at %d of %d: left alone %.0f s; meter %s, %s%s%s',
                s.tag or def.name, secs, target, c.kind and EXT.hexr(c.kind) or '-', nm and (' ' .. nm) or '', c.d2 and math.sqrt(c.d2) or -1,
                P.dw.hp or -1, P.dw.mx or -1, held[target].u - t, moved and (moved .. ' changes') or 'not readable',
                c.visible and 'in sight' or 'out of sight', mate and ', someone in its line of fire' or '', rise and string.format(', ground %.2f m over its line', rise) or '')
              .. (known and string.format('; ground map: %.0f%% of its line known (%d own, %d from nearby squares of %d), highest %s', 100 * known, co, cne, cn,
                chi and string.format('%.1f m vs its line', chi) or '-') or ''))
            end
          end
        end
      end
    end
    if not held or not next(held) then return NONE end
    local N = NONE
    for id, g in pairs(held) do if t >= g.u then held[id] = nil else N = put(N, id) end end
    return N
  end
  -- drop the target for 'reason'; with nothing else it may pick it would fire on until its timer runs out, so the mod
  -- also lets go of the target for it (up to 3 tries, 0.2 s apart; g keeps the count)
  local function drop_let_go(s, st, t, hide, reason, g)
    local r = drop_target(s, st, t, hide, reason)
    if not r.kick and g and (g.rel or 0) < 3 and t - (g.rel_t or -99) >= 0.2 and st.node == (s.def.fire_node or FIRE_NODE) then
      g.rel, g.rel_t = (g.rel or 0) + 1, t
      r.release, r.release_ai, r.quiet = st.target, true, true
    end
    return r
  end

  local function plan_sentry(s, st, bodies, t, people)
    local P, def, cands, target = s.P, s.def, st.candidates, st.target
    -- ((4.6.7 review) an ask it obeyed is not counted as ignored when it later comes back to that enemy)
    if P.kicked and target ~= 0 and target ~= P.kicked then P.kicked, P.ignored = nil, 0 end
    local armour_on = rawget(_G, 'SmarterGuardDogsArmor') == true   -- (Armor Intelligence: skipping, bursts, dropships)
    local prio_on = OPT.priority()                                   -- (Target Prioritization: gunships, armor tiers, self-defense)
    -- (test builds: which kinds of enemy each sentry goes for, by type id, for bug reports)
    if TESTER and target ~= P.seen_target then
      P.seen_target = target
      local c = st.current
      -- (4.5.2) a sentry with a range: how far each new target is, first 20 per kind (to check the range in game)
      if def.range and c and c.d2 and (range_notes[def.name] or 0) < 20 and not (P.range_seen and P.range_seen[target]) then
        P.range_seen = P.range_seen or {}; P.range_seen[target] = true
        range_notes[def.name] = (range_notes[def.name] or 0) + 1
        note(string.format('range (test): %s picked %d at %.1f m (its range %d m)', s.tag or def.name, target, math.sqrt(c.d2), def.range))
      end
      if c and c.kind then
        local a = ARMOR[c.kind]
        bump(session.sentry_types, def.name .. ': ' .. EXT.hexr(c.kind) .. ((a and (' ' .. a.name .. ' AV' .. a.av)) or (LABELS[c.kind] and (' ' .. LABELS[c.kind])) or ''))
      end
    end
    -- (enemies it could not be steered off: forgotten once they are gone from its list)
    if t >= (P.stuck_clean or 0) and next(P.stuck) then
      P.stuck_clean = t + 2
      local listed = {}
      for _, c in ipairs(cands) do listed[c.id] = true end
      for id in pairs(P.stuck) do if not listed[id] then P.stuck[id] = nil end end
    end
    local U_now, why, gap = unsafe_for(s, st, bodies, st.posts)
    st.unsafe_why, st.gap = why, gap
    for id in pairs(U_now) do P.unsafe_seen[id] = t end
    for id, seen in pairs(P.unsafe_seen) do if t - seen >= LINGER then P.unsafe_seen[id] = nil end end
    for id, until_t in pairs(P.sight_ok) do if t >= until_t then P.sight_ok[id] = nil end end

    -- ---- the sentry's own state first (nothing here depends on which enemies are about)
    -- overheating: stand down (hide everything) until it has cooled
    if def.heat and st.heat then
      local measured = st.heat_from == 'measured'
      local stop, resume = measured and HEAT.stop_measured or HEAT.stop, measured and HEAT.resume_measured or HEAT.resume
      -- (s.was_over: the game's overheated flag. Vanilla it never cools from that; with CowboyBingus's Laser Sentry
      -- Cooldown it cools to nothing and is powered up again, so it stays stood down until the flag has cleared)
      if not P.cooling and (st.heat >= stop or s.was_over) then
        P.cooling = true
        local d = session.sentries[def.name]; if d then d.cooldowns = (d.cooldowns or 0) + 1 end
        event(string.format('%ssentry_cooling: %s at %.0f%% heat (%s); holds fire until it is down to %.0f%%', READ_ONLY and 'would ' or '', s.tag or def.name, 100 * st.heat, st.heat_from, 100 * resume))
      elseif P.cooling and st.heat <= resume and not s.was_over then
        P.cooling = false
        event(string.format('sentry: %s cooled down (%.0f%%, %s), firing again', s.tag or def.name, 100 * st.heat, st.heat_from))
      end
    end
    local cooling = def.heat and st.heat and P.cooling
    -- time on the current target (it fires the whole time it is aimed at it)
    local dt = st.dt or 0
    if target ~= P.on_target then P.on_target, P.on_fire, P.on_lock = target, 0, 0 end
    if target ~= 0 then
      P.on_lock = P.on_lock + dt
      -- (only while its barrel is actually on the target: while it is still swinging round it hits nothing)
      local on = true
      if st.fwd and st.aim then
        -- ((4.6.7 review) plain numbers: no tables a frame)
        local vx, vy, vz = st.aim[1] - st.muzzle[1], st.aim[2] - st.muzzle[2], st.aim[3] - st.muzzle[3]
        local l = math.sqrt(vx * vx + vy * vy + vz * vz)
        on = l < 1e-6 or (st.fwd[1] * vx + st.fwd[2] * vy + st.fwd[3] * vz) / l >= COVER_S.aligned
      end
      if on and st.synced and (not def.fire_node or st.node == def.fire_node) then P.on_fire = P.on_fire + dt end
      target_check(s, st, P)
    end
    -- short bursts at Heavy Devastators (machine gun, Gatling: 'bursts'; with armor skipping on): fire this long at
    -- one, then rest it
    local bursts = def.bursts and armour_on
    if bursts then
      local c = st.current
      local a = c and c.kind and ARMOR[c.kind]
      -- (the whole Devastator rests: body, shield and parts are separate entries, rest_parts in engine_armor.lua)
      -- (4.6.3 review: set once per burst - while it stayed on the enemy after the burst, the rest was pushed back every frame)
      -- (4.6.4 review: and not again while it is still resting - burst_now is cleared when it is dropped, and a gun with
      -- nothing else to pick stays on it, which pushed the rest back every frame all the same)
      -- ((5.1.0 Test 1, my note: short bursts "to keep them surpressed and then if its turned around it should go full
      -- auto") no rest while its line meets the Heavy Devastator's body instead of its shield)
      local open_body = false
      if a and a.burst then local ok, r = pcall(EXT.parts_exposed, s.def, c, st.muzzle, s.id, st.aim); open_body = ok and r end
      if a and a.burst and not open_body and P.on_fire >= BURST_S.fire and P.burst_now ~= target and not (P.rest[target] and t < P.rest[target]) then
        EXT.rest_parts(P.rest, cands, c, t + BURST_S.rest); P.burst_now = target
      end
    end
    for id, until_t in pairs(P.rest) do if t >= until_t then P.rest[id] = nil end end
    -- fire spreading (Laser Sentry): its target counts as lit once it has had enough beam
    if def.spreads_fire then
      -- (a gunship doesn't burn down like the rest: it keeps the beam on it)
      local air = st.current and st.current.kind and AIR_FIRST[st.current.kind]
      -- ((4.6.6, a commenter) nor does Heavy armor - a Charger, a Bile Titan: the Laser Sentry keeps its beam on it
      -- instead of lighting it and leaving it to burn, which left it idle beside a lone Charger)
      local h = def.spreads_fire == true and st.current and st.current.kind and ARMOR[st.current.kind]
      if h and not h.sentries_skip and h.av >= 4 then air = true end
      local lz = def.spreads_fire == true
      -- ((4.6.7 review) the Laser Sentry's 'lock' rule only once it has fired on the enemy: held while it was still
      -- turning toward it, an enemy counted as lit after 1 s without the beam ever touching it, and it moved on)
      if target ~= 0 and not air and (P.on_fire >= (lz and SPREAD.laser_fire or SPREAD.fire)
        or (P.on_lock >= (lz and SPREAD.laser_lock or SPREAD.lock) and (not lz or P.on_fire > 0))) then P.lit[target] = P.lit[target] or t; P.lit_now = target end
      for id, t0 in pairs(P.lit) do if t - t0 >= SPREAD.burn then P.lit[id] = nil end end
    end

    -- ---- one pass over the enemies: every reason that depends on the enemy alone
    --  U unsafe (linger), N can't hurt, O out of sight, C cooling, B resting between bursts
    -- out of sight (behind a wall or cover; not for mortars, which lob over it): hidden while it is, like the dogs.
    -- Its current target gets a short grace while it is only turning towards it, none while it is firing
    local sight = not def.blast
    local firing = st.node == (def.fire_node or FIRE_NODE) or st.node == def.salvo_node
    -- still aboard a dropship (not for the rocket and autocannon sentries, 'hits_carried': their splash also hurts the
    -- dropship): the dropships are found in the same pass
    -- ((5.1.5 Test 28) the mortars always: "All of the mortar sentries shouldnt be firing upon enemies on the dropships.
    -- They should only target enemies already on the ground")
    local ships_wanted = (not def.hits_carried and armour_on) or def.blast
    local U, N, O, C, B, D, SP, Q, HV = NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE
    local HA = NONE   -- (4.6.3) the entries in HV that are a helldiver's (known type): only those are counted and logged
    -- (4.5.2) out of its reach (a sentry with a 'range', the Flame Sentry): enemies further from its muzzle than that
    -- are hidden from it; its current target only once it is RANGE_KEEP further out, so one at the edge isn't dropped
    -- and picked again over and over
    local RG = NONE
    local range2 = def.range and def.range ^ 2
    local keep_range2 = def.range and (def.range + RANGE_KEEP) ^ 2
    local spare = def.spares_helldivers
    local spare_all = spare and EXT.team_wanted()
    -- (with the Safety option off you are fair game: your own entry, within 1.5 m of you, isn't hidden)
    local me_open = spare and st.me and not OPT.safety() and { { at = st.me } } or nil
    local ships
    for _, c in ipairs(cands) do
      local id = c.id
      local play = in_play(c, st)
      local seen = P.unsafe_seen[id]
      if seen and t - seen < LINGER and (gap[id] or 0) < 0.3 and pickable(c, st) then U = put(U, id) end
      if play then
        if hurt_no(s, st, c) then N = put(N, id) end
        if sight and not c.visible and (id ~= target or firing or (c.memory or 0) <= COVER_S.grace) and not (P.sight_ok[id] and t < P.sight_ok[id]) then O = put(O, id) end
        if cooling then C = put(C, id) end
        if range2 and c.d2 and c.d2 > (id == target and keep_range2 or range2) then RG = put(RG, id) end
        -- ((5.1.0 Test 1) a rested Heavy Devastator whose back is turned to this sentry comes back at once: full auto)
        if bursts and P.rest[id] and t < P.rest[id] then
          local ok, r = pcall(EXT.parts_exposed, s.def, c, st.muzzle, s.id, st.current == c and st.aim or nil)
          if not (ok and r) then B = put(B, id) end
        end
      end
      -- (Tesla Tower) a helldiver in its list - you, or a teammate with Teammate safety on - is hidden from it
      -- (any helldiver with Teammate safety on; otherwise one within 6 m of you: the list's positions lag behind a
      -- running helldiver, and a helldiver it picks is zapped at once, so this errs on the wide side)
      -- (4.5: only while it isn't safe by its factions - then helldivers can't be picked, whatever their entries say)
      if spare and c.kind == AVATAR_TYPE and (spare_all or near_body(bodies, c.pos, 36)) and not (me_open and c.pos and near_body(me_open, c.pos, 2.25)) then HV = put(HV, id); HA = put(HA, id) end
      -- (4.5) and an entry whose type can't be read that stands where a helldiver is (it may be one)
      if spare and not c.kind and near_body(bodies, c.pos, 2.25) then HV = put(HV, id) end
      if ships_wanted and c.pos and c.kind then
        local a = ARMOR[c.kind]
        if a and a.sentries_skip and a.av < 10 then ships = ships or {}; ships[#ships + 1] = c.pos end
      end
    end
    -- enemies still aboard a dropship: near a dropship's body and well above the sentry, which can't be the ground
    -- troops it has just set down (those are below its hover height)
    if ships and def.blast then
      -- ((5.1.5 Test 28) a mortar's shells take 5-7 s: only enemies already on the ground. Near a dropship (DROPSHIP.near m
      -- sideways) an enemy still counts as aboard when it is inside the ship's body ('reach' m sideways, from 'body_below' m
      -- under its middle up), when it is more than 'air' m above the ground the map knows there (dropped, still falling), or - with no
      -- ground known there yet - more than 'air_guess' m above the lowest enemy near the ship, down to 'below' m under it.
      -- However high the mortar stands)
      -- (with no ground known there yet: the lowest enemy within DROPSHIP.near m of the ship stands in for it, with
      -- 'air_guess' m to spare - slopes)
      local near2, reach2 = DROPSHIP.near ^ 2, DROPSHIP.reach ^ 2
      local low = {}
      for k, q in ipairs(ships) do
        for _, c in ipairs(cands) do
          local p = c.pos
          if p and (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 <= near2 and (not low[k] or p[3] < low[k]) then low[k] = p[3] end
        end
      end
      for _, c in ipairs(cands) do
        local p = c.pos
        local a = p and c.kind and ARMOR[c.kind]
        if p and not (a and a.sentries_skip) then
          -- ((5.1.5 review) the ground under it looked up once, and only when the ship's body doesn't already settle it)
          local gz, gk
          for k, q in ipairs(ships) do
            local sx2 = (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2
            if sx2 <= near2 then
              local dz = p[3] - q[3]
              local hit = sx2 <= reach2 and dz >= -DROPSHIP.body_below and dz <= DROPSHIP.above
              if not hit then
                if not gk then gz, gk = g_at(g_key(p[1], p[2])), true end
                hit = (gz and p[3] - gz > DROPSHIP.air)
                  or (not gz and dz >= -DROPSHIP.below and dz <= DROPSHIP.above and low[k] and p[3] - low[k] > DROPSHIP.air_guess)
              end
              if hit then
                D = put(D, c.id)
                P.aboard = P.aboard or {}
                if not P.aboard[c.id] then P.aboard_n = (P.aboard_n or 0) + 1; if P.aboard_n > 128 then P.aboard, P.aboard_n = {}, 1 end end
                P.aboard[c.id], P.aboard_t = t, t
                break
              end
            end
          end
        end
      end
    end
    -- ((5.1.5 Test 32, my Test 31 game: the mortar "still seeing it target some enemies a little early off the dropship")
    -- one it counted aboard stays left alone 'settle' s after it last did: landed troops get a moment to come off)
    -- ((5.1.5 review) once the last of them is 'settle' s old the list goes: before, the loop ran every plan for the rest of
    -- the mission after the first dropship)
    if def.blast and P.aboard and t - (P.aboard_t or -99) >= DROPSHIP.settle then P.aboard, P.aboard_n = nil, 0 end
    if def.blast and P.aboard then
      for _, c in ipairs(cands) do
        local at = P.aboard[c.id]
        if at and t - at < DROPSHIP.settle and not (D ~= NONE and D[c.id]) then D = put(D, c.id) end
      end
    end
    if ships and not def.blast then
      local reach2, lo = DROPSHIP.reach ^ 2, st.base[3] + DROPSHIP.above_sentry
      for _, c in ipairs(cands) do
        local p = c.pos
        if p and p[3] >= lo then
          local a = c.kind and ARMOR[c.kind]
          if not (a and a.sentries_skip) then
            for _, q in ipairs(ships) do
              local dz = p[3] - q[3]
              if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 <= reach2 and dz >= -DROPSHIP.below and dz <= DROPSHIP.above then D = put(D, c.id); break end
            end
          end
        end
      end
    end
    -- fire spreading (Laser Sentry, like the Rover): once one is burning it moves on to an unlit one. While something
    -- unlit is about, or nothing burning is close to anyone, the burning ones are left alone (one burning right at the
    -- sentry is kept on until it is dead)
    if def.spreads_fire then
      local laser = def.spreads_fire == true
      local reach2, near2 = SPREAD.reach ^ 2, (laser and SPREAD.laser_near or SPREAD.near_you) ^ 2
      local unlit, necessary, ud2 = false, false, nil
      local keep_on = def.spreads_fire == 'keep'
      local B = st.base
      -- (close to the sentry: its self-defense reach, or for the Laser Sentry 'laser_near' m)
      local function close_by(c)
        if near_sentry(s, st, c) then return true end
        return laser and B and (c.pos[1] - B[1]) ^ 2 + (c.pos[2] - B[2]) ^ 2 + (c.pos[3] - B[3]) ^ 2 < near2
      end
      for _, c in ipairs(cands) do
        local id = c.id
        if c.pos and c.visible and open(c) and not U[id] and not N[id] and not C[id] and not D[id] and not RG[id] and c.d2 and c.d2 <= reach2 then
          if P.lit[id] then
            if near_body(people, c.pos, near2) or close_by(c) then necessary = true end
          else unlit = true; if not ud2 or c.d2 < ud2 then ud2 = c.d2 end end
        end
      end
      st.spread_state = unlit and 'spreading' or (necessary and 'finishing a close one' or ((keep_on or laser) and 'all burning, still firing' or 'letting them burn'))
      if unlit or (not necessary and not keep_on and not laser) then
        for _, c in ipairs(cands) do
          -- ('keep': only for an unlit enemy at most 'closer_keep' m farther than the burning one - closer ones first)
          -- ((4.6.7 review) the Laser Sentry never hides a burning enemy within 'laser_near' of a helldiver, unlit
          -- enemies about or not: before, only the sentry's own surroundings counted while it was spreading)
          -- ((5.1.5 Test 32) the Laser Sentry doesn't spread off a heavy one (AV4+ or a shield bearer: burning won't stop
          -- it): it keeps its beam on those. (Lighter ones it still sets alight and moves on from, as before)
          local ka = laser and c.kind and ARMOR[c.kind]
          if P.lit[c.id] and in_play(c, st) and ((unlit and not keep_on and not laser) or not near_body(people, c.pos, near2)) and not (c.pos and close_by(c))
            and not (laser and ka and (ka.av >= 4 or ka.burst))
            and not (keep_on and c.d2 and ud2 and math.sqrt(c.d2) + PRIORITY.closer_keep < math.sqrt(ud2)) then SP = put(SP, c.id) end
        end
      end
    end
    -- ((5.1.5 Test 4) ground in its way: see ground_set)
    local G = ground_set(s, st, t, firing)
    -- ((5.1.5 Test 5) firing at it without hurting it: see nodmg_set)
    local ND = nodmg_set(s, st, t, firing, armour_on)
    if TESTER and #HEALTH.open > 0 then HEALTH.track_step(s, target, P.on_fire or 0, t) end
    -- priority (rocket/autocannon: armored first; machine gun/Gatling/Laser: unarmored first; Flame: the closest
    -- first). Enemies that are burning, resting between short bursts, out of reach or hidden for any other reason
    -- don't count as the better choice
    if def.prefer and prio_on then
      local heavy, near_first = def.prefer == 'heavy', def.prefer == 'near'
      -- (4.6.4 review: its own range - 'reach' in its def, wiki: MG/Gatling/pod/FRV 75 m, Laser 50 m; else 100 m, the
      -- Autocannon's and Rocket's - so a gun never drops a close enemy for one past its range)
      local reach2, near2 = (def.reach or PRIORITY.reach) ^ 2, PRIORITY.near_you ^ 2
      -- self-defense first: while an enemy it can hurt (and isn't holding off for any reason) is right at the sentry,
      -- everything farther away waits
      local close, want, band, bwant, air
      local band2, min2 = PRIORITY.band ^ 2, s.def.min_range and s.def.min_range ^ 2
      for _, c in ipairs(cands) do
        local id = c.id
        if c.visible and open(c) and not U[id] and not N[id] and not C[id] and not O[id] and not D[id]
          and not B[id] and not SP[id] and not RG[id] and not G[id] and not ND[id] then
          if near_sentry(s, st, c) then close = close or {}; close[id] = true
          elseif not close and c.pos and c.d2 and c.d2 <= reach2 then
            if near_first then
              if not want or c.d2 < want then want = c.d2 end   -- (the closest one's distance, squared)
            elseif c.kind then
              local k = armour_tier(c, heavy, def.air_first)
              if not want or (heavy and k > want) or (not heavy and k < want) then want = k end
              -- (heavy-first guns, and the Laser Sentry ('band', 5.1.5 Test 32): the near band, and whether a gunship is
              -- about - it still comes first)
              if heavy or def.band then
                if k == (heavy and 2 or -1) then air = true end
                -- (not one it has already dropped for not hurting it: back from its rest, the band would pull the sentry
                -- straight back onto the wall it hides behind)
                if c.d2 <= band2 and not (min2 and c.d2 < min2) and not (P.nd_n and P.nd_n[id]) then
                  band = band or {}; band[id] = k
                  if not bwant or (heavy and k > bwant) or (not heavy and k < bwant) then bwant = k end
                end
              end
            end
          end
        end
      end
      if close then
        for _, c in ipairs(cands) do
          if c.pos and not close[c.id] and pickable(c, st) and not near_body(people, c.pos, near2) then Q = put(Q, c.id) end
        end
      elseif band and not air then
        -- (near band: everything outside it waits, and inside it the heaviest first - the one it is finishing kept.
        -- The Laser Sentry: inside it no armor order at all - an advancing heavy one isn't left for a lighter one)
        local e = target ~= 0 and P.dw and P.dw.e and P.dw.e[target]
        local committed = (e and e.hurt_t and t - e.hurt_t < PRIORITY.finish) or (target ~= 0 and P.on_target == target and (P.on_fire or 0) >= PRIORITY.commit)
        for _, c in ipairs(cands) do
          local id = c.id
          if c.pos and pickable(c, st) and not U[id] and not N[id] and not B[id] and not SP[id]
            and not (committed and id == target and band[id]) and not near_body(people, c.pos, near2) then
            local k = band[id]
            if k == nil or (heavy and c.kind and k < bwant) then Q = put(Q, id) end
          end
        end
      elseif want and near_first then
        local d = math.sqrt(want)
        local lim2, keep2 = (d + PRIORITY.closer) ^ 2, (d + PRIORITY.closer_keep) ^ 2
        for _, c in ipairs(cands) do
          local id = c.id
          if c.pos and c.d2 and c.d2 > (id == target and keep2 or lim2) and pickable(c, st) and not U[id] and not N[id]
            and not near_body(people, c.pos, near2) then Q = put(Q, id) end
        end
      elseif want then
        -- ((5.1.5 Test 16, my Test 15 game: "Im seeing the autocannon move on too early before it kills enemies" - 18
        -- priority switches in 88 s) an enemy it is hurting right now (its health went down in the last
        -- PRIORITY.finish s while it fired at it) is finished first; only a gunship takes it off sooner. Enemies right at
        -- the sentry still come first (above)
        -- ((5.1.5 Test 17) my Test 16 game: still 18 switches for the Autocannon. Its hits on a walker or a moving enemy
        -- don't always show in that health right away, so an enemy it has fired at for PRIORITY.commit s is kept too)
        local e = target ~= 0 and P.dw and P.dw.e and P.dw.e[target]
        local committed = (e and e.hurt_t and t - e.hurt_t < PRIORITY.finish) or (target ~= 0 and P.on_target == target and (P.on_fire or 0) >= PRIORITY.commit)
        local finishing = committed and not (want == (heavy and 2 or -1))
        for _, c in ipairs(cands) do
          -- (an enemy whose type can't be read, e.g. one being removed, is never reordered: it isn't known to be lighter)
          local id = c.id
          if c.pos and c.kind and pickable(c, st) and not U[id] and not N[id] and not B[id] and not SP[id] and not (finishing and id == target) then
            local k = armour_tier(c, heavy, def.air_first)
            if ((heavy and k < want) or (not heavy and k > want)) and not near_body(people, c.pos, near2) then Q = put(Q, c.id) end
          end
        end
      end
    end
    -- (4.5.1) enemies it was just steered off because they died: kept hidden while their entry is still in its list and
    -- not alive, up to DEAD_HIDE s, so the game can't pick the body again when it chooses (a tester saw the Supply FRV
    -- gun keep shooting corpses)
    local DD = NONE   -- ((4.6.4 review) a table only when there is something in it)
    if next(P.dead) then
      local alive_now = {}
      for _, c in ipairs(cands) do if c.alive then alive_now[c.id] = true end end
      for id, until_t in pairs(P.dead) do
        if t < until_t and not alive_now[id] then if DD == NONE then DD = {} end; DD[id] = true else P.dead[id] = nil end
      end
    end
    local hide = union(U, N, Q, C, B, SP, O, D, HV, DD, RG, G, ND)
    if TESTER then st.hide_sets = { unsafe = U, armor = N, priority = Q, cooling = C, burst_rest = B, burning = SP, out_of_sight = O, on_dropship = D, helldiver = HV, dead = DD, out_of_reach = RG, behind_ground = G, no_damage = ND } end
    -- (the helldivers' entries, hidden again right after the game's update: sentry_after)
    -- (4.5: by id, not by place - the game moves entries up its list when one before them goes, e.g. an enemy it
    -- just killed, and a helldiver's entry moved into a new place would have been left shown there)
    if spare and next(HV) then s.spare_ids = HV end
    if next(HV) then
      for id in pairs(HV) do
        -- (4.6.3 review: counted and logged only for a real helldiver's entry - one whose type can't be read, often a
        -- dead enemy lying next to one, is still hidden but was counted as a helldiver and kept here for good)
        if not P.spared then P.spared = {} end
        if HA[id] and not P.spared[id] then P.spared[id] = true; bump(session.actions, 'sentry_spared_helldiver')
          if TESTER then event(string.format('sentry: %s had a helldiver among its targets (id %d): hidden from it', s.tag or def.name, id)) end
        end
      end
    end
    -- (Tesla Tower) while it is on a helldiver, ask it to choose again every frame: no hold, no back-off (it is logged once)
    if target ~= 0 and HV[target] then
      local first = P.spare_target ~= target
      -- (4.5) counted in the log: this should stay at 0; if it doesn't, the hiding came too late for the game's pick
      -- (4.6.3: only a known helldiver's entry - one of unknown type next to a helldiver is still dropped, not counted)
      if first and HA[target] then
        bump(session.actions, 'tesla_aimed_at_helldiver')
        -- (listed up to 10 times a session, counted after that)
        if session.actions.tesla_aimed_at_helldiver <= 10 then
        -- (for everyone: rare, and the details say which way the hiding failed - shown = its entry wasn't hidden in
        -- time, hidden = picked in spite of it)
        local c, me = st.current, st.me
        local mine = c and c.pos and me and (c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + (c.pos[3] - me[3]) ^ 2 < 2.25
        -- (Test 33: and what its entry and its faction list held, to see how it could pick it)
        local fl = {}
        local perc = st.perc
        if perc then local n = u32(perc, 0); if n <= 32 then for j = 0, n - 1 do fl[#fl + 1] = tostring(u32(perc, 8 + j * 8)) end end end
        event(string.format('sentry: %s aimed at a helldiver (%s, id %d, AI step %d, its entry %s when read (mask %s, %s), its factions %s, enemy marking %s): asked to choose again every frame',
          def.name, mine and 'you' or 'a teammate', target, st.node, c and (c.mask == BLANK and 'hidden' or 'shown') or 'not listed',
          c and string.format('%08x', u32(c.mask, 0)) or '-', c and tostring(c.group) or '-', table.concat(fl, ' '), P.filter_on and 'on' or 'off'))
        end
      end
      P.spare_target, P.safety_t, P.safety_enemy, P.last_kick_t = target, t, target, t
      return { block = union({ [target] = true }, hide), kick = true, reason = 'sentry_safety', quiet = not first }
    end
    P.spare_target = nil
    -- (5.0) its target just died: choose again now instead of firing at the body until its selection timer runs out
    -- (like the dogs: once per lost target, at most every 0.1 s; checked before any hold, which mustn't keep it on a body). Also when the game has already cleared the target
    -- but it is still in its firing step with the old timer running (it keeps shooting where the enemy was): up to two
    -- asks. Not in the steps where it ignores being asked. Counted, not listed in the events (it happens every kill)
    local prev = P.prev_target or 0
    P.prev_target = target
    local cur = st.current or st.far   -- ((5.1.5 Test 31) one off its list but still in the registry isn't dead)
    if TESTER and target ~= 0 and target ~= prev then P.prev_kind = cur and cur.kind or nil end
    -- ((5.1.5 Test 3) my Autocannon Sentry in Test 2: its target, a Heavy Devastator, died with nothing else
    -- it may pick; the game kept the body as its target in its firing step 6 s past its own timer, firing into the
    -- ground, and never cleared it, so the release below (which waits for the game to clear it) never ran. Still on
    -- the dead target 0.6 s after it died, in its firing step, nothing else open: the mod clears it the way the game
    -- does (AI record target 0, targeting state 0/32767); up to 3 tries per target, 0.2 s apart)
    if target ~= 0 and P.lost_target == target and P.lost_first and not (cur and cur.alive) and t - P.lost_first >= 0.6
      and st.node == (def.fire_node or FIRE_NODE) and t - (P.stuck_t or -99) >= 0.2
      -- ((5.1.5 Test 4, my Laser Sentry burning a wall for ~27 s in Test 3) a target gone from its list can't be
      -- hidden from it - there is no entry to hide - and the game went back to it after each clear: after the first 3
      -- tries the clear is made again every 0.5 s, for as long as it goes back (firing at something not alive never helps)
      and ((P.stuck_tries or 0) < 3 or t - (P.stuck_t or -99) >= 0.5)
      -- ((5.1.5 review) up to 40 clears per target (20 s of going back to it): past that the ask below is left to it)
      and (P.stuck_tries or 0) < 40 then
      local any = false
      for _, c in ipairs(cands) do if c.id ~= target and open(c) and not hide[c.id] then any = true; break end end
      if not any then
        P.stuck_tries, P.stuck_t = (P.stuck_tries or 0) + 1, t
        bump(session.actions, 'sentry_dead_target_cleared')
        return { block = union(hide, { [target] = true }), kick = false, release = target, release_ai = true, reason = 'sentry_target_lost', quiet = true }
      end
    end
    -- (4.5.1) the body is hidden from it as well (P.dead), and if it goes back to the same dead enemy it is asked again
    -- (0.2 s later, up to 2 more times; kick() backs off after two unanswered asks anyway)
    if target ~= 0 and not (cur and cur.alive) and t - (P.lost_t or 0) >= (P.lost_target == target and 0.2 or 0.1) and st.node ~= BUSY_NODE and st.node ~= def.salvo_node
      and (P.lost_target ~= target or (P.lost_again or 0) < 2) then
      local again = P.lost_target == target
      if again then P.lost_again = (P.lost_again or 0) + 1 else P.lost_target, P.lost_again, P.lost_first, P.stuck_tries = target, 0, t, 0 end
      P.lost_t, P.lost_tries = t, 0
      P.dead[target] = t + DEAD_HIDE
      if TESTER then kill_trace_start(s, st, t, again and 'back on the dead target' or 'target died') end
      -- (4.5.3 Test 10) asked to choose with nothing else it may pick, the game picks the same dead target again and
      -- gives it a fresh timer: a tester's Rocket Sentry fired a salvo at a body for ~1.5 s after such an ask, its
      -- target no longer in its list. Then it is only hidden: the game clears the target itself at its next look, and
      -- the release below lets go of its aim at once (as for a target the game cleared, 4.5.1)
      local any = false
      for _, c in ipairs(cands) do if c.id ~= target and open(c) and not hide[c.id] then any = true; break end end
      -- (turn_hold applies only once the game has cleared the target, below: while it still holds the dead one, only
      -- hiding it can leave it on the body up to its timer - every FRV kill in a tester's logs came as a clear)
      if TESTER then kill_decision_note(s, st, target, cands, hide, any, 'died', 'asked to choose again', 'only hidden (nothing else it may pick)') end
      if not any then
        bump(session.actions, 'sentry_dead_target_hidden')
        return { block = union(hide, { [target] = true }), kick = false, reason = 'sentry_target_lost', quiet = true }
      end
      -- ((4.6.7 review) someone is in its line to it: asked as a safety stop - never backed off, flashed red)
      local r = kick(s, st, t, union(hide, { [target] = true }), { [target] = true }, U_now[target] and 'sentry_safety' or 'sentry_target_lost')
      if r.kick then r.quiet = true; bump(session.actions, again and 'sentry_target_lost_again' or 'sentry_target_lost') end
      return r
    end
    if target == 0 and prev ~= 0 then
      P.lost_from, P.lost_tries = prev, 0
      -- (not when the mod's own ask just cleared it: those get an 'ask trace')
      if TESTER and not (P.ktrace and P.ktrace.id == prev) and t - (P.last_kick_t or -99) > 0.3 then kill_trace_start(s, st, t, 'target cleared by the game') end
    end
    if target ~= 0 then P.lost_from = nil end
    if target == 0 and P.lost_from and st.node == (def.fire_node or FIRE_NODE) and (P.lost_tries or 0) < 2 and t - (P.lost_t or 0) >= 0.15 then
      local now = clock_now()
      -- (4.5.1) only when there is something it may pick: asked with nothing to choose, the game gives it a fresh
      -- second in its firing step, firing at nothing (a tester's Supply FRV gun, 'shooting between targets'); left
      -- alone, it stops when its old timer runs out
      local any = false
      if st.deadline > now then for _, c in ipairs(cands) do if open(c) and not hide[c.id] then any = true; break end end end
      local far = any and turn_far(s, st, P.lost_from, cands, hide)
      if TESTER and (P.lost_tries or 0) == 0 then kill_decision_note(s, st, P.lost_from, cands, hide, any and not far, 'cleared by the game (still firing)', 'asked to choose again',
        far and 'let go of its aim (the next enemy is far round: turn to it without firing)' or 'let go of its aim (nothing else it may pick)', 'cleared decision') end
      if far then
        if (P.lost_tries or 0) == 0 then bump(session.actions, 'sentry_turn_hold') end
        any = false
      end
      if any then
        P.lost_t, P.lost_tries = t, (P.lost_tries or 0) + 1
        bump(session.actions, 'sentry_target_lost')
        return { block = hide, kick = true, reason = 'sentry_target_lost', quiet = true }
      end
      -- (4.5.3) nothing to pick: its targeting state still holds the old target (and a second id), and while it does
      -- the gun stays in its firing step, shooting at where the enemy was - about 1 s after the game cleared the target
      -- in its AI record, whatever its timer (a tester's record traces: the FRV gun's AI cleared its own copies at its
      -- next think and stayed in step 12; it left the step the moment the targeting state went to target 0, second id
      -- 32767). The mod lets go of it the same way at once, and (4.6.2) moves back its loss time, which is what really
      -- ends the firing (steer_sentry); up to two tries
      P.lost_t, P.lost_tries = t, (P.lost_tries or 0) + 1
      bump(session.actions, 'sentry_target_released')
      return { block = hide, kick = false, release = P.lost_from, reason = 'sentry_target_lost', quiet = true }
    end
    -- (4.6.4 review: a hold for any other reason never delays a safety stop - in the sim a back-off after two ignored
    -- priority asks let a machine gun sentry fire through you for 37 frames)
    -- ((4.6.6 review) and a safety ask made in a step that ignores asks is made again the moment that step ends)
    local deaf_over = P.hold and P.hold.deaf and P.hold.reason == 'sentry_safety' and st.node ~= BUSY_NODE and st.node ~= def.salvo_node
    if P.hold and target == P.hold.target and t < P.hold.until_t and not (U_now[target] and P.hold.reason ~= 'sentry_safety') and not deaf_over then
      return { block = union(P.hold.block, hide), kick = false, reason = P.hold.reason }
    end
    P.hold = nil
    if target ~= 0 then
      -- its target is unsafe (someone in the line, in the blast, or in the way of its turn): choose again now
      if U_now[target] then return kick(s, st, t, hide, { [target] = true }, 'sentry_safety') end
      -- (in some AI steps the game doesn't choose again: step 10 for every kind, and the rocket sentry's salvo step.
      -- The other reasons wait until that step is over - asking then was only ignored, and after two ignored asks it
      -- was put on hold for longer. The target stays hidden meanwhile.)
      if st.node == BUSY_NODE or st.node == def.salvo_node then return { block = hide, kick = false } end
      -- its target is still aboard a dropship: choose again now
      if D[target] then return drop_target(s, st, t, hide, 'sentry_on_dropship') end
      -- its target went out of sight (it would be firing into the wall): choose again now
      if O[target] then return drop_target(s, st, t, hide, 'sentry_out_of_sight') end
      -- ((5.1.5 Test 4) ground between it and its target (it would be firing into the hill): choose again now
      -- (nothing else it may pick: hidden only, the game would fire on into the ground until its timer runs out - a
      -- second or more - so drop_let_go lets go of the target for it, as for a dead one)
      if G[target] then return drop_let_go(s, st, t, hide, 'sentry_behind_ground', P.ground and P.ground[target]) end
      -- ((5.1.5 Test 5) it has been firing at it without hurting it: choose again now (the same way)
      if ND[target] then return drop_let_go(s, st, t, hide, 'sentry_no_damage', P.nd and P.nd[target]) end
      -- (4.5.2) its target is past its reach (the Flame Sentry)
      if RG[target] then return drop_target(s, st, t, hide, 'sentry_out_of_reach') end
      -- short burst done (Heavy Devastator): leave it for a while
      if B[target] and P.burst_now == target then P.burst_now = nil; return drop_target(s, st, t, hide, 'sentry_burst_done') end
      -- fire spreading: its target is alight, move on (or hold the beam while everything near is burning)
      if SP[target] and P.lit_now == target then P.lit_now = nil; return drop_target(s, st, t, hide, 'sentry_spread') end
      -- overheating: drop its target so it stops firing and cools
      if C[target] then return drop_target(s, st, t, hide, 'sentry_cooling') end
      -- armor it can't hurt
      if N[target] and not P.stuck[target] then return drop_target(s, st, t, hide, 'sentry_cannot_hurt') end
      -- a better-suited enemy (by armor) is in sight: switch to it (at most every 'calm' seconds)
      if Q[target] and t - (P.prio_t or -99) >= PRIORITY.calm then
        P.prio_t = t
        return drop_target(s, st, t, hide, 'sentry_priority')
      end
    end
    -- (test builds, 4.6.2) no target for 1.5 s while live enemies are listed within 50 m: what holds them back (up to 10
    -- per sentry kind, at most one every 8 s per sentry; a tester: the Supply FRV gun has a target only 8% of the time)
    if TESTER then
      if target ~= 0 then P.idle_since = nil
      else
        P.idle_since = P.idle_since or t
        if t - P.idle_since >= 1.5 and t - (P.idle_note_t or -99) >= 8 then
          local near, any = false, false
          for _, c in ipairs(cands) do
            if c.alive and c.d2 and c.d2 < 2500 then near = true; if open(c) and not hide[c.id] then any = true end end
          end
          if near then
            P.idle_note_t = t
            kill_decision_note(s, st, 0, cands, hide, any, string.format('(none for %.1f s)', t - P.idle_since),
              'something is open to pick, the game hasn\'t picked it', 'nothing open to pick', 'idle')
          end
        end
      end
    end
    -- it stood down for someone's safety and has nothing: the moment something is safe, choose right away
    if next(U) then P.safety_seen = t end
    if target == 0 and t - (P.safety_seen or -99) < 2.0 and t - (P.last_kick_t or -99) >= 0.1 then
      for _, c in ipairs(cands) do
        if open(c) and not hide[c.id] then return kick(s, st, t, hide, {}, 'sentry_resume') end
      end
    end
    return { block = hide, kick = false }
  end

  local function note_sentry(s, st, req, me)
    bump(session.actions, req.reason)
    local d = session.sentries[s.def.name]
    if req.reason == 'sentry_cannot_hurt' then
      if d then d.armour = d.armour + 1 end
    elseif req.reason == 'sentry_safety' and d then
      -- ((4.6.7 review) one stop is asked again every 0.25 s while it lasts: noted and counted once, not on every ask)
      local P, now_t = s.P, os.clock()
      if P.stop_noted == st.target and now_t - (P.stop_noted_t or -99) < 3 then P.stop_noted_t = now_t; return end
      P.stop_noted, P.stop_noted_t = st.target, now_t
      d.stops = d.stops + 1
      local w = st.unsafe_why[st.target] or ''
      if w:find('teammate') then d.mate_stops = d.mate_stops + 1 elseif w:find('a sentry') then d.sentry_stops = (d.sentry_stops or 0) + 1 elseif w:find('SEAF') then d.seaf_stops = (d.seaf_stops or 0) + 1 elseif w:find('civilian') then d.civ_stops = (d.civ_stops or 0) + 1 end
      -- ((5.1.5 Test 34, test builds) every stop counted for the session by sentry, why and enemy, in the summary: my
      -- Test 33 log's first safety stops had scrolled out of the last 60 events)
      if TESTER then
        local c = st.current
        local a = c and c.kind and ARMOR[c.kind]
        local nm = a and a.name or (c and c.kind and (LABELS[c.kind] or EXT.hexr(c.kind))) or '?'
        session.safety_tally = session.safety_tally or {}
        local key = string.format('%s, %s: %s', s.def.name, w ~= '' and w or '?', nm)
        session.safety_tally[key] = (session.safety_tally[key] or 0) + 1
      end
    end
    if req.reason == 'sentry_burst_done' or req.reason == 'sentry_spread' or req.reason == 'sentry_out_of_sight' or req.reason == 'sentry_on_dropship' or req.reason == 'sentry_out_of_reach' or req.reason == 'sentry_behind_ground' or req.reason == 'sentry_no_damage' then
      if d then d[req.reason] = (d[req.reason] or 0) + 1 end
      return
    end
    if req.reason == 'sentry_priority' then
      if d then d.priority = (d.priority or 0) + 1 end
      return
    end
    if req.reason == 'sentry_resume' or req.reason == 'sentry_cooling' or noted_events >= 40 then return end
    noted_events = noted_events + 1
    local c = st.current
    local where = ''
    if c and c.pos and me then where = string.format(', %.1f m from you', math.sqrt((c.pos[1] - me[1]) ^ 2 + (c.pos[2] - me[2]) ^ 2 + (c.pos[3] - me[3]) ^ 2)) end
    local what
    if req.reason == 'sentry_safety' then
      local g = st.gap[st.target]
      local why = st.unsafe_why[st.target] or '?'
      local a = c and c.kind and ARMOR[c.kind]
      local nm = a and a.name or (c and c.kind and LABELS[c.kind])
      what = why .. (nm and (', ' .. nm) or '') .. where .. ((g and g < 50 and not s.def.blast and g > -5 and not why:find('swing')) and string.format(', %.2f m inside the safety margin', math.max(0, -g)) or '')
    else
      local a = c and c.kind and ARMOR[c.kind]
      what = (a and (a.name .. ', armor ' .. a.av) or '?') .. where
    end
    event(string.format('%s%s: %s (target %d, %s; AI step %d)', READ_ONLY and 'would ' or '', req.reason, (s.tag or s.def.name), st.target, what, st.node))
  end

  -- (4.6.5, my note: no firing for a second after a target is lost, for everything in the mod) still in its firing step
  -- with no target: the loss time in its AI record is moved back (EXT.loss_cut), so the game's own check ends the
  -- firing now instead of a second later - before 4.6.5 only on the Gatling, pod and FRV guns, after a release; the
  -- Machine Gun Sentry (a tester: 'it stops short of me, but sometimes still kills me') wasn't covered. Not for the
  -- salvo guns (def.salvo, def.salvo_node: the Autocannon and Rocket sentries), whose AI clears its target after the
  -- first round of every salvo - there it would cut every salvo short. Testers: what it found per kind (first 10)
  -- and how soon it then left its firing step
  local loss_notes = {}
  local function loss_step(s, st, t)
    local P, def = s.P, s.def
    local fire = def.fire_node or FIRE_NODE
    if P.lc and st.node ~= fire then
      if TESTER and P.lc.note then event(string.format('loss cut (test): %s left its firing step (AI step %d) %.2f s after', s.tag or def.name, st.node, t - P.lc.t)) end
      P.lc = nil
    end
    if P.lc and t - P.lc.t > 1.5 then
      if TESTER and P.lc.note then event(string.format('loss cut (test): %s still in its firing step %.2f s after (target %d)', s.tag or def.name, t - P.lc.t, st.target)) end
      P.lc = nil
    end
    if READ_ONLY or def.salvo or def.salvo_node or st.target ~= 0 or st.node ~= fire then return end
    if read(s.rec_addr, 4) ~= st.rec_head then return end
    -- ((4.6.5 review) its loss time unchanged since it was last left alone: nothing new, the clock isn't read)
    local lt = P.lc_left and read(s.rec_addr + 408, 8)
    if lt and lt == P.lc_left then return end
    P.lc_left = nil
    local now = clock_now()
    local age, raw = EXT.loss_cut(s.rec_addr, now)
    if not age and raw then P.lc_left = read(s.rec_addr + 408, 8) end
    local n = loss_notes[def.name] or 0
    if age then
      bump(session.actions, 'sentry_loss_cut')
      P.lc = { t = t, note = TESTER and n < 10 }
      if TESTER and n < 10 then
        loss_notes[def.name] = n + 1
        event(string.format('loss cut (test): %s lost its target %.2f s ago, still firing: loss time moved back 1 s', s.tag or def.name, age))
      end
    elseif TESTER and raw and n < 3 and t - (P.lc_note_t or -99) > 5 then
      -- (its loss time not from the last second: not this AI's, or already moved back)
      P.lc_note_t = t
      loss_notes[def.name] = n + 1
      event(string.format('loss cut (test): %s in its firing step with no target, its +408 reads %.2f s ago - left alone', s.tag or def.name, raw / 1e6))
    end
  end

  local function steer_sentry(s, st, req, me)
    if (req.kick and not req.quiet) or req.count then note_sentry(s, st, req, me) end
    if READ_ONLY then return end
    local d = session.sentries[s.def.name]
    if read(s.rec_addr, 4) ~= st.rec_head then return end   -- (its AI record changed under us: nothing written)
    local back = EXT.hider_apply(s.H, st.candidates, req.block)
    -- (4.6.4) the game showed again entries the mod had hidden from it (counted; a tester: the Armed Resupply Pod's gun
    -- kept firing at a Heavy Devastator hidden from it). Hiding them again right after the game's update (Test 4: the
    -- pod gun; Test 9: everything) never caught one in game - the game shows them again later in the frame - so the
    -- next poll's hider_apply is what hides them again
    if back > 0 and d then d.masks_back = (d.masks_back or 0) + back end
    -- (the game clock, read once for both writes below)
    local now = (req.kick or req.release) and clock_now()
    if req.kick then
      if st.deadline > now and st.deadline - now <= 1000000 then
        if not write(s.rec_addr + 152, u64bytes(now)) then stats.write_failures = stats.write_failures + 1 end
      end
    end
    if req.release then
      -- (4.5.3) its targeting state lets go of the old target (target 0, second id 32767, the game's own values), and
      -- (4.6.2) its loss time is moved back a second: after losing its target the AI fires on at the last known spot
      -- until 1 s after the loss time its record holds (+408, stamped by the game; a tester's Test 7 scans), whatever
      -- its targeting state says - the Supply FRV gun even puts that back every frame. With the time moved back, the
      -- game's own check ends the firing at its next update. Only while it still holds that same target, its AI record
      -- has none, and the loss time is from the last second
      local ts = read(s.tstate, 8)
      local rec = read(s.rec_addr, 28)
      local wrote, cleared = false, false
      local held = rec and u32(rec, 24)
      -- ((5.1.5 Test 3) release_ai: the game never cleared a dead target - its AI record target is cleared too)
      if req.release_ai and held == req.release then
        cleared = write(s.rec_addr + 24, pack32(0))
        if cleared then held = 0 else stats.write_failures = stats.write_failures + 1 end
      end
      if ts and rec and u32(ts, 0) == req.release and held == 0 then
        wrote = write(s.tstate, pack32(0) .. pack32(32767))
        if not wrote then stats.write_failures = stats.write_failures + 1 end
        -- ((4.6.5) its loss time: moved back by loss_step, for every sentry kind, each frame it is still in its firing step
        -- with no target - not only after a release)
      end
      -- (test builds, 4.6.2) what it found and did, first 10 per sentry kind (a tester: the Supply FRV gun keeps
      -- firing ~1 s after its target dies although the release ran)
      if TESTER then
        local k = s.def.name .. '/release'
        if (ktrace_count[k] or 0) < 10 then
          ktrace_count[k] = (ktrace_count[k] or 0) + 1
          event(string.format('release (test): %s let go of %d: its targeting state %s, AI target %s, step %d: %s', (s.tag or s.def.name), req.release,
            ts and string.format('%d/%d', u32(ts, 0), u32(ts, 4)) or 'unreadable', rec and tostring(u32(rec, 24)) or 'unreadable', st.node,
            (wrote and 'written 0/32767' or 'not written (it no longer held that target)') .. (cleared and ', its AI target cleared (the game kept the dead one)' or '')))
        end
      end
    end
  end

  -- ------------------------------------------------------------------ each frame
  -- the nearest live enemy inside a sentry's minimum range (nil if none), worked out once per frame
  local function too_close(s, st)
    if st.close_checked then return st.close_enemy end
    st.close_checked = true
    local r2, best = s.def.min_range ^ 2, nil
    for _, c in ipairs(st.candidates) do
      local p = c.pos
      if p and c.alive and c.kind ~= AVATAR_TYPE then
        local d2 = (p[1] - st.base[1]) ^ 2 + (p[2] - st.base[2]) ^ 2 + (p[3] - st.base[3]) ^ 2
        if d2 < r2 then best, r2 = c, d2 end
      end
    end
    st.close_enemy = best
    return best
  end
  -- st_dog: the dog's state this frame (nil when no dog is out); returns true while any sentry of yours is out
  -- ((4.6.7 review) one sentry's deciding and steering, in a pcall of its own: a read that failed for one sentry
  -- stopped every sentry after it for that frame)
  -- ((5.0 Test 9) an enemy's place as the game draws it this frame (see laser.live): the markers move with it, and the
  -- beams end on it, not on the AI's copy refreshed ~6 times a second)
  local function live(c)
    if not c then return nil end
    -- ((5.0 release review) read once a frame per enemy: the laser and the marker both ask)
    if c.live_f == FRAME then return c.live_p end
    local e = c.ent
    local p = (e and unit_position(u32(e, 12))) or c.pos
    c.live_f, c.live_p = FRAME, p
    return p
  end
  -- (5.0 Test 10) how far a sentry kind reaches (meters): its set range, the Tesla's ring, its reach, the mortars' 125,
  -- else the prioritization reach (the Autocannon and Rocket sentries' 100)
  local function reach_of(def) return def.range or def.ring or def.reach or (def.blast and 125) or PRIORITY.reach end
  -- ((5.0 Test 10, my ask: "None of the sentries or Guard dogs should put markers on enemies unless it can actually
  -- harm them") a marker only on an enemy in its reach that its armor check lets it hurt
  -- ((5.1.5 Test 2, my note: the Rocket Sentry "had a laser on its target, just no marker at long range") the enemy it is
  -- locked on (synced) gets its marker even past the reach figure: the game's own range measure isn't ours (3D from the
  -- muzzle - sentries 6-12 m above their targets in my log), and the game firing at it shows it is in reach
  -- ((5.1.5 Test 30) the mortars: the reach from the enemy's live place too (its list entry may have no place far out)
  local function mortar_mark(s, st, c)
    if hurt_no(s, st, c) then return false end
    local d2 = c.d2
    if not d2 then
      local p, b = live(c), st.base
      if not (p and b) then return false end
      d2 = (p[1] - b[1]) ^ 2 + (p[2] - b[2]) ^ 2 + (p[3] - b[3]) ^ 2
    end
    return d2 <= (reach_of(s.def) + 15) ^ 2
  end
  local function can_mark(s, st, c)
    return c and c.d2 and (c.d2 <= reach_of(s.def) ^ 2 or (c == st.current and st.synced)) and not hurt_no(s, st, c)
  end
  -- ------------------------------------------------------------------ (5.0 Test 8) Ping Targeting
  -- (my ask: "I want sentries to prioritize targets with a ping") an enemy you or a teammate ping has its spot record
  -- (SpottableComponent, 24-byte rows: +8 a word that changes with each ping, +0x10 a flag set to 1) marked - found for
  -- Smarter SEAF (its Test 4 log: each change a moment before an F8 press) and shared with it. Each sentry goes for the
  -- closest pinged enemy it can hurt (Armor Intelligence), in its reach, in view (the mortars: any) and not unsafe to
  -- fire on: everything else is hidden from it for up to 20 s after the ping, and it is asked to switch. Its own
  -- state comes first: no ping while it cools down, and the rocket sentry keeps to its minimum range. The records of the
  -- enemies your sentries see are read four times a second. Known game build only (the address checked through the
  -- behaviors table's), else off with one note
  local PING = { t = -1, rows = {}, pinged = {}, notes = 0, LAST = 20, ok = nil }
  local function ping_known()
    if PING.ok == nil and A and A.gbase and A.g and A.g.behaviours then
      PING.ok = A.ping ~= nil   -- (LuaJIT 26251122 port) the known builds carry their ping record's address
      note('ping targeting: ' .. (PING.ok and 'ready' or 'off (unknown game build: the ping record is not known for it)'))
    end
    return PING.ok
  end
  local function ping_refresh(t)
    if t < PING.t then return end
    PING.t = t + 0.25
    local m = ptr_of(read(A.ping, 8), 0)
    local h = m and read(m + 0x20, 20)
    local rows = m and ptr_of(read(m + 0x40, 8), 0)
    if not (h and rows) then return end
    local cap = u32(h, 8)
    if cap == 0 or cap > 65536 or bit.band(cap, cap - 1) ~= 0 then return end
    local seen = {}
    for _, sn in pairs(sentries) do
      local cands = sn.st and sn.st.candidates
      for _, c in ipairs(cands or {}) do
        local id = c.id
        if not seen[id] then
          seen[id] = true
          local idx = map_lookup(m + 0x20, id, 65536, h, true)
          local row = idx and idx < 65536 and read(rows + idx * 24, 24)
          if row then
            local flag, word = row:byte(17), u32(row, 8)
            local P0 = PING.pinged[id]
            if flag == 1 and word ~= 0 then
              if not P0 or P0.word ~= word then
                PING.pinged[id] = { word = word, t = t }
                -- (a ping seen happen - not one already up when the sentry first saw the enemy)
                if (P0 or PING.rows[id] ~= nil) and PING.notes < 15 then
                  PING.notes = PING.notes + 1
                  event(string.format('ping: enemy %d (%s) pinged%s: your sentries that can hurt it go for it', id,
                    c.kind and EXT.hexr(c.kind) or '?', TESTER and string.format(' (record word %08x)', word) or ''))
                end
              end
            elseif P0 then PING.pinged[id] = nil end
            PING.rows[id] = flag
          end
        end
      end
    end
    for id in pairs(PING.rows) do if not seen[id] then PING.rows[id], PING.pinged[id] = nil, nil end end
  end
  -- the pinged enemy this sentry should go for (nil if none)
  local function ping_target(s, st, t)
    if not ping_known() then return nil end
    ping_refresh(t)
    if not next(PING.pinged) then return nil end
    local def = s.def
    if def.heat and s.P.cooling then return nil end
    local R = reach_of(def)
    local min2 = def.min_range and def.min_range ^ 2
    local best, bd
    for _, c in ipairs(st.candidates) do
      local P0 = PING.pinged[c.id]
      -- ((5.0 release review) and one the game would let it take (open: its own scoring doesn't rate it 0): asked to
      -- switch to an enemy it can't engage, with everything else hidden, it sat idle for the whole ping)
      if P0 and t - P0.t <= PING.LAST and c.alive and c.pos and c.d2 and c.d2 < R * R and (c.visible or def.blast)
        and (open(c) or c.id == st.target)
        and not (min2 and c.d2 < min2) and not (st.unsafe_why and st.unsafe_why[c.id]) and not hurt_no(s, st, c) then
        if not bd or c.d2 < bd then best, bd = c, c.d2 end
      end
    end
    return best
  end
  local function sentry_step(s, st, bodies, t, people, me)
    if EXT.SGD.probe_sentry then EXT.SGD.probe_sentry(s, st, t) end   -- (numbered Tester builds: the research probe)
    local req = plan_sentry(s, st, bodies, t, people)
    -- ((5.0 Test 8) Ping Targeting: a pinged enemy it can hurt first - the others hidden, and asked to switch)
    if OPT.ping() then
      local okp, pc = pcall(ping_target, s, st, t)
      -- ((5.0 release review) a threat at the sentry's feet or right next to a helldiver still comes first: while one it
      -- may pick is about, the ping waits)
      local threat = false
      if okp and pc and not req.block[pc.id] then
        local nb2 = PRIORITY.near_you ^ 2
        for _, c in ipairs(st.candidates) do
          if c.id ~= pc.id and c.pos and c.visible and open(c) and not req.block[c.id]
            and (near_sentry(s, st, c) or near_body(people, c.pos, nb2)) then threat = true; break end
        end
      end
      if okp and pc and not threat and not req.block[pc.id] then
        -- ((5.0 release review) one table per sentry, refilled each frame: nothing keeps hold of req.block)
        local b = s.ping_block or {}
        s.ping_block = b
        for k in pairs(b) do b[k] = nil end
        for k in pairs(req.block) do b[k] = true end
        for _, c in ipairs(st.candidates) do if c.id ~= pc.id then b[c.id] = true end end
        req.block = b
        if st.target ~= pc.id then
          if not req.kick then req.kick, req.quiet, req.reason = true, true, 'sentry_ping' end
          if s.P.ping_on ~= pc.id then
            s.P.ping_on = pc.id
            bump(session.actions, 'sentry_ping_switch')
            local d = session.sentries[s.def.name]; if d then d.pings = (d.pings or 0) + 1 end
          end
        end
      elseif not okp and type(pc) == 'table' and pc[1] == Abort then
        -- ((5.0 release review) a failed read (the game moving its tables): skipped this time, tried again next time -
        -- before, one turned Ping Targeting off until the game was restarted)
      elseif not okp and not PING.err then
        PING.err = true
        note('ping targeting: off after an error: ' .. tostring(pc))
        PING.ok = false
      end
      if not pc then s.P.ping_on = nil end
    end
    if TESTER and (req.kick or req.count) and st.target ~= 0 and req.reason ~= 'sentry_target_lost' then
      -- (an ask to drop a live target with nothing else it may pick: trace what it does next)
      local any = false
      for _, c in ipairs(st.candidates) do
        if c.id ~= st.target and not req.block[c.id] and (c.eligible or (c.mask == BLANK and c.alive and (c.score or 0) > 0)) then any = true; break end
      end
      if not any then kill_trace_start(s, st, t, (req.kick and 'asked (' or 'only hidden (') .. tostring(req.reason) .. '), nothing else to pick, AI step ' .. st.node, 'ask trace') end
    end
    steer_sentry(s, st, req, me)
    loss_step(s, st, t)
    if TESTER then kill_trace_step(s, st, t) end
    -- ((5.1.5 Test 19) what the frames between full plans go on with (sentry_light)
    s.light = s.light or {}
    s.light.block, s.light.spread, s.light.why, s.light.gap, s.light.sets = req.block, st.spread_state, st.unsafe_why, st.gap, st.hide_sets
  end
  -- ((5.1.5 Test 19, my "performance can be a bit rough" with lots of enemies) a frame between two full plans: the
  -- line to its current target is checked as every frame (anyone in it: the full plan this frame instead), what it
  -- hides from the game stays hidden (written again where the game showed it), and its fire-after-a-loss cut runs.
  -- Everything else - weighing every enemy, the safety of the rest of its list, priorities, armor - waits a frame.
  -- Returns false when the full plan is needed
  local function sentry_light(s, st, bodies, t, me)
    local L = s.light
    if not L then return false end
    st.spread_state, st.unsafe_why, st.gap, st.hide_sets = L.spread, L.why, L.gap, L.sets
    if st.target ~= 0 then
      local U = unsafe_for(s, st, bodies, st.posts, st.target)
      if U[st.target] then return false end
    end
    L.req = L.req or {}
    L.req.block = L.block
    steer_sentry(s, st, L.req, me)
    loss_step(s, st, t)
    if TESTER then kill_trace_step(s, st, t) end
    return true
  end
  local step_error
  sentry_tick = function(st_dog, t, dt)
    -- (the Sentries option off: your sentries are left to the game)
    -- ((4.6.4 review) each is forgotten into 'remembered' - its tag, heat and policy - so turning the option back on
    -- mid-mission doesn't count it as placed again or reset a Laser Sentry's heat; wiped at mission end)
    if not OPT.sentries() then
      for id, s in pairs(sentries) do forget(id, s, 'Sentries option off', true) end
      -- ((4.6.4 release review) and out of a mission it goes, as with the option on (that wipe is further down)
      if (next(remembered) or next(not_steered)) and not st_dog and not EXT.in_mission() then remembered, not_steered = {}, {} end
      -- ((5.1.5 review) and the ground map, so a mission's ground never carries into the next with the option back on)
      if GMAP.count > 0 and not st_dog and not EXT.in_mission() then GMAP.z, GMAP.n, GMAP.count, GMAP.e = {}, {}, 0, {}; GMAP.people() end
      -- ((4.7.0) the SEAF soldiers and civilians are still looked up for the dog's safety: the agent list every 2 s)
      if st_dog and OPT.seaf_safety() and t >= next_scan then next_scan = t + SCAN_SECONDS; scan(t, nil, true)
      elseif not st_dog and next(SEAF.troops) and not EXT.in_mission() then SEAF.troops, SEAF.list = {}, nil end
      return false
    end
    if not st_dog and not EXT.in_mission() then
      if next(sentries) then sentry_restore() end
      -- (4.6.3 review) what is remembered about sentries goes too, also when none of yours was out at the end (all
      -- destroyed or used up): before, it could carry into the next mission and a new sentry reusing an id and unit
      -- number took over the old one's state
      if next(remembered) or next(not_steered) then remembered, not_steered = {}, {} end
      pl = nil
      noted_events = 0   -- (up to 40 sentry events are logged per mission)
      if GMAP.count > 0 then GMAP.z, GMAP.n, GMAP.count, GMAP.e = {}, {}, 0, {}; GMAP.people() end   -- ((5.1.5 Test 4) a new mission's ground is mapped afresh)
      SEAF.troops, SEAF.list = {}, nil   -- ((4.7.0) a new mission's soldiers are found afresh)
      PING.pinged, PING.rows = {}, {}   -- ((5.0 release review) and its pings
      other_teslas, other_noted = {}, {}
      return false
    end
    -- (a new sentry changes the number of agents: rescan then, at most twice a second; otherwise every 2 s)
    local tg = ptr_of(read(A.g.targeting, 8), 0)
    local th = tg and read(tg + 308, 60)   -- ((5.1.5 Test 11) the count (+320) and the list (+360) in one read
    local count = th and u32(th, 12)
    RC.tcount = count   -- ((5.1.5 Test 19) for RC.now)
    -- (only a rising count can mean a new sentry: a falling one is noted so the next rise is seen; a sentry that is
    -- removed is dropped by its own failed read, and the regular scan catches anything else)
    if count and last_count and count < last_count then last_count = count end
    -- ((5.1.5 Test 11) while the whole mod idles, the full search every 10 s (it reads every agent's row); a new agent
    -- still shows within 0.25 s: the count rising, or - one gone and one new in the same look - the last row changing)
    local last_row
    if IDLE.on and count and count > 0 then
      local tl = ptr_of(th, 52)
      last_row = tl and read(tl + (count - 1) * 8, 8)
    end
    if IDLE.wake_scan then IDLE.wake_scan, next_scan = false, 0 end   -- (waking: the lists afresh - SEAF soldiers, other sentries)
    if t >= next_scan then
      next_scan, last_scan = t + (IDLE.on and 10 or SCAN_SECONDS), t
      scan(t)
    elseif count and last_count and count > last_count and t >= (last_scan or 0) + 0.5 then
      last_scan = t
      scan(t, last_count)   -- (only the new rows)
    elseif last_row and IDLE.last_row and last_row ~= IDLE.last_row and count == last_count then
      last_scan = t
      scan(t, math.max(0, count - 4))   -- (the last rows)
    end
    IDLE.last_row = last_row
    if not next(sentries) then return false end
    -- ((5.1.5 Test 11) sentries with nothing to do idle: no target, nothing hidden from them, no enemy in their list
    -- within IDLE.range of them, for IDLE.settle s. Then only every IDLE.look s: their AI record (still theirs, no target)
    -- and their perception record (an enemy they may pick within IDLE.range, IDLE.near_hostile) - 2 reads - and their
    -- records checked once a second; a Laser Sentry's estimated heat goes on cooling meanwhile. A Tesla Tower never
    -- idles (it is kept off helldivers the whole time it is out). When every sentry idles, nothing else is done this poll
    local awake = false
    for _, s in pairs(sentries) do
      if s.asleep and not s.moved and s.st then
        if t >= (s.peek_next or 0) then
          s.peek_next = t + IDLE.look
          local el = math.max(0, t - (s.read_t or t))
          s.read_t = t
          local d = session.sentries[s.def.name]
          if d then d.out = d.out + el end
          local h = s.def.heat
          if h then s.heat = math.max(0, s.heat - h.cool * el) end
          local wake = false
          if t >= (s.check_next or 0) then
            s.check_next = t + 1.0
            local okc, cur = pcall(records_current, s)
            wake = not (okc and cur)
          end
          if not wake then
            local r = read(s.rec_addr, 28)
            wake = not (r and u32(r, 0) == s.ai and u32(r, 24) == 0) or IDLE.near_hostile(s.pbase, s.st.muzzle, IDLE.range, s.sleep_skip)
          end
          if wake then
            -- (checked and read in full at once, and the lists searched afresh)
            s.asleep, s.busy, s.check_next, s.next_read, s.idle_since = false, true, 0, 0, nil
            IDLE.wake_scan = true
          end
        end
      end
      if not s.asleep then awake = true end
    end
    if not awake then return true, false end
    local me, mates
    if st_dog then me, mates = st_dog.player_pos, st_dog.mates
    else
      if not pl or t >= pl_until then
        local ok, p = pcall(EXT.find_player)
        pl, pl_until = ok and p or nil, t + 0.25
      end
      if pl then
        me = unit_position(pl.player_unit)
        if me and pl.vehicle then
          me.vehicle = pl.vehicle
          -- (Testers: what you were piloting, once per kind)
          if TESTER and not vehicle_notes[pl.vehicle] then
            vehicle_notes[pl.vehicle] = true
            event(string.format('you (test): piloting a unit of type %s (not your helldiver): the sentries keep a %.1f m tall body %.1f m wide round it, at %.1f %.1f %.1f',
              EXT.hexr(pl.vehicle), VEHICLE_BODY.top, 2 * VEHICLE_BODY.extra, me[1], me[2], me[3]))
          end
        end
        mates = EXT.team_wanted() and EXT.teammates(pl, t) or {}
        -- (5.0) the log's teammates line: counted here too while no dog is out (only the dog's poll counted them)
        if #mates > session.team.max then session.team.max = #mates end
      end
    end
    EXT.me = me   -- ((5.0) the laser's fade with distance, while no dog is out)
    -- ((5.1.5 Test 18) where you and your teammates walk, for the ground map
    if me or (mates and mates[1]) then
      local hl = { me }
      for _, m in ipairs(mates or {}) do hl[#hl + 1] = m end
      GMAP.people(hl, t)
    end
    local bodies = bodies_for(me, mates)
    local pbodies = post_bodies(t)   -- (4.6.5 Sentry Safety: nil with the option off or no sentry out)
    -- (with Safety on, the same list; otherwise you are added back for the priority rules)
    local people = bodies
    if me and not OPT.safety() then
      people = { { at = me } }
      for _, b in ipairs(bodies) do people[#people + 1] = b end
    end
    -- (4.7.0 SEAF Safety) the SEAF soldiers and civilians join the bodies the sentries must not hit (not 'people': the priority and
    -- fire-spreading rules about enemies near a helldiver stay about helldivers)
    local fb = seaf_bodies(t, me)
    if fb and #fb > 0 then
      -- ((5.0 release review) a fresh list only when 'people' is this same list (Safety on); otherwise this frame's own
      -- list takes them directly)
      local all = bodies
      if people == bodies then all = {}; for i, b in ipairs(bodies) do all[i] = b end end
      for _, b in ipairs(fb) do all[#all + 1] = b end
      bodies = all
    end
    local registry = rptr(A.g.registry, 'registry')
    -- (its records moved: found again straight away, in this same frame, so it is never left a frame unsteered;
    -- nothing is read or written through the old copies, and its last frame's laser is dropped)
    local moved
    for id, s in pairs(sentries) do
      -- (a Tesla Tower: every frame, 4.5; and one found moved right after the game's update, sentry_after)
      -- (a Tesla Tower not yet safe by its factions: every frame, unless its records were confirmed right after the
      -- game's last update, sentry_after)
      if s.asleep and not s.moved then   -- (checked in its own look above)
      elseif s.moved_after then s.moved_after, moved = nil, true
      -- (4.5, Test 30: and every sentry while it is busy - a tester found the FRV gun's safety a moment late, and its
      -- records move often: until a move is found, its asks go to the old copy)
      -- ((4.6.6 review) a Tesla Tower is always busy: its check is skipped when sentry_after confirmed its records right
      -- after the game's last update, as meant - before, 'busy' ran it every frame anyway)
      -- ((5.1.5 Test 19) a busy sentry: only when the game's agent lists changed since its last check (RC.now) - its
      -- records move when agents come or go (a sentry placed, an enemy dying), and every frame that cost it 3-4 map
      -- look-ups. Its AI record's owner is still checked on every read, and the full check runs every CHECK_EVERY s)
      elseif t >= (s.check_next or 0) or (s.busy and not s.def.spares_helldivers and not (s.def.blast and t < (s.next_read or 0)) and s.rc_gen ~= RC.now()) or (s.def.spares_helldivers and s.after_ok ~= FRAME - 1) then
        s.check_next = t + CHECK_EVERY
        local gen = RC.now()
        local okc, cur = pcall(records_current, s)
        if okc and not cur then
          s.moved, s.spare_ids, s.st, moved = true, nil, nil, true
          -- (test builds: whether the game's lists had changed since its last check - if a move ever shows without, the
          -- skip above needs another look)
          if TESTER then s.moved_how = s.rc_gen ~= gen and 'the game\'s agent lists had changed' or 'found by the regular check, the lists unchanged' end
        elseif okc then s.rc_gen = gen end
      end
    end
    if moved then
      next_scan, last_scan = t + SCAN_SECONDS, t
      scan(t)
      if not next(sentries) then return false end
    end
    -- (4.0.6) busy: some sentry has a target, is still in its firing step, has enemies (alive) in its list or enemies
    -- hidden from it - then the main loop checks every frame; otherwise a few times a second (idle sentries were
    -- over 95% of all checks in a long mission). An enemy shows up in a sentry's list before it can be picked
    local busy = false
    for id, s in pairs(sentries) do
      -- (4.5) each sentry at its own pace: every frame while it is busy, otherwise ten times a second (before 4.5 one
      -- busy sentry - a Tesla Tower always was - had every idle one read every frame too)
      if s.asleep and not s.moved and s.st then   -- (idle: its own look above)
      -- ((5.1.5 Test 19) a busy mortar: 20 times a second, not every frame - its shells are 5-7 s in the air and it lines
      -- up for over half a second, so nothing it does turns on a frame; its marker is still drawn every frame)
      elseif s.moved or (s.busy ~= false and not s.def.blast) or not s.st or t >= (s.next_read or 0) then
        local sdt = s.read_t and math.min(t - s.read_t, 0.5) or dt
        s.read_t, s.next_read = t, t + ((s.def.blast and s.busy ~= false) and MORTAR_EVERY or 0.1)
        local ok, st, why
        s.spare_ids = nil   -- (set again by plan_sentry from this frame's read)
        if s.moved then ok, st, why = true, nil, nil else ok, st, why = pcall(read_sentry, s, registry, t) end
        if ok and st then
          s.st = st
          st.me, st.posts = me, pbodies
          -- ((4.6.5 review) its kind's height for Sentry Safety, learned from its muzzle (capped at 4 m)
          if pbodies and st.muzzle and st.base then
            local h = math.min(st.muzzle[3] - st.base[3] + 0.3, 4)
            if h > (POST.kh[s.def.name] or 0) + 0.05 then POST.kh[s.def.name] = h end
          end
          st.fwd = barrel_dir(s, st)
          heat_update(s, st, t, sdt)
          st.dt = sdt
          if s.def.spares_helldivers then tesla_filter(s, st, bodies) end
          -- ((5.1.5 Test 19) every other frame, half the sentries on each (by id): a full plan, and in between
          -- sentry_light. Always the full plan for a new target, after a move, at least every 0.1 s, and for the Tesla
          -- Tower, the mortars (read 20 times a second anyway) and sentries with heat (the Laser Sentry's beam sweeps)
          local full = true
          if s.light and s.plan_t and t - s.plan_t < 0.1 and s.plan_tg == st.target and (FRAME + s.id) % 2 == 1
            and not s.def.spares_helldivers and not s.def.blast and not s.def.heat then
            local okl, done = pcall(sentry_light, s, st, bodies, t, me)
            if okl and done then
              full = false
              session.light_frames = (session.light_frames or 0) + 1
            end
          end
          local okp, perr = true, nil
          if full then
            st.dt = s.plan_t and math.min(t - s.plan_t, 0.5) or sdt
            s.plan_t, s.plan_tg = t, st.target
            okp, perr = pcall(sentry_step, s, st, bodies, t, people, me)
            session.full_frames = (session.full_frames or 0) + 1
          end
          if not okp then
            if type(perr) == 'table' and perr[1] == Abort then
              local msg = 'sentries: read_failed: ' .. tostring(perr[2])
              if msg ~= step_error then step_error = msg; event(msg) end
            else error(perr, 0) end
          end
          local d = session.sentries[s.def.name]
          if d then
            d.out = d.out + sdt; if st.target ~= 0 then d.targeted = d.targeted + sdt end
            if s.def.min_range and too_close(s, st) then d.too_close = (d.too_close or 0) + sdt end
          end
          if TESTER then bump(session.sentry_nodes, s.def.name .. ': ' .. (st.target == 0 and 'no target' or ('AI step ' .. st.node .. (st.synced and '' or ' (not synced)')))) end
          -- busy: a target, still in its firing step, enemies hidden from it or alive in its list, or a Tesla Tower
          -- (a helldiver walking into its list is hidden the frame it shows up)
          -- ((5.1.5 Test 11) an enemy alive in its list counts only within IDLE.range of it: none engages farther)
          local b = st.target ~= 0 or st.node == (s.def.fire_node or FIRE_NODE) or next(s.H) ~= nil or s.def.spares_helldivers or false
          if not b then
            local R2 = IDLE.range * IDLE.range
            for _, c in ipairs(st.candidates) do if (c.alive and (not c.d2 or c.d2 < R2)) or c.mask == BLANK then b = true; break end end
          end
          s.busy = b
          -- (nothing to do for IDLE.settle s: it idles)
          if b or s.moved then s.idle_since = nil
          elseif not s.idle_since then s.idle_since = t
          elseif t - s.idle_since >= IDLE.settle then
            s.asleep, s.peek_next, s.check_next, s.sleep_skip = true, t + IDLE.look, t + 1.0, {}
            for _, c in ipairs(st.candidates) do if not c.alive then s.sleep_skip[c.id] = true end end
          end
        elseif not s.moved then
          -- gone (destroyed, out of ammo, picked up) or unreadable: put its masks back and forget it
          if not ok then event('sentry: ' .. (s.tag or s.def.name) .. ' dropped after a read error: ' .. tostring(type(st) == 'table' and st[2] or st)) end
          forget(id, s, ok and tostring(why) or 'read error')
          next_scan = 0   -- look for it again straight away (usually the game has only moved its records)
        end
      end
      if s.moved or s.busy then busy = true end
    end
    return next(sentries) ~= nil, busy
  end

  sentry_restore = function()
    local ok = true
    for _, s in pairs(sentries) do if not hider_restore(s.H) then ok = false end; pcall(tesla_unfilter, s) end
    sentries, remembered, not_steered = {}, {}, {}
    return ok
  end

  -- the laser for each sentry (appended to 'beams'): green along its barrel while it is on a target, flashing red
  -- toward an enemy it was just kept off for someone's safety; the Tesla Tower's reach as a green ring (plus a laser to
  -- its target), and a flashing red ring around the rocket sentry while an enemy is inside its minimum range
  -- ((5.0) key, tg: whose beam and on which target - a new target swings its end over, see laser.prepare)
  -- ((5.0 Test 7) fixed: the beam runs along the barrel, so its end isn't swung over to a new target - the barrel turns it)
  -- ((5.1.1, my note: the Supply FRV gun's laser "origin point is too far out") the beam starts 'inset' m ahead of
  -- the fire node (0.2 by default, so it leaves the barrel's mouth on guns whose fire node sits inside it); a def's
  -- 'beam_inset' overrides it - the Supply FRV gun and the Resupply Pod Gun (the same gun model) have their fire node
  -- at the barrel's tip already (the game model's muzzle bone), so theirs is 0
  -- ((5.1.5 Test 13) how long a mortar's marker stays where its shell lands, at most (a new shell moves it on)
  local MORTAR_SHOT, MORTAR_STEP = 8.5, 13   -- ((5.1.5 Test 16) its shells land 5.3-7.1 s after the salvo starts; (Test 17) 7.2 s seen too
  -- ((5.1.5 Test 14) and how long it stays where it was last aimed once the mortar has let go of its target)
  local MORTAR_LINGER = 4.0
  -- (Testers: each shell launched, where it was aimed and where the enemy stood, and how long until the enemy's health
  -- went down - the shell's flight time, to tune MORTAR_SHOT; up to 30 shells a session)
  local shot_notes = { n = 0, open = {} }
  local function mortar_shot_note(s, st, c, t)
    if shot_notes.n >= 30 then return end
    shot_notes.n = shot_notes.n + 1
    local a = c.pos
    local d = st.base and math.sqrt((c.pos[1] - st.base[1]) ^ 2 + (c.pos[2] - st.base[2]) ^ 2) or -1
    local hp = HEALTH.of(st.target)
    event(string.format('mortar shot (test): %s salvo at %d (%s) %.0f m away; marker left at %.1f %.1f %.1f%s', s.tag or s.def.name,
      st.target, c.kind and EXT.hexr(c.kind) or '-', d, a[1], a[2], a[3], hp and string.format(', health %d', hp) or ''))
    if hp then shot_notes.open[#shot_notes.open + 1] = { tag = s.tag or s.def.name, id = st.target, hp = hp, t = t, next = t + 0.1 } end
  end
  -- (the shells' flight: each open shot's enemy looked at ten times a second for up to 10 s)
  local function shot_watch(t)
    local L = shot_notes.open
    local i = 1
    while i <= #L do
      local o = L[i]
      local done = false
      if t >= o.next then
        o.next = t + 0.1
        local hp = HEALTH.of(o.id)
        if hp and hp < o.hp then event(string.format('mortar shot (test): %s\'s shell hurt %d %.1f s after it was fired (health %d -> %d)', o.tag, o.id, t - o.t, o.hp, hp)); done = true
        elseif t - o.t > 10 or not hp then event(string.format('mortar shot (test): %s\'s shell: %d not hurt within %.0f s', o.tag, o.id, t - o.t)); done = true end
      end
      if done then table.remove(L, i) else i = i + 1 end
    end
  end
  local function add_beam(beams, M, to, argb, dot, key, tg, fixed, inset)
    local v, len = norm({ to[1] - M[1], to[2] - M[2], to[3] - M[3] })
    local k = inset or 0.2
    if v and len > 1 then beams[#beams + 1] = { from = { M[1] + v[1] * k, M[2] + v[2] * k, M[3] + v[3] * k }, to = to, argb = argb, dot = dot, key = key, tg = tg, fixed = fixed } end
  end
  -- ((5.0 Test 7) where the barrel points, as far as 'to': the end of a laser fixed on the gun, and whether that end is on
  -- the target (for the cross); nil when the barrel's direction can't be read. The barrel: the axis learned or set for
  -- the kind (st.fwd), or for the Rocket and Autocannon sentries their muzzle part's 'laser_axis' (used for the laser
  -- only: their safety and turn checks don't use a barrel). Lightly smoothed (half the last frame's) so the barrel's
  -- wobble doesn't shake it
  -- (Testers, 5.0 Test 7: checks the Rocket and Autocannon sentries' laser_axis in game) while it holds steady on a
  -- target, how far each axis of its muzzle part is from the game's aim; one line per kind every 60 samples, up to 4
  local axis_stats = {}
  local function laser_axis_check(s, st, M, f)
    local v = norm({ st.aim[1] - M[1], st.aim[2] - M[2], st.aim[3] - M[3] })
    local p = s.axis_last_aim
    s.axis_last_aim = v
    if not (v and p and st.axes and dot3(v, p) > 0.9995) then return end
    local S = axis_stats[s.def.name] or { n = 0, sums = {}, logged = 0 }
    axis_stats[s.def.name] = S
    if S.logged >= 4 then return end
    for r = 1, 3 do S.sums[r] = (S.sums[r] or 0) + dot3(st.axes[r], v) end
    S.n = S.n + 1
    if S.n >= 30 then   -- ((5.1.5 Test 2) 30 steady samples (was 60): the Autocannon Sentry's never reached 60
      S.logged = S.logged + 1
      local la = s.def.laser_axis
      local m = { S.sums[1] / S.n, S.sums[2] / S.n, S.sums[3] / S.n }
      event(string.format('laser axis (test): %s, muzzle axes vs the game\'s aim (1 = on it, -1 = backward): %.3f %.3f %.3f; the laser uses axis %d (%.1f degrees off on average)',
        s.def.name, m[1], m[2], m[3], la, math.deg(math.acos(math.max(-1, math.min(1, m[la]))))))
      S.n, S.sums = 0, {}
    end
  end
  local INTO = 0.4   -- ((5.0 Test 9) meters past the point nearest the enemy's middle: the depth-tested line ends on its body
  laser.kind_name = function(kind) local a = ARMOR[kind]; return (a and a.name) or LABELS[kind] end   -- ((5.1.5 Test 22) for laser.fit_end
  local function barrel_end(s, st, M, to, c)
    local f = st.fwd or st.bdir
    local la = not st.bdir and s.def.laser_axis
    if not f and la and st.axes and not s.def.axis_off then f = st.axes[la] end
    if not f then return nil end
    -- ((5.1.5 Test 2, my ask: "the laser was missing on the autocannon sentry") a laser_axis taken from the game
    -- models (only the Rocket Sentry's was confirmed in game): if 60% or more of 90 frames (about 1.5 s) with the game's
    -- aim holding steady have it more than 10 degrees off that aim, it is the wrong axis for this kind - from then on its
    -- laser points at its target, as for a gun whose barrel can't be read (noted once)
    -- ((5.1.5 Test 3) it tripped for the Rocket Sentry too, whose axis was confirmed in game (5.0 Test 8): its barrel
    -- was still turning to a steady aim. A frame counts only when the barrel holds steady as well, on the same target,
    -- and never for a confirmed axis)
    if la and not st.fwd and st.synced and st.aim and not s.def.axis_confirmed then
      local v = norm({ st.aim[1] - M[1], st.aim[2] - M[2], st.aim[3] - M[3] })
      local pv, pf = s.axis_v, s.axis_f
      if s.axis_tgt ~= st.target then s.axis_tgt, s.axis_n, s.axis_bad, s.axis_sum, pv = st.target, 0, 0, 0, nil end
      s.axis_v, s.axis_f = v, f
      if v and pv and pf and dot3(v, pv) > 0.9995 and dot3(f, pf) > 0.99995 then
        local d = dot3(f, v)
        s.axis_n = (s.axis_n or 0) + 1
        if d < 0.985 then s.axis_bad = (s.axis_bad or 0) + 1 end
        s.axis_sum = (s.axis_sum or 0) + d
        if s.axis_n >= 90 then
          if s.axis_bad >= 0.6 * s.axis_n then
            s.def.axis_off = true
            note(string.format('laser: the %s\'s barrel axis %d is about %.0f degrees off where it aims: its laser points at its target instead', s.def.name, la,
              math.deg(math.acos(math.max(-1, math.min(1, s.axis_sum / s.axis_n))))))
            return nil
          end
          s.axis_n, s.axis_bad, s.axis_sum = 0, 0, 0
        end
      end
    end
    local p = s.beam_fwd
    if p and s.beam_fwd_t and os.clock() - s.beam_fwd_t < 0.25 then f = norm({ p[1] * 0.5 + f[1] * 0.5, p[2] * 0.5 + f[2] * 0.5, p[3] * 0.5 + f[3] * 0.5 }) or f end
    s.beam_fwd, s.beam_fwd_t = f, os.clock()
    local len = math.sqrt((to[1] - M[1]) ^ 2 + (to[2] - M[2]) ^ 2 + (to[3] - M[3]) ^ 2)
    -- ((5.0 Test 9, my ask: "sometimes floating in front of the enemies") as far as the point on the barrel's line
    -- nearest the enemy's middle, and a little into it - not as far as the aim point, which leads a moving enemy)
    local C = c and live(c)
    if C then
      local sp = (C[1] - M[1]) * f[1] + (C[2] - M[2]) * f[2] + (C[3] + AIM_UP[2] - M[3]) * f[3]
      if sp > 1 then len = sp + INTO end
    end
    local e = { M[1] + f[1] * len, M[2] + f[2] * len, M[3] + f[3] * len }
    e = laser.fit_end(e, c)   -- ((5.1.5 Test 22) never over the enemy's head, see engine_laser.lua
    if TESTER and la and st.aim and st.synced then laser_axis_check(s, st, M, f) end
    -- ((5.1.5 Test 29, test builds) the barrel from its parts against its muzzle's axis 2 and the game's aim, while it
    -- holds steady on a target: up to 4 lines per kind, each over 30 samples)
    if TESTER and st.bdir and st.aim and st.synced and st.axes then
      local v = norm({ st.aim[1] - M[1], st.aim[2] - M[2], st.aim[3] - M[3] })
      local B = s.bd_stats or { n = 0, a = 0, x = 0, logged = 0 }
      s.bd_stats = B
      if v and B.logged < 4 and s.bd_last and dot3(v, s.bd_last) > 0.9995 then
        B.n, B.a, B.x = B.n + 1, B.a + dot3(st.bdir, v), B.x + dot3(st.bdir, st.axes[2])
        if B.n >= 30 then
          B.logged = B.logged + 1
          event(string.format('barrel (test): %s, its barrel from its parts is %.1f degrees off the game\'s aim and %.1f degrees off its muzzle\'s axis 2', s.tag or s.def.name,
            math.deg(math.acos(math.max(-1, math.min(1, B.a / B.n)))), math.deg(math.acos(math.max(-1, math.min(1, B.x / B.n))))))
          B.n, B.a, B.x = 0, 0, 0
        end
      end
      s.bd_last = v
    end
    return e, (e[1] - to[1]) ^ 2 + (e[2] - to[2]) ^ 2 + (e[3] - to[3]) ^ 2 <= (math.max(1.5, 0.06 * len) + INTO) ^ 2
  end
  -- (Tesla Tower) its reach as a ring on the ground around it
  local RING_SEGMENTS = 40
  -- (alpha, red, green, blue) ((5.0, my call) both rings red - the Tesla Tower's steady, the Rocket Sentry's flashing - and
  -- a lot thicker: five bands 2.5 cm apart at two heights 4 cm apart, 400 lines a ring, built once and reused)
  local RING_TESLA, RING_RED = { 255, 200, 20, 16 }, { 255, 220, 16, 12 }
  -- (a sentry doesn't move once it is set up, so each ring is built once per sentry, radius and color and reused:
  -- rebuilt only if its base moved more than 0.2 m)
  -- (the Tesla Tower's ring is drawn as two rings 8 cm apart, a tester's call: thicker, so it reads at a distance;
  -- 'bands' lists the offsets from the radius, in meters. Three bands 6 cm apart cost 50% more drawing for about the
  -- same look)
  local RING_BANDS = { -0.05, -0.025, 0, 0.025, 0.05 }
  local TESLA_BANDS = RING_BANDS
  local RING_LAYERS = { 0, 0.04 }
  -- height above the sentry's base (meters). (4.0.6: the Tesla Tower's ring sits about a foot higher, a tester's call:
  -- on uneven ground the lower ring disappeared into the terrain; 4.5: four feet, 1.22 m, a tester's call)
  local RING_RISE, TESLA_RISE = 0.15, 1.22
  local function add_ring(beams, s, c, r, argb, bands, rise)
    bands, rise = bands or RING_BANDS, rise or RING_RISE
    s.rings = s.rings or {}
    local ring = s.rings[argb]
    if not ring or ring.r ~= r or ring.rise ~= rise or (ring.x - c[1]) ^ 2 + (ring.y - c[2]) ^ 2 + (ring.z - c[3]) ^ 2 > 0.04 then
      ring = { r = r, rise = rise, x = c[1], y = c[2], z = c[3] }
      -- (each segment starts at the point the one before it ends at, the same table: the laser builds each point once)
      for _, up in ipairs(RING_LAYERS) do
        local z = c[3] + rise + up
        for _, off in ipairs(bands) do
          local rr = r + off
          local first = { c[1] + rr, c[2], z }
          local prev = first
          for k = 1, RING_SEGMENTS do
            local a = 2 * math.pi * k / RING_SEGMENTS
            local p = k == RING_SEGMENTS and first or { c[1] + rr * math.cos(a), c[2] + rr * math.sin(a), z }
            ring[#ring + 1] = { from = prev, to = p, argb = argb }
            prev = p
          end
        end
      end
      s.rings[argb] = ring
    end
    -- (the laser keeps the rings in a line object of its own, rebuilt only when they change)
    local list = beams.rings
    if not list then list = {}; beams.rings = list end
    list[#list + 1] = ring
  end
  -- ((5.1.5 Test 30, test builds) the Autocannon and the mortars: frames it had a target but drew no marker, and why
  local function mark_gap_after(s, st, beams, n0, t)
    if not (s.def.salvo or s.def.blast) or not st or st.target == 0 then return end
    for i = n0 + 1, #beams do local b = beams[i]; if b.marker and b.key == 'm' .. s.id then return end end
    local c = st.current
    local P = s.P
    local flash = P.safety_t and t - P.safety_t < EXT.RED_SECONDS and 'its safety flash (a friendly in its line)'
      or P.oos_t and t - P.oos_t < EXT.RED_SECONDS and st.target ~= P.oos_enemy and 'its out-of-sight flash'
    local why = flash or not c and 'target not in its list' or not c.alive and 'target not alive' or not live(c) and 'no place for its target'
      or hurt_no(s, st, c) and 'one it cannot hurt (no marker by design)' or not st.synced and string.format('not synced (AI step %d)', st.node) or string.format('AI step %d', st.node)
    if c and c.d2 then why = why .. (c.d2 > 100 ^ 2 and ', 100 m+' or c.d2 > 70 ^ 2 and ', 70-100 m' or ', under 70 m') end
    session.mark_gaps = session.mark_gaps or {}
    local k = s.def.name .. ': ' .. why
    session.mark_gaps[k] = (session.mark_gaps[k] or 0) + 1
  end
  sentry_beams = function(beams, t)
    if TESTER and #shot_notes.open > 0 then pcall(shot_watch, t) end
    for _, s in pairs(sentries) do
      local st = s.st
      local gap_n0 = TESTER and #beams
      -- ((5.1.5 Test 31) for drawing: its target from the registry when its list doesn't have it (read_sentry), put back after)
      local real_current = st and st.current
      if st and not real_current and st.far then st.current = st.far end
      -- (when and at what it last fired, kept with its policy so a move of its records keeps it: 'laser_when_firing'
      -- guns show their laser only then; while firing, it may point at its target even if its aim isn't synced)
      -- ((5.1.5 review) a salvo gun whose AI has cleared its target mid-salvo keeps the enemy it fired at: before, the 0
      -- went in, so once it took that enemy back it didn't count as the one it was firing at, and its laser went early)
      if st and st.node == (s.def.fire_node or FIRE_NODE) then
        if st.target ~= 0 or not s.def.salvo then s.P.fired_t, s.P.fired_target = t, st.target else s.P.fired_t = t end
      end
      if st and not s.def.no_laser then
        local M = st.centre
        local P = s.P
        if s.def.ring then
          -- lit the whole time it is out, engaging or not, so you always know where its reach ends ((5.0) red, steady)
          add_ring(beams, s, st.base, s.def.ring, RING_TESLA, TESLA_BANDS, TESLA_RISE)
          -- and a laser to the target it is on
          local c = st.current
          if st.target ~= 0 and c and c.pos then
            local p = live(c)
            add_beam(beams, M, { p[1], p[2], p[3] + AIM_UP[2] }, EXT.FIRE, true, s.id, st.target, nil, s.def.beam_inset)
          end
        elseif P.safety_t and t - P.safety_t < EXT.RED_SECONDS then
          local e
          for _, c in ipairs(st.candidates) do if c.id == P.safety_enemy then e = c end end
          -- ((5.0 Test 7, my ask: "the color of the laser will change to green if a safety stops it") the same laser,
          -- along the barrel, turned green. ((5.0 Test 20, my ask: "the safety laser should still flash green, not solid
          -- green") flashing)
          -- ((5.0 release review) the blink keeps its own rhythm: P.safety_t is refreshed each time the hold is renewed)
          if e and e.pos and math.floor(t * EXT.FLASH_HZ * 2) % 2 == 0 then
            local p = live(e)
            local to = { p[1], p[2], p[3] + AIM_UP[2] }
            local be = barrel_end(s, st, M, to, e)
            add_beam(beams, M, be or to, EXT.FRIEND, nil, nil, nil, be ~= nil, s.def.beam_inset)
          end
        elseif P.oos_t and t - P.oos_t < EXT.RED_SECONDS and st.target ~= P.oos_enemy
          and not (st.target ~= 0 and st.node == (s.def.fire_node or FIRE_NODE)) then
          -- ((5.0) flashing gray toward the enemy it dropped out of sight, until it fires at its next one)
          local e
          for _, c in ipairs(st.candidates) do if c.id == P.oos_enemy then e = c end end
          if e and e.pos and can_mark(s, st, e) and math.floor((t - P.oos_t) * EXT.FLASH_HZ * 2) % 2 == 0 then
            local p = live(e)
            local q = { p[1], p[2], p[3] + AIM_UP[2] }
            beams[#beams + 1] = { from = q, to = q, argb = EXT.LOST, marker = true, icon = s.def.name }   -- ((5.0 Test 5) a marker, no beam)
          end
        elseif s.def.min_range and too_close(s, st) then
          -- an enemy inside its minimum range (rocket sentry): it can't fire until that one is dealt with, so its
          -- minimum range flashes red as a ring around it (like the Tesla Tower's)
          if math.floor(t * EXT.FLASH_HZ * 2) % 2 == 0 then add_ring(beams, s, st.base, s.def.min_range, RING_RED) end
        elseif st.current and st.current.pos and (st.synced or (s.def.laser_when_firing and st.target == s.P.fired_target))
          and (not s.def.laser_when_firing or t - (s.P.fired_t or -99) < LASER_FIRING_HOLD) then
          local c = st.current
          local to = (not s.def.blast and st.aim) or { c.pos[1], c.pos[2], c.pos[3] + AIM_UP[1] }
          if s.def.laser_at_enemy and not st.aim then to = { c.pos[1], c.pos[2], c.pos[3] + AIM_UP[2] } end
          -- ((5.0 Test 7, my ask: "lasers should follow where the sentry and dog actually aims like a fixed laser,
          -- rather than pointing to its next target... The marker is there for that now") the beam runs along the barrel,
          -- as far as its target, wherever the barrel points - the Rocket and Autocannon sentries' too now (their muzzle
          -- part's axis 2, from the game models: 'laser_axis'). Only a gun whose barrel can't be read at all still points
          -- at where the game aims it, smoothed
          local e, on = barrel_end(s, st, M, to, c)
          if e then to = e
          else
            on = true
            local E = s.beam_end
            if E and s.beam_target == st.target and t - (s.beam_t or 0) < 0.25 then
              local k = 1 - math.exp(-(t - s.beam_t) / BEAM_SMOOTH)
              to = { E[1] + (to[1] - E[1]) * k, E[2] + (to[2] - E[2]) * k, E[3] + (to[3] - E[3]) * k }
            end
          end
          if not e then to = laser.fit_end(to, c) end   -- ((5.1.5 Test 22) the aim point too: never over its head
          s.beam_end, s.beam_target, s.beam_t = to, st.target, t
          -- ((5.0) red while it fires - its firing step, or its salvo - amber while it is on its target but not firing yet)
          local firing = st.node == (s.def.fire_node or FIRE_NODE) or (s.def.salvo_node and st.node == s.def.salvo_node) or s.def.laser_when_firing
          -- ((5.1.5 Test 32, my Test 31 game: "the laser and marker are still ending too early on the autocannon sentry")
          -- its AI steps out of its firing step between the rounds of a salvo (my Test 29 log: 6,264 polls in step 5 to
          -- 2,118 in step 12): it counts as firing until SALVO_GAP s after it was last in its firing step on this enemy
          if not firing and s.def.salvo and s.P.fired_t and s.P.fired_target == st.target and t - s.P.fired_t < SALVO_GAP then firing = true end
          if firing then add_beam(beams, M, to, EXT.FIRE, on, s.id, st.target, e ~= nil, s.def.beam_inset) end
          -- ((5.0 Test 5) locked on: its icon over the enemy. (Test 8, my ask: "not showing consistently") the whole
          -- time it is on that enemy, firing too, not only before it fires)
          if can_mark(s, st, c) then
            local lp = live(c)
            local q = { lp[1], lp[2], lp[3] + AIM_UP[2] }
            beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, tg = st.target, icon = s.def.name }
          end
          -- ((5.1.5 Test 25) what it is on while it fires, for the salvo hold below)
          if s.def.salvo then
            local K = s.P.salvo_keep or {}
            s.P.salvo_keep = K
            K.id, K.t, K.firing = st.target, t, firing and true or K.firing and K.id == st.target
          end
        elseif s.def.salvo and s.P.salvo_keep and (st.target == 0 or st.target == s.P.salvo_keep.id) and s.P.salvo_keep.firing and t - s.P.salvo_keep.t < SALVO_HOLD then
          -- ((5.1.5 Test 30, my Test 29 game: "the marker still sometimes disappears mid salvo on autocannon") also once
          -- it has taken that enemy back but its aim isn't synced yet (its log: 104 polls in AI step 5, not synced))
          -- ((5.1.5 Test 25, my Test 24 game: "the autocannon sentry marker disappears too early. It does a 3 round salvo,
          -- and its disappearing around halfway into the salvo on its target, same with the laser") the Autocannon's AI
          -- clears its target after the first round of a salvo (see loss_step) while the other rounds still go out:
          -- its beam and marker stay on that enemy for the rest of the salvo (SALVO_HOLD s), while it is alive
          local K, c = s.P.salvo_keep, nil
          for _, x in ipairs(st.candidates) do if x.id == K.id then c = x; break end end
          -- ((5.1.5 review) or from the registry, when its list doesn't have it (far_entry))
          if not c then c = (st.far and st.far.id == K.id and st.far) or (st.far_keep and st.far_keep.id == K.id and st.far_keep) or nil end
          -- (kept up while it is still in its firing step or back on that enemy: the hold runs from the last of those)
          if c and c.alive and (st.target == K.id or st.node == (s.def.fire_node or FIRE_NODE)) then K.t = t end
          if c and c.alive and c.pos then
            local lp = live(c)
            local to = { lp[1], lp[2], lp[3] + AIM_UP[2] }
            local e, on = barrel_end(s, st, M, to, c)
            if e then to = e else on = true; to = laser.fit_end(to, c) end
            add_beam(beams, M, to, EXT.FIRE, on, s.id, K.id, e ~= nil, s.def.beam_inset)
            if can_mark(s, st, c) then
              local q = { lp[1], lp[2], lp[3] + AIM_UP[2] }
              beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, tg = K.id, icon = s.def.name }
            end
          end
        elseif s.def.salvo and st.target ~= 0 and not st.synced and st.current and st.current.alive and st.current.pos and can_mark(s, st, st.current) then
          -- ((5.1.5 review) the Autocannon on a new enemy, still turning to it (its aim not synced yet: about 26 frames a
          -- game, my Test 31 log): its marker goes up at once, no laser until it is on it, so the marker doesn't come late)
          local lp = live(st.current)
          local q = { lp[1], lp[2], lp[3] + AIM_UP[2] }
          beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, tg = st.target, icon = s.def.name }
        end
      elseif st then
        -- ((5.1.5 Test 9: "Mortars should draw markers. Just not lasers") the mortars: their icon over the enemy they are
        -- shelling. ((5.1.5 Test 13: "The mortar sentry markers need to follow a target, but once a mortar is fired, it
        -- should leave the marker where the shell will land, as the marker is pointless after a shell is launched")
        -- ((5.1.5 Test 16) my Test 15 probe, with the mortar's target's health read every frame: a mortar lines up in AI
        -- step 5, fires its salvo in step 13 and stays there until it picks again (step 4, about 8 s later); its shells
        -- come down 5.3-7.1 s after it enters step 13, two of them 0.9 s apart (e.g. 226.17 step 13, hits at 232.47 and
        -- 233.40). Its weapon record has no shot counter and mortars have no ammo meter, so the salvo is taken from that
        -- step: on entering step 13 (or a new target while in it) I leave the marker where its target is right then -
        -- where the shells land - until the next salvo or MORTAR_SHOT s, then it follows its target again)
        local c = st.current
        local salvo = st.target ~= 0 and st.node == MORTAR_STEP and (s.m_node ~= MORTAR_STEP or s.m_tg ~= st.target)
        s.m_node, s.m_tg = st.node, st.target
        -- ((5.1.5 Test 18) my Test 17 log had one Gas Mortar salvo logged twice at the same moment: its step left 13 for a
        -- frame and came back. Back in step 13 on the same target within 1.5 s isn't a new salvo (they come ~6 s apart),
        -- so the marker isn't moved for it)
        if salvo and s.shot and s.shot.tg == st.target and t - s.shot.t < 1.5 then salvo = false end
        if salvo and c and live(c) then
          local lp = live(c)
          s.shot = { at = { lp[1], lp[2], lp[3] + AIM_UP[2] }, t = t, tg = st.target }
          if TESTER then mortar_shot_note(s, st, c, t) end
        end
        local sh = s.shot
        if sh and t - sh.t < MORTAR_SHOT then
          local q = sh.at
          beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, icon = s.def.name }
        elseif st.target ~= 0 and c and c.alive and live(c) and mortar_mark(s, st, c) then
          -- ((5.1.5 Test 30, my Test 29 game: "The mortar marker still sometimes doesnt show at range") whenever it has a
          -- live target it can hurt, from the enemy's own place: no wait for its aim to sync (a mortar lines up from far
          -- off), and the distance from the enemy's live place when its list has none)
          local lp = live(c)
          local q = { lp[1], lp[2], lp[3] + AIM_UP[2] }
          beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, tg = st.target, icon = s.def.name }
          -- ((5.1.5 Test 14) my Test 13 game: the Gas Mortar's marker went away too early - the moment its target died or
          -- it let go of it, with its last shells still in the air. So I keep where its target last was and leave the
          -- marker there for MORTAR_LINGER s)
          -- ((5.1.5 Test 15) not the game's aim point: my Test 14 probe showed a mortar's flips every frame between a spot
          -- by the sentry itself and the spot it shells, which threw the lingering marker all over the place. The enemy's
          -- own spot is where the shells are going)
          s.mlast = { at = q, t = t }
        elseif s.mlast and t - s.mlast.t < MORTAR_LINGER then
          local q = s.mlast.at
          beams[#beams + 1] = { from = q, to = q, argb = EXT.LOCK, marker = true, key = 'm' .. s.id, icon = s.def.name }
        end
      end
      if TESTER then mark_gap_after(s, st, beams, gap_n0, t) end
      if st then st.current = real_current end
    end
  end

  -- test builds: one line per sentry for an F8 marker
  sentry_marker_text = function(me)
    local out = {}
    local function enemies_of(st)
      local rows = {}
      for _, c in ipairs(st.candidates) do
        if c.pos and c.d2 and c.d2 < 80 ^ 2 and (c.alive or c.mask == BLANK) then rows[#rows + 1] = c end
      end
      table.sort(rows, function(a, b) return a.d2 < b.d2 end)
      local lines = {}
      for i = 1, math.min(#rows, 10) do
        local c, why = rows[i], {}
        for k, set in pairs(st.hide_sets or {}) do if set[c.id] then why[#why + 1] = k end end
        local a = c.kind and ARMOR[c.kind]
        lines[#lines + 1] = string.format('%d %s %4.0f m %s%s%s', c.id, c.kind and EXT.hexr(c.kind) or '-', math.sqrt(c.d2),
          #why > 0 and ('hidden: ' .. table.concat(why, ',')) or '-', a and ('  ' .. a.name .. ' AV' .. a.av) or (c.kind and LABELS[c.kind] and ('  ' .. LABELS[c.kind]) or ''),
          c.id == st.target and '  <- target' or '')
      end
      return lines
    end
    for _, s in pairs(sentries) do
      local st = s.st
      if st then
        local c = st.current
        local hid = {}
        for k, set in pairs(st.hide_sets or {}) do local n = 0; for _ in pairs(set) do n = n + 1 end; if n > 0 then hid[#hid + 1] = k .. ' ' .. n end end
        local off = ''
        if st.fwd and st.aim then
          local v = norm({ st.aim[1] - st.muzzle[1], st.aim[2] - st.muzzle[2], st.aim[3] - st.muzzle[3] })
          if v then off = string.format(', barrel %.0f deg off its aim', math.deg(math.acos(math.max(-1, math.min(1, dot3(v, st.fwd)))))) end
        end
        local life = st.target == 0 and '' or (not c and ' (not listed)' or string.format(' (%s, flag %d, %s)', c.alive and 'alive' or 'dead',
          bit.band(c.flags or 0, 1), c.ent and 'in registry' or 'gone from registry'))
        local okn, now = pcall(function() return u64(rd(rptr(A.g.clock, 'clock') + 24, 8, 'clock'), 0) end)
        if okn and now then life = life .. string.format(', timer %.2fs', (st.deadline - now) / 1e6) end
        -- ((5.1.5 Test 5) its target's health as the game holds it, and how long it has fired without hurting it)
        if st.target ~= 0 then
          local hp, mx = HEALTH.of(st.target)
          local e = s.P.dw and s.P.dw.e and s.P.dw.e[st.target]
          life = life .. (hp and string.format(', health %d of %d%s', hp, mx, e and string.format(' (%.1f s of fire without a change%s)', e.acc, HEALTH.proven and '' or ', check not armed yet') or '')
            or (HEALTH.off and ', health: check off' or ', health record not found'))
        end
        out[#out + 1] = string.format('%s: target %d%s%s, AI step %d%s%s, %d enemies listed, hidden: %s%s', s.tag or s.def.name, st.target,
          c and c.kind and (' type ' .. EXT.hexr(c.kind) .. (LABELS[c.kind] and (' ' .. LABELS[c.kind]) or '')) or '', life,
          st.node, st.synced and ', aiming' or '', off, #st.candidates, #hid > 0 and table.concat(hid, ', ') or 'none',
          me and string.format(', %.0f m from you', math.sqrt((st.base[1] - me[1]) ^ 2 + (st.base[2] - me[2]) ^ 2)) or '')
          .. (st.heat and string.format(', heat %.0f%% (%s)%s', 100 * st.heat, st.heat_from, s.P.cooling and ', cooling' or '') or '')
          .. (st.spread_state and (', ' .. st.spread_state) or '')
        -- ((5.0 Test 15 research, my note: a sentry "can still fire into the ground" at an enemy just behind a rise, the
        -- laser reaching it) its target's perception entry as the game holds it - the fields around its line-of-sight byte
        -- (+48) are not known yet: F8 once while it fires into a rise and once while it hits, and compare - with the
        -- heights of the muzzle, the enemy and the game's aim point
        if c and c.entry and c.pos then
          local raw = read(c.entry, 80)
          if raw then
            local fl = {}
            for o = 16, 44, 4 do local v = f32(raw, o); fl[#fl + 1] = (v == v and math.abs(v) < 1e6) and string.format('%.2f', v) or 'x' end
            local hx = {}
            for o = 48, 63 do hx[#hx + 1] = string.format('%02x', raw:byte(o + 1)) end
            local d = math.sqrt((c.pos[1] - st.muzzle[1]) ^ 2 + (c.pos[2] - st.muzzle[2]) ^ 2)
            out[#out] = out[#out] .. string.format('\n        line of fire (test): target %.1f m away, muzzle %.2f m above its feet, the game aims %s; entry +16..+44: %s; +48..+63: %s; memory %.2f',
              d, st.muzzle[3] - c.pos[3], st.aim and string.format('%.2f m above its feet, %.2f m off it level', st.aim[3] - c.pos[3],
              math.sqrt((st.aim[1] - c.pos[1]) ^ 2 + (st.aim[2] - c.pos[2]) ^ 2)) or 'nowhere yet', table.concat(fl, ' '), table.concat(hx, ' '), c.memory or -1)
          end
        end
        for _, l in ipairs(enemies_of(st)) do out[#out] = out[#out] .. '\n        ' .. l end
      end
    end
    return out
  end
  -- (Tesla Tower) run right after the game's own update: the game writes a helldiver's entry in the tower's list afresh
  -- every frame, so the helldivers hidden from it are hidden again straight after the game's update as well as before
  -- it (both chances to be hidden when the tower next picks). 4.5: the tower's whole list is read again here and each
  -- of those helldivers is hidden wherever its entry now is; and its records are checked every frame first (a record
  -- the game moved during its update is found again by the next poll, before the tower's next pick - before 4.5 a
  -- moved record could go up to a quarter of a second with its helldivers shown)
  sentry_after = function()
    if READ_ONLY then return end
    RC.frame = -1   -- (the game's update may have moved its lists)
    for _, s in pairs(sentries) do
      local ids = not s.moved and s.spare_ids
      if ids and next(ids) then
        local okc, cur = pcall(records_current, s)
        if okc and not cur then s.moved, s.moved_after, s.spare_ids, s.st = true, true, nil, nil
        elseif okc then
          s.after_ok = FRAME
          local PB = EXT.PERC
          if PB.read(s.pbase) then
            -- (the groups' entries and the three single entries after them)
            local offs, no = s.offs or {}, 0
            s.offs = offs
            for _, grp in ipairs(EXT.GROUPS) do
              local n = PB.u32(grp[1])
              if n <= 16 then for k = 0, n - 1 do no = no + 1; offs[no] = grp[2] + k * 80 end end
            end
            for _, one in ipairs(EXT.SINGLES) do if PB.u32(one[1] + 72) ~= 0 then no = no + 1; offs[no] = one[1] end end
            for i = 1, no do
              local off = offs[i]
              local id = PB.u32(off)
              if id ~= 0 and ids[id] then
                local m = PB.str(off + 76, 4)
                if m ~= BLANK then
                  -- (a helldiver's mask is never given back with the tower's mark in it - the Tesla Tower only)
                  if s.def.spares_helldivers and bit.band(u32(m, 0), MARK) ~= 0 then m = pack32(bit.band(u32(m, 0), bit.bnot(MARK))) end
                  local addr = s.pbase + off + 76
                  local h = s.H[addr]
                  if h and h.id == id then h.before = m
                  else
                    -- ((4.6.4 review) another enemy's record at this address - the game moved its entry in its update:
                    -- kept aside under a negative key, so hider_apply adopts it where it went instead of losing its mask)
                    if h then local k = -addr; while s.H[k] do k = k - 0.25 end; s.H[k] = h end
                    s.H[addr] = { id = id, entry = s.pbase + off, before = m }
                  end
                  if not write(addr, BLANK) then stats.write_failures = stats.write_failures + 1 end
                end
              end
            end
          end
        end
      end
    end
  end
  return sentry_tick, sentry_restore, sentry_beams, sentry_after
end)()
-- ======================================================================================================
-- Main loop
-- ======================================================================================================
local next_poll, last_log, broken = 0, 0, false
local LOG_EVERY = { idle = 60, changed = 15 }   -- (4.6.7) seconds between log rewrites: in a mission / out of one (5.1.4)
local read_fail_since           -- (4.6.6 review) when the dog's reads started failing (nil: they work)
local last_poll_t
local sentry_broken, sentry_last_error = false, nil
local error_repeats = 0   -- (4.6.4 review: the same read error again, counted instead of logged again)
-- (4.5.3) Bingus' Mod Options Menu (optional, needs Bingus Shared Loader v18+): the same options as in the mod manager
-- (Arsenal), in the same order, with the same names, choices and texts, under ESC > MODS > SMARTER GUARD DOGS &
-- SENTRIES; an option with sub-options gets 'Off' first, then its sub-options (as in Armored Overhaul's rows). Each sets the same flags as the
-- option addons, which the mod reads every frame, so a change takes effect the moment it is applied. The mod manager's
-- picks are the starting values, and each row's id carries the pick it started from (the pattern shared with
-- Armored Overhaul, the project note on the Mod Options Menu), so picking something else in the mod manager starts
-- that row afresh from the new pick instead of an old saved value. The menu may load after this mod: it is looked
-- for once a second until found, and the rows are added once
local menu_step = (function()
  local ID = 'smarter_guard_dogs.'
  local MOD = 'SMARTER GUARD DOGS & SENTRIES'
  local function flag(k) return rawget(_G, 'SmarterGuardDogs' .. k) == true end
  local function set(k, v) rawset(_G, 'SmarterGuardDogs' .. k, v == true) end
  -- (Laser Brightness: the mod manager's sub-options, dimmest to brightest here - a tester's call, 4.5.3 Test 14; the mod
  -- manager lists Normal first because it preselects its first entry. No 'Off' - without the option the laser is at its
  -- normal brightness, the same as 'Normal (100%)')
  local BRIGHT = { 0.5, 0.75, 1.0, 1.5, 2.0 }
  local OPAC = { 0.25, 0.5, 0.75, 1.0 }   -- ((5.0 Test 15) Marker Opacity)
  local SIZE = { 0.5, 0.75, 1.0, 1.5, 2.0 }   -- ((5.1.0 Test 1) Marker Size, smallest first)
  -- each row, in the mod manager's order: its choices, which flags each sets, and the starting choice from the flags
  local OPTS = {
    { key = 'dogs', label = 'Guard Dogs', type = 'toggle',
      description = 'The mod handles your guard dog (Guard Dog, Rover, K-9). Turn off to leave your dog to the game; your sentries and the rest of the mod keep working.',
      apply = function(v) set('Dogs', v) end, start = function() return flag('Dogs') end },
    { key = 'sentries', label = 'Sentries', type = 'choice', choices = { 'Off', 'All sentries', 'All but the Tesla Tower' },
      description = 'The mod handles your sentries (Machine Gun, Gatling, Autocannon, Rocket, Laser, Flame, Mortar, EMS Mortar, Gas Mortar and the Tesla Tower), plus the guns on armed resupply pods and the Supply FRV. Turn off to leave your sentries to the game; your guard dog and the rest of the mod keep working.',
      apply = function(v) set('Sentries', v ~= 1); set('Tesla', v == 2) end,
      start = function() return not flag('Sentries') and 1 or (flag('Tesla') and 2 or 3) end },
    { key = 'intelligence', label = 'Intelligence', type = 'choice',
      choices = { 'Off', 'Armor Intelligence and Target Prioritization', 'Only Armor Intelligence', 'Only Target Prioritization' },
      description = 'How your dogs and sentries choose what to shoot. Armor Intelligence: they shoot armor only at parts they can hurt, burst at a Heavy Devastator\'s shield and leave dropships alone. Target Prioritization: your dog takes the closest threat to you first; your sentries take enemies at their feet, Gunships and the right armor first. Turn off to leave both to the game.',
      apply = function(v) set('Armor', v == 2 or v == 3); set('Priority', v == 2 or v == 4) end,
      start = function() local a, p = flag('Armor'), flag('Priority'); return (a and p) and 2 or (a and 3) or (p and 4) or 1 end },
    -- (5.0) Ping Targeting: its own on/off row, after Intelligence
    { key = 'ping', label = 'Ping Targeting', type = 'toggle',
      description = 'Your sentries go for an enemy you or a teammate ping: each sentry that can hurt it and has it in reach and in view turns to it first, for up to 20 seconds after the ping. The safety rules still come first, and a ping waits while an enemy is at the sentry\'s feet or right next to a helldiver. Turn off to let them pick their own targets.',
      apply = function(v) set('Ping', v) end, start = function() return flag('Ping') end },
    { key = 'safety', label = 'Safety', type = 'choice', choices = { 'Off', 'You and your teammates', 'Only you', 'Only your teammates' },
      description = 'Who your dog and your sentries never fire through: they hold fire while that helldiver is in their line of fire, don\'t swing their fire across them, mortars and the rocket sentry leave enemies next to them alone, and the Tesla Tower doesn\'t zap them or arc into them. Turn off at your own risk: they will fire through anyone. Everything else keeps working.',
      apply = function(v) set('Safety', v == 2 or v == 3); set('Teammates', v == 2 or v == 4) end,
      start = function() local y, m = flag('Safety'), flag('Teammates'); return (y and m) and 2 or (y and 3) or (m and 4) or 1 end },
    -- (4.6.5) Sentry Safety: its own on/off row, after Safety
    { key = 'sentry_safety', label = 'Sentry Safety', type = 'toggle',
      description = 'Your sentries don\'t shoot through other sentries, yours or other players\': they hold fire while one is in their line of fire, don\'t swing their fire across one, and the mortars and the rocket, autocannon and flame sentries leave alone enemies right next to one. Turn off to let them fire through sentries. Everything else keeps working.',
      apply = function(v) set('SentrySafety', v) end, start = function() return flag('SentrySafety') end },
    -- (4.7.0) SEAF Safety: its own on/off row, after Sentry Safety
    { key = 'seaf_safety', label = 'SEAF Safety', type = 'toggle',
      description = 'Your guard dog and your sentries don\'t shoot through SEAF soldiers or civilians: they hold fire while one is in their line of fire, don\'t swing their fire across one, and the mortars, the Tesla Tower and the rocket, autocannon and flame sentries leave alone enemies right next to one. Turn off to let them fire through SEAF soldiers and civilians. Everything else keeps working.',
      apply = function(v) set('SEAFSafety', v) end, start = function() return flag('SEAFSafety') end },
    -- ((5.1.3, my ask: "organize the options better for the targeting laser ... add targeting laser color as an
    -- option and then add Targeting laser Glow and Line as options again") as in the mod manager: the style here, the colors
    -- in Laser Color. New keys: the old 'laser' (Line / Glow) and 'laser_color' (Off / Red / Green / Line) rows saved other
    -- choice numbers
    -- ((release review, my ask: "Glow laser should be first, and line should be an option they can switch to") Glow
    -- first, as in the mod manager)
    { key = 'laser_style', label = 'Targeting Laser', type = 'choice', choices = { 'Glow', 'Line', 'Off' },
      description = 'A laser from the barrel of your guard dog and your sentries (not the mortars), only on your screen: one color while they fire, the other flashing when a friendly is in the way (see Laser Color). Glow: a soft glowing beam that shows through walls, like the markers. Line: a thin line that walls hide. The Tesla Tower shows its reach as a red ring.',
      apply = function(v) set('Laser', v ~= 3); set('Glow', v == 1) end,
      start = function() return not flag('Laser') and 3 or (flag('Glow') and 1 or 2) end },
    { key = 'laser_colors', label = 'Laser Color', type = 'choice', choices = { 'Red while firing', 'Green while firing' },
      description = 'The targeting laser\'s colors, for the Glow and the Line. Red while firing: red while they fire, flashing green when a friendly is in the way. Green while firing: the other way round (the colors before 5.0).',
      apply = function(v) set('LaserInvert', v == 2) end,
      start = function() return flag('LaserInvert') and 2 or 1 end },
    { key = 'laser_brightness', label = 'Laser Brightness', type = 'choice',
      choices = { 'Dim (50%)', 'Softer (75%)', 'Normal (100%)', 'Bright (150%)', 'Brightest (200%)' },
      description = 'How bright the targeting laser is: its beams and rings.',
      apply = function(v) if BRIGHT[v] then rawset(_G, 'SmarterGuardDogsLaserBrightness', BRIGHT[v]) end end,
      start = function()
        local b = rawget(_G, 'SmarterGuardDogsLaserBrightness')
        if type(b) ~= 'number' then return 3 end
        local best, bd = 3, nil
        for i, x in ipairs(BRIGHT) do if not bd or math.abs(x - b) < bd then best, bd = i, math.abs(x - b) end end
        return best
      end },
    -- (5.0 Test 13) Targeting Marker: its own row, after Laser Brightness. ((5.1.3) a choice now, as in the mod
    -- manager: through walls or hidden by them - a new key, the old 'marker' row saved on/off)
    { key = 'marker_walls', label = 'Targeting Marker', type = 'choice', choices = { 'Off', 'Through walls', 'Behind walls' },
      description = 'The gun\'s stratagem icon over the enemy your guard dog or sentry is on, only on your screen: yellow while it is on it, gray when it goes out of sight. Only on enemies it can hurt and has in reach. Through walls: shown over everything, like a ping. Behind walls: walls hide it (drawn solid, so Marker Opacity doesn\'t change it).',
      apply = function(v) set('Marker', v ~= 1); set('MarkerWalls', v == 3) end,
      start = function() return not flag('Marker') and 1 or (flag('MarkerWalls') and 3 or 2) end },
    -- (5.0 Test 15) Marker Opacity: how see-through the markers are (dimmest first, like Laser Brightness)
    { key = 'marker_opacity', label = 'Marker Opacity', type = 'choice',
      choices = { 'Faint (25%)', 'Light (50%)', 'Medium (75%)', 'Full (100%)' },
      description = 'How solid the targeting markers are drawn. Full is how they are designed; lower lets more of the game show through them.',
      apply = function(v) if OPAC[v] then rawset(_G, 'SmarterGuardDogsMarkerOpacity', OPAC[v]) end end,
      start = function()
        local o = rawget(_G, 'SmarterGuardDogsMarkerOpacity')
        if type(o) ~= 'number' then return 4 end
        local best, bd = 4, nil
        for i, x in ipairs(OPAC) do if not bd or math.abs(x - o) < bd then best, bd = i, math.abs(x - o) end end
        return best
      end },
    -- (5.1.0 Test 1) Marker Size: how big the markers are (smallest first)
    { key = 'marker_size', label = 'Marker Size', type = 'choice',
      choices = { 'Smallest (50%)', 'Small (75%)', 'Normal (100%)', 'Large (150%)', 'Largest (200%)' },
      description = 'How big the targeting markers are drawn. Normal is how they are designed.',
      apply = function(v) if SIZE[v] then rawset(_G, 'SmarterGuardDogsMarkerSize', SIZE[v]) end end,
      start = function()
        local o = rawget(_G, 'SmarterGuardDogsMarkerSize')
        if type(o) ~= 'number' then return 3 end
        local best, bd = 3, nil
        for i, x in ipairs(SIZE) do if not bd or math.abs(x - o) < bd then best, bd = i, math.abs(x - o) end end
        return best
      end },
  }
  local done, at = false, 0
  return function()
    if done or FRAME < at then return end
    at = FRAME + 60
    local menu = rawget(_G, 'ModOptionsMenu')
    if type(menu) ~= 'table' or menu.api ~= 1 or type(menu.register_option) ~= 'function' then return end
    done = true
    local added, failed = 0, nil
    for _, o in ipairs(OPTS) do
      local start = o.start()
      -- (the id carries the mod manager's pick: 'on'/'off' for a checkbox, else the choice's number)
      local id = ID .. o.key .. '.' .. (type(start) == 'boolean' and (start and 'on' or 'off') or tostring(start))
      local spec = { type = o.type, label = o.label, mod = MOD, description = o.description, choices = o.choices, default = start }
      local ok, did, why = pcall(menu.register_option, id, spec)
      if ok and did then
        added = added + 1
        local okg, v = pcall(menu.get, id)
        if okg and v ~= nil then pcall(o.apply, v) end
        pcall(menu.on_change, id, function(value) pcall(o.apply, value); session.dirty = true end)
      else
        failed = id .. ': ' .. tostring(ok and why or did)
      end
    end
    rawset(_G, 'SmarterGuardDogsMenu', added > 0)
    note('options menu: ' .. added .. ' setting(s) in the MODS tab' .. (failed and ('; not added: ' .. failed) or ''))
  end
end)()

-- (4.6.3) this frame's laser: the dog's beam and the sentries' beams, drawn together (called in a pcall from tick)
laser.step = function(st, sentries_out, t)
  laser.inv = laser.inverted()   -- ((5.1.0 release review) the Targeting Laser color choice, once a frame)
  laser.walls = rawget(_G, 'SmarterGuardDogsMarkerWalls') == true   -- ((5.1.3) Targeting Marker: Behind walls
  laser.mark_lines = 0   -- ((5.1.4) the Behind walls markers' line budget, this frame's
  -- (the markers drawn as lines - Behind walls, or a game build with no world GUI: their icons cut ahead, one a frame)
  -- ((release review) only while the markers are on, and no more once every icon is cut)
  if not laser.markers_warm and rawget(_G, 'SmarterGuardDogsMarker') == true
     and (laser.walls or not (laser.glow and laser.glow.markers_ok())) then laser.warm_markers() end
  laser.me = (st and st.player_pos) or EXT.me   -- ((5.0) beams fade with their distance from you)
  local beams = {}
  laser.dog_target = false
  if st then laser_frame(st, beams, P.safety_now and P.safety_t or nil, P.safety_enemy, P.safety_step, P.cover_t, P.cover_enemy, P.cover_step) end
  if sentries_out then sentry_beams(beams, t) end
  -- ((5.0 Test 13, my ask: "Targeting Marker should be an option that can be toggled") the markers belong to the
  -- Targeting Marker option, the beams and rings to the Targeting Laser: whatever is off is dropped here
  local lines_on, marks_on = rawget(_G, 'SmarterGuardDogsLaser') == true, OPT.marker()
  if not (lines_on and marks_on) then
    local kept = {}
    for _, b in ipairs(beams) do
      if (b.marker and marks_on) or (not b.marker and lines_on) then kept[#kept + 1] = b end
    end
    kept.rings = lines_on and beams.rings or nil
    beams = kept
  end
  if #beams > 0 or beams.rings then laser_draw(beams) else laser_clear() end
end

-- ((5.1.5 Test 11) the idle state's changes, logged once each (up to 40 a mission), and its frame counts for the log)
local function idle_note(t, working, why)
  IDLE.frames = IDLE.frames + 1
  if working then IDLE.work_frames = IDLE.work_frames + 1 end
  -- (each change between idle and working, and between idle reasons; not between the working ones, which come and go
  -- as the dog and the sentries take turns)
  if working ~= IDLE.working or (not working and why ~= IDLE.state) then
    IDLE.working, IDLE.state = working, why
    IDLE.notes = IDLE.notes + 1
    if IDLE.notes <= 40 then event(why) elseif IDLE.notes == 41 then event('(idle and working changes: no more are logged this mission)') end
  end
end

local function tick()
  local t = os.clock()
  FRAME = FRAME + 1
  -- (4.6.4) CowboyBingus's Laser Sentry Cooldown (it keeps an overheated Laser Sentry from exploding: it cools down and
  -- comes back): noted once - both work together, this mod still stands the sentry down before it overheats
  if not SGD.lsc_seen and FRAME % 120 == 1 and rawget(_G, 'LaserSentryCooldownInstalled') then
    SGD.lsc_seen = true
    note('Laser Sentry Cooldown (CowboyBingus) is installed: works alongside it (an overheated Laser Sentry cools down and comes back; this mod still cools it before it overheats)')
  end
  menu_step()
  -- (numbered Tester builds only: the research probe, engine_probe.lua - not in releases)
  if SGD.probe_step then SGD.probe_step(t) end
  -- the log is rewritten every 10 s, and within a second of anything new being noted
  -- ((4.6.4 review) a change is written within 3 s, not every second: each rewrite is a whole file on the game thread;
  -- errors and shutdown still write at once)
  -- ((4.6.7, a player reported a performance cost) each rewrite took ~3.3 ms on the game thread in a Test 3 log (every
  -- one over 1 ms - the mod's only frame spikes; everything else ~0.15 ms a frame): now every 60 s, and a change within
  -- 15 s (was every 10 s and within 3 s). Errors and shutdown still write at once)
  -- ((5.1.4, players: "the performance is much worse"; a 5.1.3 Tester log: 19 rewrites at ~3.2 ms each, the mod's only
  -- frame spikes) in a mission only once a minute and only with something new; when the mission ends, at once; out of
  -- a mission within 15 s of a change. Nothing new, no rewrite. Errors and shutdown still write at once
  local in_mission = SGD.status ~= 'not in a mission'
  if in_mission then SGD.log_mission = true end
  if not in_mission and SGD.log_mission then
    SGD.log_mission = false; last_log = t; pcall(write_log)   -- (the mission's totals, as it ends)
  elseif session.dirty and t - last_log >= (in_mission and LOG_EVERY.idle or LOG_EVERY.changed) then
    last_log = t; pcall(write_log)   -- ((4.6.6 review) in a pcall: a log error stopped the whole mod)
  end
  -- (test builds: F8 also works while no dog is out, e.g. right after you died; checked every frame so a quick
  -- press isn't missed between the slower polls)
  if TESTER and (SGD.status ~= 'active' or IDLE.dog_asleep) then pcall(check_marker, nil) end
  if broken or t < next_poll then
    -- (a frame the mod skips: the laser as it was - sent again as they are)
    if not broken and laser_wanted() then laser.redraw() end
    if IDLE.working ~= nil then idle_note(t, IDLE.working, IDLE.state) end
    return
  end
  next_poll = t + 0.1          -- relaxed while nothing is going on; every frame while a dog is out (below)
  stats.polls = stats.polls + 1
  local ok, st, why
  -- ((5.1.5 Test 11) a dog with nothing to do idles: only its look every IDLE.look s (IDLE.dog_peek); anything else
  -- wakes it, and it is then looked up afresh before anything is done)
  local asleep = false
  if IDLE.dog_asleep then
    if t < IDLE.dog_next then asleep = true
    else
      IDLE.dog_next = t + IDLE.look
      local okp, still = pcall(IDLE.dog_peek, t)
      if okp and still then asleep = true
      else IDLE.dog_asleep, IDLE.dog_since = false, nil; IDLE.dog_wake(); IDLE.wake_scan = true end
    end
  end
  if asleep then ok, st, why = true, nil, nil else ok, st, why = pcall(read_state) end
  if not ok then
    local e = st
    st = nil
    if type(e) == 'table' and e[1] == Abort then why = 'read_failed: ' .. tostring(e[2])
    else
      -- a bug in this mod rather than an unexpected game state: stop steering for the rest of the session
      -- (4.6.3: the sentries too - they are no longer ticked once 'broken' is set, so their hidden enemies and a Tesla
      -- Tower's target list are put back now, as the update wrapper below does)
      broken = true; why = 'stopped after error: ' .. tostring(e); restore()
      sentry_broken = true; pcall(sentry_restore)
    end
    stats.read_errors = stats.read_errors + 1
    -- ((4.6.4 review) the same error again: counted, not logged again - a check that kept failing filled the recent
    -- events and the first-10 error list with copies and rewrote the log every second)
    if why == last_error then
      error_repeats = error_repeats + 1
    else
      if error_repeats > 0 then event(string.format('(the last error repeated %d more time(s))', error_repeats)) end
      error_repeats = 0
      event('error: ' .. tostring(why))
      pcall(write_log); last_log = t   -- (a new error is in the log at once)
    end
    last_error = why
  end
  local status = (st or asleep) and 'active' or why
  -- ((5.1.5 review) the end of a mission, whatever is out or switched on: the damage check is armed afresh in the next
  -- one (it was reset in the sentries' step only, which returns early with the Sentries option off), and the dog's count
  -- of enemies it left alone for doing no damage goes (it decides how long the next one is left alone)
  if why == 'not in a mission' and SGD.status ~= 'not in a mission' then
    HEALTH.proven = false
    P.nd_n, P.nd, P.dw = nil, nil, nil
    read_candidates('forget')   -- ((5.1.5 Test 18) the kept registry places
    IDLE.dog_asleep, IDLE.dog_since, IDLE.notes = false, nil, 0
  end
  -- ((4.6.4 review) out of a mission: forget the laser's per-world objects - see laser.forget)
  -- ((5.1.2, my note: make sure a ring isn't left on screen) but the game keeps its world through the extraction
  -- (ship and later missions), and a line object goes on showing its last dispatch: a Tesla Tower still out, the
  -- Rocket Sentry's ring on its lit half, or a dog's beam at that moment stayed on screen until the game restarted
  -- (sims sentry_tesla_mission_end / sentry_rocket_mission_end). So on the poll the mission ends - the poll before was
  -- in it, a fraction of a second ago, too soon for the world to be rebuilt - everything is cleared once first, and
  -- only in the world it was drawn in (laser_draw only touches the objects kept for the world main_world() gives now)
  if why == 'not in a mission' and (next(laser.worlds) or (laser.glow and next(laser.glow.guis))) then
    if SGD.status ~= 'not in a mission' then laser.clear_now() end
    laser.forget()
  end
  local dogname = st and st.dog.name or (asleep and SGD.dog) or nil
  if status ~= SGD.status then event('status: ' .. tostring(status)) end
  if dogname and dogname ~= SGD.dog then event('dog: ' .. dogname) end
  local dt = last_poll_t and math.min(t - last_poll_t, 0.5) or 0
  last_poll_t = t
  session.state_time[tostring(status)] = (session.state_time[tostring(status)] or 0) + dt
  if dogname then
    local d = session.dog_time[dogname] or { out = 0, targeted = 0, firing = 0 }
    session.dog_time[dogname] = d
    d.out = d.out + dt
    if st and st.target ~= 0 then d.targeted = d.targeted + dt; if st.node == 7 then d.firing = d.firing + dt end end
  end
  if asleep then
    -- (the dog idles: nothing to read or steer)
  elseif not st then
    SGD.status, SGD.dog = why, nil
    -- ((4.6.6 review) a failed read keeps the dog's hidden enemies hidden for up to half a second: putting them all
    -- back at once let the game pick the enemy behind you while the dog was still out. Each one is put back only if its
    -- entry still holds that enemy, so keeping them is safe; out of a mission, an error or the dog gone puts them back)
    local transient = type(why) == 'string' and why:find('^read_failed') ~= nil
    if transient then read_fail_since = read_fail_since or t else read_fail_since = nil end
    if next(hidden) and not (transient and t - read_fail_since < 0.5) then restore() end
  else
    read_fail_since = nil
    SGD.status, SGD.dog = 'active', st.dog.name
    if #st.mates > session.team.max then session.team.max = #st.mates end
    if st.mates_found ~= session.team.last then
      session.team.last = st.mates_found
      session.team.notes = session.team.notes + 1
      if session.team.notes <= 20 then
        event(string.format('teammates: %d found', st.mates_found) .. (TESTER and (' (' .. team_detail(st.player_pos) .. ')') or ''))
      end
    end
    next_poll = 0
    local dreq = plan(st)
    steer(st, dreq)
    if SGD.probe_dog then SGD.probe_dog(st, t) end   -- (numbered Tester builds: the research probe)
    if TESTER then
      pcall(SGD.dog_seaf_check, st, dreq, t)
      pcall(check_marker, st)
      -- how the dog spends its time while out: docked on your back (reloading), no target, or its AI step
      local P2, D = st.player_pos, st.drone_pos
      local docked = P2 and D and ((D[1] - P2[1]) ^ 2 + (D[2] - P2[2]) ^ 2) < 1.2 ^ 2
      bump(session.steps, st.dog.name .. ': ' .. (docked and 'docked on your back' or (st.target == 0 and 'no target' or ('AI step ' .. st.node))))
    end
    -- nothing around and nothing hidden: look three times a second less often (enemies take a moment to arrive)
    if #st.candidates == 0 and st.target == 0 and not next(hidden) then next_poll = t + 0.05 end
    -- ((5.1.5 Test 11) nothing to do - no target, nothing hidden from it, no enemy alive in its list within IDLE.range -
    -- for IDLE.settle s: it idles. The bodies in its list then are left out of its look (they never come back to life))
    local quiet = st.target == 0 and not next(hidden)
    if quiet then
      local R2 = IDLE.range * IDLE.range
      for _, c in ipairs(st.candidates) do if (c.alive and (not c.d2 or c.d2 < R2)) or c.mask == BLANK then quiet = false; break end end
    end
    if not quiet then IDLE.dog_since = nil
    elseif not IDLE.dog_since then IDLE.dog_since = t
    elseif t - IDLE.dog_since >= IDLE.settle then
      IDLE.dog_asleep, IDLE.dog_next, IDLE.dog_since = true, t + IDLE.look, nil
      local skip = {}
      for _, c in ipairs(st.candidates) do if not c.alive then skip[c.id] = true end end
      IDLE.dog_skip = skip
    end
    if RESEARCH then local okr, er = pcall(research_frame, st); if not okr then RESEARCH = false; note('research stopped: ' .. tostring(er)) end end
  end
  -- sentries (4.0): handled whether or not a dog is out; polled every frame while one of yours is out
  local sentries_out, sentries_busy = false, false
  if not sentry_broken then
    local ok3, r, busy = pcall(sentry_tick, st, t, dt)
    if ok3 then sentries_out, sentries_busy = r, busy
    elseif type(r) == 'table' and r[1] == Abort then
      -- (a structure that couldn't be read this time, e.g. during loading: try again next poll)
      local msg = 'sentries: read_failed: ' .. tostring(r[2])
      if msg ~= sentry_last_error then sentry_last_error = msg; event(msg) end
    else
      sentry_broken = true; last_error = 'sentries stopped after error: ' .. tostring(r)
      event('error: ' .. last_error); pcall(sentry_restore)
    end
  end
  -- (every frame while a sentry is busy; idle ones - no target, no enemy in their lists - ten times a second)
  if sentries_busy then next_poll = 0 end
  -- ((5.1.5 Test 11) the whole mod idles while no dog is awake and no sentry is busy: a poll every IDLE.look s)
  local working = st ~= nil or sentries_busy == true
  if not working then next_poll = math.max(next_poll, t + IDLE.look); IDLE.idle_s = IDLE.idle_s + dt end
  IDLE.on = not working
  idle_note(t, working, working and (st and ('working: your ' .. st.dog.name .. ' (an enemy within ' .. IDLE.range .. ' m, or a target)')
      or ('working: your sentries (an enemy within ' .. IDLE.range .. ' m, a target, or a Tesla Tower out)'))
    or (why == 'not in a mission' and 'idle: not in a mission (menus, the ship or loading)')
    or ((asleep or sentries_out) and ('idle: no enemy within ' .. IDLE.range .. ' m of your guard dog or sentries'))
    or 'idle: no guard dog out and no sentries of yours')
  -- the laser: the dog's beam and the sentries' beams, drawn together
  -- (4.6.3) in a pcall of its own: an error in the laser (it is only for show) stops the laser, not the steering
  -- ((5.1.2) nothing is drawn out of a mission: sentries still read as out there (the end of a mission, before their
  -- units go) were drawn again into fresh objects, which the next poll forgot - on screen until the game restarted)
  if laser_wanted() and laser_ready() and why ~= 'not in a mission' then
    local okl, errl = pcall(laser.step, st, sentries_out, t)
    if not okl then laser_fail(errl) end
  else laser_clear() end
end

local ok, err = pcall(function() A = resolve_layout() end)
if not ok then
  SGD.status = 'off: ' .. tostring(err)
  note('could not find the game addresses, the mod stays off: ' .. tostring(err))
  pcall(write_log)
  return
end

local game_update, game_shutdown = rawget(_G, 'update'), rawget(_G, 'shutdown')
if type(game_update) ~= 'function' then
  SGD.status = 'off: game update function not found'; pcall(write_log); return
end
do
  -- (after the game's update: the Tesla Tower's hidden helldivers are hidden again, see sentry_after. 4.6.4 Test 9
  -- tried the same for every sentry and the dog: in game it never found one shown again - the game shows hidden
  -- entries again later in the frame, after this hook - so it was taken out)
  local function after(...)
    if not broken and not sentry_broken then pcall(sentry_after) end
    return ...
  end
  -- (4.0.6 test builds) what the mod itself costs each frame, measured with the high-precision system timer: the log
  -- shows the average and highest, and how many frames went over 1 ms
  local timed = TESTER and pcall(function()
    pcall(ffi.cdef, 'int SgdQueryPerformanceCounter(int64_t *count) __asm__("QueryPerformanceCounter");')
    pcall(ffi.cdef, 'int SgdQueryPerformanceFrequency(int64_t *freq) __asm__("QueryPerformanceFrequency");')
    local q, f = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
    assert(K32.SgdQueryPerformanceFrequency(f) ~= 0 and f[0] > 0)
    local per_ms = tonumber(f[0]) / 1000
    local T = { n = 0, sum = 0, max = 0, over = 0, parts = {} }
    session.timing = T
    -- (4.6.7 Test 1, a player reported a high performance cost) the main parts timed too - the log rewrite, reading
    -- the dog's state, the sentries and the laser - so a test log shows which one makes the slow frames
    local q2 = ffi.new('int64_t[1]')
    local function finish(Pt, a, ...)
      K32.SgdQueryPerformanceCounter(q2)
      local ms = tonumber(q2[0] - a) / per_ms
      Pt.n, Pt.sum = Pt.n + 1, Pt.sum + ms
      if ms > Pt.max then Pt.max = ms end
      if ms > 1 then Pt.over = Pt.over + 1 end
      return ...
    end
    local function part(name, fn)
      local Pt = { name = name, n = 0, sum = 0, max = 0, over = 0 }
      T.parts[#T.parts + 1] = Pt
      return function(...) K32.SgdQueryPerformanceCounter(q2); return finish(Pt, q2[0], fn(...)) end
    end
    write_log = part('writing the log', write_log)
    read_state = part('reading the dog and enemies', read_state)
    sentry_tick = part('sentries', sentry_tick)
    laser.step = part('laser', laser.step)
    SGD.time_tick = function()
      K32.SgdQueryPerformanceCounter(q); local a = q[0]
      local ok2, e = pcall(tick)
      K32.SgdQueryPerformanceCounter(q)
      local ms = tonumber(q[0] - a) / per_ms
      T.n, T.sum = T.n + 1, T.sum + ms
      if ms > T.max then T.max = ms end
      if ms > 1 then T.over = T.over + 1 end
      return ok2, e
    end
  end)
  if TESTER and not timed then note('frame timing (test): not available') end
  -- ((5.1.5 Test 20) code the game's LuaJIT (2.1.0-alpha) can never compile, so it isn't asked to: the frame's entry
  -- points (they call back into the game), the laser and marker drawing (every line and triangle is a call into the
  -- game) and the F8 key check. My Test 19 log had the compiler start and give up on these about 20,000 times in a
  -- 16-minute session - wasted work every time. Turning them off changes nothing else: they ran uncompiled anyway
  do
    local j = rawget(_G, 'jit')
    if type(j) == 'table' and type(j.off) == 'function' then
      -- ((5.1.5 Test 22) and union (select and pairs: 1,812 give-ups in my Test 19 log) and the Mod Options Menu's
      -- registration check (551)
      for _, f in ipairs({ tick, laser_draw_body, laser_ready, check_marker, sentry_after, SGD.time_tick or tick, union, menu_step }) do
        if type(f) == 'function' then pcall(j.off, f, true) end
      end
    end
  end
  rawset(_G, 'update', function(...)
    local ok2, e
    if SGD.time_tick then ok2, e = SGD.time_tick() else ok2, e = pcall(tick) end
    if not ok2 then
      -- ((4.6.4 review) said so in the log too: before, it kept saying 'status: active' while nothing ran any more)
      if not broken then
        local why = 'stopped after error: tick: ' .. tostring(e)
        SGD.status = why; pcall(event, 'error: ' .. why)
      end
      broken = true; sentry_broken = true; last_error = 'tick: ' .. tostring(e); pcall(restore); pcall(sentry_restore)
    end
    return after(game_update(...))
  end)
end
rawset(_G, 'shutdown', function(...)
  pcall(restore)
  pcall(sentry_restore)
  pcall(research_close)
  SGD.status = 'closed'
  pcall(write_log)
  if type(game_shutdown) == 'function' then return game_shutdown(...) end
end)
SGD.status = 'waiting'
pcall(write_log)
