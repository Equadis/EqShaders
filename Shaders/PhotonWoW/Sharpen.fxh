// PhotonWoW/Sharpen.fxh
// FidelityFX CAS exactly as Photon v1.3b program/final.fsh cas_filter() runs it:
// on display-encoded (sRGB-ish) values, as the very last step, with sharpness = CAS_INTENSITY * 2 - 1.

#ifndef PW_SHARPEN_FXH
#define PW_SHARPEN_FXH

uniform float CASIntensity <
    ui_type = "slider"; ui_category = "Sharpening (Photon CAS)";
    ui_label = "CAS intensity"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Photon default 0.5 (sharpness 0.0).";
> = 0.5;
uniform bool Dither8Bit <
    ui_category = "Sharpening (Photon CAS)";
    ui_label = "Output dither (hides banding from the tone curve)";
> = true;

float3 pw_cas(sampler s, float2 uv, float sharpness)
{
    float2 px = PW_PIXEL_SIZE;
    float3 a = tex2Dlod(s, float4(uv + float2(-px.x, -px.y), 0, 0)).rgb;
    float3 b = tex2Dlod(s, float4(uv + float2( 0.0,  -px.y), 0, 0)).rgb;
    float3 c = tex2Dlod(s, float4(uv + float2( px.x, -px.y), 0, 0)).rgb;
    float3 d = tex2Dlod(s, float4(uv + float2(-px.x,  0.0), 0, 0)).rgb;
    float3 e = tex2Dlod(s, float4(uv, 0, 0)).rgb;
    float3 f = tex2Dlod(s, float4(uv + float2( px.x,  0.0), 0, 0)).rgb;
    float3 g = tex2Dlod(s, float4(uv + float2(-px.x,  px.y), 0, 0)).rgb;
    float3 h = tex2Dlod(s, float4(uv + float2( 0.0,   px.y), 0, 0)).rgb;
    float3 i = tex2Dlod(s, float4(uv + float2( px.x,  px.y), 0, 0)).rgb;

    // soft min and max (2x bigger, extra multiply factored out)
    float3 min_color = min(min(min(d, e), min(f, b)), h);
    min_color += min(min(min(min_color, a), min(c, g)), i);

    float3 max_color = max(max(max(d, e), max(f, b)), h);
    max_color += max(max(max(max_color, a), max(c, g)), i);

    float3 w = saturate(min(min_color, 2.0 - max_color) / max(max_color, 1e-5));
    w = 1.0 - pw_sqr(1.0 - w);
    w *= -1.0 / lerp(8.0, 5.0, sharpness);

    float3 weight_sum = 1.0 + 4.0 * w;
    return saturate((b + d + f + h) * w + e) / weight_sum;
}

#endif
