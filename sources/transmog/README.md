# HD2 Transmog

**English** · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/README.ru.md)

Combine an owned armor's appearance, base stats, and passive in **Helldivers 2**. Save the combination as a Custom Variant and equip it through the game's Armory.

> [!IMPORTANT]
> Requires **Bingus Shared Loader v15+ / API 1**, installed separately, and **Arsenal** for the installation described here. Keep one loader enabled alongside Transmog. With Arsenal's default priority, put the loader **last, at the bottom**, then **Purge / Deploy**. With first-mod priority enabled, put it first. See the [loader's installation instructions](https://github.com/CowboyBingus/BingusSharedLoader/blob/main/INSTALL.txt).

**Version: 0.2.4 Experimental.** This is an experimental prerelease. Clothing packs and multiplayer support are still under validation; read the [known limits](#compatibility-and-known-limits) before installing.

[Download on Nexus Mods](https://www.nexusmods.com/helldivers2/mods/16633?tab=files) · [GitHub releases](https://github.com/tyrypyrking/HD2-Transmog/releases) · [Changelog](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/CHANGELOG.md) · [Report a problem](https://github.com/tyrypyrking/HD2-Transmog/issues/new/choose)

## Contents

- [Features](#features)
- [Install](#install)
- [Create and equip a variant](#create-and-equip-a-variant)
- [Settings](#settings)
- [Update or uninstall](#update-or-uninstall)
- [Compatibility and known limits](#compatibility-and-known-limits)
- [Troubleshooting](#troubleshooting)
- [API documentation](#api-documentation)
- [Build from source](#build-from-source)

## Features

- **Independent armor choices:** choose a look, base-stat profile, and passive from equipment you own. Base stats exclude the donor's passive bonus; your selected passive is applied separately.
- **Native Armory cards:** preview saved variants, inspect their stats and passive, and equip them with Apply. Creating a card does not equip it.
- **Mouse and controller support:** use the native look grid and a guided creator, including ultrawide layouts.
- **Helmet and cape variants:** available when supported passive or weight changes are detected in that slot. Transmog does not add passive effects to vanilla helmets or capes.
- **Persistent recipes:** keep armor, helmet, and cape variants between launches. Verified body-armor variants can restore automatically on the ship.
- **Optional integrations:** exact armor recipes in compatible DiverKit presets; experimental clothing packs and generated thumbnails.

## Install

Players need the packaged ZIPs; Python, LuaJIT, and the source repository are only needed to build the mod.

1. **Close Helldivers 2.** Open Arsenal and use it to manage this installation.
2. Download an installable **HD2 Transmog Foundation** ZIP from the [mod's Files page](https://www.nexusmods.com/helldivers2/mods/16633?tab=files) or a [GitHub release](https://github.com/tyrypyrking/HD2-Transmog/releases). Use the release's packaged mod, not GitHub's **Source code** archive. Follow that release's notes if its version differs from this README.
3. Download [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) separately. Transmog requires **v15 or newer with API 1**; follow upstream's current release instructions. Arsenal does not install this dependency for you.
4. Import both ZIPs into Arsenal and enable **HD2 Transmog Foundation** and **Bingus Shared Loader**. Replace an existing entry when updating; do not keep duplicate versions enabled.
5. In Arsenal's default load order, put **Bingus Shared Loader last**. If you use first-mod priority, put it first instead. Let Arsenal assign patch numbers.
6. Choose the [Transmog settings](#settings), then **Purge / Deploy** with the game closed.
7. Start the game. On the ship, open **Armory → Equipment → Armor**. Look for **Custom Variants** and the **+** card.

The loader also documents HD2MM installation. This project's option selection and validation use Arsenal; the steps above describe that workflow.

## Create and equip a variant

1. Open the ship's **Armory → Equipment → Armor**, then **Custom Variants → +**.
2. Choose an owned **look**. For a modded look with supported toggles, **Set the look** lets you customize it before continuing.
3. Choose **base stats**, then a **passive**. The stats step is skipped when disabled in Arsenal or when only one verified choice exists.
4. Select **Create** to save the variant.
5. Select its new card, then press the game's **Apply** button to equip it.

**Remove variant** deletes the saved card without changing worn armor. Pre-mission Equipment can select saved body-armor variants; create and remove them in the ship Armory. Newly owned equipment becomes available automatically; reopen the category if its native thumbnail list has not refreshed.

For helmets and capes, open their equipment tab and use **+ → Look → Passive → Create**, then select the card and **Apply**. Their stats follow the chosen look. Each slot uses its own donors and saves. Ordinary helmet/cape variants must be applied again after restarting.

### Controller controls

| Control | Action |
| --- | --- |
| D-pad / left stick | Move focus |
| A | Select or activate the focused button; press and release to Apply a ready selected card |
| B | Back; cancel at the first step |
| Y | Cancel creation |
| LB / RB | Change choice pages |
| Left / right in stats or passive lists | Move between choices and action buttons |

Selecting a passive focuses **Create**; press A again to confirm. In **Set the look**, left/right changes the focused row's choice and down past the last row reaches **Next**. WASD browsing follows the native grid selection; use mouse or controller controls to confirm. Controller coverage is for XInput/Steam Input; other controller backends are not verified.

## Settings

These three settings are independent. Change them in **Arsenal → Options**, deploy with the game closed, and restart. Existing saved recipes retain their original stats.

| Arsenal option | Default | Effect |
| --- | --- | --- |
| **HD2 Transmog Foundation** | **Independent armor stats (default)** | Choose look, base stats, and passive. **Disable armor stat selection** makes base stats follow the look. |
| **Helmet and cape variants** | **On (default)** | Enable the creator when supported changes are detected in those slots. Older installations may retain Off. |
| **Armor thumbnail passive icons** | **On (default)** | Show passive badges on armor thumbnails. Off keeps passive-selection and detail-panel icons visible. |
| **Armory interface** | **On (default)** | The custom cards, the creator and the generated previews in the Armory. Off leaves the stock Armory; saved variants and the clothing API keep working. |
| **Developer tools** | **Off (default)** | The debug bridge and the in-game test suite. Leave it off unless a maintainer asks for it. |

With the optional **Mod Options Menu** host installed, **Options → MODS → HD2 Transmog** also provides preview settings and diagnostics:

- **Generated previews: Off (default)** leaves the images Transmog already cached in place and a missing modded card blank; nothing is rendered. **On** renders the card images and the Armory page's gear tiles of modded looks through the game's full pipeline while an Armory item list is open.
- **Mod author's choice**, **Force HD2**, or **Force Studio** selects the thumbnail style when generation is on. Each style has its own disk cache.
- **Regenerate now** checks renderer compatibility, then rebuilds previews. Keep an Armory item list open. Existing images remain until successful replacements are saved; other styles' caches are retained.
- **Armory 3D preview: Game default** (the default) leaves the large Armory model to the game. **Full render** draws it through the full game rendering pipeline with Transmog's lighting and colour grade, which needs temporal anti-aliasing.
- **Export logs to Desktop → Export now**, then **Apply**, saves a dated `HD2-Transmog-Logs-*.txt` report on your Desktop. The row confirms success or failure; repeat the action for another report.
- **Clear saved data → Clear now**, then **Apply**, starts over: your saved variants, worn looks and clothing homes are set aside as copies named `-cleared-<time>` in the Transmog state folder, fresh files are written, and the row asks for a restart. Nothing is deleted for good.

With **Generated previews** on, missing visible custom thumbnails generate on demand. Cached restarts do not initialize the thumbnail renderer; it is released when generation finishes. A missing variant image shows a loading placeholder until the correct look is ready.

## Update or uninstall

### Update

Close the game, import the new ZIP **as an update to the same Transmog entry**, keep the loader enabled, Purge / Deploy, and restart. When upgrading from the old combined Arsenal options, reselect all three independent settings once.

**0.2.3 → 0.2.4:** everything is retained. On the first start your saved variants are copied into `transmog-v3.state` (helmets and capes into `helmets-v3.state` and `capes-v3.state`), which only 0.2.4 and later write; the older files stay exactly as they were, so 0.2.3 and earlier keep working from them if you go back, and what you saved on either version waits for it. **0.2.2 → 0.2.3:** everything is retained; the save format is unchanged. **0.2.1 → 0.2.2:** saved variants, equipment and generated thumbnails are retained. Standard Issue has no grid perk badge.

**0.2.0 → 0.2.1:** saved variants and equipment are retained. Old generated thumbnails are invalidated to remove images built from modified source templates; keep the item list open while the correct images regenerate automatically.

**0.1.5 → 0.2.0:** no manual conversion or re-creation is needed. Names, looks, stats, and passives survive. Stable variant identities are assigned on read; the next save writes the new format. Before replacing a legacy save, Transmog preserves and verifies its bytes in a `<name>-v1.state` backup, adding a content-derived suffix if an existing backup differs. Failed writes retain the previous primary file. Since 0.2.4 a damaged file is kept aside and the newest good save is used; saving is never disabled.

To downgrade to 0.1.5, restore the appropriate legacy backups while the game is closed; 0.1.5 cannot read the newer save format.

### Uninstall

Close the game, disable Transmog and any clothing packs that depend on it in Arsenal, then Purge / Deploy. Keep Bingus Shared Loader enabled if other installed mods require it.

Saved variants remain in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Transmog`. Preserve that folder if you might reinstall. Mod-private restore files are ignored without Transmog; the game retains ordinary native equipment IDs.

## Compatibility and known limits

### Clothing packs — experimental

Compatible packs appear in **Modded Armors**, after Custom Variants. Install their ZIPs alongside Transmog and the loader through Arsenal. A registration-only preview ZIP contains no usable clothing; a registered piece needs a verified native binding before it can be equipped. The Sister Lacrima port supplies armor and helmet using its authored Lean model for both body choices; no cape was supplied.

Clothing multiplayer replication has been implemented and measured on two machines. Three/four-player sessions, host migration, and rejoin are not fully certified. Peers need compatible packs to resolve custom looks. This is separate from the older, registration-only appearance API. See the [clothing API reference](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#clothing-api-2).

### DiverKit — optional

Equip the intended Transmog variant, then save or overwrite the DiverKit preset. Keep the corresponding Transmog definition. Older presets containing only a native armor ID need to be saved again; removed or changed definitions also require recapture. Excluding **Armor** from a preset leaves it untouched.

Modded armor presets retain the clothing UUID and saved variant identity, then resolve the current rendering record when applied. Discovery follows long callback chains and C-Rig-style hook records without pinning a Transmog release number. Missing or changed bindings are rejected before equipment writes.

Compatibility is checked through capabilities at runtime. Live QA confirmed custom-armor preset save/apply with DiverKit **8.10.4**; automated coverage also includes **8.8.1** and **8.10.1**. This does not guarantee every release. Unsupported interfaces show a notice; when the save boundary can be identified, capture is blocked rather than losing the custom recipe.

### Passive providers and Mod Bindings Menu

Standalone Mod Bindings Menu can coexist with Transmog. Use either its standalone package or the Megapack option, as its author instructs.

Helmet/cape passive assignments are detected from native data without a provider-specific adapter. Changing effect values does not revoke ownership. Transmog preserves late passive assignments on records whose passive it has not explicitly selected; an unexpected change to an explicit variant still stops verification. Provider overlays may use their own original-passive tables and can disagree with the selected Transmog passive. Unavailable saved donors are preserved, not silently replaced.

### Current limits

- **Ownership and equipment:** ordinary looks, stat donors, and passives are rechecked before save/apply. Unavailable recipes stay saved. Body-armor restoration waits for an idle ship, the expected native carrier, and a valid owned definition; an interrupted restore is not automatically retried next launch.
- **Accessories:** automatic restoration of ordinary helmet/cape variants and pre-mission accessory editing are not implemented. Experimental registered clothing has its own guarded restore path. Passive combat effects and stacking depend on the game and the passive provider; UI/readback verification does not prove combat behavior.
- **Previews:** parent Armor/Helmet/Cape tiles use the equipped modded look’s cached image. The Armor section uses a separate image with the default B-01 helmet; this does not change your equipped helmet. If it is missing, open the item list to generate it; a loading indicator replaces the native donor image. Live generation has been verified at 1920×1080 on Linux/Proton and 3840×2160 on Windows, alongside earlier 2560×1440 checks. Other sizes, including ultrawide, have offline framing coverage but not the same live validation. Bulk generation may hold the last large-model frame. A full regeneration run still needs retesting after a reported crash.
- **Performance:** some Armory overhead remains. Idle menu detection can take up to 250 ms. A measured 40-card redraw improved from 15 FPS / 62 seconds to 65 FPS / 14.4 seconds on the tested system. This does not establish that the separately reported low GPU power/FPS issue is resolved.
- **Game updates:** native bindings are validated against the executable. Structural changes may need a Transmog update. Full mission behavior, every passive combination, and all other-mod combinations are not verified; the reported double-passive case still needs testing in an affected environment.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No Custom Variants / + card | Both mods enabled, one loader copy, winning loader priority, and a fresh Purge / Deploy with the game closed. Start with the ship Armory's Armor tab. |
| No helmet/cape creator | Set **Helmet and cape variants → On**. The slot must contain supported passive/weight changes; Transmog alone does not add them. Reopen the Armory after a catalog change. |
| A saved card is missing | Check ownership and required clothing packs. Unavailable definitions stay saved; do not delete the state folder. |
| Modded clothing is unavailable | Check `clothing-status.txt` and the binding failure reason in the log. Registration alone is not rendering readiness. |
| Thumbnail is missing or wrong | Keep the item list open for generation. Check preview style and renderer diagnostics before using **Regenerate now**. Parent section tiles have a separate known limitation. |
| A DiverKit preset loses its custom recipe | Equip the variant in Transmog and overwrite the preset with a compatible DiverKit interface. Retain its Transmog definition. |
| "Saved variants restored from a backup" or "Saved variants could not be read" | A saved file was damaged, for example by a sync tool or an interrupted write. Transmog keeps the last three saves and used the newest good one, or started fresh when none was good; saving goes on and there is nothing to do. The damaged file is kept beside the others as `<name>-damaged-<time>.state` and is included when you export logs. |

Use the [issue forms](https://github.com/tyrypyrking/HD2-Transmog/issues/new/choose) for crashes, equipment problems, or other bugs. Include mod/loader/game versions, enabled mods, steps to reproduce, expected versus actual behavior, and these files from the affected run when available:

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\
├── Logs\
│   ├── HD2Transmog.log
│   ├── HD2Transmog.previous.log   (and .previous-2.log, .previous-3.log)
│   └── BingusSharedLoader.log
└── Transmog\
    ├── problems.txt              (what you were shown and the problems this session; the report opens with both)
    ├── health.txt
    ├── game-contract.txt
    ├── STATUS.txt
    ├── clothing-status.txt       (for clothing packs)
    ├── transmog-v3.state         (your saved variants; -gen1 to -gen3 are the previous saves)
    ├── transmog-v3-damaged-*.state (a damaged file, kept, when present)
    ├── transmog.state, transmog-v1*.state (saved by earlier versions, left as they were)
    └── equipped*.state, clothing-homes.state, preview-*.state
```

The easiest way to collect logs is **Options → MODS → HD2 Transmog → Export logs to Desktop → Export now → Apply**. Attach the resulting `HD2-Transmog-Logs-*.txt` from your Desktop. Windows uses the configured Desktop (including redirected folders); Linux/Proton uses the Desktop configured in `user-dirs.dirs`, or `~/Desktop` when unset. Under Proton the report goes to the Linux Desktop, never into the Wine prefix, and its header names the Desktop it chose and why. Every available `.log` file in the loader's log folder is copied in full, including retained Transmog sessions and other mods' logs. The report opens with the session's problems summary, the same block `problems.txt` holds; that file stays in `Transmog\` for reading directly and is not copied again. The report also contains, from `Transmog\`, `health.txt`, `game-contract.txt`, `STATUS.txt` and `clothing-status.txt` when present, a listing of every `.state` save file with its size and first line, and a copy of `transmog.state` and its kept-aside originals `transmog-v*.state`, up to 64 KiB each. The save files hold kit ids, toggle words and the names you gave your variants, nothing else; variant names are included in the report. Unreadable files are listed in the report and the row shows a partial result. Existing exports are never overwritten. No upload happens automatically. If Mod Options Menu is absent or export fails, collect the files above manually. The report opens with two blocks, `Shown to the player:` (every message the mod showed you) and `Problems this session:` (every failure it recorded, first seen and how often), then the logs, the status files (a file never written is listed as `[MISSING: <name>]`), a listing of your save files and a copy of `transmog.state`.

Missing logs do not prevent a report. The current Transmog log and three previous sessions are retained; export cannot recover already rotated or unrecorded events. `state.loaded` reports saved counts; `presentation.saved` distinguishes stored, shown, and unavailable cards. `catalog.helmets` and `catalog.capes` report verified and owned counts plus detected gameplay changes; `helmet.transmog_enabled` records the Arsenal setting.

## API documentation

The in-game Lua API lives under `HD2Transmog`; it is not an HTTP service. Loader API, clothing API, appearance API, and saved-state versions are separate contracts.

| API | Status and purpose | Documentation |
| --- | --- | --- |
| `HD2Transmog.clothing` — API **2**, asset ABI **1** and **2** | Experimental pack registration, look controls, variant defaults, and events; asset ABI 2 keeps a pack's assets out of memory until one of its looks is on screen | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#clothing-api-2) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#clothing-api-2) |
| `HD2Transmog.equipment` — API **1** | Read-only: the game's catalog, what the local player has equipped, and when it is safe to act around equipment | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#equipment-api-1) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#equipment-api-1) |
| `HD2Transmog.equipment` — API **2** | Experimental, for mods that change equipment data themselves: what a variant counts as in play, an event for every change of it, and named authorities with one holder each | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#equipment-api-2) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#equipment-api-2) |
| `HD2Transmog.health()` | What is working and what is off, by name | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#health) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#health) |
| `HD2Transmog.previews` | Thumbnail rebuild/status and preview preferences; detect methods before use | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#preview-api) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#preview-api) |
| `HD2Transmog.appearances` — API **1**, asset ABI **1** | Draft registration/inspection only; independent rendering is unavailable | [English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#appearance-api-1) · [Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.ru.md#appearance-api-1) |

Start with the [API quick start](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#quick-start). Detailed English references: [SDK index](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/README.md), [clothing runtime](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/CLOTHING.md), [worked pack-authoring guide](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/AUTHORING.md), and the [Appearance API 1 draft](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/APPEARANCES.md). The API reference includes method signatures, return values, failure handling, examples, and [what stays the same](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/sdk/API.md#what-stays-the-same) for packs built against it, in both languages.

## Build from source

See [Build and development — English](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/CONTRIBUTING.md) / [Сборка и разработка — Русский](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/CONTRIBUTING.ru.md) for prerequisites, reproducible builds, offline tests, CI artifacts, and source provenance. Version history and detailed validation notes are in the [changelog](https://github.com/tyrypyrking/HD2-Transmog/blob/v0.2.4/CHANGELOG.md).
