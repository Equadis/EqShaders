// EqBridge: ReShade add-on that hands rendering state the shaders cannot see to EqShaders as uniforms.
// READ-ONLY: it reads a few floats from the game's own memory (camera position/orientation, weather state) and writes
// ReShade uniforms. It never writes game memory and touches nothing but rendering state.
//
// Addresses (WoW.exe 1.12.1.5875, found by static analysis of the client; Comfy's [client] camAddr is the same block):
//   camera world position   float x,y,z        at 0x00C7CF20
//   camera matrix block     4x4 floats         at 0x00C7CF30 (orientation; layout is logged for verification)
//   weather manager         pointer            at 0x00C6326C ; +0x0C target grade (float 0..1), +0x10 previous grade,
//                                                                +0x20 weather type (int 0..3)
// Config: EqBridge.ini next to WoW.exe. Log: Logs\EqBridge.log
// Build: see build.ps1 (llvm-mingw, i686). ReShade is MSVC-built, so its virtual methods are called by hand (__thiscall).

#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdio>
#include <cstdint>
#include <cstdarg>
#include <cstring>
#include <cmath>
#include <string>
#include <map>

using namespace reshade::api;

namespace
{
    constexpr uintptr_t ADDR_CAM_POS = 0x00C7CF20;
    constexpr uintptr_t ADDR_CAM_BLOCK = 0x00C7CF20;   // dump from the position through the matrices
    constexpr size_t    CAM_BLOCK_BYTES = 0x1E0;
    constexpr uintptr_t ADDR_CAM_M = 0x00C7CF30;
    constexpr uintptr_t ADDR_WEATHER_PTR = 0x00C6326C;

    effect_runtime *g_runtime = nullptr;
    FILE *g_log = nullptr;
    std::string g_dir;
    bool g_push = true;            // write uniforms
    int  g_log_hz = 2;             // memory dump rate while logging (0 = off)
    bool g_selftest_done = false, g_selftest_ok = false;
    bool g_have_uniforms = false;
    std::map<std::string, uint64_t> g_uni;     // uniform name -> handle (EqShaders.fx)
    float g_last_block[CAM_BLOCK_BYTES / 4] = {};
    ULONGLONG g_last_log = 0;
    uint32_t g_frames = 0;

    void logf(const char *fmt, ...)
    {
        if (!g_log) return;
        va_list a; va_start(a, fmt); vfprintf(g_log, fmt, a); va_end(a);
        fputc('\n', g_log); fflush(g_log);
    }

