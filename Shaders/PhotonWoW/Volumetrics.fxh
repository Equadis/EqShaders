// PhotonWoW/Volumetrics.fxh
// Screen-space light shafts. This is NOT Photon's c0_vl (which raymarches the view ray through
// the shadow map). It is the classic radial-blur crepuscular-ray approximation:
//   * occluder mask  = bright sky pixels (sun disc / lit cloud) from the HDR scene
//   * march toward the projected sun position, accumulate with decay
//   * weighted by Photon's two-lobe Henyey-Greenstein phase against the manual sun direction
// Limits: needs the sun in front of the camera and on screen (or just off it); cannot be shadowed by
// geometry that is not in the depth buffer; UI elements share the "sky" depth and may leak.

#ifndef PW_VOLUMETRICS_FXH
#define PW_VOLUMETRICS_FXH

uniform float ShaftIntensity <
    ui_type = "slider"; ui_category = "Light shafts (screen-space)";
    ui_label = "Intensity"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.35;
uniform float ShaftThreshold <
    ui_type = "slider"; ui_category = "Light shafts (screen-space)";
    ui_label = "Sky brightness threshold (HDR)"; ui_min = 0.5; ui_max = 8.0; ui_step = 0.05;
    ui_tooltip = "Only sky pixels brighter than this seed shafts. Raise it if bright UI elements generate rays.";
> = 2.0;
uniform float ShaftDensity <
    ui_type = "slider"; ui_category = "Light shafts (screen-space)";
    ui_label = "Ray length (fraction of distance to sun)"; ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
> = 0.85;
uniform float ShaftDecay <
    ui_type = "slider"; ui_category = "Light shafts (screen-space)";
    ui_label = "Decay"; ui_min = 0.80; ui_max = 1.0; ui_step = 0.005;
> = 0.96;

texture PW_ShaftTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler PW_ShaftSampler { Texture = PW_ShaftTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

// returns (sun uv, visible) ; visible = 0 when the sun is behind the camera
float3 pw_sun_screen()
{
    float3 sd = pw_sun_dir_view();
    float2 uv = pw_view_to_uv(sd * 10.0);
    return float3(uv, sd.z < -0.02 ? 1.0 : 0.0);
}

float4 PS_Shafts(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 sun = pw_sun_screen();
    if (sun.z < 0.5) return float4(0, 0, 0, 1);

    float2 delta = (sun.xy - uv) * (ShaftDensity / float(PW_SHAFT_SAMPLES));
    float jitter = pw_ign(pos.xy * 2.0, 3.0);
    float2 p = uv + delta * jitter;

    float3 acc = 0.0;
    float w = 1.0;
    [unroll]
    for (int i = 0; i < PW_SHAFT_SAMPLES; ++i)
    {
        if (p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0)
        {
            float d = pw_depth_at(p);
            if (pw_is_sky(d))
            {
                float3 c = tex2Dlod(PW_SceneHDRSampler, float4(p, 0, 0)).rgb;
                float l = pw_luma(c);
                acc += c * saturate((l - ShaftThreshold) / ShaftThreshold) * w;
            }
        }
        p += delta;
        w *= ShaftDecay;
    }
    acc /= float(PW_SHAFT_SAMPLES);

    // Photon's mie phase (fog/overworld/analytic.glsl), evaluated for this pixel's view ray
    float LoV = dot(pw_ray_dir_view(uv), pw_sun_dir_view());
    float phase = 0.7 * pw_henyey_greenstein(LoV, 0.5) + 0.3 * pw_henyey_greenstein(LoV, -0.2);
    phase /= PW_ISOTROPIC_PHASE; // normalised so isotropic = 1

    return float4(acc * phase, 1.0);
}

float3 pw_shafts_at(float2 uv)
{
    return tex2Dlod(PW_ShaftSampler, float4(uv, 0, 0)).rgb;
}

#endif
