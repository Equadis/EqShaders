// PhotonWoW/ColorGrade.fxh
// Ported from Photon v1.3b program/c19_color_grading.fsh and include/utility/color.glsl.
// Note: Photon's "rgb_to_hsl" is actually HSV (z = max channel). That is preserved on purpose,
// because the teal/orange/green isolation curves were tuned against it.

#ifndef PW_COLORGRADE_FXH
#define PW_COLORGRADE_FXH

uniform float GradeBrightness <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Brightness"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float GradeContrast <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Contrast"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float GradeSaturation <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Saturation"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;
uniform float GradeOrangeSat <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Orange saturation boost"; ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;
uniform float GradeTealSat <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Teal saturation boost"; ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.10;
uniform float GradeGreenSat <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Green saturation boost"; ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;
uniform float GradeGreenHue <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Green hue shift (degrees)"; ui_min = -8.0; ui_max = 8.0; ui_step = 1.0;
> = 0.0;
uniform float VignetteIntensity <
    ui_type = "slider"; ui_category = "Colour grade (Photon c19)";
    ui_label = "Vignette intensity"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;

// Photon: global.glsl pulse() with periodic wrap
float pw_pulse(float x, float center, float width, float period)
{
    x = (x - center + 0.5 * period) / period;
    x = frac(x) * period - 0.5 * period;
    x = abs(x) / width;
    return x > 1.0 ? 0.0 : 1.0 - pw_cubic_smooth(x);
}

// Photon: color.glsl
float3 pw_rgb_to_hsl(float3 c)
{
    const float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    const float e = 1e-6;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 pw_hsl_to_rgb(float3 c)
{
    const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    c.yz = saturate(c.yz);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float pw_isolate_hue(float3 hsl, float center, float width)
{
    if (hsl.y < 1e-2 || hsl.z < 1e-2) return 0.0;
    return pw_pulse(hsl.x * 360.0, center, width, 360.0);
}

float3 pw_gain(float3 x, float k)
{
    float3 s = step(0.5, x);
    float3 a = 0.5 * pow(2.0 * lerp(x, 1.0 - x, s), k);
    return lerp(a, 1.0 - a, s);
}

// rgb: Rec.2020 linear HDR in, same out. (white balance omitted: default 6500K is identity)
float3 pw_grade_input(float3 rgb)
{
    float brightness = 0.83 * GradeBrightness;
    float contrast   = 1.00 * GradeContrast;
    float saturation = 0.98 * GradeSaturation;

    rgb *= brightness;

    const float log_midpoint = -2.473931188; // log2(0.18)
    rgb = log2(rgb + PW_EPS);
    rgb = contrast * (rgb - log_midpoint) + log_midpoint;
    rgb = max(exp2(rgb) - PW_EPS, 0.0);

    float lum = pw_luma(rgb);
    rgb = max(lerp(lum.xxx, rgb, saturation), 0.0);
    return rgb;
}

// rgb: Rec.709 linear [0,1] in, same out
float3 pw_grade_output(float3 rgb)
{
    rgb = sqrt(rgb); // roughly perceptual

    float3 hsl = pw_rgb_to_hsl(rgb);

    float orange = pw_isolate_hue(hsl, 30.0, 20.0);
    hsl.y *= 1.0 + GradeOrangeSat * orange;

    float teal = pw_isolate_hue(hsl, 210.0, 20.0);
    hsl.y *= 1.0 + GradeTealSat * teal;

    float green = pw_isolate_hue(hsl, 90.0, 44.0);
    hsl.x += (GradeGreenHue / 360.0) * green;
    hsl.y *= 1.0 + GradeGreenSat * green;

    rgb = pw_hsl_to_rgb(hsl);
    rgb = pw_gain(rgb, 1.05);
    return rgb * rgb;
}

float pw_vignette(float2 uv)
{
    const float vignette_size = 16.0;
    float intensity = 0.08 * VignetteIntensity;
    float v = vignette_size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    return pow(max(v, 0.0), intensity);
}

#endif
