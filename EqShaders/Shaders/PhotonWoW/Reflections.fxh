// PhotonWoW/Reflections.fxh
// EXPERIMENTAL screen-space reflections. Photon's reflections use its material G-buffer
// (roughness, F0/metal, water mask) and a sky/cloud environment map, none of which exist here.
// This pass:
//   * treats every upward-facing surface as a weak reflector (Schlick, F0 below)
//   * "up" comes from the manual camera pitch slider, because the view matrix is unknown
//   * marches the depth buffer in view space; misses fall back to a flat sky colour
// Expect false reflections on wet-looking dry ground. Real water reflections need a water mask
// (hook; see PORT_MAP.md).

#ifndef PW_REFLECTIONS_FXH
#define PW_REFLECTIONS_FXH

uniform float ReflStrength <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Strength"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.5;
uniform float ReflF0 <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Base reflectance F0"; ui_min = 0.0; ui_max = 0.2; ui_step = 0.001;
    ui_tooltip = "0.02 = dielectric/water.";
> = 0.02;
uniform float ReflCameraPitch <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Camera pitch (deg, + = looking up)"; ui_min = -89.0; ui_max = 89.0; ui_step = 1.0;
    ui_tooltip = "Needed to know which way is up. Keep your camera level (0) while using SSR, or adjust to match.";
> = 0.0;
uniform float ReflMinUp <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Min. up-facing (normal.up)"; ui_min = 0.5; ui_max = 1.0; ui_step = 0.005;
> = 0.93;
uniform float ReflMaxDistance <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Max. ray distance (yards)"; ui_min = 5.0; ui_max = 300.0; ui_step = 1.0;
> = 80.0;
uniform float ReflThickness <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Hit thickness (yards)"; ui_min = 0.1; ui_max = 10.0; ui_step = 0.1;
> = 1.5;
uniform float3 ReflSkyColor <
    ui_type = "color"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Fallback sky colour";
> = float3(0.45, 0.62, 0.95);
uniform float ReflSkyIntensity <
    ui_type = "slider"; ui_category = "Reflections (experimental SSR)";
    ui_label = "Fallback sky intensity"; ui_min = 0.0; ui_max = 10.0; ui_step = 0.05;
> = 1.5;

float4 PS_SSR(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 scene = tex2Dlod(PW_SceneAfterWet, float4(uv, 0, 0));
    float d = pw_depth_at(uv);
    if (pw_is_sky(d)) return scene;

    float3 p0 = pw_view_pos(uv, d);
    float3 n = pw_view_normal(uv);
    float3 v = normalize(p0);

    float pitch = radians(ReflCameraPitch);
    float3 up_view = float3(0.0, cos(pitch), -sin(pitch));
    float up = dot(n, up_view);
    float mask = smoothstep(ReflMinUp, 1.0, up);
    if (mask <= 0.0) return scene;

    float3 r = reflect(v, n);
    float fresnel = ReflF0 + (1.0 - ReflF0) * pow(1.0 - saturate(dot(n, -v)), 5.0);

    float3 sky = pw_srgb_to_working(ReflSkyColor) * ReflSkyIntensity;
    float3 refl = sky;
    float hit_conf = 0.0;

    if (r.z < 0.0)
    {
        float jitter = pw_ign(pos.xy, 7.0);
        float step_len = ReflMaxDistance / float(PW_SSR_STEPS) * 0.2;
        float t = step_len * (0.5 + jitter);
        float grow = pow(5.0, 1.0 / float(PW_SSR_STEPS)); // total length ~ geometric series

        [unroll]
        for (int i = 0; i < PW_SSR_STEPS; ++i)
        {
            float3 p = p0 + r * t;
            if (p.z > -DepthNear) break;
            float2 suv = pw_view_to_uv(p);
            if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) break;

            float sd = pw_depth_at(suv);
            float diff = (-p.z) - sd; // > 0: ray is behind the surface
            if (diff > 0.0 && diff < ReflThickness + 0.05 * t && !pw_is_sky(sd))
            {
                float2 e = abs(suv - 0.5) * 2.0;
                float edge = 1.0 - pw_linear_step(0.8, 1.0, max(e.x, e.y));
                refl = tex2Dlod(PW_SceneAfterWet, float4(suv, 0, 0)).rgb;
                hit_conf = edge;
                break;
            }
            t += step_len;
            step_len *= grow;
            if (t > ReflMaxDistance) break;
        }
    }

    // misses and screen-edge hits fall back to the flat sky colour
    float3 contribution = lerp(sky, refl, hit_conf);
    scene.rgb += contribution * fresnel * mask * ReflStrength;
    return scene;
}

#endif
