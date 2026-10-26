// EqUIGate: ReShade add-on that renders the ReShade effects BEFORE WoW draws its UI, so bloom, tonemap, AO, CAS and
// the rest never touch the HUD. Rendering only: it reads pass/draw events and calls effect_runtime::render_effects.
//
// What a frame looks like (measured with Ctrl+F10 dumps, OctoWoW + DXVK + ComfyAtmosphere, in-world):
//   world passes on Comfy's redirected target -> shadow-map passes (no colour target) -> Comfy composite/ray passes into the
//   game's real back-buffer image T -> UI: a few passes on T with hundreds of small blended draws -> DXVK blit to the swapchain.
// So the UI starts at the first "heavy" pass on T. Each frame we learn
//   T = colour target of the last heavy pass (>= HeavyDraws draws),
//   K = ordinal, among the passes on T, of the first heavy pass,  P = draws issued before it,
// and next frame we render the effects at the start of the K-th pass on T (only if >= P/2 draws came before it, so the
// login/loading screens, where the first pass already is the UI, are left to ReShade's normal present-time rendering).
// If a frame never reaches the trigger, ReShade renders at present as before (HUD affected for that frame only).
//
// Config: EqUIGate.ini next to WoW.exe. Ctrl+F10 dumps one frame's pass/draw list to Logs\EqUIGate.log.
// Build: see build.ps1 (llvm-mingw, i686).

#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstdarg>
#include <cstdlib>
#include <string>
#include <vector>

using namespace reshade::api;

namespace
{
    effect_runtime *g_runtime = nullptr;
    FILE *g_log = nullptr;
    std::string g_dir;

    // config (EqUIGate.ini)
    bool g_enabled = true;
    int g_heavy = 20;          // a pass with at least this many draws counts as UI-heavy
    int g_min_prior = 200;     // never trigger with fewer draws than this before the pass
    int g_skip = 0;            // heavy passes on T to let through before triggering (fine tuning)
    bool g_diag = false;
    FILETIME g_ini_time = {};

    struct pass_rec { uint64_t rt; uint32_t draws; uint32_t prior; };

    struct frame_state
    {
        uint64_t frame = 0;
        uint32_t draws = 0;
        std::vector<pass_rec> passes;
        uint64_t cur_rt = 0;
        uint32_t cur_draws = 0, cur_prior = 0;
        bool in_pass = false;
        bool triggered = false;
        uint32_t t_ordinal = 0;          // passes begun on the predicted T so far
    } g_fs;

    // learned from the previous frame
    uint64_t g_T = 0; uint32_t g_K = 0, g_P = 0;
    std::vector<uint64_t> g_Tset;   // DXVK rotates the back-buffer image views between frames, so T is a small set of recent handles
    bool in_Tset(uint64_t h) { for (uint64_t v : g_Tset) if (v == h) return true; return false; }
    std::atomic<uint64_t> g_present_count{ 0 };
    uint32_t g_trig_frames = 0, g_total_frames = 0;
    bool g_capture = false, g_capture_next = false;
    std::string g_cap_lines;

    void logf(const char *fmt, ...)
    {
        if (!g_log) return;
        va_list a; va_start(a, fmt); vfprintf(g_log, fmt, a); va_end(a);
        fputc('\n', g_log); fflush(g_log);
    }

    void cap(const char *fmt, ...)
    {
        if (!g_capture) return;
        char b[256]; va_list a; va_start(a, fmt); vsnprintf(b, sizeof b, fmt, a); va_end(a);
        g_cap_lines += b; g_cap_lines += '\n';
    }

    void read_config()
    {
        const std::string p = g_dir + "EqUIGate.ini";
        g_enabled = GetPrivateProfileIntA("EqUIGate", "Enabled", 1, p.c_str()) != 0;
        g_heavy = GetPrivateProfileIntA("EqUIGate", "HeavyDraws", 20, p.c_str());
        g_min_prior = GetPrivateProfileIntA("EqUIGate", "MinPriorDraws", 200, p.c_str());
        g_skip = GetPrivateProfileIntA("EqUIGate", "SkipHeavyPasses", 0, p.c_str());
        g_diag = GetPrivateProfileIntA("EqUIGate", "Diag", 0, p.c_str()) != 0;
        WIN32_FILE_ATTRIBUTE_DATA d;
        if (GetFileAttributesExA(p.c_str(), GetFileExInfoStandard, &d)) g_ini_time = d.ftLastWriteTime;
    }

