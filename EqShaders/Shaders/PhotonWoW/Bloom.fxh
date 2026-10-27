// PhotonWoW/Bloom.fxh
// Photon v1.3b bloom: 6-level mip pyramid (c5-c10 downsample), 9-tap binomial gaussian on every
// tile (c12/c13), then a top-down weighted upsample chain (c14-c18); the result is blended into
// the scene at 12% * BLOOM_INTENSITY in c19.
//   downsample : 13-tap filter from "Next Generation Post Processing in Call of Duty: AW"
//   gaussian   : weights 0.2734375 0.21875 0.109375 0.03125 0.00390625, taps within 2px of the tile edge rejected
//   upsample   : dest*(1-w) + bilinear(src)*w, w = mix(0.25, 0.90, 0.5 * BLOOM_SPREAD)
// Photon packs the tiles into one atlas; ReShade gets one texture per tile (same maths, no atlas bookkeeping).

#ifndef PW_BLOOM_FXH
#define PW_BLOOM_FXH

uniform float BloomIntensity <
    ui_type = "slider"; ui_category = "Bloom (Photon c5-c19)";
    ui_label = "Intensity"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_tooltip = "Photon: mix(scene, bloom, 0.12 * BLOOM_INTENSITY).";
> = 1.0;
uniform float BloomThreshold <
    ui_type = "slider"; ui_category = "Bloom (Photon c5-c19)";
    ui_label = "Light threshold"; ui_min = 0.0; ui_max = 8.0; ui_step = 0.05;
    ui_tooltip = "Only light above this (expanded HDR luminance, LDR white = 8) blooms: lamps, sun glints, glowing spells.\nThe test is made on an 8x8-pixel average, so thin bright UI text and icons stay below it.\n0 = Photon's original bloom of the whole image.";
> = 3.0;
uniform float BloomKnee <
    ui_type = "slider"; ui_category = "Bloom (Photon c5-c19)";
    ui_label = "Threshold softness"; ui_min = 0.05; ui_max = 6.0; ui_step = 0.05;
> = 2.0;
uniform float BloomSpread <
    ui_type = "slider"; ui_category = "Bloom (Photon c5-c19)";
    ui_label = "Spread"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;

#define PW_BL(i) max(BUFFER_WIDTH / (2 << i), 1)
#define PW_BH(i) max(BUFFER_HEIGHT / (2 << i), 1)

texture PW_BD0 { Width = BUFFER_WIDTH / 2;  Height = BUFFER_HEIGHT / 2;  Format = RGBA16F; };
texture PW_BD1 { Width = BUFFER_WIDTH / 4;  Height = BUFFER_HEIGHT / 4;  Format = RGBA16F; };
texture PW_BD2 { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 8;  Format = RGBA16F; };
texture PW_BD3 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture PW_BD4 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; };
texture PW_BD5 { Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F; };

texture PW_BT0 { Width = BUFFER_WIDTH / 2;  Height = BUFFER_HEIGHT / 2;  Format = RGBA16F; };
texture PW_BT1 { Width = BUFFER_WIDTH / 4;  Height = BUFFER_HEIGHT / 4;  Format = RGBA16F; };
texture PW_BT2 { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 8;  Format = RGBA16F; };
texture PW_BT3 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture PW_BT4 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; };
texture PW_BT5 { Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F; };

texture PW_BU0 { Width = BUFFER_WIDTH / 2;  Height = BUFFER_HEIGHT / 2;  Format = RGBA16F; };
texture PW_BU1 { Width = BUFFER_WIDTH / 4;  Height = BUFFER_HEIGHT / 4;  Format = RGBA16F; };
texture PW_BU2 { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 8;  Format = RGBA16F; };
texture PW_BU3 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture PW_BU4 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; };

