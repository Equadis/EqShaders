# Port map: Photon v1.3b -> Classic WoW

Classes: **A** directly portable to ReShade · **B** approximable from colour+depth · **C** doable if we extract more data from WoW · **D** depends on Minecraft/Iris-specific renderer data.
Photon file names below are from `shaders/` in SixthSurge/photon (v1.3b era). The v0.1 port map mislabelled several (grading is `c19_color_grading`, not c14; c12/c13 are the gaussian, c14–c18 the upsample).

## Status by Photon system

| Photon system | Photon source | Class | v0.2 status | Why |
|---|---|---|---|---|
| Colour grade (brightness/contrast/saturation, HSV teal/orange/green, gain) | `c19_color_grading.fsh` | **A** | Ported 1:1 (white-balance omitted, default 6500K = identity) | Pure per-pixel colour maths. Only difference: input is WoW's LDR, so the pipeline adds an LDR→HDR expansion first. |
| Tonemap (Lottes + 7 other operators) | `tonemap_operators.glsl` | **A** | Ported (ACES variants not yet) | Per-pixel. Same expansion caveat. |
| Vignette | `c19` | **A** | Ported (pre-grade, as Photon) | Per-pixel, UV only. |
| CAS sharpen | `final.fsh` | **A** | Ported 1:1 (runs on display-encoded values, last step) | Per-pixel 3×3. |
| Bloom pyramid | `c5_c10`, `c11`, `c12/13`, `c14_c18`, `c19` | **A** | Ported (6 tiles, 13-tap CoD downsample, 9-tap binomial, weighted upsample, 12% mix) | Pure image filtering. Real HDR would give brighter/cleaner bloom; here highlights come from the expansion curve. |
| Dither | `final.fsh` | **A** | Triangular IGN dither instead of Bayer16 | Cosmetic. |
| DOF | `c2_dof.fsh` | **B** | Ported CoC + Vogel disc; auto-focus added | Needs depth (have it). CoC is evaluated on a reconstructed non-linear depth to match Photon's constants. Blurs UI unless sky/clear pixels are excluded (they are, by default). |
| GTAO / SSAO | `d3_ao.fsh`, `gtao.glsl` | **B** | Ported GTAO maths; normals rebuilt from depth; IGN + bilateral blur replaces TAA accumulation | Photon reads a G-buffer normal and accumulates over frames. We have neither, so quality is below Photon at silhouettes and has residual noise. Radius is WoW yards. |
| Atmospheric / analytic fog | `fog/overworld/analytic.glsl` | **B** | Multiple-scattering structure ported; sun dir/colours are manual; no height falloff | Needs world position and the sky model; we only have view distance. |
| Light shafts / volumetric light | `c0_vl.fsh` | **B** (approx.) / **C** (real) | Screen-space radial shafts, manual sun direction | Photon marches the view ray through the shadow map. Without shadows, screen-space shafts are only a look-alike and need the sun on-screen. |
| Screen-space reflections | `composite*` SSR | **B** | Experimental, off by default | No roughness/F0/water mask; "up" comes from a manual pitch slider. Useful as a demo only. |
| Sky / atmosphere LUT | `d0_sky_map`, `sky/atmosphere.glsl` | **B/C** | Not ported | Can be rebuilt from time-of-day. Needs a sky mask that excludes the UI (C). |
| Volumetric clouds | `d1_clouds` | **C** | Not ported | Pure procedural: does not need Minecraft data, but must replace WoW's sky draw and be depth-composited. Needs sun direction + view/projection matrices + a way to know sky pixels without the UI (hook). |
| Motion blur | `c20_motion_blur` | **C** | Not ported | Needs previous-frame matrices (camera motion) — obtainable from `SetTransform`. |
| TAA / TAAU / temporal AO / temporal fog | `c3`, `c4`, … | **C** | Not ported | Needs sub-pixel projection jitter (inject into the projection matrix) + motion vectors + history. Without jitter, TAA only denoises. |
| Shadow maps, PCSS, cascades | `shadowcomp`, `shadow.*` | **C** | Impossible in ReShade | Needs the scene geometry from the sun's view: record the draw calls (VB/IB/world matrix/texture) and replay them into a depth target. Requires a D3D9 hook. |
| Water (normals, refraction, caustics, fog) | `gbuffers_water`, `composite` | **C** | Not ported | Needs a water mask (which draw call/vertex data is water) and a world position. |
| Material / PBR (roughness, F0, emission, SSS) | G-buffer | **C → D** | Not ported | WoW has no PBR textures. Class C gets a *heuristic* material ID per draw category (terrain/WMO/M2/water/sky) and fake roughness; there is no real data to decode. |
| World-space normals | G-buffer | **C** | View-space from depth only | Hook can emit real vertex normals from a G-buffer pass (FFP geometry carries normals). |
| LPV / coloured block lights | `lpv/*`, `lighting/lpv` | **D** | Not ported | Minecraft voxel grid + block light emission data from the terrain. WoW has no voxel world. A *replacement* (per-draw light sources from point lights/emissive M2s injected into a froxel grid) is a new system, not a port. |
| Shaped terrain, waving foliage, rain/snow particles, biome effects, hand/held-item depth, block IDs | various `gbuffers_*` | **D** | Not applicable | Minecraft geometry/entity/biome specifics. |

