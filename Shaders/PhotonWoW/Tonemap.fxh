// PhotonWoW/Tonemap.fxh
// Photon tonemap operators (post_processing/tonemap_operators.glsl) + an LDR->HDR expansion stage.
//
// WHY THE EXPANSION EXISTS: Photon tonemaps an HDR scene. WoW hands us an already-tonemapped
// 8-bit image. Running Lottes on it unmodified maps white (1.0) to 0.66 and the whole image
// goes grey and dark (that was the v0.1 bug). We first lift LDR into a pseudo-HDR range with an
// inverse-Reinhard curve whose white point equals Photon's Lottes hdr_max (8.0), so LDR white
// lands back at ~white after the Photon curve. Dark/mid values are barely touched.

#ifndef PW_TONEMAP_FXH
#define PW_TONEMAP_FXH

uniform int TonemapOperator <
    ui_type = "combo";
    ui_category = "Tone mapping";
    ui_label = "Tonemap operator";
    ui_items = "Lottes (Photon default)\0Hejl 2015\0Hejl-Burgess (Tech)\0Tech (Lux)\0Uncharted 2\0Ozius\0Reinhard\0Reinhard (Jodie)\0None (identity)\0";
    ui_tooltip = "Photon v1.3b ships with Lottes. ACES variants are not ported yet.";
> = 0;

uniform float HdrExpansion <
    ui_type = "slider";
    ui_category = "Tone mapping";
    ui_label = "LDR -> HDR highlight expansion";
    ui_tooltip = "0 = treat game image as-is (white will render grey through Photon's curve).\n"
                 "0.875 = LDR white expands to 8.0 = Photon's Lottes white point, so white stays white.\n"
                 "Higher = more bloom-able, punchier highlights.";
    ui_min = 0.0; ui_max = 0.97; ui_step = 0.005;
> = 0.875;

uniform float Exposure <
    ui_type = "slider";
    ui_category = "Tone mapping";
    ui_label = "Exposure";
    ui_tooltip = "Photon uses auto-exposure; WoW has no HDR luminance so this is fixed.";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.01;
> = 1.0;

// Photon: tonemap_lottes (GDC 2016 "Advanced Techniques and Optimization of HDR Color Pipelines")
float3 pw_tonemap_lottes(float3 rgb)
{
    const float a = 1.5;      // contrast
    const float d = 0.91;     // shoulder contrast
    const float hdr_max = 8.0;
    const float mid_in = 0.26;
    const float mid_out = 0.32;

    const float b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
                  / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    const float c = (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
                  / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

    rgb = max(rgb, 0.0);
    return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

float3 pw_tonemap_hejl_2015(float3 rgb)
{
    const float white_point = 5.0;
    float4 vh = float4(rgb, white_point);
    float4 va = (1.425 * vh) + 0.05;
    float4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;
    return vf.rgb / vf.www;
}

float3 pw_tonemap_hejl_burgess(float3 rgb)
{
    rgb = rgb * min(1.0, 1.0 - 0.8 * exp(-rgb / 0.004));
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return pw_display_eotf_inv(rgb);
}

float3 pw_tonemap_tech(float3 rgb)
{
    float3 a = rgb * min(1.0, 1.0 - exp(-1.0 / 0.038 * rgb));
    a = lerp(a, rgb, rgb * rgb);
    return a / (a + 0.6);
}

float3 pw_uncharted2_partial(float3 x)
{
    const float a = 0.15, b = 0.50, c = 0.10, d = 0.20, e = 0.02, f = 0.30;
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
}

float3 pw_tonemap_uncharted2(float3 rgb)
{
    const float exposure_bias = 2.0;
    float3 curr = pw_uncharted2_partial(rgb * exposure_bias);
    float3 white_scale = 1.0 / pw_uncharted2_partial(float3(11.2, 11.2, 11.2));
    return curr * white_scale;
}

float3 pw_tonemap_ozius(float3 rgb)
{
    const float a = 0.46;
    const float b = 0.60;
    rgb *= 1.6;
    float3 cr = lerp(dot(rgb, float3(0.2722, 0.6741, 0.0537)).xxx, rgb, 0.5) + 1.0;
    rgb = pow(rgb / (1.0 + rgb), a);
    return pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b);
}

float3 pw_tonemap_reinhard(float3 rgb) { return rgb / (rgb + 1.0); }

float3 pw_tonemap_reinhard_jodie(float3 rgb)
{
    float3 r = rgb / (rgb + 1.0);
    return lerp(rgb / (pw_luma(rgb) + 1.0), r, r);
}

float3 pw_tonemap(float3 rgb)
{
    if (TonemapOperator == 0) return pw_tonemap_lottes(rgb);
    if (TonemapOperator == 1) return pw_tonemap_hejl_2015(rgb);
    if (TonemapOperator == 2) return pw_tonemap_hejl_burgess(rgb);
    if (TonemapOperator == 3) return pw_tonemap_tech(rgb);
    if (TonemapOperator == 4) return pw_tonemap_uncharted2(rgb);
    if (TonemapOperator == 5) return pw_tonemap_ozius(rgb);
    if (TonemapOperator == 6) return pw_tonemap_reinhard(rgb);
    if (TonemapOperator == 7) return pw_tonemap_reinhard_jodie(rgb);
    return rgb;
}

// Inverse-Reinhard LDR expansion: x / (1 - s*x). Applied per channel in linear working space.
float3 pw_expand_ldr(float3 lin)
{
    float3 x = saturate(lin);
    return x / max(1.0 - x * HdrExpansion, 1.0 / 64.0);
}

#endif
