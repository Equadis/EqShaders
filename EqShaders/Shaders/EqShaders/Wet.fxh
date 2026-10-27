// EqShaders/Wet.fxh : wet ground and reflective puddles that build up in rain and dry out afterwards.
//
//  stage     : after the lighting pass (SceneLit, linear HDR), before DOF/bloom/tonemap. Reads depth + normals rebuilt from depth,
//              writes SceneWet. SceneLit has mip levels, used as the blurred "environment" for rough reflections.
//  inputs    : Bridge.fxh (camera pose, weather type/grade from the client, biome wetness from EqProfiles).
//  wetness   : a 1x1 state texture (ping-pong A/B) integrates rain over time: ground wetness rises while it rains, puddle fill
//              rises slower, both fall slowly afterwards (puddles last longest). The biome baseline is the floor they dry to.
//  ground    : world-space normal (camera basis from the bridge) must point up; a 3 px vs 1 px normal comparison rejects bumpy
//              foliage; greenish pixels are down-weighted; characters have no flat ground normal and fade out the same way.
//  puddles   : world-anchored low-frequency fbm noise (domain warped, in WoW x,y yards) + a depression term from neighbouring
//              depths (lower than its surroundings = more water). Threshold falls as the puddle fill rises.
//  reflection: view-space ray march against the depth buffer (16 steps, thickness test, edge fade) sampling the lit scene
//              at a roughness-dependent mip; misses fall back to the sky/horizon colour from the top of the screen.
//  ripples   : two layers of jittered world-space ring cells (expanding rings + a tiny splash flash) whose density follows rain.

#ifndef EQ_WET_FXH
#define EQ_WET_FXH

uniform bool WetEnable <
    ui_category = "Wet ground"; ui_label = "Wet ground and puddles";
> = true;
uniform float WetStrength <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Wetness strength";
    ui_tooltip = "How much wet ground darkens and gains sheen at full wetness.";
    ui_min = 0.0; ui_max = 1.5; ui_step = 0.01;
> = 1.0;
uniform float WetPuddleAmount <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Puddle amount";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.6;
uniform float WetPuddleSize <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Puddle size (yards)";
    ui_min = 1.0; ui_max = 15.0; ui_step = 0.1;
> = 4.5;
uniform float WetReflection <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Puddle reflection strength";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float WetRipples <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Puddle ripple strength";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float WetAccumSpeed <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Accumulation speed";
    ui_tooltip = "1 = ground soaked in about 40 s of steady rain, puddles in about 90 s.";
    ui_min = 0.2; ui_max = 4.0; ui_step = 0.01;
> = 1.0;
uniform float WetDrySpeed <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Drying speed";
    ui_tooltip = "1 = ground dries in about 3 minutes, puddles in about 5.";
    ui_min = 0.2; ui_max = 4.0; ui_step = 0.01;
> = 1.0;
uniform int WetQuality <
    ui_type = "combo"; ui_category = "Wet ground"; ui_label = "Reflection quality";
    ui_items = "Low (10 steps)\0Medium (16 steps)\0High (24 steps)\0";
> = 1;

uniform float WetSunSpec <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Sun sheen strength";
    ui_tooltip = "Direct sun specular on wet ground and puddles. The glint is a broad GGX lobe with Fresnel, not a mirror hotspot.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float WetSheenRoughness <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Wet sheen roughness";
    ui_tooltip = "Higher = a wider, softer sun sheen visible from more camera angles.";
    ui_min = 0.15; ui_max = 0.8; ui_step = 0.01;
> = 0.38;
uniform float WetGameplayBias <
    ui_type = "slider"; ui_category = "Wet ground"; ui_label = "Third-person angle bias";
    ui_tooltip = "Gently widens the sheen around typical third-person camera pitches. A smooth bump, not a cutoff. 0 = physical.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.6;
uniform float3 WetSunColor <
    ui_type = "color"; ui_category = "Wet ground"; ui_label = "Sun colour";