#define PW_BLOOM_SAMPLER(name, tex) \
    sampler name { Texture = tex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

PW_BLOOM_SAMPLER(PW_SBD0, PW_BD0)
PW_BLOOM_SAMPLER(PW_SBD1, PW_BD1)
PW_BLOOM_SAMPLER(PW_SBD2, PW_BD2)
PW_BLOOM_SAMPLER(PW_SBD3, PW_BD3)
PW_BLOOM_SAMPLER(PW_SBD4, PW_BD4)
PW_BLOOM_SAMPLER(PW_SBD5, PW_BD5)
PW_BLOOM_SAMPLER(PW_SBT0, PW_BT0)
PW_BLOOM_SAMPLER(PW_SBT1, PW_BT1)
PW_BLOOM_SAMPLER(PW_SBT2, PW_BT2)
PW_BLOOM_SAMPLER(PW_SBT3, PW_BT3)
PW_BLOOM_SAMPLER(PW_SBT4, PW_BT4)
PW_BLOOM_SAMPLER(PW_SBT5, PW_BT5)
PW_BLOOM_SAMPLER(PW_SBU0, PW_BU0)
PW_BLOOM_SAMPLER(PW_SBU1, PW_BU1)
PW_BLOOM_SAMPLER(PW_SBU2, PW_BU2)
PW_BLOOM_SAMPLER(PW_SBU3, PW_BU3)
PW_BLOOM_SAMPLER(PW_SBU4, PW_BU4)

float3 pw_bloom_fetch(sampler s, float2 uv)
{
    return tex2Dlod(s, float4(uv, 0.0, 0.0)).rgb;
}

// Photon c5_c10: 13-tap downsample. `texel` = source texel size in uv units.
float4 pw_bloom_down(sampler s, float2 uv, float2 texel)
{
    float2 pad = 3.0 * texel;
    uv = clamp(uv, pad, 1.0 - pad);

    float3 c = pw_bloom_fetch(s, uv) * 0.125;

    c += pw_bloom_fetch(s, uv + float2( 1.0,  1.0) * texel) * 0.125;
    c += pw_bloom_fetch(s, uv + float2(-1.0,  1.0) * texel) * 0.125;
    c += pw_bloom_fetch(s, uv + float2( 1.0, -1.0) * texel) * 0.125;
    c += pw_bloom_fetch(s, uv + float2(-1.0, -1.0) * texel) * 0.125;

    c += pw_bloom_fetch(s, uv + float2( 2.0,  0.0) * texel) * 0.0625;
    c += pw_bloom_fetch(s, uv + float2(-2.0,  0.0) * texel) * 0.0625;
    c += pw_bloom_fetch(s, uv + float2( 0.0,  2.0) * texel) * 0.0625;
    c += pw_bloom_fetch(s, uv + float2( 0.0, -2.0) * texel) * 0.0625;

    c += pw_bloom_fetch(s, uv + float2( 2.0,  2.0) * texel) * 0.03125;
    c += pw_bloom_fetch(s, uv + float2(-2.0,  2.0) * texel) * 0.03125;
    c += pw_bloom_fetch(s, uv + float2( 2.0, -2.0) * texel) * 0.03125;
    c += pw_bloom_fetch(s, uv + float2(-2.0, -2.0) * texel) * 0.03125;

    return float4(c, 1.0);
}

// Photon c12/c13: 9-tap binomial gaussian, taps within 2 texels of the tile edge are dropped.
float4 pw_bloom_blur(sampler s, float2 uv, float2 texel, float2 dir, float2 size)
{
    float2 texel_pos = uv * size;
    float3 sum = 0.0;
    float wsum = 0.0;

    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float k = float(abs(i));
        float w = (k < 0.5) ? 0.2734375 : (k < 1.5) ? 0.21875 : (k < 2.5) ? 0.109375 : (k < 3.5) ? 0.03125 : 0.00390625;
        float2 p = texel_pos + dir * float(i);
        float2 lo = float2(2.0, 2.0);
        float2 hi = size - 2.0;
        w *= (p.x >= lo.x && p.x < hi.x + 1.0 && p.y >= lo.y && p.y < hi.y + 1.0) ? 1.0 : 0.0;
        sum += pw_bloom_fetch(s, uv + dir * texel * float(i)) * w;
        wsum += w;
    }
    return float4(sum / max(wsum, 1e-5), 1.0);
}

// Photon c14_c18: dest*(1-w) + bilinear(src)*w
float4 pw_bloom_up(sampler dest, sampler src, float2 uv)
{
    const float src_weight = lerp(0.25, 0.90, 0.5 * BloomSpread);
    float3 c = pw_bloom_fetch(dest, uv) * (1.0 - src_weight);
    c += pw_bloom_fetch(src, uv) * src_weight;
    return float4(c, 1.0);
}

#define PW_TEXEL(i) float2(1.0 / float(PW_BL(i)), 1.0 / float(PW_BH(i)))
#define PW_SIZE(i)  float2(float(PW_BL(i)), float(PW_BH(i)))

// ---- downsample passes (level 0 reads the scene, which is full-res) ----
// Level 0 reads the scene with the SKY left out: a wide bright sky (overcast, horizon haze) is not a light, and letting it
// bloom washed the whole frame out whenever more sky came into view (zooming the camera out or tilting it up).
float3 pw_bloom_fetch_nosky(float2 uv)
{
    float3 c = tex2Dlod(PW_SceneFinal, float4(uv, 0.0, 0.0)).rgb;
    return pw_is_sky(pw_depth_at(uv)) ? float3(0.0, 0.0, 0.0) : c;
}

