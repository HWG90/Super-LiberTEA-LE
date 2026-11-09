# HUD+ selection handoff

The adapter recognizes the selection cleanup interface, not a version number. Local, unmodified HUD+ 0.2.8 and 0.2.9 Lua were exercised in isolated LuaJIT fixtures. This does not establish live gameplay or runtime frame cost.

When ASS owns selection, it restores the original list through HUD+ vanilla(false), closes the HUD+ duplicate once, and suppresses HUD+ list/picker rendering. Shared extension arrow observation remains available. Weapon, cooldown, health and other HUD+ features are outside this handoff. When ASS releases ownership, original prepare/observe/put methods and return values resume.

## Weapon row

HUD+'s weapon line draws the game's option cells for the held weapon right of the weapon row, where the weapon status strip sits. The strip leaves out each option HUD+ already shows and puts any others after HUD+'s cells. If HUD+ shows them all, the strip hides itself. Turning an option off in HUD+'s menu brings its strip icon back. The strip only reads HUD+'s weapon line, recognized by its shape, and changes nothing of HUD+'s. It uses a HUD+ cell only while that cell is a live widget of the same weapon HUD.

The immediate-picker contract cancels the pending selection. The paced-picker contract also restores the held menu trigger, releases consumed aim, and clears selection timing and remembered selection using HUD+ reset/frame methods. Only instance methods are wrapped. Settings and shared classes are not modified.

## Forward compatibility

A future HUD+ release can change observe/put presentation code without a new adapter entry if its verified lifecycle and picker cleanup contract remain compatible. prepare, vanilla, drop and close are fingerprinted; picker contracts verify reset and, when present, frame and leave, together with their Lua cleanup helpers. Missing interfaces or unfamiliar cleanup implementations are rejected without partial mutation. This is compatibility by interface, not a guarantee for every future release.

If a future release changes cleanup, inspect that source and add a behavior-named picker contract to picker_contracts in src/hud_plus.lua. If the lifecycle changes, introduce a separate reviewed lifecycle contract rather than weakening validation or adding a version-only exception. Exercise that owner's real feature, picker and runtime modules with the fixture below. Do not copy third-party source into a release package.

## Bytecode layout

A fingerprint is a checksum of `string.dump(fn,true)`, and LuaJIT's dump follows the VM's bytecode frame layout. The original game ran a non-GC64 LuaJIT 2.1.0-alpha (FR1). LLL's runtime under the LuaJIT boot is GC64 (FR2), and the same function dumps to other bytes there. With FR1 pins only, the adapter refused HUD+ in game ("lifecycle prepare"). That happened for the HUD+ 0.2.9 LuaJIT 26251122 port and for unmodified 0.2.9 alike.

Each pin now holds the same reviewed code in both layouts, `fr1` and `fr2`. The adapter reads the running layout from the dump header (flag 0x08) and compares only that layout's value. A layout with no value, or a VM without LuaJIT dumps, never matches. The `fr2` values come from the same unmodified 0.2.9 source. LLL runtime's LuaJIT (commit a4c0645, GC64) and stock GC64 LuaJIT 2.1 give equal values, and the FR1 build reproduces every earlier pin. A refusal names the layout, for example "lifecycle prepare (fr2 bytecode)".

The port's `features.world_hud`, `features.stratagem` and `game.stratagem_*` modules compile to the same bytecode as 0.2.9's: the port only reformatted them. Its build changes are in core, native, data and product modules, outside this handoff. So the port binds the paced-picker contract with 0.2.9's lifecycle. The immediate-picker contract (0.2.8) has no `fr2` value because that source wasn't at hand, so it is refused under GC64.

Discovery scans only changed update wrappers and is bounded to eight scans, 128 closures per scan, 64 upvalues per closure and 16 runtimes. Program and feature identity checks detect recreation without rescanning unchanged closures. An active handoff performs cleanup once per ownership transition. Unknown owners remain untouched.

## Verification

Set HD2_HUD_PLUS_SOURCE to the HUD+ product Lua, then run from native-work/dbf-ass-luajit:

    luajit tests/offline_hud_plus_stratagem.lua divers_best_friend

Repeat for each target, with a GC64 LuaJIT (fr2) and a non-GC64 one (fr1). Fixtures cover disabled/resumed ownership, both update-wrapper orders, callback returns, held-trigger/aim cleanup, changed presentation with stable cleanup, unsupported contracts, program and feature recreation, no duplicate wrapping, 10000 unchanged discovery frames and 10000 active frames without repeated drop.

Before accepting deployment, verify visible list ownership, Confirm, release selection, aiming, close/reopen, disable/re-enable and mission transitions in game. Builds remain review candidates until that evidence exists.

## Inspected artifact identities

HUD+ 0.2.8 original ZIP SHA-256: bcb2c911eadb3a016e12b915709ffba96ffa111723512105c0f9ded899d92a71 (Nexus mod 15298, file 69169).

HUD+ 0.2.9 source came from the local Arsenal library. Its main Lua SHA-256 is 31af81f2942cb6c0a1aae6d4ce83b6d9e86644392082d25037c829fa63c3b34e. Those exact source bytes occur at offset 5171 in patch_0, SHA-256 f6f43e580d3d5ea64c601d921e5e12352accedd332a3a6dd07f5ec0312f56212. Library naming and metadata identify 0.2.9; source/patch agreement was independently checked. No claim about installed game bytes is made.

The HUD+ 0.2.9 LuaJIT 26251122 port (Arsenal "HudPlusPlus", r9) was compared through its bundle Lua, SHA-256 537e430a2974f6315d93950b34857f84f9ee7b22514972704fee6e37e56cb770.

The earlier compatibility baseline was published R42 tag r42-ui-recovery-test, commit dfc7b209c6e8e496b72d89971b538185235a9c7b. This R45 review work retains recovery, blacklist and selection safeguards and includes the existing worktree changes. New compatibility behavior remains undeployed.

LLL cleanup now restores the exact HUD+ instance methods before a reload, leaving shared classes untouched. If another owner has replaced one of those wrappers, cleanup refuses rather than overwriting it.
