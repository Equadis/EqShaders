// PhotonWoW/Common.fxh
// Shared constants, colour-space helpers, fullscreen VS, global UI.
// Math marked "Photon:" is ported from Photon v1.3b (SixthSurge), see PHOTON_LICENSE.txt.

#ifndef PW_COMMON_FXH
#define PW_COMMON_FXH

// ---------------------------------------------------------------------------
//  Effect-level switches (appear under "Edit global preprocessor definitions").
//  A disabled stage is removed from the technique entirely (zero cost).
// ---------------------------------------------------------------------------
#ifndef PW_ENABLE_AO
    #define PW_ENABLE_AO 1
#endif
#ifndef PW_ENABLE_VOLUMETRICS
    #define PW_ENABLE_VOLUMETRICS 0
#endif
#ifndef PW_ENABLE_SSR
    #define PW_ENABLE_SSR 0
#endif
#ifndef PW_ENABLE_DOF
    #define PW_ENABLE_DOF 0
#endif
#ifndef PW_ENABLE_BLOOM
    #define PW_ENABLE_BLOOM 1
#endif
#ifndef PW_ENABLE_CAS
    #define PW_ENABLE_CAS 1
#endif
#ifndef PW_AO_SLICES
    #define PW_AO_SLICES 2      // Photon default GTAO_SLICES
#endif
#ifndef PW_AO_STEPS
    #define PW_AO_STEPS 4       // Photon default GTAO_HORIZON_STEPS is 3; 4 compensates for no TAA
#endif
#ifndef PW_DOF_SAMPLES
    #define PW_DOF_SAMPLES 32   // Photon default 40
#endif
#ifndef PW_SHAFT_SAMPLES
    #define PW_SHAFT_SAMPLES 32
#endif
#ifndef PW_SSR_STEPS
    #define PW_SSR_STEPS 24
#endif

#define PW_PIXEL_SIZE float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
#define PW_ASPECT     (float(BUFFER_WIDTH) / float(BUFFER_HEIGHT))

// ---------------------------------------------------------------------------
//  Constants (Photon: global.glsl)
// ---------------------------------------------------------------------------
static const float PW_PI      = 3.14159265359;
static const float PW_TAU     = 6.28318530718;
static const float PW_HALF_PI = 1.57079632679;
static const float PW_EPS     = 1e-6;
static const float PW_ISOTROPIC_PHASE = 0.07957747154; // 1 / (4 pi)

// ---------------------------------------------------------------------------
//  Global UI
// ---------------------------------------------------------------------------
uniform int DebugView <
    ui_type = "combo";
    ui_category = "Debug / calibration";
    ui_label = "Debug view";
    ui_tooltip = "Use these to calibrate depth BEFORE judging any effect.\n"
                 "Raw depth: the unmodified depth texture ReShade hands us. Black = near, white = far for standard (non-reversed) depth.\n"
                 "Linear depth: after reversal/multiplier/offset/exponent and linearisation, log-scaled so near and far are both visible.\n"
                 "Inverted depth: 1 - raw.\n"
                 "Distance rings: red/white bands every 'Ring spacing' yards; walk to a known distance and check.\n"
                 "Sky mask: white = treated as sky/clear (also UI, which has no depth).";
    ui_items = "Off\0Raw depth\0Linear depth (log scaled)\0Inverted depth\0Distance rings\0Sky mask\0Reconstructed normals\0Ambient occlusion\0Fog factor\0Light shafts\0Bloom (final tile)\0Depth sanity (log-stretched; blue = exactly 1.0)\0Contact sheet (4x3: original + all views)\0Depth probe (numeric centre readout)\0";
> = 0;

uniform float RingSpacing <
    ui_type = "slider";
    ui_category = "Debug / calibration";
    ui_label = "Ring spacing (yards)";
    ui_min = 1.0; ui_max = 100.0; ui_step = 1.0;
> = 10.0;

uniform float MasterStrength <
    ui_type = "slider";
    ui_category = "Global";
    ui_label = "Master strength";
    ui_tooltip = "Crossfade between the untouched game image and the full Photon pipeline.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform float ProtectDepthless <
    ui_type = "slider";
    ui_category = "Global";
    ui_label = "Protect depth-less pixels (sky / letterbox / some UI)";
    ui_tooltip = "Blends pixels whose depth is the cleared value back to the untouched game image.\n"
                 "UI drawn over world geometry has that geometry's depth, so this cannot mask the HUD in general.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform int framecount < source = "framecount"; >;
uniform float frametime < source = "frametime"; >;