    void poll_config()
    {
        static uint32_t n = 0;
        if ((++n % 240) != 0) return;
        WIN32_FILE_ATTRIBUTE_DATA d;
        const std::string p = g_dir + "EqUIGate.ini";
        if (GetFileAttributesExA(p.c_str(), GetFileExInfoStandard, &d) && CompareFileTime(&d.ftLastWriteTime, &g_ini_time) != 0)
        {
            read_config();
            logf("config reloaded: Enabled=%d HeavyDraws=%d MinPriorDraws=%d SkipHeavyPasses=%d Diag=%d", g_enabled, g_heavy, g_min_prior, g_skip, g_diag);
        }
    }

    void close_pass()
    {
        if (!g_fs.in_pass) return;
        g_fs.passes.push_back({ g_fs.cur_rt, g_fs.cur_draws, g_fs.cur_prior });
        g_fs.in_pass = false;
    }

    void learn_from_frame()
    {
        close_pass();
        int last_heavy = -1;
        for (int i = (int)g_fs.passes.size() - 1; i >= 0; --i)
            if (g_fs.passes[i].draws >= (uint32_t)g_heavy) { last_heavy = i; break; }
        if (last_heavy < 0) { g_T = 0; g_K = 0; g_P = 0; return; }
        const uint64_t T = g_fs.passes[last_heavy].rt;
        uint32_t ordinal = 0, K = 0, P = 0, heavy = 0;
        for (const pass_rec &p : g_fs.passes)
        {
            if (p.rt != T) continue;
            ++ordinal;
            if (p.draws >= (uint32_t)g_heavy)
            {
                if (heavy++ == (uint32_t)g_skip) { K = ordinal; P = p.prior; break; }
            }
        }
        g_T = T; g_K = K; g_P = P;
        if (!in_Tset(T)) { g_Tset.push_back(T); if (g_Tset.size() > 8) g_Tset.erase(g_Tset.begin()); }
    }

    void new_frame_if_needed()
    {
        const uint64_t pc = g_present_count.load();
        if (pc == g_fs.frame) return;

        if (g_fs.frame != 0)
        {
            ++g_total_frames;
            if (g_fs.triggered) ++g_trig_frames;
            learn_from_frame();
            if (g_capture)
            {
                logf("=== frame %llu: %u draws, %zu passes, T %llx K %u P %u, triggered %d", (unsigned long long)g_fs.frame, g_fs.draws, g_fs.passes.size(), (unsigned long long)g_T, g_K, g_P, g_fs.triggered);
                if (g_log) { fputs(g_cap_lines.c_str(), g_log); fflush(g_log); }
                g_capture = false; g_cap_lines.clear();
            }
            if (g_diag || (g_total_frames % 600) == 0)
                logf("frame %llu: draws %u passes %zu | T %llx K %u P %u | triggered %d (%u of %u frames)", (unsigned long long)g_fs.frame, g_fs.draws, g_fs.passes.size(), (unsigned long long)g_T, g_K, g_P, g_fs.triggered, g_trig_frames, g_total_frames);
        }
        if (g_capture_next) { g_capture = true; g_capture_next = false; }
        g_fs = frame_state();
        g_fs.frame = pc;
        poll_config();
        if ((GetAsyncKeyState(VK_CONTROL) & 0x8000) && (GetAsyncKeyState(VK_F10) & 0x8000)) g_capture_next = true;
    }

    // The add-on is built with a MinGW toolchain (Itanium C++ ABI) but ReShade uses the MSVC ABI, so the one virtual call we
    // need is made by hand: vtable slot 10 of effect_runtime (api_object 4 + get_device + get_hwnd, get_back_buffer,
    // get_back_buffer_count, get_current_back_buffer_index, get_command_queue = render_effects), __thiscall.
    typedef void(__attribute__((thiscall)) *render_effects_fn)(void *self, void *cmd_list, uint64_t rtv, uint64_t rtv_srgb);
    void render_effects_now(command_list *cmd, uint64_t view)
    {
        static int once = 0;
        if (!once) { once = 1; logf("runtime %p vtable %p slots[4..12]: %p %p %p %p %p %p %p %p %p", (void *)g_runtime, *(void **)g_runtime, ((void **)*(void **)g_runtime)[4], ((void **)*(void **)g_runtime)[5], ((void **)*(void **)g_runtime)[6], ((void **)*(void **)g_runtime)[7], ((void **)*(void **)g_runtime)[8], ((void **)*(void **)g_runtime)[9], ((void **)*(void **)g_runtime)[10], ((void **)*(void **)g_runtime)[11], ((void **)*(void **)g_runtime)[12]); }
        void **vt = *reinterpret_cast<void ***>(g_runtime);
        reinterpret_cast<render_effects_fn>(vt[10])(g_runtime, cmd, view, view);
    }

