// PhotonWoW/Depth.fxh
// Depth conditioning + linearisation + view-space reconstruction.
//
// Everything downstream works in VIEW-SPACE YARDS, with a right-handed view space
// (x right, y up, camera looks down -z) so Photon's GLSL view-space maths ports 1:1.
//
// Nothing here assumes how WoW lays out depth. Pipeline:
//   raw -> [reverse?] -> *multiplier + offset -> ^exponent -> linearise(mode, near, far) -> yards
// Use the Debug views to tune each stage.

#ifndef PW_DEPTH_FXH
#define PW_DEPTH_FXH

uniform bool DepthReversed <
    ui_category = "Depth calibration";
    ui_label = "Reversed depth (1 = near)";
    ui_tooltip = "D3D9/DXVK WoW normally writes standard depth (0 = near, 1 = far): leave OFF.\n"
                 "If the 'Raw depth' view is white up close and black far away, turn this ON.";
> = false;

uniform int DepthMode <
    ui_type = "combo";
    ui_category = "Depth calibration";
    ui_label = "Depth encoding";
    ui_items = "Perspective (standard D3D)\0Logarithmic\0Linear\0";
    ui_tooltip = "Perspective: z_buf = F/(F-N) * (1 - N/z) (what a plain D3D9 projection matrix writes).\n"
                 "Logarithmic: ReShade's log convention (some wrappers / modded clients).\n"
                 "Linear: depth already proportional to distance.";
> = 0;

uniform float DepthNear <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Near plane (yards)";
    ui_min = 0.01; ui_max = 10.0; ui_step = 0.01;
> = 0.20;

uniform float DepthFar <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Far plane (yards)";
    ui_tooltip = "WoW sets this from the view-distance / terrain-distance cvars (and from fog in some clients). Calibrate with 'Distance rings'.";
    ui_min = 50.0; ui_max = 5000.0; ui_step = 1.0;
> = 1000.0;

uniform float DepthMultiplier <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Depth multiplier";
    ui_min = 0.1; ui_max = 10.0; ui_step = 0.001;
> = 1.0;

uniform float DepthOffset <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Depth offset";
    ui_min = -0.5; ui_max = 0.5; ui_step = 0.0001;
> = 0.0;

uniform float DepthExponent <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Depth exponent";
    ui_tooltip = "Applied to the conditioned [0,1] depth before linearisation. 1.0 = untouched.";
    ui_min = 0.1; ui_max = 4.0; ui_step = 0.001;
> = 1.0;

uniform float VerticalFOV <
    ui_type = "drag";
    ui_category = "Depth calibration";
    ui_label = "Vertical FOV (degrees)";
    ui_tooltip = "Needed to rebuild view-space positions/normals. Calibrate with 'Reconstructed normals': a flat floor should be a smooth uniform colour, not banded.\n"
                 "Classic WoW's default FoV cvar (1.5708 rad) is a HORIZONTAL-ish value: vertical FOV is much smaller (~60 deg at 16:9 is a sensible start).";
    ui_min = 20.0; ui_max = 120.0; ui_step = 0.1;
> = 60.0;

// -------------------------------------------------------------------------
texture DepthBufferTex : DEPTH;
sampler DepthBuffer
{
    Texture = DepthBufferTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

// Linearised view-space distance along the view axis, in yards. Sky/clear = DepthFar.
texture PW_DepthLinTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; };
sampler PW_DepthLin
{
    Texture = PW_DepthLinTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

float pw_raw_depth(float2 uv)
{
    return tex2Dlod(DepthBuffer, float4(uv, 0.0, 0.0)).x;
}

float pw_condition_depth(float raw)
{
    float z = DepthReversed ? 1.0 - raw : raw;
    z = saturate(z * DepthMultiplier + DepthOffset);
    return pow(z, DepthExponent);
}

// conditioned [0,1] -> yards
float pw_linearise_depth(float z)
{
    float n = DepthNear;
    float f = max(DepthFar, n + 0.01);

    float d;
    if (DepthMode == 0)
        d = n * f / (f - z * (f - n));
    else if (DepthMode == 1)
        d = n * (exp2(z * log2(f / n + 1.0)) - 1.0);
    else
        d = lerp(n, f, z);

    return clamp(d, n, f);
}

// yards -> the NON-linear [0,1] depth an OpenGL-style projection (Photon's) would store.
// Photon's DOF and some other effects are defined on that value.
float pw_nonlinear_depth01(float d)
{
    float n = DepthNear, f = DepthFar;
    return (f / (f - n)) * (1.0 - n / max(d, n));
}

float PS_LinearDepth(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float z = pw_condition_depth(pw_raw_depth(uv));
    // Cleared depth (sky, and anything drawn without depth such as the UI) -> far plane.
    return (z >= 0.99999) ? DepthFar : pw_linearise_depth(z);
}

// ---------------------------------------------------------------------------
//  View-space reconstruction
// ---------------------------------------------------------------------------
float pw_sky_distance() { return DepthFar * 0.9999; }

float2 pw_tan_half_fov()
{
    float ty = tan(radians(VerticalFOV) * 0.5);
    return float2(ty * PW_ASPECT, ty);
}

float pw_depth_at(float2 uv)
{
    return tex2Dlod(PW_DepthLin, float4(uv, 0.0, 0.0)).x;
}

bool pw_is_sky(float d) { return d >= pw_sky_distance(); }

float3 pw_view_pos(float2 uv, float d)
{
    float2 t = pw_tan_half_fov();
    return float3((uv.x * 2.0 - 1.0) * t.x * d, (1.0 - uv.y * 2.0) * t.y * d, -d);
}

// view-space position -> uv (position must be in front of the camera, z < 0)
float2 pw_view_to_uv(float3 p)
{
    float2 t = pw_tan_half_fov();
    float w = max(-p.z, 1e-4);
    float2 ndc = float2(p.x / (w * t.x), p.y / (w * t.y));
    return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

// Normal from depth: per axis, pick the smaller one-sided difference (avoids smearing across silhouettes).
// Returns a unit vector facing the camera.
float3 pw_view_normal(float2 uv)
{
    float2 px = PW_PIXEL_SIZE;
    float dc = pw_depth_at(uv);
    float dl = pw_depth_at(uv - float2(px.x, 0.0));
    float dr = pw_depth_at(uv + float2(px.x, 0.0));
    float du = pw_depth_at(uv - float2(0.0, px.y));
    float dd = pw_depth_at(uv + float2(0.0, px.y));

    float3 pc = pw_view_pos(uv, dc);

    float3 dx = (abs(dr - dc) < abs(dl - dc))
              ? pw_view_pos(uv + float2(px.x, 0.0), dr) - pc
              : pc - pw_view_pos(uv - float2(px.x, 0.0), dl);
    float3 dy = (abs(dd - dc) < abs(du - dc))
              ? pw_view_pos(uv + float2(0.0, px.y), dd) - pc
              : pc - pw_view_pos(uv - float2(0.0, px.y), du);

    return normalize(cross(dy, dx));
}

#endif