> = float3(1.0, 0.86, 0.62);
uniform float WetSunAzimuth <
    ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Sun azimuth (match comfyatmos.ini [sun] azimuth)";
    ui_min = 0.0; ui_max = 360.0; ui_step = 1.0;
> = 45.0;
uniform float WetSunElevation <
    ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Sun elevation (match [sun] elevation)";
    ui_min = 5.0; ui_max = 89.0; ui_step = 1.0;
> = 55.0;
uniform float WetSunAzOffset <
    ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Sun azimuth offset (degrees)";
    ui_min = -180.0; ui_max = 180.0; ui_step = 1.0;
> = 0.0;
uniform float WetSunHandedness <
    ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Sun azimuth handedness (+1 / -1)";
    ui_min = -1.0; ui_max = 1.0; ui_step = 2.0;
> = 1.0;

// --- calibration of the camera matrix convention (set once; see HANDOFF) ---
uniform bool WetAxesColumns <
    ui_category = "Wet ground calibration"; ui_label = "Camera axes are the matrix COLUMNS (off = rows)";
> = false;
uniform int WetAxisRight < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Right axis index"; ui_min = 0; ui_max = 2; > = 1;
uniform int WetAxisUp    < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Up axis index";    ui_min = 0; ui_max = 2; > = 2;
uniform int WetAxisFwd   < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Forward axis index"; ui_min = 0; ui_max = 2; > = 0;
uniform float WetSignRight < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Right sign"; ui_min = -1.0; ui_max = 1.0; ui_step = 2.0; > = -1.0;
uniform float WetSignUp    < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Up sign";    ui_min = -1.0; ui_max = 1.0; ui_step = 2.0; > = 1.0;
uniform float WetSignFwd   < ui_type = "slider"; ui_category = "Wet ground calibration"; ui_label = "Forward sign"; ui_min = -1.0; ui_max = 1.0; ui_step = 2.0; > = 1.0;

uniform float EqTimer < source = "timer"; >;

