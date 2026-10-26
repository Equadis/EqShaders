// EqFog: scales WoW's linear fog start/end so the grey "fog wall" moves out. Rendering only: it rewrites the two fog
// render-state values the game already sends to Direct3D9 (D3DRS_FOGSTART / D3DRS_FOGEND), nothing else.
//
// Loaded by VanillaFixes through dlls.txt (put it BEFORE comfyatmos.dll so ComfyAtmosphere sees the game's raw values
// and this DLL scales what finally reaches DXVK). Chains by patching the shared D3D9 device vtable, like ComfyAtmosphere.
// Config: EqFog.ini next to WoW.exe, re-read every few seconds. Log: Logs\EqFog.log.
// Build: see build.ps1 (llvm-mingw, i686). Pure C-style COM calls, so the MinGW/MSVC C++ ABI difference does not matter.

#define NOMINMAX
#include <windows.h>
#include <d3d9.h>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <cstdint>
#include <string>

namespace
{
    typedef IDirect3D9 *(WINAPI *Direct3DCreate9_t)(UINT);
    typedef HRESULT(WINAPI *CreateDevice_t)(IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS *, IDirect3DDevice9 **);
    typedef HRESULT(WINAPI *SetRenderState_t)(IDirect3DDevice9 *, D3DRENDERSTATETYPE, DWORD);

    Direct3DCreate9_t g_real_create = nullptr;
    CreateDevice_t g_real_createdevice = nullptr;
    SetRenderState_t g_real_srs = nullptr;
    bool g_device_patched = false;

    FILE *g_log = nullptr;
    std::string g_dir;
    float g_start_scale = 1.0f, g_end_scale = 1.0f, g_min_end = 0.0f, g_min_start = 0.0f;
    bool g_enabled = true;
    FILETIME g_ini_time = {};
    unsigned g_calls = 0, g_logged = 0;

    void logf(const char *fmt, ...)
    {
        if (!g_log) return;
        va_list a; va_start(a, fmt); vfprintf(g_log, fmt, a); va_end(a);
        fputc('\n', g_log); fflush(g_log);
    }

    float getf(const char *key, float def)
    {
        char b[64], d[64];
        snprintf(d, sizeof d, "%g", def);
        GetPrivateProfileStringA("EqFog", key, d, b, sizeof b, (g_dir + "EqFog.ini").c_str());
        return (float)atof(b);
    }

    void read_config()
    {
        g_enabled = GetPrivateProfileIntA("EqFog", "Enabled", 1, (g_dir + "EqFog.ini").c_str()) != 0;
        g_start_scale = getf("StartScale", 1.0f);
        g_end_scale = getf("EndScale", 1.0f);
        g_min_start = getf("MinStart", 0.0f);
        g_min_end = getf("MinEnd", 0.0f);
        WIN32_FILE_ATTRIBUTE_DATA d;
        if (GetFileAttributesExA((g_dir + "EqFog.ini").c_str(), GetFileExInfoStandard, &d)) g_ini_time = d.ftLastWriteTime;
        logf("config: Enabled=%d StartScale=%g EndScale=%g MinStart=%g MinEnd=%g", g_enabled, g_start_scale, g_end_scale, g_min_start, g_min_end);
    }

    void poll_config()
    {
        WIN32_FILE_ATTRIBUTE_DATA d;
        if (GetFileAttributesExA((g_dir + "EqFog.ini").c_str(), GetFileExInfoStandard, &d) && CompareFileTime(&d.ftLastWriteTime, &g_ini_time) != 0)
            read_config();
    }