    bool read_mem(uintptr_t addr, void *dst, size_t n)
    {
        SIZE_T got = 0;
        return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(addr), dst, n, &got) && got == n;
    }

    void read_config()
    {
        const std::string p = g_dir + "EqBridge.ini";
        g_push = GetPrivateProfileIntA("EqBridge", "Push", 1, p.c_str()) != 0;
        g_log_hz = GetPrivateProfileIntA("EqBridge", "LogHz", 2, p.c_str());
    }

    // ---- ReShade effect_runtime virtual calls (MSVC __thiscall) ----
    // slots: 5 get_hwnd, 7 get_back_buffer_count, 8 get_current_back_buffer_index, 20 enumerate_uniform_variables,
    //        23 get_uniform_variable_name, 30 get_uniform_value_float, 34 set_uniform_value_float
    typedef void *(__attribute__((thiscall)) *fn_hwnd)(void *);
    typedef uint32_t(__attribute__((thiscall)) *fn_u32)(void *);
    typedef void(__attribute__((thiscall)) *fn_enum)(void *, const char *, void (*)(void *, uint64_t, void *), void *);
    typedef void(__attribute__((thiscall)) *fn_name)(void *, uint64_t, char *, size_t *);
    typedef void(__attribute__((thiscall)) *fn_getf)(void *, uint64_t, float *, size_t, size_t);
    typedef void(__attribute__((thiscall)) *fn_setf)(void *, uint64_t, const float *, size_t, size_t);

    void *vslot(int i) { return (*reinterpret_cast<void ***>(g_runtime))[i]; }

    void on_uniform(void *rt, uint64_t var, void *)
    {
        char name[128] = {}; size_t sz = sizeof name;
        reinterpret_cast<fn_name>(vslot(23))(rt, var, name, &sz);
        if (name[0]) g_uni[name] = var;
    }

    void enumerate_uniforms()
    {
        g_uni.clear();
        reinterpret_cast<fn_enum>(vslot(20))(g_runtime, "EqShaders.fx", on_uniform, nullptr);
        g_have_uniforms = !g_uni.empty();
        std::string names;
        for (auto &kv : g_uni) if (kv.first.compare(0, 2, "Eq") == 0) names += kv.first + " ";
        logf("uniforms enumerated: %zu total; Eq* = %s", g_uni.size(), names.c_str());
    }

    void self_test()
    {
        g_selftest_done = true;
        // 1. get_hwnd must be the game window; 2. back buffer count is the swapchain's image count (3 in this setup)
        void *hwnd = reinterpret_cast<fn_hwnd>(vslot(5))(g_runtime);
        uint32_t count = reinterpret_cast<fn_u32>(vslot(7))(g_runtime);
        uint32_t cur = reinterpret_cast<fn_u32>(vslot(8))(g_runtime);
        const bool hwnd_ok = IsWindow(static_cast<HWND>(hwnd)) != 0;
        char title[64] = {}; if (hwnd_ok) GetWindowTextA(static_cast<HWND>(hwnd), title, sizeof title);
        logf("self-test: get_hwnd=%p (IsWindow=%d, title '%s'), back_buffer_count=%u, current_index=%u", hwnd, hwnd_ok, title, count, cur);
        g_selftest_ok = hwnd_ok && count >= 1 && count <= 8 && cur < count;

        // 3. round-trip a uniform: read MasterStrength (default 1.0) through get_uniform_value_float
        enumerate_uniforms();
        auto it = g_uni.find("MasterStrength");
        if (it != g_uni.end())
        {
            float v = -1.0f;
            reinterpret_cast<fn_getf>(vslot(30))(g_runtime, it->second, &v, 1, 0);
            logf("self-test: MasterStrength read back as %g", v);
            if (!(v >= 0.0f && v <= 1.0f)) g_selftest_ok = false;
        }
        else logf("self-test: MasterStrength not found (EqShaders.fx not loaded yet?)");
        logf("self-test %s", g_selftest_ok ? "PASSED: uniform pushing enabled" : "FAILED: uniform pushing disabled");
    }

    void set3(const char *name, float x, float y, float z)
    {
        auto it = g_uni.find(name); if (it == g_uni.end()) return;
        const float v[3] = { x, y, z };
        reinterpret_cast<fn_setf>(vslot(34))(g_runtime, it->second, v, 3, 0);
    }
    void set1(const char *name, float x)
    {
        auto it = g_uni.find(name); if (it == g_uni.end()) return;
        reinterpret_cast<fn_setf>(vslot(34))(g_runtime, it->second, &x, 1, 0);
    }

    void dump_block(const float *blk)
    {
        for (size_t o = 0; o < CAM_BLOCK_BYTES / 4; o += 4)
        {
            if (o && blk[o] == 0 && blk[o + 1] == 0 && blk[o + 2] == 0 && blk[o + 3] == 0) continue;
            logf("  +%03zX: %11.4f %11.4f %11.4f %11.4f", o * 4, blk[o], blk[o + 1], blk[o + 2], blk[o + 3]);
        }
    }

    void on_begin_effects(effect_runtime *, command_list *, resource_view, resource_view)
    {
        ++g_frames;
        if (!g_runtime) return;
        if (!g_selftest_done && g_frames > 120) self_test();
        if (g_selftest_ok && !g_have_uniforms && (g_frames % 300) == 0) enumerate_uniforms();

        float block[CAM_BLOCK_BYTES / 4] = {};
        const bool cam_ok = read_mem(ADDR_CAM_BLOCK, block, sizeof block);

        // weather
        uint32_t wptr = 0; float grade = 0, prev = 0; int32_t wtype = 0; bool wok = false;
        if (read_mem(ADDR_WEATHER_PTR, &wptr, 4) && wptr > 0x10000)
        {
            uint8_t w[0x28];
            if (read_mem(wptr, w, sizeof w)) { memcpy(&grade, w + 0x0C, 4); memcpy(&prev, w + 0x10, 4); memcpy(&wtype, w + 0x20, 4); wok = true; }
        }

        const ULONGLONG now = GetTickCount64();
        if (g_log_hz > 0 && cam_ok && now - g_last_log >= 1000u / g_log_hz)
        {
            g_last_log = now;
            bool changed = false;
            for (size_t i = 0; i < CAM_BLOCK_BYTES / 4; ++i) if (fabsf(block[i] - g_last_block[i]) > 1e-4f) { changed = true; break; }
            if (changed)
            {
                memcpy(g_last_block, block, sizeof block);
                logf("cam pos (%.2f, %.2f, %.2f) | weather ptr %08X type %d grade %.3f prev %.3f", block[0], block[1], block[2], wptr, wtype, grade, prev);
                dump_block(block);
            }
        }

        if (g_push && g_selftest_ok && g_have_uniforms && cam_ok)
        {
            const float *m = block + (ADDR_CAM_M - ADDR_CAM_BLOCK) / 4;   // 4x4 at +0x10
            set3("EqCamPos", block[0], block[1], block[2]);
            set3("EqCamM0", m[0], m[1], m[2]);
            set3("EqCamM1", m[4], m[5], m[6]);
            set3("EqCamM2", m[8], m[9], m[10]);
            set1("EqWeatherType", wok ? static_cast<float>(wtype) : 0.0f);
            set1("EqWeatherGrade", wok ? grade : 0.0f);
            set1("EqBridgeOK", 1.0f);
        }
    }

    void on_reloaded(effect_runtime *) { if (g_selftest_ok) enumerate_uniforms(); }
    void on_init_runtime(effect_runtime *rt) { g_runtime = rt; logf("effect runtime attached"); }
    void on_destroy_runtime(effect_runtime *rt) { if (g_runtime == rt) g_runtime = nullptr; }
}

extern "C" __declspec(dllexport) const char *NAME = "EqBridge";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Feeds camera pose and weather (read-only) to EqShaders.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    switch (reason)
    {
    case DLL_PROCESS_ATTACH:
    {
        if (!reshade::register_addon(hModule)) return FALSE;
        char path[MAX_PATH]; GetModuleFileNameA(nullptr, path, MAX_PATH);
        g_dir = path; g_dir.resize(g_dir.find_last_of("\\/") + 1);
        // only the game process: skip the VanillaFixes launcher probe
        if (strstr(path, "WoW.exe") == nullptr && strstr(path, "wow.exe") == nullptr) { return TRUE; }
        CreateDirectoryA((g_dir + "Logs").c_str(), nullptr);
        g_log = fopen((g_dir + "Logs\\EqBridge.log").c_str(), "w");
        read_config();
        logf("EqBridge loaded in %s: Push=%d LogHz=%d", path, g_push, g_log_hz);
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_runtime);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_runtime);
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
        reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reloaded);
        break;
    }
    case DLL_PROCESS_DETACH:
        reshade::unregister_addon(hModule);
        if (g_log) fclose(g_log);
        break;
    }
    return TRUE;
}
