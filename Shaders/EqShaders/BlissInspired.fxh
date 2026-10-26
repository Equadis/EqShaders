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
    ui_items = "Photon base\0Bliss-inspired hybrid (clean-room)\0Bliss-inspired strong (clean-room)\0";
    ui_tooltip = "The Bliss-inspired modes are independently authored look approximations. No Bliss shader source is included or ported.";
> = 1;

uniform float EqFantasyStrength <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy look strength";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.65;

uniform float EqFantasyWarmHighlights <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Warm highlights";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.38;

uniform float EqFantasyCoolShadows <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Cool atmospheric shadows";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.24;

uniform float EqFantasySaturation <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy saturation";
    ui_min = -0.25; ui_max = 0.50; ui_step = 0.01;
> = 0.10;

uniform float EqFantasyGreenLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Lush green lift";
    ui_min = 0.0; ui_max = 0.50; ui_step = 0.01;
> = 0.10;

uniform float EqFantasyBlueLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Sky / water blue lift";
    ui_min = 0.0; ui_max = 0.40; ui_step = 0.01;
> = 0.05;

uniform float EqFantasyContrast <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy contrast";
    ui_min = 0.85; ui_max = 1.25; ui_step = 0.01;
> = 1.04;

uniform float EqFantasyShadowLift <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Atmospheric shadow lift";
    ui_min = 0.0; ui_max = 0.20; ui_step = 0.005;
> = 0.035;

uniform float EqFantasyBloomBoost <
    ui_type = "slider"; ui_category = "EqShaders look";
    ui_label = "Fantasy bloom boost";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

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
    c *= lerp(1.0.xxx, cool_tint, shadow * EqFantasyCoolShadows * amount);
    c *= lerp(1.0.xxx, warm_tint, highlight * EqFantasyWarmHighlights * amount);

    // Lift the deepest shadows very slightly instead of crushing them. The blue-biased lift
    // helps distant/rainy scenes retain atmospheric colour rather than becoming grey/black.
    c += float3(0.55, 0.72, 1.00) * (EqFantasyShadowLift * shadow * amount * 0.08);

    // Gentle scene contrast around photographic middle grey.
    float contrast = lerp(1.0, EqFantasyContrast, amount);
    c = max((c - 0.18) * contrast + 0.18, 0.0);

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
