// PhotonWoW v0.3 - Photon v1.3b look/maths ported to a ReShade post-process for Classic WoW.
//
// Photon Shaders (c) 2021-2025 Benjamin Stott "SixthSurge". Ported maths is used under the terms of
// the Photon license (included as PHOTON_LICENSE.txt): personal use, no money, not for
// monetised distribution platforms. Do not redistribute this port on Modrinth/CurseForge/etc.
//
// Pass order mirrors Photon's deferred/composite order where the data allows it:
//   depth linearise -> LDR->HDR expansion -> GTAO (+bilateral) -> [shafts] -> lighting (AO, fog, shafts)
//   -> [SSR] -> [DOF c2] -> bloom pyramid (c5-c18) -> composite (c19: bloom mix, exposure, vignette,
//   grade_input, tonemap, grade_output) -> CAS (final)
//
// Start with DebugView = "Raw depth" and calibrate depth first. See README.md.

#include "PhotonWoW/Common.fxh"
#include "PhotonWoW/Depth.fxh"
#include "PhotonWoW/Debug.fxh"
#include "PhotonWoW/Tonemap.fxh"
#include "PhotonWoW/ColorGrade.fxh"
#include "PhotonWoW/AO.fxh"
#include "PhotonWoW/Fog.fxh"
#include "PhotonWoW/Volumetrics.fxh"
#include "PhotonWoW/Reflections.fxh"
#include "PhotonWoW/DOF.fxh"
#include "PhotonWoW/Bloom.fxh"
#include "PhotonWoW/Sharpen.fxh"

// ---------------------------------------------------------------------------
//  Prep: sRGB backbuffer -> linear Rec.2020 pseudo-HDR
// ---------------------------------------------------------------------------
float4 PS_Prep(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 srgb = tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb;
    float3 lin = pow(max(srgb, 0.0), 2.2);      // Photon: from_srgb()
    lin = pw_expand_ldr(lin);                   // WoW-only: LDR -> HDR
    return float4(mul(PW_REC709_TO_REC2020, lin), 1.0);
}

// ---------------------------------------------------------------------------
//  Lighting: AO, atmospheric fog, light shafts applied to scene radiance (pre-tonemap, like Photon)
// ---------------------------------------------------------------------------
float4 PS_Lighting(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 c = tex2Dlod(PW_SceneHDRSampler, float4(uv, 0, 0)).rgb;
    float d = pw_depth_at(uv);
    bool sky = pw_is_sky(d);

#if PW_ENABLE_AO
    if (!sky)
    {
        float ao = pw_ao_at(uv);
        float protect = 1.0 - AOBrightProtect * smoothstep(0.5, 3.0, pw_luma(c));
        c *= lerp(1.0, ao, AOStrength * protect);
    }
#endif

    float transmittance = 1.0;
    c = pw_apply_fog(c, d, pw_ray_dir_view(uv), sky, transmittance);

#if PW_ENABLE_VOLUMETRICS
    c += pw_shafts_at(uv) * ShaftIntensity;
#endif

    return float4(c, transmittance);
}

// ---------------------------------------------------------------------------
//  Composite: Photon c19_color_grading.fsh
// ---------------------------------------------------------------------------
float3 pw_debug_view(float2 uv, bool sky, int mode)
{
    float raw = pw_raw_depth(uv);
    float d = pw_depth_at(uv);
    float lin_log = saturate(log2(d / DepthNear) / log2(DepthFar / DepthNear));

    if (mode == 0) return tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb;
    if (mode == 1) return raw.xxx;
    if (mode == 2) return lin_log.xxx;
    if (mode == 3) return (1.0 - raw).xxx;
    if (mode == 4)
    {
        float band = frac(d / RingSpacing);
        float line_mask = (band < 0.04 || band > 0.96) ? 1.0 : 0.0;
        float stripe = (frac(floor(d / RingSpacing) * 0.5) < 0.25) ? 0.25 : 0.55;
        return lerp(stripe.xxx * float3(0.6, 0.8, 1.0), float3(1.0, 0.1, 0.1), line_mask) * (sky ? 0.15 : 1.0);
    }
    if (mode == 5) return sky ? float3(1, 1, 1) : float3(0, 0, 0);
    if (mode == 6) return sky ? float3(0, 0, 0) : pw_view_normal(uv) * 0.5 + 0.5;
    if (mode == 7)
    {
#if PW_ENABLE_AO
        return pw_ao_at(uv).xxx;
#else
        return float3(1, 0, 1);
#endif
    }
    if (mode == 8) return (1.0 - tex2Dlod(PW_SceneFinal, float4(uv, 0, 0)).a).xxx;
    if (mode == 9)
    {
#if PW_ENABLE_VOLUMETRICS
        float3 s = pw_shafts_at(uv) * ShaftIntensity;
        return pw_display_eotf(s / (1.0 + s));
#else
        return float3(1, 0, 1);
#endif
    }
    if (mode == 10)
    {
#if PW_ENABLE_BLOOM
        float3 b = pw_get_bloom(uv);
        return pw_display_eotf(b / (1.0 + b));
#else
        return float3(1, 0, 1);
#endif
    }
    // 13: numeric readout of the centre pixel (raw depth + linear yards) for near/far calibration
    if (mode == 13) return pw_depth_probe(uv);
    // 11: depth sanity. blue = exactly 1.0 (cleared / sky / depth-less UI), red = exactly 0.0, grey = -log2(1-raw)/24.
    // The log stretch exposes structure that a plain raw view hides when a perspective depth buffer sits at 0.93-0.999.
    if (raw >= 0.99999) return float3(0.0, 0.0, 0.6);
    if (raw <= 0.00001) return float3(0.6, 0.0, 0.0);
    return saturate(-log2(max(1.0 - raw, 1e-7)) / 24.0).xxx;
}