// ---- state: x = ground wetness, y = puddle fill, z = smoothed rain, w = unused ----
texture PW_WetStateATex { Width = 1; Height = 1; Format = RGBA32F; };
texture PW_WetStateBTex { Width = 1; Height = 1; Format = RGBA32F; };
sampler PW_WetStateA { Texture = PW_WetStateATex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_WetStateB { Texture = PW_WetStateBTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };

float4 PS_WetState(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 s = tex2Dlod(PW_WetStateA, float4(0.5, 0.5, 0, 0));
    if (!eq_bridge_ok()) return s;                       // login screen, loading: freeze the state

    float2 w = eq_weather();
    float rain = (abs(w.x - 1.0) < 0.5 || abs(w.x - 3.0) < 0.5) ? w.y : 0.0;   // rain and storm; snow adds no water
    float3 prof = eq_profile_ok() ? eq_profile_wet() : float3(0.0, 0.0, 0.0);
    float dt = min(frametime * 0.001, 0.1);

    float rs = lerp(s.z, rain, saturate(dt * 0.8));      // follow the client's rain smoothly
    float wet = s.x, pud = s.y;
    if (rs > 0.04)
    {
        wet += (1.0 - wet) * dt * 0.045 * WetAccumSpeed * (0.4 + rs);
        if (rs > 0.2) pud += dt * 0.011 * WetAccumSpeed * rs;
    }
    else
    {
        wet -= dt * 0.0056 * WetDrySpeed;
        pud -= dt * 0.0034 * WetDrySpeed;
    }
    wet = clamp(wet, prof.x, 1.0);
    pud = clamp(pud, prof.y, 1.0);
    pud = min(pud, max(wet, prof.y));                    // puddles never outgrow the wetness
    return float4(wet, pud, rs, 0.0);
}
float4 PS_WetStateCopy(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2Dlod(PW_WetStateB, float4(0.5, 0.5, 0, 0));
}

// ---- camera basis from the bridge ----
float3 eq_axis(int idx)
{
    float3 r0 = eq_cam_row(0), r1 = eq_cam_row(1), r2 = eq_cam_row(2);
    if (WetAxesColumns) return float3(idx == 0 ? r0.x : (idx == 1 ? r0.y : r0.z),
                                      idx == 0 ? r1.x : (idx == 1 ? r1.y : r1.z),
                                      idx == 0 ? r2.x : (idx == 1 ? r2.y : r2.z));
    return idx == 0 ? r0 : (idx == 1 ? r1 : r2);
}
// view space (x right, y up, z toward the camera) -> world direction (WoW: z is up)
float3 eq_view_to_world_dir(float3 v)
{
    return eq_axis(WetAxisRight) * WetSignRight * v.x + eq_axis(WetAxisUp) * WetSignUp * v.y + eq_axis(WetAxisFwd) * WetSignFwd * (-v.z);
}
float3 eq_world_to_view_dir(float3 w)
{
    return float3(dot(w, eq_axis(WetAxisRight) * WetSignRight), dot(w, eq_axis(WetAxisUp) * WetSignUp), -dot(w, eq_axis(WetAxisFwd) * WetSignFwd));
}

// normal from depth with a selectable pixel step (the stock one uses 1 px)
float3 eq_normal_step(float2 uv, float k)
{
    float2 px = PW_PIXEL_SIZE * k;
    float dc = pw_depth_at(uv);
    float dl = pw_depth_at(uv - float2(px.x, 0.0)), dr = pw_depth_at(uv + float2(px.x, 0.0));
    float du = pw_depth_at(uv - float2(0.0, px.y)), dd = pw_depth_at(uv + float2(0.0, px.y));
    float3 pc = pw_view_pos(uv, dc);
    float3 dx = (abs(dr - dc) < abs(dl - dc)) ? pw_view_pos(uv + float2(px.x, 0.0), dr) - pc : pc - pw_view_pos(uv - float2(px.x, 0.0), dl);
    float3 dy = (abs(dd - dc) < abs(du - dc)) ? pw_view_pos(uv + float2(0.0, px.y), dd) - pc : pc - pw_view_pos(uv - float2(0.0, px.y), du);
    return normalize(cross(dy, dx));
}

// ---- noise ----
float eq_hash(float2 p)
{
    p = frac(p * float2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return frac((p.x + p.y) * p.x);
}
float eq_vnoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(eq_hash(i), eq_hash(i + float2(1, 0)), f.x), lerp(eq_hash(i + float2(0, 1)), eq_hash(i + float2(1, 1)), f.x), f.y);
}
float eq_fbm(float2 p)
{
    p += 0.45 * (float2(eq_vnoise(p * 0.7 + 11.0), eq_vnoise(p * 0.7 + 37.0)) - 0.5);   // domain warp: no blobs
    return 0.55 * eq_vnoise(p) + 0.28 * eq_vnoise(p * 2.13 + 5.0) + 0.17 * eq_vnoise(p * 4.7 + 9.0);
}

// rain rings on a world-space grid: returns the horizontal normal offset, splash flash in z
float3 eq_ripples(float2 xy, float t, float rain)
{
    float3 acc = float3(0.0, 0.0, 0.0);
    [unroll]
    for (int layer = 0; layer < 2; ++layer)
    {
        float2 q = xy * (1.7 + 0.9 * float(layer)) + float(layer) * 7.3;
        float2 cell = floor(q);
        float h = eq_hash(cell);
        float h2 = eq_hash(cell + 17.1);
        float act = step(h2, saturate(rain * 1.1));
        float age = frac(t * (0.75 + 0.35 * h) + h * 5.0);
        float2 centre = cell + 0.25 + 0.5 * float2(eq_hash(cell + 3.7), eq_hash(cell + 9.1));
        float2 d = q - centre;
        float r = length(d) / (1.7 + 0.9 * float(layer));          // yards
        float radius = age * 0.42;
        float ring = sin((r - radius) * 70.0) * exp(-pow((r - radius) * 16.0, 2.0)) * pow(1.0 - age, 2.0);
        float2 dir = d / max(length(d), 1e-4);
        acc.xy += dir * ring * act;
        acc.z += act * smoothstep(0.035, 0.0, r) * saturate(1.0 - age * 9.0);   // brief splash dot at the start
    }
    return acc;
}

