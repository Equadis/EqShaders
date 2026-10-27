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

// ---------------------------------------------------------------------------------------------------------------------
// Depth-guided edge smoothing (anti-aliasing). WoW runs without MSAA here (8x MSAA hides the depth ComfyAtmosphere needs),
// so geometry edges are smoothed in post. Edges are found from DEPTH curvature, not colour, so UI text and icons (which
// write no depth) are never blurred. Along an edge the colour is averaged across it, in the direction of the luma gradient.
// ---------------------------------------------------------------------------------------------------------------------
#ifndef PW_ENABLE_AA
    #define PW_ENABLE_AA 1
#endif

uniform int AAMode <
    ui_type = "combo"; ui_category = "Anti-aliasing (depth guided)";
    ui_label = "Mode";
    ui_items = "Off\0Geometry edges\0Geometry edges + thin detail (foliage, grass, fences)\0";
    ui_tooltip = "Both modes are spatial and find edges from DEPTH, so UI text and icons are never blurred.\nThin detail also calms sub-pixel foliage, grass and branches, where the depth is busy.";
> = 2;
uniform float AAStrength <
    ui_type = "slider"; ui_category = "Anti-aliasing (depth guided)";
    ui_label = "Edge smoothing"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "0 = off. Only geometry edges (depth discontinuities) are smoothed; the HUD is untouched.";
> = 0.9;
uniform float AAThinDetail <
    ui_type = "slider"; ui_category = "Anti-aliasing (depth guided)";
    ui_label = "Thin detail smoothing"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "How much busy sub-pixel geometry is averaged (mode 2). Surfaces whose depth is smooth keep every texture detail.";
> = 0.6;
uniform float AAEdgeThreshold <
    ui_type = "slider"; ui_category = "Anti-aliasing (depth guided)";
    ui_label = "Edge sensitivity (lower = more edges)"; ui_min = 0.002; ui_max = 0.10; ui_step = 0.001;
    ui_tooltip = "Relative depth curvature that counts as an edge. Raise it if flat ground shimmers or softens.";
> = 0.012;

float pw_luma_srgb(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

// 0..1 edge amount from depth curvature (about 0 on any flat or evenly sloping surface)
float pw_aa_edge(float2 uv)
{
    float2 px = PW_PIXEL_SIZE;
    float d  = pw_depth_at(uv);
    float dl = pw_depth_at(uv - float2(px.x, 0.0));
    float dr = pw_depth_at(uv + float2(px.x, 0.0));
    float du = pw_depth_at(uv - float2(0.0, px.y));
    float dd = pw_depth_at(uv + float2(0.0, px.y));
    float inv = 1.0 / max(d, 0.1);
    float curv = max(abs(dl + dr - 2.0 * d), abs(du + dd - 2.0 * d)) * inv;
    return smoothstep(AAEdgeThreshold, AAEdgeThreshold * 3.0, curv);
}

// 0..1: how "busy" the depth is round this pixel (sub-pixel leaves, grass blades, branches, fence wires). Flat or evenly sloping
// ground, walls and textured surfaces give ~0 here, so their texture detail is not touched.
float pw_aa_thin(float2 uv)
{
    float2 px = PW_PIXEL_SIZE;
    float d = pw_depth_at(uv);
    float inv = 1.0 / max(d, 0.5);
    float s = 0.0;
    s += abs(pw_depth_at(uv + float2(-px.x, -px.y)) - d);
    s += abs(pw_depth_at(uv + float2( px.x, -px.y)) - d);
    s += abs(pw_depth_at(uv + float2(-px.x,  px.y)) - d);
    s += abs(pw_depth_at(uv + float2( px.x,  px.y)) - d);
    s += abs(pw_depth_at(uv + float2(-2.0 * px.x, 0.0)) - d);
    s += abs(pw_depth_at(uv + float2( 2.0 * px.x, 0.0)) - d);
    s += abs(pw_depth_at(uv + float2(0.0, -2.0 * px.y)) - d);
    s += abs(pw_depth_at(uv + float2(0.0,  2.0 * px.y)) - d);
    return smoothstep(0.010, 0.060, s * inv * 0.125 * 8.0);
}

float3 pw_aa_iso(sampler s, float2 uv)
{
    float2 px = PW_PIXEL_SIZE;
    float3 c = tex2Dlod(s, float4(uv, 0, 0)).rgb * 0.36;
    c += tex2Dlod(s, float4(uv + float2( px.x, 0.0), 0, 0)).rgb * 0.16;
    c += tex2Dlod(s, float4(uv - float2( px.x, 0.0), 0, 0)).rgb * 0.16;
    c += tex2Dlod(s, float4(uv + float2(0.0,  px.y), 0, 0)).rgb * 0.16;
    c += tex2Dlod(s, float4(uv - float2(0.0,  px.y), 0, 0)).rgb * 0.16;
    return c;
}

float3 pw_aa_colour(sampler s, float2 uv)
{
    float2 px = PW_PIXEL_SIZE;
    float3 c  = tex2Dlod(s, float4(uv, 0, 0)).rgb;
    float lr = pw_luma_srgb(tex2Dlod(s, float4(uv + float2(px.x, 0.0), 0, 0)).rgb);
    float ll = pw_luma_srgb(tex2Dlod(s, float4(uv - float2(px.x, 0.0), 0, 0)).rgb);
    float ld = pw_luma_srgb(tex2Dlod(s, float4(uv + float2(0.0, px.y), 0, 0)).rgb);
    float lu = pw_luma_srgb(tex2Dlod(s, float4(uv - float2(0.0, px.y), 0, 0)).rgb);
    float2 g = float2(lr - ll, ld - lu);
    float len = length(g);
    if (len < 1e-4) return c;
    float2 n = g / len * px;               // across the edge
    float3 a1 = tex2Dlod(s, float4(uv + n * 0.5, 0, 0)).rgb;
    float3 a2 = tex2Dlod(s, float4(uv - n * 0.5, 0, 0)).rgb;
    float3 b1 = tex2Dlod(s, float4(uv + n * 1.25, 0, 0)).rgb;
    float3 b2 = tex2Dlod(s, float4(uv - n * 1.25, 0, 0)).rgb;
    return c * 0.4 + (a1 + a2) * 0.2 + (b1 + b2) * 0.1;
}

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
