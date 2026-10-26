// PhotonWoW/AO.fxh
// GTAO ported from Photon v1.3b include/lighting/ao/gtao.glsl (Jimenez et al. 2016 + Photon's
// multibounce approximation and radius/falloff handling).
//
// Differences from Photon, all forced by the platform:
//  * view normal is rebuilt from depth (Photon reads its G-buffer normal)
//  * no TAA accumulation -> interleaved-gradient-noise + depth-aware bilateral blur instead
//  * radius is in WoW yards (see AO radius); the sky/clear depth is skipped like Photon's depth==1

#ifndef PW_AO_FXH
#define PW_AO_FXH

uniform float AOStrength <
    ui_type = "slider"; ui_category = "Ambient occlusion (GTAO)";
    ui_label = "Strength"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Photon multiplies ambient light by AO and (AO_IN_SUNLIGHT) sunlit light by a reduced AO. A post-process cannot separate the two, so this is one blend.";
> = 0.85;
uniform float AORadius <
    ui_type = "slider"; ui_category = "Ambient occlusion (GTAO)";
    ui_label = "Radius (yards)"; ui_min = 0.1; ui_max = 8.0; ui_step = 0.05;
    ui_tooltip = "Photon GTAO_RADIUS default is 2.0 Minecraft blocks (~metres). WoW yards are 0.91 m.";
> = 2.0;
uniform float AOMaxScreenRadius <
    ui_type = "slider"; ui_category = "Ambient occlusion (GTAO)";
    ui_label = "Max screen radius (fraction of screen height)"; ui_min = 0.02; ui_max = 0.5; ui_step = 0.01;
    ui_tooltip = "Clamps the horizon search near the camera where a world-space radius would cover the whole screen.";
> = 0.12;
uniform float AOBlurSharpness <
    ui_type = "slider"; ui_category = "Ambient occlusion (GTAO)";
    ui_label = "Bilateral blur depth sensitivity"; ui_min = 1.0; ui_max = 100.0; ui_step = 1.0;
> = 30.0;
uniform float AOBrightProtect <
    ui_type = "slider"; ui_category = "Ambient occlusion (GTAO)";
    ui_label = "Reduce AO on bright pixels"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Stand-in for Photon's AO_IN_SUNLIGHT split: bright (sunlit) pixels receive less occlusion.";
> = 0.5;

static const float PW_GTAO_FALLOFF_START = 0.75; // Photon: GTAO_FALLOFF_START

