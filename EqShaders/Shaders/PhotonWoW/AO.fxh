// PhotonWoW/AO.fxh
// Two-scale GTAO (Jimenez et al. 2016, with Photon v1.3b's multibounce approximation): a SHORT-range "contact" term and a
// MEDIUM-range "broad" term are integrated in one pass from the same slice directions, so crevices, the ground under feet,
// rocks and trunks get a hard dark contact line while corners and canopies get a softer, wider occlusion.
//
//   buffers  : linearised depth (PW_DepthLinTex). The view-space normal is rebuilt from depth (WoW gives us no G-buffer).
//   runs at  : after Prep, before fog/bloom/tonemap, on the linear HDR scene (so AO darkens the light, not the final picture)
//   denoise  : spatial depth-aware blur (9 taps x2) + a depth-gated temporal accumulate that only blends history where the
//              same surface is still at the same pixel (camera and object static); history is rejected the moment anything moves
//   rejected : sky (no AO, and sky taps are never occluders), distance fade, thickness (nearer occluders are ignored so no halo
//              round characters), screen-edge clamp, depth-discontinuity-aware blur
//
// No world-space or camera-angle terms anywhere: everything is view-space, so the result cannot change at a particular yaw.

#ifndef PW_AO_FXH
#define PW_AO_FXH

#ifndef PW_AO_QUALITY
    #define PW_AO_QUALITY 1          // 0 low, 1 medium (default), 2 high; set in the global preprocessor definitions
#endif
#if PW_AO_QUALITY == 0
    #define PW_AO_SL   2
    #define PW_AO_ST_W 3
    #define PW_AO_ST_C 2
#elif PW_AO_QUALITY == 2
    #define PW_AO_SL   3
    #define PW_AO_ST_W 6
    #define PW_AO_ST_C 4
#else
    #define PW_AO_SL   2
    #define PW_AO_ST_W 4
    #define PW_AO_ST_C 3
#endif

uniform float AOStrength <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Strength (broad)"; ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
    ui_tooltip = "Exponent on the medium-range occlusion: 1 = plain AO, 2 = AO squared (much darker corners and canopy shade).";
> = 1.3;
uniform float AOContact <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Contact strength"; ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
    ui_tooltip = "Exponent on the short-range occlusion: the dark line where objects meet the ground and in creases.";
> = 1.8;
uniform float AORadius <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Radius (yards)"; ui_min = 0.5; ui_max = 8.0; ui_step = 0.05;
    ui_tooltip = "Reach of the broad term. WoW yards are 0.91 m.";
> = 3.0;
uniform float AODistance <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Fade distance (yards)"; ui_min = 10.0; ui_max = 300.0; ui_step = 1.0;
    ui_tooltip = "AO fades out between 60% and 100% of this distance.";
> = 90.0;
uniform float AOContactRadius <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Contact radius (yards)"; ui_min = 0.1; ui_max = 2.0; ui_step = 0.05;
> = 0.7;
uniform float AOThickness <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Thickness (share of the radius)"; ui_min = 0.1; ui_max = 2.0; ui_step = 0.01;
    ui_tooltip = "A sample nearer the camera than the surface by more than this share of the AO radius does not shade it. Stops dark halos on the ground and walls behind characters, crates and trees.";
> = 0.35;
uniform float AOEdgeReject <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Silhouette rejection"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Fades AO out on pixels at a strong depth jump (object outlines), where reconstructed normals are wrong and AO turns into a dark outline.";
> = 0.85;
uniform float AONearFade <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Near-camera fade (yards)"; ui_min = 0.5; ui_max = 20.0; ui_step = 0.1;
    ui_tooltip = "AO fades in between 35% and 100% of this distance from the camera, so a character or crate right in front of the camera does not get dirty self-occlusion.";
> = 6.0;
uniform bool AOTemporal <
    ui_category = "Ambient occlusion";
    ui_label = "Temporal denoise (only where nothing moves)";
    ui_tooltip = "Off by default: with no motion vectors, any history can leave ghosts. Spatial denoise only.";
> = false;
uniform float AOMaxScreenRadius <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Max screen radius (fraction of screen height)"; ui_min = 0.02; ui_max = 0.5; ui_step = 0.01;
    ui_tooltip = "Clamps the horizon search near the camera where a world-space radius would cover the whole screen.";
