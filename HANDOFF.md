# PhotonWoW handoff (v0.3, 2026-10-26)

Photon v1.3b (SixthSurge) look/maths ported to a ReShade effect for OctoWoW. This file is the current state, so the next MVP (combined with another mod) can start from facts rather than re-discovery.

## 1. What is installed and how it is wired

```
WoW.exe (32-bit, 1.12.1, launched via VanillaFixes.exe)
  -> D:\Octowow\d3d9.dll = DXVK 3.1.1 (x86)              [untouched]
    -> Vulkan (NVIDIA RTX 3080, driver 610.88, vulkan-1.dll 1.4.341)
      -> ReShade 6.8.0.2156 Addon, Vulkan implicit layer VK_LAYER_reshade (32-bit)
```

- ReShade is enabled **only for the game process** by `VK_ADD_IMPLICIT_LAYER_PATH=D:\Octowow\reshade`, set in `D:\Octowow\Launch_WoW_PhotonWoW.bat`. No registry change, no DLL replaced/renamed, no D3D9 chain. Starting WoW any other way = vanilla rendering.
- ReShade ran inside both `VanillaFixes.exe` (a short probe, exits by itself) and `WoW.exe`. Only `WoW.exe` presents frames.
- Other Vulkan layers already registered on this machine (Steam overlay/fossilize, OBS hook) load alongside; no conflict seen.
- The loader finds ReShade via `D:\Octowow\reshade\ReShade32.json`; `ReShade.ini` and `ReShade.log` are in the game folder. Overlay key **Home**, screenshot (post-effect) **PrtScn** -> `D:\Octowow\reshade\screenshots`.
- Provenance: official installer `ReShade_Setup_6.8.0_Addon.exe` from reshade.me (SHA-256 `afe4c8f13048306307983b8b3d41d5bf00a86820440b0e57dea10950e1176445`), payload extracted (not executed), installer kept as `reshade\ReShade_Setup_6.8.0_Addon.exe.source`.

