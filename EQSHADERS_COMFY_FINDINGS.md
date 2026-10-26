# EqShaders + ComfyAtmosphere: findings (2026-10-26)

## Root cause: Comfy looked installed but did nothing

1. **WoW antialiasing was 8x (`gxMultisample "8"`).** Comfy needs a readable (INTZ) depth buffer. D3D9 cannot make an INTZ stand-in for a multisampled depth buffer (`hr=0x8876086A`). Log: `depth: could not create an INTZ ... stand-in ... depth stays unreadable`, then every 300 frames `volume: ... drawn 0; skipped: no depth 300`. Fog, volumetric light, sun shadows on the world and water depth all need that depth, so they were silently skipped.
   - After `/console gxMultisample 1` + `/script RestartGx()` (live, no relog): `multisample 0`, `drawn 300; skipped: no depth 0`, and the world visibly changed (fog, blue water, haze).
   - **Keep `gxMultisample 0` (or 1).** WoW writes it to Config.wtf on exit. Use ReShade/CAS for edge quality.
2. **Slider values beat the INI.** The addon's sliders are stored as `comfy*` CVars in `WTF\Config.wtf` and win over `comfyatmos.ini`, also after F11. Your sliders were already at 200 (mist density/height/brightness/sun/horizon). Edit them with `/console comfyMistDensity 25` etc., or the Video > Atmosphere page (Defaults button resets them). INI-only settings (e.g. `[time] hour`) do take effect on F11.
3. **F11 did nothing** until `[general] hotkeys = 1` (now set, with `trace = 1`).
4. `[general] enabled = 0` + F11 did **not** switch effects off (effects kept running). Treat the master INI switch as read at load only; use the in-game "Atmosphere Effects" box.

## Verified (screenshots + `Logs\comfyatmos.log`)

| System | State |
|---|---|
| DLL loaded, device hooked, 50/50 shaders | Working |
| Time of day (INI `[time] hour 13` -> 20 + F11 gave a sunset-pink scene) | Working |
| Fog / mist (`comfyMistDensity` 200 -> 100 -> 0 -> 25) | Working once depth readable |
| Volumetric light (`comfyVolumeStrength` 100 -> 0 -> 30) | Working once depth readable |
| Water (bright blue, depth-aware after MSAA off) | Working |
| Shadow maps (4096, ~1.1 ms replay) | Maps built; visible sun shadows not judged (rain, overcast) |
| Grass, lamps, night | Not tested |

## Open

- **HUD:** Comfy's haze also tints HUD backdrops (chat, unit frame); the player portrait went missing in the unit frame after MSAA off. Needs a look at Comfy settings / draw order.
- **Grey fog wall:** the game's own fog (rain: start ~105, end ~490 yd; farClip 1000). Comfy's `[fog] reach = 200` yd hands over to it ("the game's own fog is the far wall"). Fix is to raise `reach` and suppress the game's outdoor fog; not tested yet.
- **Far clip / culling, water wakes, Comfy->EqShaders bridge:** not started.

## Tools added

- `tools\eq_capture.ps1` (foreground WoW, optional key, screenshot), `tools\eq_setini.ps1` (edit `comfyatmos.ini` key).

## Rollback

- `D:\Octowow\EqShaders\backups\comfyatmos.ini.orig` and `Config.wtf.orig` hold the pre-test files. Other rollback as in the install report.

## Update: HUD haze and fog wall (same day)

- **HUD haze is not Comfy.** Comfy draws fog/volumetrics/rays between world and UI (`[rays] placement = 0`), and action-bar icons stay unfogged. The grey chat/unit-frame backdrops are translucent UI over a bright haze. The missing portrait appeared after `RestartGx()` (UI glitch), also with fog at 0. The remaining HUD effect is EqShaders (bloom/tonemap/CAS run after the UI). Real fix = ReShade add-on that renders effects before the UI; needs a 32-bit C++ build toolchain (none installed).
- **Fog wall:** the game's fog (rain: start 25-105, end ~440-490 yd). Comfy has no setting to move it. Comfy `[fog] reach` raised 200 -> 700 and `brightness` 0.45 -> 0.9 in comfyatmos.ini (view looks natural, wall itself not re-tested). ReShade cannot undo it past the end distance (pixels are pure fog colour).
- **Far clip:** `farclip 2000` produced no new fog-distance log lines; not conclusive. Reverted to 1000. Needs a high vantage point to test; culling untested.
- Options for a real extension: patch Light.dbc fog distances (MPQ patch), or a small D3D9 hook scaling fog start/end (OctoFog did this; its proxy d3d9.dll replaces DXVK's, so it was not reinstalled).