float4 PS_BloomDown0(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 texel = PW_PIXEL_SIZE;
    float2 pad = 3.0 * texel;
    uv = clamp(uv, pad, 1.0 - pad);

    float3 c = pw_bloom_fetch_nosky(uv) * 0.125;
    c += pw_bloom_fetch_nosky(uv + float2( 1.0,  1.0) * texel) * 0.125;
    c += pw_bloom_fetch_nosky(uv + float2(-1.0,  1.0) * texel) * 0.125;
    c += pw_bloom_fetch_nosky(uv + float2( 1.0, -1.0) * texel) * 0.125;
    c += pw_bloom_fetch_nosky(uv + float2(-1.0, -1.0) * texel) * 0.125;
    c += pw_bloom_fetch_nosky(uv + float2( 2.0,  0.0) * texel) * 0.0625;
    c += pw_bloom_fetch_nosky(uv + float2(-2.0,  0.0) * texel) * 0.0625;
    c += pw_bloom_fetch_nosky(uv + float2( 0.0,  2.0) * texel) * 0.0625;
    c += pw_bloom_fetch_nosky(uv + float2( 0.0, -2.0) * texel) * 0.0625;
    c += pw_bloom_fetch_nosky(uv + float2( 2.0,  2.0) * texel) * 0.03125;
    c += pw_bloom_fetch_nosky(uv + float2(-2.0,  2.0) * texel) * 0.03125;
    c += pw_bloom_fetch_nosky(uv + float2( 2.0, -2.0) * texel) * 0.03125;
    c += pw_bloom_fetch_nosky(uv + float2(-2.0, -2.0) * texel) * 0.03125;
    return float4(c, 1.0);
}
float4 PS_BloomDown1(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_down(PW_SBD0, uv, PW_TEXEL(0)); }
// Bright-pass: from level 2 (1/8 resolution) on, only light above BloomThreshold is kept.
float4 PS_BloomDown2(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = pw_bloom_down(PW_SBD1, uv, PW_TEXEL(1));
    float w = (BloomThreshold <= 0.0) ? 1.0 : smoothstep(BloomThreshold, BloomThreshold + BloomKnee, pw_luma(c.rgb));
    return float4(c.rgb * w, 1.0);
}
float4 PS_BloomDown3(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_down(PW_SBD2, uv, PW_TEXEL(2)); }
float4 PS_BloomDown4(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_down(PW_SBD3, uv, PW_TEXEL(3)); }
float4 PS_BloomDown5(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_down(PW_SBD4, uv, PW_TEXEL(4)); }

// ---- gaussian passes: H writes T, V writes back into D ----
float4 PS_BloomH0(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD0, uv, PW_TEXEL(0), float2(1, 0), PW_SIZE(0)); }
float4 PS_BloomH1(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD1, uv, PW_TEXEL(1), float2(1, 0), PW_SIZE(1)); }
float4 PS_BloomH2(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD2, uv, PW_TEXEL(2), float2(1, 0), PW_SIZE(2)); }
float4 PS_BloomH3(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD3, uv, PW_TEXEL(3), float2(1, 0), PW_SIZE(3)); }
float4 PS_BloomH4(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD4, uv, PW_TEXEL(4), float2(1, 0), PW_SIZE(4)); }
float4 PS_BloomH5(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBD5, uv, PW_TEXEL(5), float2(1, 0), PW_SIZE(5)); }

float4 PS_BloomV0(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT0, uv, PW_TEXEL(0), float2(0, 1), PW_SIZE(0)); }
float4 PS_BloomV1(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT1, uv, PW_TEXEL(1), float2(0, 1), PW_SIZE(1)); }
float4 PS_BloomV2(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT2, uv, PW_TEXEL(2), float2(0, 1), PW_SIZE(2)); }
float4 PS_BloomV3(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT3, uv, PW_TEXEL(3), float2(0, 1), PW_SIZE(3)); }
float4 PS_BloomV4(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT4, uv, PW_TEXEL(4), float2(0, 1), PW_SIZE(4)); }
float4 PS_BloomV5(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_blur(PW_SBT5, uv, PW_TEXEL(5), float2(0, 1), PW_SIZE(5)); }

// ---- upsample chain, coarsest first ----
float4 PS_BloomUp4(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_up(PW_SBD4, PW_SBD5, uv); }
float4 PS_BloomUp3(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_up(PW_SBD3, PW_SBU4, uv); }
float4 PS_BloomUp2(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target { return pw_bloom_up(PW_SBD2, PW_SBU3, uv); }
// The two finest levels hold the unthresholded image (that is the "everything glows" haze), so with a threshold they
// are left out of the chain and the bloom is built from the thresholded coarse levels only.
float4 PS_BloomUp1(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (BloomThreshold <= 0.0) return pw_bloom_up(PW_SBD1, PW_SBU2, uv);
    return float4(pw_bloom_fetch(PW_SBU2, uv) * lerp(0.25, 0.90, 0.5 * BloomSpread), 1.0);
}
float4 PS_BloomUp0(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    if (BloomThreshold <= 0.0) return pw_bloom_up(PW_SBD0, PW_SBU1, uv);
    return float4(pw_bloom_fetch(PW_SBU1, uv) * lerp(0.25, 0.90, 0.5 * BloomSpread), 1.0);
}

// Photon c19: get_bloom() clamps uv by 6 px so the tile edge never shows
float3 pw_get_bloom(float2 uv)
{
    float2 pad = 6.0 * PW_PIXEL_SIZE;
    return pw_bloom_fetch(PW_SBU0, clamp(uv, pad, 1.0 - pad));
}

#endif