float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (DebugView == 12)
    {
        // contact sheet: 4 columns x 3 rows, tile 0 = untouched game image, tiles 1..11 = debug views
        float2 g = uv * float2(4.0, 3.0);
        int tile = int(floor(g.y)) * 4 + int(floor(g.x));
        float2 luv = frac(g);
        return float4(pw_debug_view(luv, pw_is_sky(pw_depth_at(luv)), tile), 1.0);
    }
    if (DebugView != 0)
        return float4(pw_debug_view(uv, pw_is_sky(pw_depth_at(uv)), DebugView), 1.0);

    float3 scene = tex2Dlod(PW_SceneFinal, float4(uv, 0, 0)).rgb;

#if PW_ENABLE_BLOOM
    float bloom_intensity = 0.12 * BloomIntensity;
    scene = lerp(scene, pw_get_bloom(uv), bloom_intensity);
#endif

    scene *= Exposure;
    scene *= pw_vignette(uv);

    scene = pw_grade_input(scene);
    scene = pw_tonemap(scene);

    scene = saturate(mul(PW_REC2020_TO_REC709, scene));
    scene = pw_grade_output(scene);

    return float4(pw_display_eotf(scene), 1.0);
}

// ---------------------------------------------------------------------------
//  Final: Photon CAS + dither, crossfade with the untouched frame
// ---------------------------------------------------------------------------
float4 PS_Final(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 c = tex2Dlod(PW_CompSampler, float4(uv, 0, 0)).rgb;
    if (DebugView != 0) return float4(saturate(c), 1.0); // debug views bypass CAS/dither/master mix

#if PW_ENABLE_CAS
    c = pw_cas(PW_CompSampler, uv, CASIntensity * 2.0 - 1.0);
#endif

    if (Dither8Bit)
        c += (pw_ign(pos.xy, 0.0) + pw_ign(pos.xy, 17.0) - 1.0) * (1.0 / 255.0);

    float3 original = tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb;

    // Depth-less pixels (sky dome without depth writes, letterbox, UI drawn over cleared depth) can be kept untouched.
    // UI drawn over geometry inherits that geometry's depth, so this is NOT a general UI mask (see README).
    float keep = pw_is_sky(pw_depth_at(uv)) ? ProtectDepthless : 0.0;
    return float4(lerp(original, saturate(c), MasterStrength * (1.0 - keep)), 1.0);
}

// ---------------------------------------------------------------------------
technique PhotonWoW <
    ui_label = "PhotonWoW";
    ui_tooltip = "Photon v1.3b post-processing pipeline for Classic WoW. Calibrate depth first (Debug view).";