## Renderer data needed per feature

| Need | Source in Classic WoW | ReShade | D3D9 hook |
|---|---|---|---|
| Depth | Depth buffer (ReShade copies it; check the Raw-depth debug view) | yes, fragile | yes, exact |
| Camera view/projection (FOV, near, far, pitch/yaw) | `SetTransform(VIEW/PROJECTION)` or vertex-shader constants | no (manual sliders) | yes |
| Previous-frame matrices, motion vectors | Same, kept one frame | no | yes (camera-only motion; animated models need per-draw history) |
| Sun / moon direction, light colour, ambient | WoW lights the world with D3D lights/ambient/fog render states (`SetLight`, `D3DRS_AMBIENT`, `D3DRS_FOGCOLOR`) | no (manual) | yes — *expected, verify with a capture* |
| Time of day | Derived from light colour/direction, or read from client memory | no | yes |
| Fog start/end/colour | `D3DRS_FOG*` (the OctoFog DLL already reads these) | no | yes |
| Sky pixel mask | Sky draw call identification, or stencil | partial (depth = far; includes UI) | yes |
| UI exclusion | Capture the frame before UI draws | no (ReShade runs after UI) | yes |
| World position | Depth + inverse view-projection | partial (needs FOV by hand) | yes |
| World normals | Vertex normals via a G-buffer pass | no (derived from depth) | yes |
| Water / terrain / model / WMO classification | Draw-call category: vertex format, stride, shader/state, blend mode, call order | no | yes |
| Shadows | Record scene draws, replay from sun | no | yes |
| GI | Reflective shadow map / froxel injection from the above | no | yes (large project) |

## How to get the data (ordered by cost)

1. **Instrument first, build second.** Capture a frame with RenderDoc on the DXVK/Vulkan path or `apitrace` on D3D9. Answer: fixed-function or shaders? what do `SetTransform`/`SetLight` carry? what are the draw categories? This costs hours, not weeks, and decides everything below.
2. **ReShade add-on (C++).** The add-on API exposes `draw`/`draw_indexed` events, render-target/depth views and (on native D3D9) constant updates. It can copy the depth buffer at a chosen draw (e.g. right before the UI) and so give a UI-free scene. *Caveat for this client:* the log shows `d3d9.dll` is **DXVK v3.1.1**, so ReShade sees Vulkan (layer) and shader constants are already repacked by DXVK; fixed-function state is invisible there.
3. **D3D9 proxy in front of DXVK** (the same trick the existing OctoFog/SuperWoW/nampower DLLs use to live in-process). Wrap `IDirect3DDevice9`: capture state, matrices, lights, fog; tag draw calls; render extra targets; inject our own pixel/vertex shaders; replay geometry into a sun depth map; run the Photon passes (ported HLSL) at the right point in the frame, before UI. Everything in the tables above is reachable from here.
4. **Replace the renderer** (own D3D11/Vulkan back-end consuming the recorded frame). Maximum fidelity, maximum cost. Not recommended until step 3 shows its limits.

Scope note: all of the above is rendering-state capture only. Nothing reads or writes game logic, entities or network data, and nothing automates gameplay.
