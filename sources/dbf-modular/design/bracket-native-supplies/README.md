# Bracket native supplies pass

User reference: reference.png. Keep Bracket unboxed with token text shadows.

- Remove the numeric health percentage; make the health track/fill5px at1080p.
- Pair stim count with the native syringe texture; pair grenade count with the stock HUD's current equipped-grenade texture. Preserve native source aspect ratios, fixed supply slots and contextual visibility.
- Place the original weapon-controls strip directly below the ammo value. Reserve/reload support must clear the strip. Hybrid heat's vertical bar must clear the controls as well as the maximum percentage value.
- Keep all original DBF controls, countdowns, settings, model anchors and Quiet aiming behavior.

Native Heat Limiter is a separate withheld experiment. It must not load or be included as a DLL in this HUD package after dev.12 observer acceptance crashed. Both dev.11 and dev.12 incidents are retained under dist/incidents; stable dev.10 was restored before this HUD pass.

Offline geometry/native-call fixtures and package hashes do not establish in-game appearance. Record deployment and user visual acceptance separately.

The next pass adds thin open side brackets around the visible health/stamina/supply group. Padding is measured from actual text and native icon extents; the trim follows the vitals anchor, participates in viewport/sight clearance, and disappears when no vitals are visible. Cooldowns remain outside. A native heat-coil image follows the weapon role, upright to the left of the vertical meter with matching bottom edges, and turned sideways to the left of the horizontal meter; unknown artwork retains the HEAT text fallback.

Live dev.14 confirmed the Scythe filled texture fb6b3350a1645aa8 matches the slatted coil reference. It is the weapon resource definition at+1032, separate from the+1040 spare-cell outline and the+22208 gun picture. Stable icon sampling runs before optional model geometry and retains a final current-weapon/resource proof within the existing read budget.