// ---- sun specular ----
// sun direction in WoW world axes (z up) from azimuth/elevation; az offset and handedness are calibration for Comfy's convention
float3 eq_sun_dir_world()
{
    float az = radians(WetSunAzimuth + WetSunAzOffset);
    float el = radians(WetSunElevation);
    return normalize(float3(cos(el) * cos(az), WetSunHandedness * cos(el) * sin(az), sin(el)));
}

// gradient of a two-octave value noise in world xy (yards): the surface "grain" that lets small facets catch the sun
float2 eq_micro_grad(float2 xy)
{
    float e = 0.07;
    float f0 = eq_vnoise(xy * 3.7 + 21.0) * 0.6 + eq_vnoise(xy * 9.3 + 5.0) * 0.4;
    float fx = eq_vnoise((xy + float2(e, 0.0)) * 3.7 + 21.0) * 0.6 + eq_vnoise((xy + float2(e, 0.0)) * 9.3 + 5.0) * 0.4;
    float fy = eq_vnoise((xy + float2(0.0, e)) * 3.7 + 21.0) * 0.6 + eq_vnoise((xy + float2(0.0, e)) * 9.3 + 5.0) * 0.4;
    return -float2(fx - f0, fy - f0) / e;
}

// GGX specular * N.L for unit N, V (to camera), L (to sun), all in the same space. F0 for dielectrics (water 0.02, wet ground 0.04).
float eq_ggx(float3 N, float3 V, float3 L, float a, float F0, out float NoL)
{
    a = max(a, 0.05);
    float3 H = normalize(L + V);
    NoL = saturate(dot(N, L));
    float NoV = saturate(dot(N, V));
    float NoH = saturate(dot(N, H));
    float VoH = saturate(dot(V, H));
    float a2 = a * a;
    float dd = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (3.14159265 * dd * dd + 1e-5);
    float k = a * 0.5;
    float vis = 0.25 / ((NoL * (1.0 - k) + k) * (NoV * (1.0 - k) + k) + 1e-4);   // Schlick-GGX visibility
    float F = F0 + (1.0 - F0) * pow(1.0 - VoH, 5.0);
    return min(D * vis * F * NoL, 30.0);
}

// ---- reflections ----
float3 eq_sky_env(float3 r_view, float lod)
{
    // far point along the reflected ray; if it lands on screen use that pixel, else the sky at the top of the frame
    float3 fpt = r_view * 2000.0;
    float2 uvf = pw_view_to_uv(fpt);
    float2 top = float2(saturate(uvf.x), 0.04);
    float3 sky = tex2Dlod(PW_SceneLitSampler, float4(top, 0, 4.0)).rgb;
    if (fpt.z < -1.0 && uvf.x > 0.0 && uvf.x < 1.0 && uvf.y > 0.0 && uvf.y < 1.0)
        sky = lerp(sky, tex2Dlod(PW_SceneLitSampler, float4(uvf, 0, lod)).rgb, 0.7);
    return sky;
}

