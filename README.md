# EqShaders

**EqShaders** is an experimental graphics/shader stack for WoW 1.12 / OctoWoW.

The MVP combines three complementary pieces:

- **ComfyAtmosphere** handles renderer-level/world-space effects inside WoW's D3D9 path: real sun shadows, shadow maps, volumetric lighting, world fog, lamps, water/grass features and time-of-day behaviour.
- **Photon-derived EqShaders processing** runs afterward in ReShade and provides GTAO, bloom, Lottes tonemapping, colour grading, vignette, CAS sharpening and depth/debug tooling.
- **EqShaders fantasy look** is an independently authored, clean-room visual mode inspired by the publicly observable look of Bliss Shaders: warmer highlights, cooler atmospheric shadows, lush greens/blues, stronger luminous bloom and a more fantasy-oriented final grade.

The intended render path is:

```text
WoW.exe (32-bit, 1.12.1)
  -> ComfyAtmosphere (D3D9 / VanillaFixes)
  -> DXVK
  -> Vulkan
  -> ReShade Vulkan layer
  -> EqShaders.fx
  -> final frame
```

This is deliberately an integration MVP rather than a source-code merge. The renderer backend and ReShade layer remain separate components with their own licenses; see `THIRD_PARTY.md`.

## Bliss-inspired mode and licensing

Bliss Shaders itself is **All Rights Reserved** and is based on Chocapic13's shaders. EqShaders therefore does **not** copy, vendor, translate or port Bliss/Chocapic shader source.

Instead, `Shaders/EqShaders/BlissInspired.fxh` is a clean-room implementation using ordinary rendering techniques to approximate high-level visual characteristics visible in public screenshots and published settings descriptions.

In ReShade, under **EqShaders look -> Visual style**, choose:

- **Photon base** — original Photon-derived EqShaders appearance;
- **Bliss-inspired hybrid (clean-room)** — current MVP default;
- **Bliss-inspired strong (clean-room)** — stronger version for testing.

The hybrid keeps Photon as the mathematical post-processing base while adding independently authored warm/cool split toning, foliage/blue-channel emphasis, shadow lift and extra bloom energy.

## MVP status

The original PhotonWoW ReShade effect was tested on OctoWoW's DXVK/Vulkan path with ReShade 6.8.0 Addon and rendered successfully on the login scene. The combined EqShaders stack still needs full in-world validation for depth, HUD behaviour, ComfyAtmosphere interaction and real gameplay performance.

The preset intentionally avoids double-applying renderer effects:

| Effect | MVP owner |
| --- | --- |
| Real sun/world shadows | ComfyAtmosphere |
| Shadow maps | ComfyAtmosphere |
| Volumetric lighting | ComfyAtmosphere |
| World fog | ComfyAtmosphere |
| Lamps / time of day / moving grass | ComfyAtmosphere |
| Water renderer changes | ComfyAtmosphere |
| GTAO / contact AO | EqShaders |
| Bloom | EqShaders / Photon base, with optional fantasy boost |
| Tonemap / base colour grade | Photon-derived EqShaders layer |
| Fantasy colour treatment | Clean-room EqShaders look layer |
| CAS sharpening | EqShaders |
| ReShade fog | Disabled by default |
| ReShade shafts | Disabled by default |
| SSR / DOF | Disabled by default; experimental |

## Install

The installer expects a working WoW 1.12 / OctoWoW client. The tested setup uses DXVK plus a **32-bit ReShade Vulkan layer**. ReShade itself is not redistributed here.

From PowerShell in the repository folder:

```powershell
.\Install-EqShaders.ps1 "D:\Octowow"
```

The installer will:

1. copy `EqShaders.fx`, the Photon-derived include headers and EqShaders clean-room look headers to `reshade-shaders\Shaders`;
2. copy `EqShaders.ini` to the game folder;
3. download the pinned official ComfyAtmosphere `v0.17.1-alpha` release **only if `comfyatmos.dll` is not already installed**;
4. add `comfyatmos.dll` to `dlls.txt` and remove obsolete split `comfyfog/comfygrass/comfytime` entries as required by upstream;
5. create `Launch_EqShaders.bat`;
6. leave existing ComfyAtmosphere DLL/config/addon files untouched if they are already present.

