// EqShaders MVP v0.2 - Classic WoW shader stack combining Photon-derived post processing,
// a clean-room Bliss-inspired fantasy look, and ComfyAtmosphere as the world-space backend.
//
// Architecture:
//   WoW 1.12 -> ComfyAtmosphere (D3D9 world effects) -> DXVK -> Vulkan -> ReShade -> EqShaders
//
// ComfyAtmosphere owns real sun shadows, shadow maps, volumetric light, world fog, lamps,
// water/grass/time-of-day features. EqShaders owns the final-image pipeline: depth
// linearisation, GTAO, bloom, tonemap, colour grade, optional fantasy look, vignette,
// CAS and diagnostics.
//
// Photon Shaders (c) 2021-2025 Benjamin Stott "SixthSurge". Ported maths remains subject
// to PHOTON_LICENSE.txt. ComfyAtmosphere is a separate GPL-3.0 component downloaded from
// its upstream release by the EqShaders installer; see THIRD_PARTY.md.
//
// Bliss Shaders is All Rights Reserved. EqShaders does NOT include or port Bliss/Chocapic
// source. The selectable Bliss-inspired look is an independently authored clean-room
// approximation of publicly observable visual characteristics.
//
// Duplicate screen-space fog/shafts/DOF/SSR are intentionally off by default in EqShaders.ini.
// Start with Debug view = Contact sheet when validating a new client/depth setup.

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
#include "EqShaders/BlissInspired.fxh"
#include "EqShaders/Bridge.fxh"
#if PW_ENABLE_WET
    #include "EqShaders/Wet.fxh"
#endif
#include "EqShaders/AntiTile.fxh"

float4 PS_Prep(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 srgb = tex2Dlod(BackBuffer, float4(eq_unstrip(uv), 0, 0)).rgb;   // the bridge pixels are painted over
    float3 lin = pow(max(srgb, 0.0), 2.2);
    lin = pw_expand_ldr(lin);
    return float4(mul(PW_REC709_TO_REC2020, lin), 1.0);
}

float4 PS_Lighting(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 c = tex2Dlod(PW_SceneHDRSampler, float4(uv, 0, 0)).rgb;
    float d = pw_depth_at(uv);
    bool sky = pw_is_sky(d);

#if PW_ENABLE_AO
    if (!sky && DbgAO)
    {
        c *= pw_ao_factor(uv, pw_luma(c));
    }
#endif

    // Hide the repetition of tiled ground textures (world-space, ground-facing surfaces only).
    if (!sky) c = eq_anti_tile(c, uv, d);

    // Interiors: the game lights a room with one flat ambient. Push that ambient down and keep what is already bright
    // (torches, candles, fires, daylight through a window), so the room reads as dark + warm pools of light. A toe curve on
    // luminance, not a global exposure change: bright pixels pass untouched, the ambient-only ones fall away. At night the
    // windows give nothing, so the floor drops lower still. Fades with the addon's indoor amount; the sky/HUD are skipped.
    float indoor = sky ? 0.0 : eq_indoor_amount();
    if (indoor > 0.001)
    {
        float L = pw_luma(c);
        float floorGain = lerp(0.30, 0.52, eq_daylight());
        float lit = smoothstep(0.02, 0.55, L);
        c *= lerp(1.0, lerp(floorGain, 1.0, lit), indoor);
    }

    // Runtime fog remains available for diagnostics/fallback, but EqShaders.ini disables it
    // because ComfyAtmosphere provides world-aware fog before ReShade.
    float transmittance = 1.0;
    if (DbgFogStage)
        c = pw_apply_fog(c, d, pw_ray_dir_view(uv), sky, transmittance);

#if PW_ENABLE_VOLUMETRICS
    // Fallback only. ComfyAtmosphere is the default volumetric-light backend.
    c += pw_shafts_at(uv) * ShaftIntensity;
#endif

    return float4(c, transmittance);
}

float3 eq_debug_view(float2 uv, bool sky, int mode)
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
        return pw_ao_at(uv).yyy;   // broad AO
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
    if (mode == 13) return pw_depth_probe(uv);
    if (mode == 14) return tex2Dlod(BackBuffer, float4(uv, 0, 0)).aaa;
#if PW_ENABLE_WET
    if (mode >= 19 && mode <= 23) return eq_wet_debug(uv, mode);
#endif
    if (mode == 15) return sky ? float3(0, 0, 0) : frac(pw_view_pos(uv, d) * 0.1) ;
    if (mode == 16)
    {
        // N.V: cosine between the depth-reconstructed normal and the ray to the camera. A static wall should vary smoothly
        // with the camera; any hard edge here is a reconstruction fault, not lighting.
        float3 p = pw_view_pos(uv, d);
        return sky ? float3(0, 0, 0) : saturate(dot(pw_view_normal(uv), normalize(-p))).xxx;
    }
    if (mode == 17)
    {
#if PW_ENABLE_AO
        return (1.0 - pw_ao_factor(uv, 0.5)).xxx;   // darkening actually applied to a mid-grey pixel
#else
        return float3(1, 0, 1);
#endif
    }
    if (mode == 18)
    {
#if PW_ENABLE_AO
        return pw_ao_at(uv).xxx;   // contact AO alone
#else
        return float3(1, 0, 1);
#endif
    }
    if (raw >= 0.99999) return float3(0.0, 0.0, 0.6);
    if (raw <= 0.00001) return float3(0.6, 0.0, 0.0);
    return saturate(-log2(max(1.0 - raw, 1e-7)) / 24.0).xxx;
}