float3 eq_trace(float3 p, float3 r, float rough, float dither, out float conf)
{
    conf = 0.0;
    int steps = (WetQuality == 0) ? 10 : ((WetQuality == 1) ? 16 : 24);
    float maxd = 40.0;
    float stepl = maxd / float(steps);
    float t = stepl * (0.4 + 0.8 * dither);
    float tprev = 0.0;
    bool hit = false;
    float2 uvh = float2(0.0, 0.0);
    if (r.z < -0.02)
    {
        [loop]
        for (int i = 0; i < 24; ++i)
        {
            if (i >= steps) break;
            float3 q = p + r * t;
            if (q.z > -0.2) break;
            float2 uvq = pw_view_to_uv(q);
            if (uvq.x < 0.0 || uvq.x > 1.0 || uvq.y < 0.0 || uvq.y > 1.0) break;
            float sd = pw_depth_at(uvq);
            float diff = (-q.z) - sd;
            if (diff > 0.0 && diff < 0.6 + 0.12 * t)
            {
                float tm = 0.5 * (t + tprev);
                uvh = pw_view_to_uv(p + r * tm);
                hit = true;
                break;
            }
            tprev = t;
            t += stepl * (1.0 + 0.06 * float(i));
        }
    }
    float3 col;
    if (hit)
    {
        float2 e = min(uvh, 1.0 - uvh);
        conf = smoothstep(0.0, 0.07, min(e.x, e.y)) * saturate(1.0 - tprev / maxd * 0.6);
        col = tex2Dlod(PW_SceneLitSampler, float4(uvh, 0, rough * 3.5)).rgb;
        if (pw_is_sky(pw_depth_at(uvh))) conf *= 0.9;
    }
    else col = float3(0.0, 0.0, 0.0);
    float3 env = eq_sky_env(r, 2.0 + rough * 2.5);
    return lerp(env, col, conf);
}

// ground / puddle masks used by the main pass and the debug views
struct EqWetMasks { float ground; float wet; float puddle; float3 pw; float3 nw; float depress; float noise; };

EqWetMasks eq_wet_masks(float2 uv, float d, float4 st, float3 scene_rgb)
{
    EqWetMasks m;
    float3 pv = pw_view_pos(uv, d);
    float3 n1 = pw_view_normal(uv);
    float3 n3 = eq_normal_step(uv, 3.0);
    float3 nw = eq_view_to_world_dir(n1);
    float up = nw.z;
    float smoothN = smoothstep(0.80, 0.94, dot(n1, n3));
    float lum = max(pw_luma(scene_rgb), 1e-4);
    float3 chroma = scene_rgb / lum;
    float plant = saturate((chroma.g - max(chroma.r, chroma.b) - 0.02) * 5.0) * smoothstep(0.03, 0.2, lum);
    float distFade = 1.0 - smoothstep(55.0, 120.0, d);
    m.ground = smoothstep(0.60, 0.86, up) * smoothN * distFade * (1.0 - 0.55 * plant);

    float3 wp = eq_cam_pos() + eq_view_to_world_dir(float3(pv.x, pv.y, pv.z));
    m.pw = wp; m.nw = nw;

    // depression: how much higher the surroundings are than this point (world z), 6 taps at ~1.4 yd
    float rpx = clamp(1.4 * 0.5 * float(BUFFER_HEIGHT) / (pw_tan_half_fov().y * d), 3.0, 40.0);
    float dep = 0.0, cnt = 0.0;
    [unroll]
    for (int k = 0; k < 6; ++k)
    {
        float a = float(k) * 1.0472;
        float2 suv = uv + float2(cos(a), sin(a)) * rpx * PW_PIXEL_SIZE;
        float sd = pw_depth_at(suv);
        if (!pw_is_sky(sd) && abs(sd - d) < 2.5)
        {
            float3 dp = eq_view_to_world_dir(pw_view_pos(suv, sd) - pv);
            dep += dp.z; cnt += 1.0;
        }
    }
    dep = (cnt > 0.0) ? dep / cnt : 0.0;
    m.depress = saturate(dep / 0.12);

    float n = eq_fbm(wp.xy / max(WetPuddleSize, 0.5));
    m.noise = n;
    float field = n + 0.28 * m.depress - 0.10 * (1.0 - smoothstep(0.88, 0.99, up));
    float th = 1.0 - saturate(st.y * (0.3 + 1.1 * WetPuddleAmount));
    m.puddle = smoothstep(th - 0.06, th + 0.06, field) * smoothstep(0.90, 0.985, up) * smoothN * distFade * (1.0 - plant);
    // damp -> wet -> puddle: the wet sheen follows the same field loosely, so edges are gradual
    float damp = saturate(st.x * WetStrength * (0.75 + 0.5 * eq_fbm(wp.xy * 0.35 + 3.0)));
    m.wet = m.ground * damp;
    m.puddle *= saturate(st.x * 1.5);
    return m;
}