The installer keeps a one-time copy of the original `dlls.txt` at:

```text
EqShaders\dlls.txt.before-eqshaders
```

## Launch

Run:

```text
Launch_EqShaders.bat
```

The launcher sets the local ReShade Vulkan implicit-layer path when `reshade\ReShade32.json` exists, then starts `VanillaFixes.exe` when available so `comfyatmos.dll` can load from `dlls.txt`.

In ReShade:

1. press **Home**;
2. select `EqShaders.ini`;
3. enable **EqShaders [EqShaders.fx]**;
4. expand **EqShaders look** to switch between Photon base and the clean-room fantasy modes.

## First in-world test

Before judging the look, validate depth:

1. log into a character;
2. press **Home**;
3. expand **EqShaders -> Debug / calibration**;
4. set **Debug view** to **Contact sheet**;
5. capture a screenshot;
6. compare FPS with EqShaders on/off.

After depth is confirmed, set Debug view back to **Off** and compare **Photon base** against **Bliss-inspired hybrid** from the same camera position.

## Why ComfyAtmosphere matters

A pure ReShade port only sees the final colour/depth buffers. ComfyAtmosphere hooks the WoW/DXVK D3D9 device and can work with actual world rendering, including sun-position-driven shadow maps and volumetric lighting. That makes it a much better backend for the parts of Minecraft-style rendering that cannot be recreated faithfully as a post-process.

The next architectural milestone is a small bridge that exposes selected ComfyAtmosphere runtime data to EqShaders, such as:

- sun direction;
- camera/view/projection data;
- time of day;
- fog colour/state;
- weather state;
- indoor/outdoor state;
- water state;
- potentially shared depth/shadow information.

That would let the fantasy look react to the actual world/weather state instead of being a static final grade.

## Current limitations

- HUD/UI is drawn over world geometry, so a depth-only mask cannot reliably exclude it from post effects.
- Photon-derived processing receives WoW's LDR backbuffer rather than Minecraft/Iris HDR/G-buffer inputs.
- The Bliss-inspired layer is a clean-room visual approximation, not Bliss shader code and not a 1:1 port.
- Material-specific Bliss features such as true Minecraft water/PBR/voxel lighting cannot be reproduced by ReShade alone.
- ReShade SSR/DOF remain experimental and are off in the combined preset.
- ComfyAtmosphere officially documents a tested DXVK 2.7.1 setup; the user's current OctoWoW stack is DXVK 3.1.1, so compatibility must be validated in-world.

## Project files

```text
EqShaders.ini                         Combined ReShade preset
Install-EqShaders.ps1                MVP installer/integrator
Uninstall-EqShaders.ps1              Rollback/removal helper
Shaders/EqShaders.fx                 User-facing EqShaders ReShade technique
Shaders/EqShaders/BlissInspired.fxh  Clean-room fantasy look module
Shaders/PhotonWoW/*.fxh              Existing Photon-derived implementation modules
PHOTON_LICENSE.txt                   Photon upstream terms
THIRD_PARTY.md                       Component/license/pinning information
PORT_MAP.md                          Original Photon -> WoW port mapping
HANDOFF.md                           Development/testing notes from the first ReShade MVP
```

Internal `PW_` symbols and the `Shaders/PhotonWoW/` include directory are intentionally retained in the MVP to avoid a risky mechanical rename while rendering behaviour is still being validated.

## Credits

- Photon Shaders / SixthSurge — visual reference and ported shader maths; see `PHOTON_LICENSE.txt`.
- aloofbit / ComfyAtmosphere — WoW 1.12 renderer-level atmosphere backend, GPL-3.0.
- Xonk___ / Bliss Shaders and Chocapic13 — visual inspiration only; **no Bliss/Chocapic source is included or ported**.
- ReShade — post-processing runtime.

EqShaders is an independent integration project and is not affiliated with OctoWoW, Blizzard, Photon, Bliss or ComfyAtmosphere.
