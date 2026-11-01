# Goose Gadget Kit 0.5.10 (the LE build ships only Spawner and First Person)

The kit's source for Steam build 26251122 with the Lua exactly as 0.5.10 shipped. Super LiberTEA - LE builds
Gadget Kit LE from it with `package/gadget-kit-le/` (its main.lua and src/mcm.lua) and leaves out the Unlocks and
Gameplay modules (`package/build_package.py`, LE_DROPPED). Native ADS helpers: `native/first_person/` and
`native/near_clip/` (`build*.py`); the binaries ship in the release.
