// EqShaders/Bridge.fxh
// Values from the game that a post-process cannot see, delivered as PIXELS:
//   * EqPixelBridge.dll (a D3D9 hook) writes 16 pixels into the bottom-right corner of the back buffer just before Present:
//       camera world position, camera matrix, weather type and grade (read-only from the client's memory).
//   * the EqProfiles addon (Lua) draws 4 coloured cells at the bottom edge: the biome's baseline ground wetness.
// A 20x1 pass decodes them once per frame into PW_BridgeTex and PS_Prep / PS_Final paint the corner over, so the
// pixels never reach the screen. If the markers are missing every accessor reports "not valid" and wet-ground switches off.
//
// Native strip: x = W-1-i, y = H-1, i = 0..15 (see EqPixelBridge.cpp for the layout). Lua strip: 6-pixel cells starting at
// x = 700, centres at y = H-4.

#ifndef EQ_BRIDGE_FXH
#define EQ_BRIDGE_FXH

#define EQ_BRIDGE_TEXELS 20.0
#define EQ_LUA_STRIP_X0  700.0
#define EQ_LUA_CELL      6.0

texture PW_BridgeTex { Width = 20; Height = 1; Format = RGBA32F; };
sampler PW_BridgeS { Texture = PW_BridgeTex; AddressU = CLAMP; AddressV = CLAMP; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; };

// 0..15 native strip, 16..19 Lua strip. Output: x = 24-bit value / 16777215, yzw = the three bytes / 255
float4 PS_BridgeDecode(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    int i = int(pos.x);
    float2 p;
    if (i < 16)
        p = float2(float(BUFFER_WIDTH) - 1.0 - float(i) + 0.5, float(BUFFER_HEIGHT) - 0.5);
    else
        p = float2(EQ_LUA_STRIP_X0 + EQ_LUA_CELL * float(i - 16) + 0.5 * EQ_LUA_CELL, float(BUFFER_HEIGHT) - 4.0);
    float3 b = round(tex2Dlod(BackBuffer, float4(p * PW_PIXEL_SIZE, 0, 0)).rgb * 255.0);
    float v = (b.r * 65536.0 + b.g * 256.0 + b.b) / 16777215.0;
    return float4(v, b / 255.0);
}

float4 eq_btex(int i) { return tex2Dlod(PW_BridgeS, float4((float(i) + 0.5) / EQ_BRIDGE_TEXELS, 0.5, 0, 0)); }

bool eq_bytes_are(float3 got, float3 want) { return all(abs(got * 255.0 - want) < 0.5); }

// the native strip (camera + weather) is present, intact, and the game world is up
bool eq_bridge_ok()
{
    float4 a = eq_btex(0), f = eq_btex(14), z = eq_btex(15);
    return eq_bytes_are(a.yzw, float3(234.0, 113.0, 177.0))    // 0xEA 0x71 0xB1
        && eq_bytes_are(z.yzw, float3(21.0, 142.0, 78.0))      // 0x15 0x8E 0x4E
        && abs(f.y * 255.0 - 1.0) < 0.5                        // format version 1
        && abs(f.z * 255.0 - 255.0) < 0.5;                     // world valid
}

float3 eq_cam_pos()
{
    return float3(eq_btex(1).x * 40000.0 - 20000.0,
                  eq_btex(2).x * 40000.0 - 20000.0,
                  eq_btex(3).x * 12000.0 - 4000.0);
}

// row r (0..2) of the camera matrix block, first three columns
float3 eq_cam_row(int r)
{
    return float3(eq_btex(4 + r * 3).x, eq_btex(5 + r * 3).x, eq_btex(6 + r * 3).x) * 2.5 - 1.25;
}

// weather: x = type (0 fine, 1 rain, 2 snow, 3 storm), y = grade 0..1
float2 eq_weather()
{
    float4 w = eq_btex(13);
    return float2(round(w.y * 255.0), w.z);
}

// Lua strip present? and the biome's baseline: x = ground wetness, y = puddle tendency, z = murk (0 clear .. 1 muddy)
bool eq_profile_ok()
{
    return eq_bytes_are(eq_btex(16).yzw, float3(255.0, 0.0, 255.0)) && eq_bytes_are(eq_btex(19).yzw, float3(0.0, 255.0, 255.0));
}
float3 eq_profile_wet() { return eq_btex(17).yzw; }
// the player is indoors (EqProfiles' flag): no rain, no puddles
bool eq_indoor() { return eq_profile_ok() && eq_btex(18).y > 0.5; }
// 0..1 how far indoors (faded by the addon), and daylight 0 (night) .. 1 (day)
float eq_indoor_amount() { return eq_profile_ok() ? eq_btex(18).y : 0.0; }
float eq_daylight() { return eq_profile_ok() ? eq_btex(18).z : 1.0; }

// uv to read the ORIGINAL game image from: the two strips are replaced by the row 8 pixels higher
float2 eq_unstrip(float2 uv)
{
    float2 pp = uv / PW_PIXEL_SIZE;
    bool in_native = pp.x >= float(BUFFER_WIDTH) - 18.0;
    bool in_lua = pp.x >= EQ_LUA_STRIP_X0 - 4.0 && pp.x < EQ_LUA_STRIP_X0 + EQ_LUA_CELL * 4.0 + 4.0;
    bool bottom = pp.y >= float(BUFFER_HEIGHT) - 8.0;
    if (bottom && (in_native || in_lua)) uv.y -= 9.0 * PW_PIXEL_SIZE.y;
    return uv;
}

#endif
