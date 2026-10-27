# EqShaders live files (as of 2026-10-27)

Copies of what runs in `D:\Octowow`: the ReShade effect (`Shaders/EqShaders.fx`, `Shaders/EqShaders/*.fxh`, the Photon includes in `Shaders/PhotonWoW`),
the presets (`Presets/EqShaders.ini` for ReShade, `Presets/comfyatmos.ini` for ComfyAtmosphere) and the EqProfiles WoW addon (`AddOns/EqProfiles`).

ComfyAtmosphere's water shader is changed by same-length text patches applied to the release `comfyatmos.dll`
(`tools/patch_comfy_water.py`, `_shore.py`, `_wavetile.py`, `_reflect.py`, `_glint.py`, applied in that order). The DLL is not in the repo.

Known: the sun-glint lobes (`_glint.py`) were last tuned at night in rain; a daylight check is still open.
