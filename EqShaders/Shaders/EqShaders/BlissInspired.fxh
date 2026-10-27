// EqShaders/BlissInspired.fxh
//
// Clean-room fantasy look for EqShaders, visually inspired by the publicly observable
// characteristics of Bliss Shaders (scene variation, warm highlights, cool atmospheric
// shadows, lush greens, blue skies and generous bloom).
//
// IMPORTANT: No Bliss / Chocapic13 shader source is copied or ported here. Bliss is
// All Rights Reserved. This file is an independently authored approximation built only
// from general rendering techniques and the published visual/settings descriptions.

#ifndef EQ_BLISS_INSPIRED_FXH
#define EQ_BLISS_INSPIRED_FXH

uniform int EqLookMode <
    ui_type = "combo";
    ui_category = "EqShaders look";
    ui_label = "Visual style";
    ui_items = "Photon base\0Natural grade (clean-room)\0Natural grade, strong (clean-room)\0";
    ui_tooltip = "Natural grade: gentle warm sun / cool sky split, a little extra saturation and contrast, no shadow lift. Independently authored; no third-party shader source is included.";
> = 1;

uniform float EqFantasyStrength <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy look strength";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.75;

uniform float EqFantasyWarmHighlights <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Warm highlights";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.16;

uniform float EqFantasyCoolShadows <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Cool atmospheric shadows";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.1;

uniform float EqFantasySaturation <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy saturation";
    ui_min = -0.25; ui_max = 0.50; ui_step = 0.01;
> = 0.08;

uniform float EqFantasyGreenLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Lush green lift";
    ui_min = 0.0; ui_max = 0.50; ui_step = 0.01;
> = 0;

uniform float EqFantasyBlueLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Sky / water blue lift";
    ui_min = 0.0; ui_max = 0.40; ui_step = 0.01;
> = 0;

uniform float EqFantasyContrast <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy contrast";
    ui_min = 0.85; ui_max = 1.25; ui_step = 0.01;
> = 1.06;

uniform float EqFantasyShadowLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Atmospheric shadow lift";
    ui_min = 0.0; ui_max = 0.20; ui_step = 0.005;
> = 0.08;

uniform float EqFantasyBloomBoost <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy bloom boost";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0;

float eq_fantasy_amount()
{
    if (EqLookMode == 0) return 0.0;
    float mode_gain = (EqLookMode == 2) ? 1.30 : 1.0;
    return saturate(EqFantasyStrength * mode_gain);
}

float eq_luma709(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Rec.2020 linear HDR in/out. This happens before the Photon colour grade / tonemap.
float3 eq_fantasy_pre_tonemap(float3 c)
{
    float amount = eq_fantasy_amount();
    if (amount <= 0.0001) return c;

    float lum = max(pw_luma(c), 0.0);
    float shadow = 1.0 - smoothstep(0.08, 0.75, lum);
    float highlight = smoothstep(0.55, 2.25, lum);

    // Cool ambient shade + warm sunlit/highlight split. This is deliberately mild because
    // ComfyAtmosphere already supplies the actual world-space light and shadow behaviour.
    float3 cool_tint = float3(0.90, 0.975, 1.10);
    float3 warm_tint = float3(1.09, 1.015, 0.91);
    float3 neutral = float3(1.0, 1.0, 1.0);
    c *= lerp(neutral, cool_tint, shadow * EqFantasyCoolShadows * amount);
    c *= lerp(neutral, warm_tint, highlight * EqFantasyWarmHighlights * amount);

    // Shadow floor: indirect light. A shaded face is a darker version of its material, never black. The lift keeps each pixel's
    // own hue (so texture and colour survive) and fades out by mid-tones. Up to 0.20 on the slider = a linear floor of 0.08.
    float3 hue = clamp(c / (lum + 0.01), 0.3, 2.0);
    c += hue * (EqFantasyShadowLift * 0.4 * amount * (1.0 - smoothstep(0.0, 0.30, lum)));

    // Gentle contrast around middle grey, but only from the mid-tones up: the deep end is not pushed to black.
    float contrast = lerp(1.0, EqFantasyContrast, amount);
    float3 contrasted = max((c - 0.18) * contrast + 0.18, 0.0);
    c = lerp(c, contrasted, smoothstep(0.03, 0.22, lum));

    return c;
}

// Rec.709 linear [0,1] in/out. This happens after Photon output grading and before display EOTF.
float3 eq_fantasy_post_grade(float3 c)
{
    float amount = eq_fantasy_amount();
    if (amount <= 0.0001) return c;

    c = saturate(c);
    float lum = eq_luma709(c);

    // Saturation in linear light, kept conservative to avoid neon WoW UI/text.
    c = saturate(lerp(lum.xxx, c, 1.0 + EqFantasySaturation * amount));

    // Approximate vegetation and blue-surface masks from channel dominance. These are not
    // material IDs; they are intentionally soft so UI/characters are not aggressively recoloured.
    float green_dom = saturate((c.g - max(c.r, c.b)) * 5.0 + 0.10);
    green_dom *= smoothstep(0.04, 0.55, lum) * (1.0 - smoothstep(0.80, 1.0, lum));
    c.g = saturate(c.g * (1.0 + EqFantasyGreenLift * green_dom * amount));

    float blue_dom = saturate((c.b - max(c.r, c.g)) * 4.0 + 0.08);
    blue_dom *= smoothstep(0.08, 0.85, lum);
    c.b = saturate(c.b * (1.0 + EqFantasyBlueLift * blue_dom * amount));
    c.g = saturate(c.g * (1.0 + 0.30 * EqFantasyBlueLift * blue_dom * amount));

    return c;
}

float eq_fantasy_bloom_gain()
{
    return 1.0 + EqFantasyBloomBoost * eq_fantasy_amount();
}

#endif
