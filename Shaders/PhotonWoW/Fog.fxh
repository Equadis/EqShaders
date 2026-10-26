// PhotonWoW/Fog.fxh
// Atmospheric fog following the structure of Photon's include/fog/overworld/analytic.glsl:
//   optical depth -> transmittance -> scattering integral -> Rayleigh + Mie (two-lobe HG) -> 4-octave
//   multiple-scattering loop (scatter_amount *= 0.5, anisotropy *= 0.7).
//
// NOT portable from Photon (needs the renderer, see PORT_MAP.md):
//   * world position / height falloff  (needs camera world position + inverse view matrix)
//   * real light_dir / sun_dir / ambient_color from the sky model (needs time of day + sky capture)
//   * shadowed (volumetric) fog
// So: sun direction is a manual camera-relative input and light colours are user inputs.
// Scattering coefficients are NORMALISED Earth-like Rayleigh ratios, not Photon's physical units,
// because WoW world scale and fog density are not Minecraft's.

#ifndef PW_FOG_FXH
#define PW_FOG_FXH

uniform float SunAzimuth <
    ui_type = "slider"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Sun azimuth (deg, 0 = straight ahead)"; ui_min = -180.0; ui_max = 180.0; ui_step = 1.0;
    ui_tooltip = "Without a hook we do not know the camera yaw or time of day. Point this at the sun yourself.\n"
                 "Hooked version: read WoW's sun/light direction and view matrix (see PORT_MAP.md).";
> = 20.0;
uniform float SunElevation <
    ui_type = "slider"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Sun elevation (deg above camera horizon)"; ui_min = -30.0; ui_max = 90.0; ui_step = 1.0;
> = 25.0;
uniform float3 SunColor <
    ui_type = "color"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Sun light colour";
> = float3(1.0, 0.90, 0.75);
uniform float SunIntensity <
    ui_type = "slider"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Sun intensity"; ui_min = 0.0; ui_max = 40.0; ui_step = 0.1;
> = 8.0;
uniform float3 AmbientColor <
    ui_type = "color"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Sky ambient colour";
> = float3(0.45, 0.62, 0.95);
uniform float AmbientIntensity <
    ui_type = "slider"; ui_category = "Sun / sky (manual, camera-relative)";
    ui_label = "Ambient intensity"; ui_min = 0.0; ui_max = 20.0; ui_step = 0.1;
> = 3.0;

uniform bool EnableFog <
    ui_category = "Atmospheric fog";
    ui_label = "Enable atmospheric fog";
    ui_tooltip = "WoW already bakes fog into the image. Stacking this on top double-fogs. Start with the game's own fog reduced (see OctoFog.ini DensityMultiplier).";
> = false;
uniform float FogRayleighDensity <
    ui_type = "slider"; ui_category = "Atmospheric fog";
    ui_label = "Rayleigh (blue) optical depth at 500 yd"; ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
> = 0.30;
uniform float FogMieDensity <
    ui_type = "slider"; ui_category = "Atmospheric fog";
    ui_label = "Mie (haze) optical depth at 500 yd"; ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
> = 0.45;
uniform float FogSkyFog <
    ui_type = "slider"; ui_category = "Atmospheric fog";
    ui_label = "Fog on sky/clear pixels"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Sky shares depth with the UI. Keep at 0 unless the UI is masked.";
> = 0.0;

// Photon: phase_functions.glsl
float pw_henyey_greenstein(float nu, float g)
{
    float gg = g * g;
    return (PW_ISOTROPIC_PHASE - PW_ISOTROPIC_PHASE * gg) / pow(max(1.0 + gg - 2.0 * g * nu, 1e-4), 1.5);
}

float3 pw_sun_dir_view()
{
    float az = radians(SunAzimuth);
    float el = radians(SunElevation);
    return normalize(float3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)));
}

float3 pw_ray_dir_view(float2 uv)
{
    float2 t = pw_tan_half_fov();
    return normalize(float3((uv.x * 2.0 - 1.0) * t.x, (1.0 - uv.y * 2.0) * t.y, -1.0));
}

// scene, ambient and light colours in Rec.2020 working space. Returns lit colour; transmittance_lum = luminance of T.
float3 pw_apply_fog(float3 scene, float dist_axis, float3 ray_dir, bool sky, out float transmittance_lum)
{
    transmittance_lum = 1.0;
    if (!EnableFog) return scene;
    if (sky && FogSkyFog <= 0.0) return scene;

    const float3 rayleigh_coeff = float3(0.175, 0.408, 1.0) * (FogRayleighDensity / 500.0);
    const float3 mie_scatter_coeff = float3(1.0, 1.0, 1.0) * (FogMieDensity / 500.0);
    const float3 mie_extinction_coeff = mie_scatter_coeff * 1.11;

    float ray_length = dist_axis / max(-ray_dir.z, 0.05); // axis depth -> radial distance
    float2 airmass = float2(ray_length, ray_length) * 0.5;

    float3 optical_depth = rayleigh_coeff * airmass.x + mie_extinction_coeff * airmass.y;
    float3 transmittance = exp(-optical_depth);
    float3 scattering_integral = (1.0 - transmittance) / max(optical_depth, PW_EPS);

    float3 rayleigh_scattering = scattering_integral * airmass.x * rayleigh_coeff;
    float3 mie_scattering = scattering_integral * airmass.y * mie_scatter_coeff;

    float3 light_color = pw_srgb_to_working(SunColor) * SunIntensity;
    float3 ambient_color = pw_srgb_to_working(AmbientColor) * AmbientIntensity;

    float LoV = dot(ray_dir, pw_sun_dir_view());

    // multiple scattering (Photon analytic.glsl)
    float3 scattering = 2.0 * (rayleigh_scattering + mie_scattering) * PW_ISOTROPIC_PHASE * ambient_color;

    float scatter_amount = 1.0;
    float anisotropy = 1.0;
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        float mie_phase = 0.7 * pw_henyey_greenstein(LoV, 0.5 * anisotropy)
                        + 0.3 * pw_henyey_greenstein(LoV, -0.2 * anisotropy);

        scattering += scatter_amount * (rayleigh_scattering * PW_ISOTROPIC_PHASE + mie_scattering * mie_phase) * light_color;

        scatter_amount *= 0.5;
        anisotropy *= 0.7;
    }

    float f = sky ? FogSkyFog : 1.0;
    transmittance = lerp(1.0, transmittance, f);
    transmittance_lum = dot(transmittance, float3(0.3333, 0.3333, 0.3334));
    return scene * transmittance + max(scattering, 0.0) * f;
}

#endif