// ---------------------------------------------------------------------------
//  Maths helpers
// ---------------------------------------------------------------------------
float pw_sqr(float x)   { return x * x; }
float2 pw_sqr(float2 x) { return x * x; }
float3 pw_sqr(float3 x) { return x * x; }

float pw_linear_step(float e0, float e1, float x) { return saturate((x - e0) / (e1 - e0)); }

float pw_cubic_smooth(float x) { return x * x * (3.0 - 2.0 * x); }

float pw_luma(float3 rgb_2020) { return dot(rgb_2020, float3(0.2627, 0.6780, 0.0593)); } // Photon: luminance_weights (Rec.2020)

// Interleaved gradient noise (Jimenez 2014); replaces Photon's blue-noise texture (no assets needed).
float pw_ign(float2 px, float offset)
{
    return frac(52.9829189 * frac(dot(px + offset * 5.588238, float2(0.06711056, 0.00583715))));
}

// Photon: sampling.glsl vogel_disc_sample
float2 pw_vogel_disc(int i, int n, float rotation)
{
    const float golden_angle = 2.4;
    float r = sqrt(float(i) + 0.5) / sqrt(float(n));
    float theta = float(i) * golden_angle + rotation;
    return r * float2(cos(theta), sin(theta));
}

// ---------------------------------------------------------------------------
//  Colour spaces. Photon grades in Rec.2020 "working space"; the game
//  backbuffer is gamma-encoded Rec.709/sRGB.
//  (column-vector convention: use mul(M, v))
// ---------------------------------------------------------------------------
static const float3x3 PW_REC709_TO_REC2020 = float3x3(
    0.6274040, 0.3292820, 0.0433136,
    0.0690970, 0.9195400, 0.0113612,
    0.0163916, 0.0880132, 0.8955950);
static const float3x3 PW_REC2020_TO_REC709 = float3x3(
     1.6604910, -0.5876411, -0.0728499,
    -0.1245505,  1.1328999, -0.0083494,
    -0.0181508, -0.1005789,  1.1187297);

// Photon: from_srgb() uses a plain 2.2 power on input...
float3 pw_srgb_to_working(float3 srgb)
{
    return mul(PW_REC709_TO_REC2020, pow(max(srgb, 0.0), 2.2));
}

// ...and Photon's display_eotf (Jodie's sqrt approximation) on output.
float3 pw_display_eotf(float3 lin)
{
    return 1.14374 * (-0.126893 * lin + sqrt(max(lin, 0.0)));
}

float3 pw_display_eotf_inv(float3 s)
{
    return s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878);
}

// ---------------------------------------------------------------------------
//  Full-screen triangle VS (identical to ReShade's PostProcessVS)
// ---------------------------------------------------------------------------
void PW_VS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD0)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
//  Back buffer
// ---------------------------------------------------------------------------
texture BackBufferTex : COLOR;
sampler BackBuffer
{
    Texture = BackBufferTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR;
};

// ---------------------------------------------------------------------------
//  Pipeline buffers (all RGBA16F, Rec.2020 linear HDR, alpha = fog transmittance after lighting)
//    SceneHDR -> [AO, fog, shafts] -> SceneLit -> [SSR] -> SceneRefl -> [DOF] -> SceneDOF
//    -> bloom pyramid -> composite (bloom mix, exposure, vignette, grade, tonemap) -> Comp -> CAS -> backbuffer
// ---------------------------------------------------------------------------
texture PW_SceneHDRTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture PW_SceneLitTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture PW_SceneReflTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture PW_SceneDOFTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture PW_CompTex      { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };

#define PW_LINEAR_SAMPLER(name, tex)     sampler name { Texture = tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

PW_LINEAR_SAMPLER(PW_SceneHDRSampler,  PW_SceneHDRTex)
PW_LINEAR_SAMPLER(PW_SceneLitSampler,  PW_SceneLitTex)
PW_LINEAR_SAMPLER(PW_SceneReflSampler, PW_SceneReflTex)
PW_LINEAR_SAMPLER(PW_SceneDOFSampler,  PW_SceneDOFTex)
PW_LINEAR_SAMPLER(PW_CompSampler,      PW_CompTex)

#if PW_ENABLE_SSR
    #define PW_SceneInDOF PW_SceneReflSampler
#else
    #define PW_SceneInDOF PW_SceneLitSampler
#endif
#if PW_ENABLE_DOF
    #define PW_SceneFinal PW_SceneDOFSampler
#else
    #define PW_SceneFinal PW_SceneInDOF
#endif

#endif
