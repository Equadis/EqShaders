// PhotonWoW/DOF.fxh
// Photon v1.3b c2_dof.fsh. The circle of confusion is Photon's, evaluated on the NON-linear
// [0,1] depth an OpenGL projection would store (we rebuild it from yards with near/far):
//   CoC = min(|depth - focus|, 0.1) * (DOF_INTENSITY * 0.2 / 1.37) * vec2(1, aspect) * proj[1][1]
// Samples: Vogel disc rotated per pixel (Photon uses a noise texture + r1 sequence).
// Differences: sky/clear pixels (which include the UI) are left sharp by default.

#ifndef PW_DOF_FXH
#define PW_DOF_FXH

uniform float DOFIntensity <
    ui_type = "slider"; ui_category = "Depth of field (Photon c2)";
    ui_label = "Intensity"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float DOFFocusDistance <
    ui_type = "slider"; ui_category = "Depth of field (Photon c2)";
    ui_label = "Focus distance (yards, -1 = auto centre focus)"; ui_min = -1.0; ui_max = 100.0; ui_step = 0.5;
> = -1.0;
uniform float DOFFocusSpeed <
    ui_type = "slider"; ui_category = "Depth of field (Photon c2)";
    ui_label = "Auto-focus speed"; ui_min = 0.5; ui_max = 20.0; ui_step = 0.1;
> = 4.0;
uniform bool DOFBlurSky <
    ui_category = "Depth of field (Photon c2)";
    ui_label = "Blur sky / clear pixels (also blurs the UI!)";
> = false;

texture PW_FocusTex     { Width = 1; Height = 1; Format = R32F; };
texture PW_FocusPrevTex { Width = 1; Height = 1; Format = R32F; };
sampler PW_FocusSampler     { Texture = PW_FocusTex;     MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };
sampler PW_FocusPrevSampler { Texture = PW_FocusPrevTex; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };

float PS_FocusUpdate(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // centre + 4 neighbours, nearest valid
    float d = pw_depth_at(float2(0.5, 0.5));
    float2 o = 6.0 * PW_PIXEL_SIZE;
    d = min(d, pw_depth_at(float2(0.5, 0.5) + float2( o.x, 0.0)));
    d = min(d, pw_depth_at(float2(0.5, 0.5) + float2(-o.x, 0.0)));
    d = min(d, pw_depth_at(float2(0.5, 0.5) + float2(0.0,  o.y)));
    d = min(d, pw_depth_at(float2(0.5, 0.5) + float2(0.0, -o.y)));

    float prev = tex2Dlod(PW_FocusPrevSampler, float4(0.5, 0.5, 0, 0)).x;
    if (prev <= 0.0) prev = d; // first frame
    float k = 1.0 - exp(-DOFFocusSpeed * frametime * 0.001);
    return lerp(prev, d, k);
}

float PS_FocusCopy(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2Dlod(PW_FocusSampler, float4(0.5, 0.5, 0, 0)).x;
}

float4 PS_DOF(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 scene = tex2Dlod(PW_SceneInDOF, float4(uv, 0, 0));

    float d = pw_depth_at(uv);
    if (pw_is_sky(d) && !DOFBlurSky) return scene;

    float focus_yd = DOFFocusDistance < 0.0 ? tex2Dlod(PW_FocusSampler, float4(0.5, 0.5, 0, 0)).x : DOFFocusDistance;
    float depth_nl = pw_nonlinear_depth01(d);
    float focus_nl = pw_nonlinear_depth01(max(focus_yd, DepthNear));

    float proj11 = 1.0 / tan(radians(VerticalFOV) * 0.5);
    float2 coc = min(abs(depth_nl - focus_nl), 0.1) * (DOFIntensity * 0.2 / 1.37)
               * float2(1.0, PW_ASPECT) * proj11;

    // sub-pixel blur: skip
    if (coc.x * BUFFER_WIDTH < 0.4) return scene;

    float theta = pw_ign(pos.xy, 11.0) * PW_TAU;

    float3 sum = 0.0;
    [unroll]
    for (int i = 0; i < PW_DOF_SAMPLES; ++i)
    {
        float2 offset = pw_vogel_disc(i, PW_DOF_SAMPLES, theta);
        float2 suv = clamp(uv + offset * coc, 0.0, 1.0 - 2.0 * PW_PIXEL_SIZE);
        sum += tex2Dlod(PW_SceneInDOF, float4(suv, 0, 0)).rgb;
    }
    return float4(sum / float(PW_DOF_SAMPLES), scene.a);
}

#endif