texture PW_AORawTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
texture PW_AOTempTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
texture PW_AOTex     { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler PW_AORaw  { Texture = PW_AORawTex;  AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_AOTemp { Texture = PW_AOTempTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_AOFinal{ Texture = PW_AOTex;     AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

float pw_integrate_arc(float2 h, float n, float cos_n)
{
    float2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n);
    return 0.25 * (tmp.x + tmp.y);
}

float pw_max_horizon_angle(float3 view_slice_dir, float3 viewer_dir, float2 uv, float3 view_pos,
                           float radius, float dither)
{
    float step_size = (AORadius / float(PW_AO_STEPS)) * radius;

    float max_cos_theta = -1.0;

    float2 ray_step = pw_view_to_uv(view_pos + view_slice_dir * step_size) - uv;
    float ray_len = max(length(ray_step), 1e-6);
    // keep the march inside a sane screen-space footprint
    float max_len = AOMaxScreenRadius / float(PW_AO_STEPS);
    ray_step *= min(1.0, max_len / ray_len);
    ray_len = max(length(ray_step), 1e-6);

    float2 ray_pos = uv + ray_step * (dither + max(PW_PIXEL_SIZE.x, PW_PIXEL_SIZE.y) / ray_len);

    [unroll]
    for (int i = 0; i < PW_AO_STEPS; ++i)
    {
        if (ray_pos.x >= 0.0 && ray_pos.x <= 1.0 && ray_pos.y >= 0.0 && ray_pos.y <= 1.0)
        {
            float d = pw_depth_at(ray_pos);
            if (!pw_is_sky(d))
            {
                float3 offset = pw_view_pos(ray_pos, d) - view_pos;
                float len_sq = dot(offset, offset);
                if (len_sq > 1e-8)
                {
                    float inv_len = rsqrt(len_sq);

                    float distance_falloff = pw_linear_step(PW_GTAO_FALLOFF_START * AORadius, AORadius,
                                                            len_sq * inv_len / radius);

                    float cos_theta = dot(viewer_dir, offset) * inv_len;
                    cos_theta = lerp(cos_theta, -1.0, distance_falloff);
                    max_cos_theta = max(cos_theta, max_cos_theta);
                }
            }
        }
        ray_pos += ray_step;
    }

    return acos(clamp(max_cos_theta, -1.0, 1.0));
}

float PS_AO(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float d = pw_depth_at(uv);
    if (pw_is_sky(d)) return 1.0;

    float3 view_pos = pw_view_pos(uv, d);
    float3 view_normal = pw_view_normal(uv);

    float2 dither = float2(pw_ign(pos.xy, 0.0), pw_ign(pos.xy, 1.0));

    // local working space (Photon gtao.glsl)
    float3 viewer_dir = normalize(-view_pos);
    float3 viewer_right = normalize(cross(float3(0.0, 1.0, 0.0), viewer_dir));
    float3 viewer_up = cross(viewer_dir, viewer_right);
    // GLSL mat3(right, up, dir) * v  ==  right*v.x + up*v.y + dir*v.z
    // reduce AO radius very close up (Photon)
    float ao_radius = max(0.25 + 0.75 * smoothstep(0.0, 81.0, dot(view_pos, view_pos)), 0.5);

    float ao = 0.0;

    [unroll]
    for (int i = 0; i < PW_AO_SLICES; ++i)
    {
        float slice_angle = (float(i) + dither.x) * (PW_PI / float(PW_AO_SLICES));

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

        float2 max_horizon_angles;
        max_horizon_angles.x = pw_max_horizon_angle(-view_slice_dir, viewer_dir, uv, view_pos, ao_radius, dither.y);
        max_horizon_angles.y = pw_max_horizon_angle( view_slice_dir, viewer_dir, uv, view_pos, ao_radius, dither.y);

        max_horizon_angles = gamma + clamp(float2(-1.0, 1.0) * max_horizon_angles - gamma, -PW_HALF_PI, PW_HALF_PI);
        ao += pw_integrate_arc(max_horizon_angles, gamma, cos_gamma) * len_sq * inv_norm;
    }

    const float albedo = 0.2; // albedo of surroundings (multibounce approximation, Photon)
    ao /= float(PW_AO_SLICES);
    ao /= albedo * ao + (1.0 - albedo);

    return saturate(ao);
}

// Depth-aware separable blur (9 taps): replaces Photon's temporal accumulation.
float PS_AOBlurH(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dc = pw_depth_at(uv);
    if (pw_is_sky(dc)) return 1.0;
    float sum = 0.0, wsum = 0.0;
    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float2 suv = uv + float2(PW_PIXEL_SIZE.x * float(i), 0.0);
        float ds = pw_depth_at(suv);
        float w = exp(-0.5 * pw_sqr(float(i) / 2.5)) * exp(-AOBlurSharpness * abs(ds - dc) / max(dc, 0.5));
        sum += tex2Dlod(PW_AORaw, float4(suv, 0, 0)).x * w;
        wsum += w;
    }
    return sum / max(wsum, 1e-5);
}

float PS_AOBlurV(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float dc = pw_depth_at(uv);
    if (pw_is_sky(dc)) return 1.0;
    float sum = 0.0, wsum = 0.0;
    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float2 suv = uv + float2(0.0, PW_PIXEL_SIZE.y * float(i));
        float ds = pw_depth_at(suv);
        float w = exp(-0.5 * pw_sqr(float(i) / 2.5)) * exp(-AOBlurSharpness * abs(ds - dc) / max(dc, 0.5));
        sum += tex2Dlod(PW_AOTemp, float4(suv, 0, 0)).x * w;
        wsum += w;
    }
    return sum / max(wsum, 1e-5);
}

float pw_ao_at(float2 uv)
{
    return tex2Dlod(PW_AOFinal, float4(uv, 0, 0)).x;
}

#endif
