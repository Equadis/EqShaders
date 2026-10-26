# PhotonWoW v0.2

Photon v1.3b (SixthSurge) post-processing maths ported to a ReShade effect for Classic WoW / OctoWoW. Goal: reproduce Photon's tonemap, grading, bloom, GTAO, DOF and CAS as exactly as an image-space effect can, and document what needs renderer access (`PORT_MAP.md`).

Licence: Photon's licence applies to the ported maths (`PHOTON_LICENSE.txt`). Personal use only; do not sell it or post it on monetised platforms (Modrinth, CurseForge, â€¦).

## Layout

```
PhotonWoW/
â”œâ”€â”€ Shaders/PhotonWoW.fx           technique, passes, composite
â”œâ”€â”€ Shaders/PhotonWoW/*.fxh        Common, Depth, Tonemap, ColorGrade, AO, Bloom, Fog,
â”‚                                  Volumetrics, Reflections, DOF, Sharpen
â”œâ”€â”€ PhotonWoW.ini                  ReShade preset (Photon defaults)
â”œâ”€â”€ PORT_MAP.md                    Photon system -> A/B/C/D, data needs, hook options
â”œâ”€â”€ tools/Install.ps1              copies files into a ReShade install
â””â”€â”€ tools/check_hlsl.py            offline compile check (ps_3_0) of every pass
```

## Install (verified on this OctoWoW: 32-bit WoW.exe 1.12.1 -> DXVK 3.1.1 d3d9.dll -> Vulkan -> ReShade 6.8.0 Addon layer)

ReShade runs as a **Vulkan implicit layer enabled only for the game process** via `VK_ADD_IMPLICIT_LAYER_PATH`. No registry/system change, no DLL in the game folder is replaced or renamed, DXVK is untouched, no D3D9 chain.

Added to `D:\Octowow`: `reshade\` (ReShade32.dll + ReShade32.json + Uninstall-PhotonWoW.ps1 + screenshots), `reshade-shaders\`, `ReShade.ini`, `PhotonWoW.ini`, `Launch_WoW_PhotonWoW.bat`, `ReShade.log` (generated).
Launch with `Launch_WoW_PhotonWoW.bat`. Launching normally gives vanilla rendering.
Rollback: run `reshade\Uninstall-PhotonWoW.ps1`, or delete exactly the items above.
Overlay: **Home**. Screenshot (post-effect): **PrtScn** -> `reshade\screenshots`.
## Calibrate depth first (5 minutes, do not skip)

Everything except colour grade, bloom and CAS depends on depth. Use **Debug view**:

1. `Depth-buffer sanity`: world should be grey ramp, never solid blue (cleared) or red. Solid blue = ReShade is reading the wrong/cleared depth buffer: change the Generic Depth source.
2. Easiest: `Contact sheet` (4x3 grid: original + every debug view in one frame). On the OctoWoW login scene it showed correct, non-reversed 24-bit depth (selected buffer: 3440x1440 D24S8), a valid sky mask, smooth normals and sensible AO.
2. `Raw depth`: near dark, far white. Backwards? Turn on **Reversed depth**. WoW through DXVK should be standard (not reversed).
3. `Distance rings`: red lines every *Ring spacing* yards. Stand next to something at a known distance (e.g. 10 yd to a target dummy) and adjust **Far plane** (and **Near plane**) until rings land correctly. If nothing lines up at any value, try **Depth encoding** = Logarithmic/Linear, then **Depth exponent**.
4. `Reconstructed normals`: a flat road must be a smooth single colour. Banded or tilted = wrong **Vertical FOV**.
5. `Ambient occlusion` / `Fog factor`: check against the above, then turn the debug view off.

The DXVK log shows a `D16_UNORM_S8_UINT -> D24_UNORM_S8_UINT` substitution. If WoW is asking for 16-bit depth, expect stair-stepped distant depth (visible in `Distance rings`) and AO banding there; lower AO radius or accept it.

## Pipeline (mirrors Photon's order)

`depth linearise â†’ LDRâ†’HDR expansion â†’ GTAO + bilateral blur â†’ [shafts] â†’ lighting (AO, fog, shafts) â†’ [SSR] â†’ [DOF] â†’ bloom pyramid â†’ composite (12% bloom mix, exposure, vignette, grade_input, tonemap, grade_output) â†’ CAS + dither`

Optional stages are removed from the technique with preprocessor definitions (ReShade â†’ *Edit global preprocessor definitions*): `PW_ENABLE_AO/BLOOM/CAS` (default 1), `PW_ENABLE_VOLUMETRICS/SSR/DOF` (default 0), `PW_AO_SLICES`, `PW_AO_STEPS`, `PW_DOF_SAMPLES`, `PW_SHAFT_SAMPLES`, `PW_SSR_STEPS`.

## Known limits (be aware before judging the look)

- WoW delivers an 8-bit, tonemapped image; Photon tonemaps HDR. The **HDR expansion** (default 0.875 â†’ LDR white = Photon's white point 8.0) is the bridge. It is a stand-in, not a recovery of lost highlight data. Photon's tonemap toe is deliberately contrasty: shadows come out darker than the source (input 0.10 â†’ output 0.04).
- ReShade runs after the UI: grade, bloom, vignette and CAS affect the HUD. Depth-dependent effects skip UI because it has "sky" depth, but the grade cannot. A hook can run before UI (see `PORT_MAP.md`).
- Sun direction/colour, fog colour and camera pitch are manual sliders. They are not read from the game.
- Fog stacks with WoW's own fog and OctoFog; leave `EnableFog` off until depth is calibrated, then reduce the game's fog first.

## Verification status

- All 36 pass entry points compile as `ps_3_0` with every optional stage on (`python -I tools/check_hlsl.py Shaders/PhotonWoW.fx -DPW_ENABLE_SSR=1 -DPW_ENABLE_DOF=1 -DPW_ENABLE_VOLUMETRICS=1`). That checks HLSL, not ReShade's own FX parser, and nothing has run in WoW yet.
- Photon constants/curves were taken from the Photon source, not from memory (`c19_color_grading.fsh`, `tonemap_operators.glsl`, `gtao.glsl`, `c5_c10`/`c12`/`c14_c18` bloom, `c2_dof.fsh`, `final.fsh` CAS, `fog/overworld/analytic.glsl`).