>
{
    pass DepthLinearise { VertexShader = PW_VS; PixelShader = PS_LinearDepth; RenderTarget = PW_DepthLinTex; }
    pass Prep           { VertexShader = PW_VS; PixelShader = PS_Prep;        RenderTarget = PW_SceneHDRTex; }

#if PW_ENABLE_AO
    pass AORaw   { VertexShader = PW_VS; PixelShader = PS_AO;      RenderTarget = PW_AORawTex; }
    pass AOBlurH { VertexShader = PW_VS; PixelShader = PS_AOBlurH; RenderTarget = PW_AOTempTex; }
    pass AOBlurV { VertexShader = PW_VS; PixelShader = PS_AOBlurV; RenderTarget = PW_AOTex; }
#endif

#if PW_ENABLE_VOLUMETRICS
    pass Shafts { VertexShader = PW_VS; PixelShader = PS_Shafts; RenderTarget = PW_ShaftTex; }
#endif

    pass Lighting { VertexShader = PW_VS; PixelShader = PS_Lighting; RenderTarget = PW_SceneLitTex; }

#if PW_ENABLE_SSR
    pass SSR { VertexShader = PW_VS; PixelShader = PS_SSR; RenderTarget = PW_SceneReflTex; }
#endif

#if PW_ENABLE_DOF
    pass FocusUpdate { VertexShader = PW_VS; PixelShader = PS_FocusUpdate; RenderTarget = PW_FocusTex; }
    pass FocusCopy   { VertexShader = PW_VS; PixelShader = PS_FocusCopy;   RenderTarget = PW_FocusPrevTex; }
    pass DOF         { VertexShader = PW_VS; PixelShader = PS_DOF;         RenderTarget = PW_SceneDOFTex; }
#endif

#if PW_ENABLE_BLOOM
    pass BloomDown0 { VertexShader = PW_VS; PixelShader = PS_BloomDown0; RenderTarget = PW_BD0; }
    pass BloomDown1 { VertexShader = PW_VS; PixelShader = PS_BloomDown1; RenderTarget = PW_BD1; }
    pass BloomDown2 { VertexShader = PW_VS; PixelShader = PS_BloomDown2; RenderTarget = PW_BD2; }
    pass BloomDown3 { VertexShader = PW_VS; PixelShader = PS_BloomDown3; RenderTarget = PW_BD3; }
    pass BloomDown4 { VertexShader = PW_VS; PixelShader = PS_BloomDown4; RenderTarget = PW_BD4; }
    pass BloomDown5 { VertexShader = PW_VS; PixelShader = PS_BloomDown5; RenderTarget = PW_BD5; }

    pass BloomH0 { VertexShader = PW_VS; PixelShader = PS_BloomH0; RenderTarget = PW_BT0; }
    pass BloomV0 { VertexShader = PW_VS; PixelShader = PS_BloomV0; RenderTarget = PW_BD0; }
    pass BloomH1 { VertexShader = PW_VS; PixelShader = PS_BloomH1; RenderTarget = PW_BT1; }
    pass BloomV1 { VertexShader = PW_VS; PixelShader = PS_BloomV1; RenderTarget = PW_BD1; }
    pass BloomH2 { VertexShader = PW_VS; PixelShader = PS_BloomH2; RenderTarget = PW_BT2; }
    pass BloomV2 { VertexShader = PW_VS; PixelShader = PS_BloomV2; RenderTarget = PW_BD2; }
    pass BloomH3 { VertexShader = PW_VS; PixelShader = PS_BloomH3; RenderTarget = PW_BT3; }
    pass BloomV3 { VertexShader = PW_VS; PixelShader = PS_BloomV3; RenderTarget = PW_BD3; }
    pass BloomH4 { VertexShader = PW_VS; PixelShader = PS_BloomH4; RenderTarget = PW_BT4; }
    pass BloomV4 { VertexShader = PW_VS; PixelShader = PS_BloomV4; RenderTarget = PW_BD4; }
    pass BloomH5 { VertexShader = PW_VS; PixelShader = PS_BloomH5; RenderTarget = PW_BT5; }
    pass BloomV5 { VertexShader = PW_VS; PixelShader = PS_BloomV5; RenderTarget = PW_BD5; }

    pass BloomUp4 { VertexShader = PW_VS; PixelShader = PS_BloomUp4; RenderTarget = PW_BU4; }
    pass BloomUp3 { VertexShader = PW_VS; PixelShader = PS_BloomUp3; RenderTarget = PW_BU3; }
    pass BloomUp2 { VertexShader = PW_VS; PixelShader = PS_BloomUp2; RenderTarget = PW_BU2; }
    pass BloomUp1 { VertexShader = PW_VS; PixelShader = PS_BloomUp1; RenderTarget = PW_BU1; }
    pass BloomUp0 { VertexShader = PW_VS; PixelShader = PS_BloomUp0; RenderTarget = PW_BU0; }
#endif

    pass Composite { VertexShader = PW_VS; PixelShader = PS_Composite; RenderTarget = PW_CompTex; }
    pass Final     { VertexShader = PW_VS; PixelShader = PS_Final; }
}

