-- The only loader descriptor; components never register independent updates.
return mod.require("engine/app.lua").descriptor(mod, _G)