float4 PS_Wet(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 scene = tex2Dlod(PW_SceneLitSampler, float4(uv, 0, 0));
    if (!WetEnable || !eq_bridge_ok() || eq_indoor()) return scene;
    float4 st = tex2Dlod(PW_WetStateA, float4(0.5, 0.5, 0, 0));
    if (st.x < 0.004) return scene;
    float d = pw_depth_at(uv);
    if (pw_is_sky(d) || d > 150.0) return scene;

    EqWetMasks m = eq_wet_masks(uv, d, st, scene.rgb);
    if (m.wet < 0.003 && m.puddle < 0.003) return scene;

    float3 c = scene.rgb;
    float soak = m.wet;
    // same material, soaked: darker, a little richer (water in the pores), texture untouched
    c *= lerp(1.0, 0.60, soak);
    float lum = pw_luma(c);
    c = lerp(lum.xxx, c, 1.0 + 0.30 * soak);

    float3 pv = pw_view_pos(uv, d);
    float3 v = normalize(pv);                              // camera -> point (view space, unit)
    float3 nv = pw_view_normal(uv);                        // unit, facing the camera
    float3 vv = -v;                                        // point -> camera

    // Everything below is in VIEW space with unit vectors: the sun comes in as a world direction and is converted with the
    // same camera basis as the normals, so N, V, L and H are all in one space.
    float3 Lv = normalize(eq_world_to_view_dir(eq_sun_dir_world()));

    // wet terrain micro-normals: low-strength, world-anchored, so neighbouring fragments catch the sun differently
    float3 nwm = normalize(m.nw + float3(eq_micro_grad(m.pw.xy) * (0.10 * soak), 0.0));
    float3 nvm = normalize(eq_world_to_view_dir(nwm));
    float NoVm = saturate(dot(nvm, vv));

    // roughness: broad by default, widened a little around the common third-person pitch by a smooth bump (no thresholds)
    float widen = 1.0 + WetGameplayBias * 0.9 * exp(-pow((NoVm - 0.42) / 0.28, 2.0));
    float a_sheen = clamp(WetSheenRoughness * widen, 0.08, 0.9);

    // direct sun: GGX lobe with Schlick-Fresnel on V.H (rises smoothly toward grazing), faded in shade by scene brightness
    float sunLit = smoothstep(0.35, 1.3, pw_luma(scene.rgb));
    float NoL_s;
    float spec = eq_ggx(nvm, vv, Lv, a_sheen, 0.04, NoL_s);
    c += WetSunColor * spec * 3.5 * WetSunSpec * soak * (1.0 - m.puddle) * sunLit;

    // environment: roughness-aware Fresnel on N.V (never loses reflectivity at grazing angles), kept weaker than the sun
    float fenv = 0.04 + (max(1.0 - a_sheen, 0.04) - 0.04) * pow(1.0 - NoVm, 5.0);
    float3 rv = reflect(v, nvm);
    float3 sheen = eq_sky_env(rv, 2.0 + 3.0 * a_sheen);
    c += sheen * fenv * soak * 0.40 * WetReflection * (1.0 - m.puddle) * (1.0 + 0.35 * (eq_vnoise(float2(m.pw.x * 0.41 + m.pw.y * 0.17, m.pw.y * 0.43 - m.pw.x * 0.19) + 57.0) * 2.0 - 1.0));   // spread over ~2 yards, off-axis: repeats do not glint alike

    if (m.puddle > 0.004)
    {
        float pm = m.puddle;
        float rain = st.z;
        float3 rip = eq_ripples(m.pw.xy, EqTimer * 0.001, rain) * WetRipples;
        // distort the normal in world space: ripples + a little fine wobble so it is not a perfect mirror
        float wob = (eq_vnoise(m.pw.xy * 9.0 + EqTimer * 0.0004) - 0.5) * 0.05;
        float3 nwd = normalize(float3(rip.x * 0.35 + wob, rip.y * 0.35 - wob, 1.0));
        float3 nvd = normalize(eq_world_to_view_dir(nwd));
        float3 rp = reflect(v, nvd);
        float conf;
        float dither = pw_ign(pos.xy, float(framecount));
        float3 refl = eq_trace(pv, rp, 0.12, dither, conf);
        float NoVp = saturate(dot(nvd, -v));
        float fp = 0.06 + 0.94 * pow(1.0 - NoVp, 5.0);
        float rs = saturate((0.30 + 0.70 * fp) * WetReflection);
        // water over dirt: darker base with a murky tint, darker edge ring, then the reflection on top
        float murk = eq_profile_ok() ? eq_profile_wet().z : 0.0;
        float edge = pm * (1.0 - pm) * 4.0;
        c *= lerp(1.0, 0.70 - 0.2 * murk, pm);
        c *= 1.0 - 0.25 * edge * soak;
        c = lerp(c, refl, saturate(rs * pm * 0.9));
        // sun glint on the puddle: a tighter lobe than the damp sheen, but still widened at typical pitches, on the rippled normal
        float widen_p = 1.0 + WetGameplayBias * 0.8 * exp(-pow((NoVp - 0.42) / 0.28, 2.0));
        float a_pud = clamp(0.11 * widen_p, 0.06, 0.4);
        float NoL_p;
        float spec_p = eq_ggx(nvd, vv, Lv, a_pud, 0.02, NoL_p);
        c += WetSunColor * spec_p * 5.0 * WetSunSpec * WetReflection * pm * sunLit;
        c += float3(1.0, 1.0, 1.0) * rip.z * pm * rain * 0.9 * WetRipples * 3.0;     // splash flash (HDR white)
    }
    return float4(c, scene.a);
}