> = 0.12;
uniform float AOBlurSharpness <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Blur depth sensitivity"; ui_min = 1.0; ui_max = 100.0; ui_step = 1.0;
> = 30.0;
uniform float AOBrightProtect <
    ui_type = "slider"; ui_category = "Ambient occlusion";
    ui_label = "Less AO on bright (sunlit) pixels"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "A post effect cannot split ambient from sunlight, so lit pixels are given a smaller AO exponent. Lower = deeper shade in sunlight too.";
> = 0.3;

static const float PW_GTAO_FALLOFF_START = 0.75; // Photon: GTAO_FALLOFF_START

texture PW_AORawTex   { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };   // x contact, y broad
texture PW_AOTempTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
texture PW_AOTex      { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };   // spatially denoised
texture PW_AOFinalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; }; // + temporal; z = stability
texture PW_AOHistTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture PW_DepthHistTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; };
sampler PW_AORaw    { Texture = PW_AORawTex;   AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_AOTemp   { Texture = PW_AOTempTex;  AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_AOBlur   { Texture = PW_AOTex;      AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_AOFinal  { Texture = PW_AOFinalTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };
sampler PW_AOHist   { Texture = PW_AOHistTex;  AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_DepthHist{ Texture = PW_DepthHistTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };

float pw_integrate_arc(float2 h, float n, float cos_n)
{
    float2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n);
    return 0.25 * (tmp.x + tmp.y);
}

// One horizon search along +-slice direction; R in yards. `d0` = this pixel's linear depth.
float pw_horizon_wide(float3 view_slice_dir, float3 viewer_dir, float2 uv, float3 view_pos, float d0, float R, float dither)
{
    float step_size = R / float(PW_AO_ST_W);
    float max_cos_theta = -1.0;

    float2 ray_step = pw_view_to_uv(view_pos + view_slice_dir * step_size) - uv;
    float ray_len = max(length(ray_step), 1e-6);
    ray_step *= min(1.0, (AOMaxScreenRadius / float(PW_AO_ST_W)) / ray_len);
    ray_len = max(length(ray_step), 1e-6);
    float2 ray_pos = uv + ray_step * (dither + max(PW_PIXEL_SIZE.x, PW_PIXEL_SIZE.y) / ray_len);

    [unroll]
    for (int i = 0; i < PW_AO_ST_W; ++i)
    {
        if (ray_pos.x >= 0.0 && ray_pos.x <= 1.0 && ray_pos.y >= 0.0 && ray_pos.y <= 1.0)
        {
            float ds = pw_depth_at(ray_pos);
            if (!pw_is_sky(ds))
            {
                float3 offset = pw_view_pos(ray_pos, ds) - view_pos;
                float len_sq = dot(offset, offset);
                if (len_sq > 1e-8)
                {
                    float inv_len = rsqrt(len_sq);
                    float falloff = pw_linear_step(PW_GTAO_FALLOFF_START * R, R, len_sq * inv_len);
                    float thick = 1.0 - smoothstep(AOThickness * R, AOThickness * R * 2.2, d0 - ds); // ds nearer the camera than us, relative to the radius
                    float cos_theta = lerp(dot(viewer_dir, offset) * inv_len, -1.0, max(falloff, 1.0 - thick));
                    max_cos_theta = max(cos_theta, max_cos_theta);
                }
            }
        }
        ray_pos += ray_step;
    }
    return acos(clamp(max_cos_theta, -1.0, 1.0));
}

float pw_horizon_contact(float3 view_slice_dir, float3 viewer_dir, float2 uv, float3 view_pos, float d0, float R, float dither)
{
    float step_size = R / float(PW_AO_ST_C);
    float max_cos_theta = -1.0;

    float2 ray_step = pw_view_to_uv(view_pos + view_slice_dir * step_size) - uv;
    float ray_len = max(length(ray_step), 1e-6);
    ray_step *= min(1.0, (AOMaxScreenRadius / float(PW_AO_ST_C)) / ray_len);
    ray_len = max(length(ray_step), 1e-6);
    float2 ray_pos = uv + ray_step * (dither + max(PW_PIXEL_SIZE.x, PW_PIXEL_SIZE.y) / ray_len);

    [unroll]
    for (int i = 0; i < PW_AO_ST_C; ++i)
    {
        if (ray_pos.x >= 0.0 && ray_pos.x <= 1.0 && ray_pos.y >= 0.0 && ray_pos.y <= 1.0)
        {
            float ds = pw_depth_at(ray_pos);
            if (!pw_is_sky(ds))
            {
                float3 offset = pw_view_pos(ray_pos, ds) - view_pos;
                float len_sq = dot(offset, offset);
                if (len_sq > 1e-8)
                {
                    float inv_len = rsqrt(len_sq);
                    float falloff = pw_linear_step(PW_GTAO_FALLOFF_START * R, R, len_sq * inv_len);
                    float thick = 1.0 - smoothstep(AOThickness * R, AOThickness * R * 2.2, d0 - ds);
                    float cos_theta = lerp(dot(viewer_dir, offset) * inv_len, -1.0, max(falloff, 1.0 - thick));
                    max_cos_theta = max(cos_theta, max_cos_theta);
                }
            }
        }
        ray_pos += ray_step;
    }
    return acos(clamp(max_cos_theta, -1.0, 1.0));
}

float2 PS_AO(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float d = pw_depth_at(uv);
    if (pw_is_sky(d)) return float2(1.0, 1.0);

    float3 view_pos = pw_view_pos(uv, d);
    float3 view_normal = pw_view_normal(uv);

    // static per-pixel noise; it is rotated frame to frame only where last frame's history says this pixel is stable,
    // so a moving camera never sees a flickering pattern
    float stable = AOTemporal ? tex2Dlod(PW_AOHist, float4(uv, 0, 0)).z : 0.0;
    float jitter = (stable > 0.5) ? float(framecount % 8) * 3.1 : 0.0;
    float2 dither = float2(pw_ign(pos.xy, jitter), pw_ign(pos.xy, jitter + 1.0));

    float3 viewer_dir = normalize(-view_pos);
    float3 viewer_right = normalize(cross(float3(0.0, 1.0, 0.0), viewer_dir));
    float3 viewer_up = cross(viewer_dir, viewer_right);

    float near_scale = saturate(d / 12.0);
    float r_wide = AORadius * lerp(0.5, 1.0, near_scale);
    float r_contact = AOContactRadius * lerp(0.6, 1.0, near_scale);

    float2 ao = 0.0;

    [unroll]
    for (int i = 0; i < PW_AO_SL; ++i)
    {
        float slice_angle = (float(i) + dither.x) * (PW_PI / float(PW_AO_SL));
        float3 slice_dir = float3(cos(slice_angle), sin(slice_angle), 0.0);
        float3 view_slice_dir = viewer_right * slice_dir.x + viewer_up * slice_dir.y + viewer_dir * slice_dir.z;

        float3 ortho_dir = slice_dir - dot(slice_dir, viewer_dir) * viewer_dir;
        float3 axis = cross(slice_dir, viewer_dir);
        float3 projected_normal = view_normal - axis * dot(view_normal, axis);

        float len_sq = max(dot(projected_normal, projected_normal), 1e-8);
        float inv_norm = rsqrt(len_sq);
        float sgn_gamma = sign(dot(ortho_dir, projected_normal));
        float cos_gamma = saturate(dot(projected_normal, viewer_dir) * inv_norm);
        float gamma = sgn_gamma * acos(cos_gamma);

        float2 hw, hc;
        hw.x = pw_horizon_wide(-view_slice_dir, viewer_dir, uv, view_pos, d, r_wide, dither.y);
        hw.y = pw_horizon_wide( view_slice_dir, viewer_dir, uv, view_pos, d, r_wide, dither.y);
        hc.x = pw_horizon_contact(-view_slice_dir, viewer_dir, uv, view_pos, d, r_contact, dither.y);
        hc.y = pw_horizon_contact( view_slice_dir, viewer_dir, uv, view_pos, d, r_contact, dither.y);

        hw = gamma + clamp(float2(-1.0, 1.0) * hw - gamma, -PW_HALF_PI, PW_HALF_PI);
        hc = gamma + clamp(float2(-1.0, 1.0) * hc - gamma, -PW_HALF_PI, PW_HALF_PI);
        ao.y += pw_integrate_arc(hw, gamma, cos_gamma) * len_sq * inv_norm;
        ao.x += pw_integrate_arc(hc, gamma, cos_gamma) * len_sq * inv_norm;
    }

    const float albedo = 0.2; // albedo of surroundings (multibounce approximation, Photon)
    ao /= float(PW_AO_SL);
    ao /= albedo * ao + (1.0 - albedo);

    // outlines: at a strong depth jump the one-sided normal is wrong and AO becomes a dark rim; fade it out
    float2 px = PW_PIXEL_SIZE;
    float jump = max(max(abs(pw_depth_at(uv + float2(px.x, 0.0)) - d), abs(pw_depth_at(uv - float2(px.x, 0.0)) - d)),
                     max(abs(pw_depth_at(uv + float2(0.0, px.y)) - d), abs(pw_depth_at(uv - float2(0.0, px.y)) - d))) / max(d, 0.5);
    float keep = 1.0 - AOEdgeReject * smoothstep(0.035, 0.14, jump);
    // right in front of the camera (a character in close third person, a crate): no AO
    keep *= smoothstep(0.35 * AONearFade, AONearFade, d);
    return saturate(lerp(float2(1.0, 1.0), ao, keep));
}

// Depth-aware separable blur (9 taps) on both channels; the temporal pass below handles what is left.
float2 PS_AOBlurH(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dc = pw_depth_at(uv);
    if (pw_is_sky(dc)) return float2(1.0, 1.0);
    float2 sum = 0.0; float wsum = 0.0;
    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float2 suv = uv + float2(PW_PIXEL_SIZE.x * float(i), 0.0);
        float ds = pw_depth_at(suv);
        float w = exp(-0.5 * pw_sqr(float(i) / 2.5)) * exp(-AOBlurSharpness * abs(ds - dc) / max(dc, 0.5));
        sum += tex2Dlod(PW_AORaw, float4(suv, 0, 0)).xy * w;
        wsum += w;
    }
    return sum / max(wsum, 1e-5);
}

float2 PS_AOBlurV(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dc = pw_depth_at(uv);
    if (pw_is_sky(dc)) return float2(1.0, 1.0);
    float2 sum = 0.0; float wsum = 0.0;
    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float2 suv = uv + float2(0.0, PW_PIXEL_SIZE.y * float(i));
        float ds = pw_depth_at(suv);
        float w = exp(-0.5 * pw_sqr(float(i) / 2.5)) * exp(-AOBlurSharpness * abs(ds - dc) / max(dc, 0.5));
        sum += tex2Dlod(PW_AOTemp, float4(suv, 0, 0)).xy * w;
        wsum += w;
    }
    return sum / max(wsum, 1e-5);
}

// Temporal accumulate, gated: history is only used where the same surface sits at the same pixel as last frame, and it is
// dropped when it disagrees with the current estimate. There is no reprojection (no camera pose), so it never smears.
float4 PS_AOTemporal(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 cur = tex2Dlod(PW_AOBlur, float4(uv, 0, 0)).xy;
    if (!AOTemporal) return float4(cur, 0.0, 1.0);

    float d = pw_depth_at(uv);
    if (pw_is_sky(d)) return float4(1.0, 1.0, 0.0, 1.0);
    float dh = tex2Dlod(PW_DepthHist, float4(uv, 0, 0)).x;
    float4 h = tex2Dlod(PW_AOHist, float4(uv, 0, 0));

    float valid = (abs(d - dh) / max(d, 0.5) < 0.0025) ? 1.0 : 0.0;
    float diff = max(abs(cur.x - h.x), abs(cur.y - h.y));
    valid *= 1.0 - smoothstep(0.10, 0.28, diff);

    float conf = valid * min(h.z + 0.125, 1.0);
    float2 res = lerp(cur, h.xy, valid * 0.8 * saturate(conf * 2.0));
    return float4(res, conf, 1.0);
}

float4 PS_AOHistAO(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2Dlod(PW_AOFinal, float4(uv, 0, 0));
}

float PS_AOHistDepth(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return pw_depth_at(uv);
}

// x = contact AO, y = broad AO (1 = open, 0 = fully occluded), already faded with distance
float2 pw_ao_at(float2 uv)
{
    float2 ao = tex2Dlod(PW_AOFinal, float4(uv, 0, 0)).xy;
    float fade = 1.0 - smoothstep(AODistance * 0.6, AODistance, pw_depth_at(uv));
    return lerp(float2(1.0, 1.0), ao, fade);
}

// the factor applied to a pixel of luminance `lum` (HDR linear)
float pw_ao_factor(float2 uv, float lum)
{
    float2 ao = pw_ao_at(uv);
    float prot = 1.0 - AOBrightProtect * smoothstep(0.5, 3.0, lum);
    return pow(max(ao.y, 1e-3), AOStrength * prot) * pow(max(ao.x, 1e-3), AOContact * prot);
}

#endif
