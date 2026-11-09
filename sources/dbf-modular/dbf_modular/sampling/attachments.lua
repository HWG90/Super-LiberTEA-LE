-- Editable model-local calibration, in native model units. These offsets move
-- with the animated bone's full affine pose; UI text remains screen-upright.
-- Body uses the currently resolved head bone; weapon uses its current firing
-- node. First-person uses its own rig's semantic weapon attachment, advanced
-- 0.5 model units along its forward axis: the raw pivot may sit behind/below
-- the eye while its rendered weapon extends forward (Fird projection contract).
-- This is an editable attachment calibration, not a measured mesh silhouette.
-- Never replace these with fixed numeric node indices or world offsets.
return {
    body = { offset = { x = -0.04, y = 0, z = -0.12 } },
    weapon = { offset = { x = 0.04, y = -0.08, z = 0.02 } },
    viewmodel = { offset = { x = 0, y = 0.5, z = 0 } },
    -- Selectable True First Person attachment calibrations. Bone hashes live
    -- in sampling/first_person_bones.lua; numeric indices are never retained.
    tfp_left_wrist = { offset = { x = 0, y = 0, z = 0 } },
    tfp_left_elbow = { offset = { x = 0, y = 0, z = 0 } },
    tfp_bone = { offset = { x = 0, y = 0, z = 0 } },
    -- Actual selected weapon skeleton origin/parts, not the FPS attachment.
    tfp_weapon = { offset = { x = 0, y = 0, z = 0 } },
}
