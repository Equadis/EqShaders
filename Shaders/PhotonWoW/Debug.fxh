// PhotonWoW/Debug.fxh
// Numeric depth probe drawn with a 7-segment font (ReShade has no text rendering).
// Purpose: calibrate near/far without guessing. Aim the screen-centre crosshair at something at a KNOWN
// distance, read the raw depth, repeat at a second distance, then solve near/far with tools/solve_depth.py
// (raw z of a standard D3D projection is linear in 1/distance:  z = a - a*N*(1/d),  a = F/(F-N)).

#ifndef PW_DEBUG_FXH
#define PW_DEBUG_FXH

// 7-segment masks: bit0=a(top) 1=b(top-right) 2=c(bottom-right) 3=d(bottom) 4=e(bottom-left) 5=f(top-left) 6=g(middle)
float pw_seg_mask(int d)
{
    if (d == 0) return 63.0;
    if (d == 1) return 6.0;
    if (d == 2) return 91.0;
    if (d == 3) return 79.0;
    if (d == 4) return 102.0;
    if (d == 5) return 109.0;
    if (d == 6) return 125.0;
    if (d == 7) return 7.0;
    if (d == 8) return 127.0;
    return 111.0;
}

bool pw_seg_on(float mask, int bit)
{
    return frac(floor(mask / exp2(float(bit))) * 0.5) >= 0.5;
}

// p in [0,1]^2 inside one digit cell (y down)
float pw_digit_pixel(float2 p, int digit)
{
    const float t = 0.16;
    float m = pw_seg_mask(digit);
    float on = 0.0;
    bool xin = p.x > t && p.x < 1.0 - t;
    if (pw_seg_on(m, 0) && p.y < t && xin) on = 1.0;
    if (pw_seg_on(m, 6) && abs(p.y - 0.5) < t * 0.5 && xin) on = 1.0;
    if (pw_seg_on(m, 3) && p.y > 1.0 - t && xin) on = 1.0;
    if (pw_seg_on(m, 1) && p.x > 1.0 - t && p.y > t && p.y < 0.5) on = 1.0;
    if (pw_seg_on(m, 2) && p.x > 1.0 - t && p.y > 0.5 && p.y < 1.0 - t) on = 1.0;
    if (pw_seg_on(m, 5) && p.x < t && p.y > t && p.y < 0.5) on = 1.0;
    if (pw_seg_on(m, 4) && p.x < t && p.y > 0.5 && p.y < 1.0 - t) on = 1.0;
    return on;
}

// Draws `value` (>= 0) as <int_digits> digits, a point, <frac_digits> digits. `cell` = pixel-space uv of a cell grid
// whose origin is the top-left of the number. Returns 1 where the glyph is lit, 0 elsewhere (and -1 outside the number).
float pw_number_pixel(float2 g, float value, int int_digits, int frac_digits)
{
    int cells = int_digits + 1 + frac_digits;
    if (g.x < 0.0 || g.y < 0.0 || g.y >= 1.0 || g.x >= float(cells)) return -1.0;

    int c = int(floor(g.x));
    float2 p = float2(frac(g.x), g.y);

    float scaled = floor(value * exp2(0.0) * pow(10.0, float(frac_digits)) + 0.5);
    if (c == int_digits)
        return (length(p - float2(0.5, 0.9)) < 0.12) ? 1.0 : 0.0; // decimal point

    int k = (c < int_digits) ? (int_digits - 1 - c) + frac_digits : (frac_digits - 1 - (c - int_digits - 1));
    float digit = floor(frac(floor(scaled / pow(10.0, float(k))) * 0.1) * 10.0 + 0.5);
    return pw_digit_pixel(p, int(min(digit, 9.0)));
}

float3 pw_depth_probe(float2 uv)
{
    float3 base = tex2Dlod(BackBuffer, float4(uv, 0, 0)).rgb * 0.35;

    float2 c0 = float2(0.5, 0.5);
    float raw = pw_raw_depth(c0);
    float lin = pw_depth_at(c0);

    // crosshair
    float2 px = (uv - c0) / PW_PIXEL_SIZE;
    if ((abs(px.x) < 1.5 && abs(px.y) < 14.0) || (abs(px.y) < 1.5 && abs(px.x) < 14.0))
        return float3(1.0, 0.2, 0.2);

    // readout block: cell height 36 px, 2 rows, anchored top-left of a panel right of centre
    float cell_h = 36.0 * PW_PIXEL_SIZE.y;
    float cell_w = 24.0 * PW_PIXEL_SIZE.x;
    float2 origin = float2(0.52, 0.42);
    float2 rel = (uv - origin) / float2(cell_w, cell_h);

    // panel
    if (rel.x > -0.5 && rel.x < 11.5 && rel.y > -0.3 && rel.y < 2.9)
        base = lerp(base, float3(0.0, 0.0, 0.0), 0.8);

    // row 0: raw depth as 0.1234567 ; row 1: linear yards as 0123.45
    float v0 = pw_number_pixel(float2(rel.x, rel.y), raw, 1, 7);
    float v1 = pw_number_pixel(float2(rel.x, rel.y - 1.5), lin, 4, 2);
    if (v0 > 0.5) return float3(0.2, 1.0, 0.3);
    if (v1 > 0.5) return float3(1.0, 0.9, 0.2);
    return base;
}

#endif