float3 eq_wet_debug(float2 uv, int mode)
{
    float d = pw_depth_at(uv);
    float4 st = tex2Dlod(PW_WetStateA, float4(0.5, 0.5, 0, 0));
    if (mode == 22)
    {
        // bridge state strip: green bridge ok, blue profile ok, red = rain, yellow = wetness, cyan = puddle fill
        float2 w = eq_weather();
        if (uv.y < 0.1) return float3(eq_bridge_ok() ? 0.1 : 0.9, eq_bridge_ok() ? 0.8 : 0.1, 0.1);
        if (uv.y < 0.2) return eq_profile_ok() ? float3(0.1, 0.2, 0.9) : float3(0.3, 0.3, 0.3);
        if (uv.y < 0.3) return float3(1.0, 0.0, 0.0) * (w.x * 0.33 + 0.1) * (uv.x < w.y ? 1.0 : 0.15);
        if (uv.y < 0.4) return float3(1.0, 1.0, 0.0) * (uv.x < st.x ? 1.0 : 0.15);
        if (uv.y < 0.5) return float3(0.0, 1.0, 1.0) * (uv.x < st.y ? 1.0 : 0.15);
        return tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb * 0.5;
    }
    if (pw_is_sky(d) || !eq_bridge_ok()) return float3(0.0, 0.0, 0.0);
    float3 scene = tex2Dlod(PW_SceneLitSampler, float4(uv, 0, 0)).rgb;
    EqWetMasks m = eq_wet_masks(uv, d, float4(1.0, 1.0, 1.0, 0.0), scene);
    if (mode == 19) return m.ground.xxx;
    if (mode == 20) return m.puddle.xxx;
    if (mode == 21) return frac(m.pw * 0.25);
    return float3(m.nw * 0.5 + 0.5);                     // 23: world-space normal
}

#endif