float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (DebugView == 12)
    {
        float2 g = uv * float2(4.0, 3.0);
        int tile = int(floor(g.y)) * 4 + int(floor(g.x));
        float2 luv = frac(g);
        return float4(eq_debug_view(luv, pw_is_sky(pw_depth_at(luv)), tile), 1.0);
    }
    if (DebugView != 0)
        return float4(eq_debug_view(uv, pw_is_sky(pw_depth_at(uv)), DebugView), 1.0);

    float3 scene = tex2Dlod(PW_SceneFinal, float4(uv, 0, 0)).rgb;

#if PW_ENABLE_BLOOM
    // The clean-room fantasy mode increases bloom energy slightly, matching the softer,
    // luminous presentation we are targeting without changing the Photon bloom pyramid.
    float bloom_intensity = DbgBloom ? 0.12 * BloomIntensity * eq_fantasy_bloom_gain() : 0.0;
    scene = lerp(scene, pw_get_bloom(uv), bloom_intensity);
#endif

    scene *= Exposure;
    scene *= pw_vignette(uv);

    // Clean-room Bliss-inspired split-toning/contrast is deliberately applied BEFORE the
    // existing Photon grade+tonemap, so the underlying Photon maths stays intact/selectable.
    if (DbgLook) scene = eq_fantasy_pre_tonemap(scene);
    scene = pw_grade_input(scene);
    scene = pw_tonemap(scene);
    scene = saturate(mul(PW_REC2020_TO_REC709, scene));
    scene = pw_grade_output(scene);
    if (DbgLook) scene = eq_fantasy_post_grade(scene);

    return float4(pw_display_eotf(scene), 1.0);
}

float4 PS_Final(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float3 c = tex2Dlod(PW_CompSampler, float4(uv, 0, 0)).rgb;
    if (DebugView != 0) return float4(saturate(c), 1.0);

#if PW_ENABLE_CAS
    if (DbgAA)
    {
        float3 plain = c;
        c = pw_cas(PW_CompSampler, uv, CASIntensity * 2.0 - 1.0);
        // far texture is not sharpened: sharpening there turns a tiled texture into a shimmering grid (the HUD has no depth: untouched)
        float dfar = pw_depth_at(uv);
        if (!pw_is_sky(dfar)) c = lerp(c, plain, AntiTileFarDetail * smoothstep(50.0, 220.0, dfar));
    }
#endif

#if PW_ENABLE_AA
    // Sharpen the interior, smooth the silhouettes: edges take the unsharpened, edge-averaged colour.
    if (AAMode > 0 && DbgAA)
    {
        float edge = pw_aa_edge(uv) * AAStrength;
        float thin = (AAMode >= 2) ? pw_aa_thin(uv) * AAThinDetail : 0.0;
        float m = max(edge, thin);
        if (m > 0.001)
        {
            float3 dir = pw_aa_colour(PW_CompSampler, uv);
            float3 iso = pw_aa_iso(PW_CompSampler, uv);
            c = lerp(c, lerp(dir, iso, saturate(thin * 1.4)), m);
        }
    }
#endif

    if (Dither8Bit)
        c += (pw_ign(pos.xy, 0.0) + pw_ign(pos.xy, 17.0) - 1.0) * (1.0 / 255.0);

    float3 original = tex2Dlod(BackBuffer, float4(eq_unstrip(uv), 0, 0)).rgb;
    float keep = pw_is_sky(pw_depth_at(uv)) ? ProtectDepthless : 0.0;
    return float4(lerp(original, saturate(c), MasterStrength * (1.0 - keep)), 1.0);
}

technique EqShaders <
    ui_label = "EqShaders";
    ui_tooltip = "EqShaders MVP: ComfyAtmosphere world lighting + Photon-derived post pipeline + optional clean-room Bliss-inspired fantasy look.";
>
{
    pass BridgeDecode   { VertexShader = PW_VS; PixelShader = PS_BridgeDecode; RenderTarget = PW_BridgeTex; }
    pass DepthLinearise { VertexShader = PW_VS; PixelShader = PS_LinearDepth; RenderTarget = PW_DepthLinTex; }
    pass Prep           { VertexShader = PW_VS; PixelShader = PS_Prep;        RenderTarget = PW_SceneHDRTex; }

#if PW_ENABLE_AO
    pass AORaw   { VertexShader = PW_VS; PixelShader = PS_AO;      RenderTarget = PW_AORawTex; }
    pass AOBlurH { VertexShader = PW_VS; PixelShader = PS_AOBlurH; RenderTarget = PW_AOTempTex; }
    pass AOBlurV { VertexShader = PW_VS; PixelShader = PS_AOBlurV; RenderTarget = PW_AOTex; }
    pass AOTemporal  { VertexShader = PW_VS; PixelShader = PS_AOTemporal;  RenderTarget = PW_AOFinalTex; }
    pass AOHistAO    { VertexShader = PW_VS; PixelShader = PS_AOHistAO;    RenderTarget = PW_AOHistTex; }
    pass AOHistDepth { VertexShader = PW_VS; PixelShader = PS_AOHistDepth; RenderTarget = PW_DepthHistTex; }
#endif

#if PW_ENABLE_VOLUMETRICS
    pass Shafts { VertexShader = PW_VS; PixelShader = PS_Shafts; RenderTarget = PW_ShaftTex; }
#endif

    pass Lighting { VertexShader = PW_VS; PixelShader = PS_Lighting; RenderTarget = PW_SceneLitTex; }

#if PW_ENABLE_WET
    pass WetState     { VertexShader = PW_VS; PixelShader = PS_WetState;     RenderTarget = PW_WetStateBTex; }
    pass WetStateCopy { VertexShader = PW_VS; PixelShader = PS_WetStateCopy; RenderTarget = PW_WetStateATex; }
    pass Wet          { VertexShader = PW_VS; PixelShader = PS_Wet;          RenderTarget = PW_SceneWetTex; }
#endif

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
