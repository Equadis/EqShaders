# Rain signals for the wet-ground system (investigation, 2026-10-31)

**BLUF:** The cleanest source is the game's own weather state (type + grade), which `EqPixelBridge` already writes into the frame for ReShade. Nothing needs detecting from pixels. The rain splash draw is a good *second*, exposure-aware signal and can be detected cheaply by Comfy; splash positions exist but cost a Comfy source change. **Measured live (2026-10-31, Southshore, rain grade 1.0):** rain draws vanish entirely indoors, stay drawn under an open roof and at a shore. Not yet tested: roof edge, cave, per-splash shelter, how the client picks positions.

Evidence labels: **[file]** read from the client archives or our source, **[source]** read from ComfyAtmosphere / EqPixelBridge source, **[log]** from our logs, **[untested]** not verified.

## 1. The assets
- `Textures\Weather\RainDropSplash01.blp`, in `Data\patch.MPQ` **[file]**. BLP2, palette, 1-bit alpha, 256 x 256, 9 mips. Decoded to a PNG: a 4 x 4 flipbook of 64 x 64 frames, an animated splash (rings, then a crown, then a rising column). The client holds it as A4R4G4B4 **[source]**. Only one variant exists in the archives I could open.
- `Textures\Weather\RainDrop01.blp`, the rain streaks **[file]**. BLP2, DXT, 16 x 128, 8 mips. Different asset, different draw.
- Also `SnowMist01.blp` (the grey mist) **[log]**.
- Dump tool: `tools\blp_dump.py`.

## 2. How they are drawn **[source]**
- **Splashes (measured):** at `weatherDensity 3` the splashes are drawn as **11 to 13 draws per frame, 5.3k to 6.1k triangles each (about 67k to 77k per frame)**, through a vertex shader (the position is built in the shader from per-draw constants; `c12` steps down from about 2.2 by about 0.19 per draw, an age/phase). Texture = RainDropSplash01 (256 x 256, A4R4G4B4), alpha blended, depth write off. This replaces the older note of one fixed-function draw of 1024 triangles. Drawn after the world ends, so shaders such as Comfy's can swap in their own.
- **Streaks (measured):** 10 to 12 draws per frame of about 6.1k triangles (61k to 73k per frame), 16 x 128 texture.
- **Streaks:** blend `DESTCOLOR` / `SRCCOLOR`, depth write off, texture 16 x 128.
- Comfy already identifies the splash draw (`IsSplashDraw`: format + blend + the texture's pixels compared with the file, cached per texture, so no per-frame scan) and routes it through its own pixel shader.

## 3. Detecting the draw
- **Easy for Comfy, not for ReShade.** ReShade only sees frame buffers; Comfy hooks the D3D9 calls before DXVK.
- Comfy already counts the streak triangles each frame and eases the result into `WaterRainAmount()` (0..1, about 1 s). So "rain is being drawn" is already a cheap, draw-derived signal.
- Getting a new signal from Comfy into EqShaders needs a delivery path (a few more strip pixels, like the weather one). That needs a Comfy source change and the mingw-built DLL, which is not yet proven in-game. Our binary text patches cannot add new C++.

## 4. How the game decides where splashes go
- **Not reverse-engineered.** The notes (Comfy, 2026-10-05 and 2026-10-12) say the client draws splashes **on the ground, never on the water surface**, and also on the **sea bed**, so near a shore they show through shallow water. That fits "particles near the camera, placed at the ground height" and not "a fall-and-collide test per drop". **[untested hypothesis]**
- Whether the ground height is the terrain mesh, the collision mesh, or includes WMO floors is unknown. So is whether roofs or trees suppress them. Related CVars exist: `weatherDensity` (3 in our config) and `particleDensity`, which scale the counts.

## 5. Better state than the splash: the weather manager **[source]**
- `EqPixelBridge` reads the weather manager (`0x00C6326C`: grade float at `+0x0C`, type int at `+0x20`) each frame and writes **type (0 fine, 1 rain, 2 snow, 3 storm) and grade 0..1** into the frame; `Bridge.fxh` already decodes it (`eq_weather()`).
- Comfy also reads the server's weather packet (`SMSG_WEATHER 0x2F4`) with its own handler patch (`weather.cpp`). Same data, earlier than the drops.
- Limits: it is the zone's weather, not what reaches the player. Indoors and under cover it still says rain. We already have an indoor flag (EqProfiles `IsIndoors` through the Lua strip, and Comfy's `MapIndoors` from the map files).

## 6. Splash positions
- **Moderate.** The draw carries camera-space positions in the vertex data (about 2048 vertices x 24 bytes, roughly 50 KB). Comfy already reads vertices out of draws elsewhere (lamps, 32 to 128 per draw) and already turns the splash's camera-space positions into world positions on the GPU (`WaterSplashBegin`). A CPU read of one draw per frame is feasible; turning that into a persistent per-area wetness map is the larger part of the job. Needs a Comfy rebuild.

## 7. Indoors, roofs, water (measured with Comfy's F12 probe, `toolsain_probe.ps1` / `rain_count.ps1`)
| Spot | Splash draws | Splash triangles | Streak draws | Streak triangles |
|---|---|---|---|---|
| Open ground | 13 | 77,133 | 12 | 73,389 |
| Under an open roof (covered walkway) | 11 | 67,530 | 10 | 61,426 |
| Inside the inn | **0** | **0** | **0** | **0** |
| Shore, outdoors | 11 | 67,555 | 10 | 61,436 |
- **Indoors the game draws no rain at all** (both counts exactly 0). Under an open roof and at the shore they are still drawn, at about 85 to 88 percent of the open count (one frame each, so that difference may be noise). The draw count is therefore a clean *indoor* signal and **not** a shelter signal.
- Water: the splashes are placed on the ground, including the bed under shallow water. The splash shader already discards splashes whose position is under the map's water level, so terrain and water impacts *can* be separated, but only by position, not by the draw. Rain on water has its own system in Comfy (rings).
- Rain on water has its own system in Comfy (rings), not this texture.

## 8. Approaches compared
| | Reliability | Complexity | Cost | Needs DLL/add-on | Survives client/mod changes |
|---|---|---|---|---|---|
| A. Weather state | high; zone-wide only | done | none | no (bridge exists) | high; fixed client addresses |
| B. Splash draw seen | high; knows rain reaches the ground in view | moderate | one draw check | Comfy source change | medium |
| C. Splash positions | high; per-spot | high | 50 KB/frame read | Comfy source change | medium |
| D. Pixel detection | low | high | readback | no | low |

## 9. Ranking, best to worst
1. **Weather state (type, grade) times the indoor flag, as ReShade uniforms.** Already built. Smallest path: nothing new.
2. **Splash-draw presence, as an "exposed rain" gate** on top of 1, to catch shelter under trees or roofs outdoors.
3. **Splash positions into a local wetness field.** Only if per-spot puddles matter.
4. **Visual detection from the final frame.** Do not.

## 10. Still open (needs rain, hotkeys on, F12 pressed by the user: synthetic F12 did not start the probe)
In rain, with `[general] hotkeys=1` and F12: stand in the open, under a tree, under a roof, at the edge of a roof, inside a building, in a cave, and beside a lake. At each, note whether splash triangles are drawn (Comfy's probe lists `RAIN SPLASHES (N triangles)` lines) and screenshot the ground. This will settle sections 4 and 7.