    HRESULT WINAPI my_set_render_state(IDirect3DDevice9 *dev, D3DRENDERSTATETYPE state, DWORD value)
    {
        if ((state == D3DRS_FOGSTART || state == D3DRS_FOGEND) && (++g_calls % 600) == 0) poll_config();
        if ((state == D3DRS_FOGSTART || state == D3DRS_FOGEND) && g_enabled)
        {
            float v; memcpy(&v, &value, 4);
            // world fog is in yards (tens to hundreds); values <= 20 are the game's "no fog" and UI states: leave them
            if (v > 20.0f)
            {
                const float in = v;
                if (state == D3DRS_FOGEND) { v *= g_end_scale; if (v < g_min_end) v = g_min_end; }
                else { v *= g_start_scale; if (v < g_min_start) v = g_min_start; }
                if (g_logged < 40 && v != in) { ++g_logged; logf("%s %.1f -> %.1f", state == D3DRS_FOGEND ? "FOGEND" : "FOGSTART", in, v); }
                memcpy(&value, &v, 4);
            }
        }
        return g_real_srs(dev, state, value);
    }

    void patch_vtable_slot(void **vtable, int index, void *replacement, void **original)
    {
        DWORD old;
        if (!VirtualProtect(&vtable[index], sizeof(void *), PAGE_READWRITE, &old)) return;
        *original = vtable[index];
        vtable[index] = replacement;
        VirtualProtect(&vtable[index], sizeof(void *), old, &old);
    }

    void **g_vtable = nullptr;
    DWORD WINAPI late_patch(LPVOID)
    {
        Sleep(8000);
        void **vt = g_vtable;
        patch_vtable_slot(vt, 57, reinterpret_cast<void *>(my_set_render_state), reinterpret_cast<void **>(&g_real_srs));
        logf("SetRenderState hooked (vtable %p, previous %p)", (void *)vt, (void *)g_real_srs);
        return 0;
    }
    HRESULT WINAPI my_create_device(IDirect3D9 *d3d, UINT adapter, D3DDEVTYPE type, HWND wnd, DWORD flags, D3DPRESENT_PARAMETERS *pp, IDirect3DDevice9 **out)
    {
        const HRESULT hr = g_real_createdevice(d3d, adapter, type, wnd, flags, pp, out);
        if (SUCCEEDED(hr) && out && *out && !g_device_patched)
        {
            // Patch late, so we end up OUTSIDE ComfyAtmosphere's own SetRenderState hook (it attaches about a second after
            // the device exists). Comfy then sees the scaled fog values it reads back from the device, not a mismatch.
            g_device_patched = true;
            g_vtable = *reinterpret_cast<void ***>(*out);
            CreateThread(nullptr, 0, late_patch, nullptr, 0, nullptr);
            logf("device %p created: SetRenderState hook scheduled (vtable %p)", *out, (void *)g_vtable);
        }
        return hr;
    }

    IDirect3D9 *WINAPI my_create9(UINT sdk)
    {
        IDirect3D9 *d3d = g_real_create(sdk);
        if (d3d && !g_real_createdevice)
        {
            void **vt = *reinterpret_cast<void ***>(d3d);
            patch_vtable_slot(vt, 16, reinterpret_cast<void *>(my_create_device), reinterpret_cast<void **>(&g_real_createdevice));
            logf("Direct3DCreate9: CreateDevice hooked (vtable %p)", vt);
        }
        return d3d;
    }

    // WoW.exe imports only LoadLibraryA and resolves Direct3DCreate9 itself, so the hook goes into d3d9.dll's own export
    // table: patch WoW.exe's import of KERNEL32!LoadLibraryA, and when d3d9.dll comes back, redirect its export entry.
    typedef HMODULE(WINAPI *LoadLibraryA_t)(LPCSTR);
    LoadLibraryA_t g_real_ll = nullptr;
    bool g_eat_patched = false;