### Files added (all under D:\Octowow, nothing existing was edited)
`reshade\` (ReShade32.dll/.json, installer .source, Uninstall-PhotonWoW.ps1, screenshots\), `reshade-shaders\Shaders\` (PhotonWoW.fx + PhotonWoW\*.fxh + licence), `reshade-shaders\Textures\` (empty), `ReShade.ini`, `PhotonWoW.ini` (preset), `Launch_WoW_PhotonWoW.bat`, `ReShade.log` (generated), and the source project `PhotonWoW\` (this folder; includes tools and the licence).

### Rollback
Run `D:\Octowow\reshade\Uninstall-PhotonWoW.ps1` (removes `reshade\`, `reshade-shaders\`, `ReShade.ini`, `ReShade.log`, `PhotonWoW.ini`, the launcher bat; leaves the `PhotonWoW\` source folder). Or delete exactly those items by hand. Game, DXVK and `dxvk.conf` were never modified.

## 2. Pipeline (shader side)

`DepthLinearise -> Prep (sRGB->linear Rec.2020, LDR->HDR expansion) -> GTAO (+2 bilateral passes) -> [Shafts] -> Lighting (AO, fog, shafts) -> [SSR] -> [DOF c2] -> bloom pyramid (6 down + 12 blur + 5 up) -> Composite (12% bloom mix, exposure, vignette, Photon grade_input, tonemap, grade_output, display EOTF) -> Final (CAS + dither, MasterStrength mix)`

Optional stages are preprocessor switches (`PW_ENABLE_AO/BLOOM/CAS` default 1; `PW_ENABLE_VOLUMETRICS/SSR/DOF` default 0). Photon constants were taken from the Photon source (`c19_color_grading.fsh`, `tonemap_operators.glsl`, `gtao.glsl`, bloom `c5_c10/c12/c14_c18`, `c2_dof.fsh`, `final.fsh` CAS, `fog/overworld/analytic.glsl`). Details per file: README.md and PORT_MAP.md.

## 3. Verified facts

| Item | Result |
|---|---|
| ReShade compile | `PhotonWoW.fx` compiles in ReShade 6.8 in Basic / Medium / Full configs; the only ReShade-specific error found was `fmod` (not available), fixed. |
| Offline check | `tools\check_hlsl.py`: 36/36 pass entry points compile as `ps_3_0`. This does not catch ReShade-parser quirks (the `fmod` case proved that). |
| Depth buffer | Generic Depth add-on auto-selected a 3440x1440 **D24S8** buffer (login: 85 draws; a second D24S8 with 3 draws is not used). Standard (non-reversed) orientation; cleared/sky = exactly 1.0. |
| Cost (GPU, 3440x1440, RTX 3080) | Basic 0.46 ms (5 passes) / Medium 1.67 ms (31) / Full 3.27 ms (36). Costliest: DOF 1.08, AORaw 0.57, Shafts 0.51 ms. |
| FPS | Login scene is frame-capped at 180, so it shows no loss. In-world with the contact sheet (not the real effect) the user measured 133 fps / 7.52 ms. **No baseline-vs-effect FPS exists yet.** |
| In-world contact sheet (user capture) | AO good, normals plausible, sky mask correct, no red (no exact-0) in depth sanity, HUD visible in every tile. |

## 4. Open problems (concrete)

1. **HUD is affected by every effect (user requirement: it must not be).** Depth cannot separate it: UI drawn over geometry inherits that geometry's depth (DOF blurred the login buttons; in-world the minimap/chat/action bars appear in the bloom tile). `ProtectDepthless` only protects pixels whose depth is the cleared value (sky, letterbox, some UI). A real fix needs the effects to run **before the UI is drawn**: either (a) a ReShade add-on that calls `effect_runtime::render_effects` on the scene render target at the draw where the UI begins (heuristic: first draw after the 3D pass with depth test disabled / HUD viewport), then lets the UI draw over the result; or (b) the "other mod": a hook that can provide a pre-UI colour target or a UI mask. Either way the shader side only needs one change: read colour/depth from the supplied target instead of the backbuffer.
2. **Near/far are uncalibrated in-world.** In the contact sheet, ring bands showed a single colour and the linear view was uniform grey, i.e. computed distances were all < 10 yd even for distant buildings, while AO and normals still looked right. So either far/near are far from reality, or the depth is not a plain perspective mapping. v0.3 adds tools to settle it in one session: *Depth probe* (numeric raw depth + linear yards at the centre crosshair), a log-stretched sanity tile, and `tools\solve_depth.py` (two readings at known distances -> near/far; z is linear in 1/d). AO radius, fog, DOF and SSR all use yards, so this gates their correctness.
3. **Baseline FPS unknown** (see section 3).
4. **Photon look comparison not done** (no Photon reference render here). Tonemap/grade/CAS/bloom maths are 1:1; the difference is input (WoW's LDR, bridged by `HdrExpansion` 0.875). Shadows come out darker than the source (input 0.10 -> 0.04), which is Photon's toe acting on already-lit LDR.
5. **Fog, shafts, SSR defaults are blind-tuned**; fog double-stacks with WoW fog / OctoFog.
6. Faint diagonal banding in the reconstructed-normals view on the login scene (cause not diagnosed; depth is 24-bit).
7. Probe digit glyphs: '1' renders thin and can look blank at 1440p; read the other digits and repeat the measurement if unsure.

## 5. Next-session recipe (≈10 minutes, in-world)

1. `Launch_WoW_PhotonWoW.bat`, log in, Home -> Debug view = **Depth probe**. Aim the crosshair at a flat surface at ~5 yd, note raw (green) and yards (yellow). Move to ~40 yd (target dummy/wall, along the view axis) and note again. Then:
   `python -I D:\Octowow\PhotonWoW\tools\solve_depth.py <z1> <d1> <z2> <d2>` and enter near/far in the Depth section (also in `PhotonWoW.ini`).
2. Debug view = **Distance rings** (should now band properly) and **Contact sheet**; send a screenshot.
3. Baseline vs effect FPS: Home -> Statistics with the technique unticked / ticked / Full (`PW_ENABLE_VOLUMETRICS/SSR/DOF=1`).

## 6. Interface notes for combining with another mod

- The effect needs, per frame: scene colour, depth (any size; currently ReShade's selected buffer), and optionally: camera vertical FOV, near/far, sun direction in view space, light/fog colours. All currently manual uniforms in `Depth.fxh` / `Fog.fxh`; PORT_MAP.md lists the renderer data each Photon system needs (matrices, sun/light state, draw-call classes, sky/UI masks, previous-frame matrices for TAA/motion blur, geometry replay for shadows).
- Scope boundary kept so far: rendering only. Nothing reads or writes game logic, entities or network data.
- Photon licence (`PHOTON_LICENSE.txt`): personal use; no money; do not redistribute on monetised platforms.

## 7. Where things are

- Source of truth for edits: `D:\Octowow\PhotonWoW\` (mirror of `reshade-shaders\Shaders`). Keep them in sync: `tools\Install.ps1 -GameDir D:\Octowow` copies project -> live.
- Helper scripts used this session (not in the project): none required; screenshots/stats were driven by ad-hoc PowerShell.