    void count_draw(uint32_t verts)
    {
        new_frame_if_needed();
        ++g_fs.draws; ++g_fs.cur_draws;
        cap("  draw %u pass-draw %u verts %u", g_fs.draws, g_fs.cur_draws, verts);
    }

    bool on_draw(command_list *, uint32_t v, uint32_t, uint32_t, uint32_t) { count_draw(v); return false; }
    bool on_draw_indexed(command_list *, uint32_t v, uint32_t, uint32_t, int32_t, uint32_t) { count_draw(v); return false; }

    bool on_begin_render_pass(command_list *cmd, uint32_t count, const render_pass_render_target_desc *rts, const render_pass_depth_stencil_desc *ds, render_pass_flags)
    {
        new_frame_if_needed();
        close_pass();
        const uint64_t rt = (count >= 1 && rts) ? rts[0].view.handle : 0;
        g_fs.cur_rt = rt; g_fs.cur_draws = 0; g_fs.cur_prior = g_fs.draws; g_fs.in_pass = true;
        cap("pass %zu rt %llx rts %u depth-view %llx prior-draws %u", g_fs.passes.size() + 1, (unsigned long long)rt, count, (unsigned long long)(ds ? ds->view.handle : 0), g_fs.draws);

        if (g_enabled && g_runtime && !g_fs.triggered && g_T != 0 && g_K != 0 && rt != 0 && in_Tset(rt))
        {
            ++g_fs.t_ordinal;
            if (g_fs.t_ordinal == g_K && g_fs.draws >= (uint32_t)g_min_prior && g_fs.draws * 2 >= g_P)
            {
                g_fs.triggered = true;
                cap("  >>> render_effects here (T-pass %u, %u draws before)", g_fs.t_ordinal, g_fs.draws);
                static int n_logged = 0;
                if (n_logged < 6) { ++n_logged; logf("trigger %d: frame %llu, T-pass %u, %u draws before, rt %llx -> calling render_effects", n_logged, (unsigned long long)g_fs.frame, g_fs.t_ordinal, g_fs.draws, (unsigned long long)rt); }
                render_effects_now(cmd, rt);
                if (n_logged <= 6) logf("trigger %d: render_effects returned", n_logged);
            }
        }
        return false;
    }

    void on_present(command_queue *, swapchain *, const rect *, const rect *, uint32_t, const rect *)
    {
        g_present_count.fetch_add(1);
    }

    void on_begin_effects(effect_runtime *, command_list *, resource_view rtv, resource_view)
    {
        static int n = 0; if (n < 8) { ++n; logf("reshade_begin_effects #%d (rtv %llx)", n, (unsigned long long)rtv.handle); }
    }
    void on_finish_effects(effect_runtime *, command_list *, resource_view rtv, resource_view)
    {
        static int n = 0; if (n < 8) { ++n; logf("reshade_finish_effects #%d (rtv %llx)", n, (unsigned long long)rtv.handle); }
    }

    void on_init_runtime(effect_runtime *rt) { g_runtime = rt; logf("effect runtime attached"); }
    void on_destroy_runtime(effect_runtime *rt) { if (g_runtime == rt) g_runtime = nullptr; }
}

extern "C" __declspec(dllexport) const char *NAME = "EqUIGate";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Renders ReShade effects before the WoW UI is drawn.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    switch (reason)
    {
    case DLL_PROCESS_ATTACH:
    {
        if (!reshade::register_addon(hModule)) return FALSE;
        char path[MAX_PATH]; GetModuleFileNameA(nullptr, path, MAX_PATH);
        g_dir = path; g_dir.resize(g_dir.find_last_of("\\/") + 1);
        CreateDirectoryA((g_dir + "Logs").c_str(), nullptr);
        g_log = fopen((g_dir + "Logs\\EqUIGate.log").c_str(), "w");
        read_config();
        logf("EqUIGate loaded: Enabled=%d HeavyDraws=%d MinPriorDraws=%d SkipHeavyPasses=%d Diag=%d", g_enabled, g_heavy, g_min_prior, g_skip, g_diag);
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_runtime);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_runtime);
        reshade::register_event<reshade::addon_event::draw>(on_draw);
        reshade::register_event<reshade::addon_event::draw_indexed>(on_draw_indexed);
        reshade::register_event<reshade::addon_event::begin_render_pass>(on_begin_render_pass);
        reshade::register_event<reshade::addon_event::present>(on_present);
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
        reshade::register_event<reshade::addon_event::reshade_finish_effects>(on_finish_effects);
        break;
    }
    case DLL_PROCESS_DETACH:
        reshade::unregister_addon(hModule);
        if (g_log) fclose(g_log);
        break;
    }
    return TRUE;
}