    bool patch_export(HMODULE mod)
    {
        BYTE *base = reinterpret_cast<BYTE *>(mod);
        auto *dos = reinterpret_cast<IMAGE_DOS_HEADER *>(base);
        auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
        const IMAGE_DATA_DIRECTORY &dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
        if (!dir.VirtualAddress) return false;
        auto *ex = reinterpret_cast<IMAGE_EXPORT_DIRECTORY *>(base + dir.VirtualAddress);
        auto *names = reinterpret_cast<DWORD *>(base + ex->AddressOfNames);
        auto *ords = reinterpret_cast<WORD *>(base + ex->AddressOfNameOrdinals);
        auto *funcs = reinterpret_cast<DWORD *>(base + ex->AddressOfFunctions);
        for (DWORD i = 0; i < ex->NumberOfNames; ++i)
        {
            if (strcmp(reinterpret_cast<char *>(base + names[i]), "Direct3DCreate9") != 0) continue;
            DWORD *slot = &funcs[ords[i]];
            DWORD old;
            if (!VirtualProtect(slot, sizeof(DWORD), PAGE_READWRITE, &old)) return false;
            g_real_create = reinterpret_cast<Direct3DCreate9_t>(base + *slot);
            *slot = static_cast<DWORD>(reinterpret_cast<BYTE *>(&my_create9) - base);
            VirtualProtect(slot, sizeof(DWORD), old, &old);
            logf("d3d9.dll export Direct3DCreate9 redirected (module %p, original %p)", (void *)mod, (void *)g_real_create);
            return true;
        }
        return false;
    }

    HMODULE WINAPI my_load_library(LPCSTR name)
    {
        HMODULE m = g_real_ll(name);
        if (m && !g_eat_patched && name)
        {
            const char *slash = strrchr(name, '\\'); const char *file = slash ? slash + 1 : name;
            if (_stricmp(file, "d3d9.dll") == 0 || _stricmp(file, "d3d9") == 0) g_eat_patched = patch_export(m);
        }
        return m;
    }

    bool patch_iat()
    {
        if (HMODULE m = GetModuleHandleA("d3d9.dll")) g_eat_patched = patch_export(m); // already loaded
        BYTE *base = reinterpret_cast<BYTE *>(GetModuleHandleA(nullptr));
        auto *dos = reinterpret_cast<IMAGE_DOS_HEADER *>(base);
        auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
        const IMAGE_DATA_DIRECTORY &dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
        if (!dir.VirtualAddress) return false;
        for (auto *imp = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR *>(base + dir.VirtualAddress); imp->Name; ++imp)
        {
            if (_stricmp(reinterpret_cast<char *>(base + imp->Name), "KERNEL32.dll") != 0) continue;
            auto *orig = reinterpret_cast<IMAGE_THUNK_DATA *>(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
            auto *iat = reinterpret_cast<IMAGE_THUNK_DATA *>(base + imp->FirstThunk);
            for (; orig->u1.AddressOfData; ++orig, ++iat)
            {
                if (orig->u1.Ordinal & IMAGE_ORDINAL_FLAG) continue;
                auto *name = reinterpret_cast<IMAGE_IMPORT_BY_NAME *>(base + orig->u1.AddressOfData);
                if (strcmp(name->Name, "LoadLibraryA") != 0) continue;
                DWORD old;
                if (!VirtualProtect(&iat->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) return false;
                g_real_ll = reinterpret_cast<LoadLibraryA_t>(iat->u1.Function);
                iat->u1.Function = reinterpret_cast<DWORD>(&my_load_library);
                VirtualProtect(&iat->u1.Function, sizeof(void *), old, &old);
                return true;
            }
        }
        return false;
    }
}
BOOL APIENTRY DllMain(HMODULE, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        char path[MAX_PATH]; GetModuleFileNameA(nullptr, path, MAX_PATH);
        g_dir = path; g_dir.resize(g_dir.find_last_of("\\/") + 1);
        CreateDirectoryA((g_dir + "Logs").c_str(), nullptr);
        g_log = fopen((g_dir + "Logs\\EqFog.log").c_str(), "w");
        logf("EqFog loaded in %s", path);
        read_config();
        logf(patch_iat() ? "import of KERNEL32!LoadLibraryA patched" : "WARNING: could not patch the LoadLibraryA import");
    }
    return TRUE;
}
