// EqShaders/AntiTile.fxh: hides the repetition of tiled ground textures (paths, roads, grass, sand, rock, snow) without blurring them.
// Two parts. (1) Macro variation: on ground-facing surfaces, brightness, saturation and colour temperature vary over tens of yards in
// WORLD space (it does not move with the camera), from procedural noise, so there is no noise texture to tile: three octaves at
// 83/31/13 yards, each rotated by a different angle and offset, and domain-warped so the value-noise cell grid never lines up.
// (2) Far detail: the final sharpening is faded out with distance, so far texture is not pushed into a shimmering repeat.
// Needs the Wet module's world-position helpers (the bridge's camera); without them the macro variation does nothing, on purpose:
// a screen-space version would swim with the camera.

#ifndef EQ_ANTITILE_FXH
#define EQ_ANTITILE_FXH

uniform float AntiTileStrength <
    ui_type = "slider"; ui_category = "Anti-tiling";
    ui_label = "Macro variation";
    ui_tooltip = "World-space brightness / saturation / temperature variation over large ground areas. 1 = about +-8%.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 1.0;
uniform float AntiTileFarDetail <
    ui_type = "slider"; ui_category = "Anti-tiling";
    ui_label = "Fade sharpening with distance";
    ui_tooltip = "How much of the final sharpening is removed on far surfaces (50 to 220 yards). 0 = none.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.7;

#if PW_ENABLE_WET
float2 eq_rot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// about -1..1, no visible period
float eq_macro_noise(float2 xy, float seed)
{
    float2 w = float2(eq_vnoise(eq_rot2(xy, 0.40) / 53.0 + seed + 3.1), eq_vnoise(eq_rot2(xy, 1.90) / 53.0 + seed + 9.7)) - 0.5;
    float2 p = xy + w * 38.0;
    float a = eq_vnoise(eq_rot2(p,  0.38) / 83.0 + seed);
    float b = eq_vnoise(eq_rot2(p, -0.71) / 31.0 + seed * 1.7 + 4.4);
    float c = eq_vnoise(eq_rot2(p,  1.17) / 13.0 + seed * 2.3 + 8.1);
    return (0.52 * a + 0.34 * b + 0.14 * c - 0.5) * 2.0;
}

float3 eq_anti_tile(float3 c, float2 uv, float d)
{
    if (AntiTileStrength <= 0.001 || !eq_bridge_ok()) return c;
    float3 nw = eq_view_to_world_dir(pw_view_normal(uv));
    float ground = smoothstep(0.45, 0.80, nw.z);
    float fade = smoothstep(2.0, 8.0, d) * (1.0 - smoothstep(250.0, 600.0, d));
    float m = ground * fade * AntiTileStrength;
    if (m < 0.002) return c;
    float3 wp = eq_cam_pos() + eq_view_to_world_dir(pw_view_pos(uv, d));
    float nb = eq_macro_noise(wp.xy, 1.0);
    float ns = eq_macro_noise(wp.xy + 211.0, 5.0);
    float nt = eq_macro_noise(wp.xy - 97.0, 9.0);
    float lum = pw_luma(c);
    c *= 1.0 + 0.10 * nb * m;                                          // brightness
    c = lerp(lum.xxx, c, 1.0 + 0.12 * ns * m);                         // saturation
    c *= float3(1.0 + 0.04 * nt * m, 1.0 + 0.01 * nt * m, 1.0 - 0.04 * nt * m);   // warm <-> cool
    return max(c, 0.0);
}

#else
float3 eq_anti_tile(float3 c, float2 uv, float d) { return c; }
#endif

#endif
