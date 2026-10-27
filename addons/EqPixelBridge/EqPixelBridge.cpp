// EqPixelBridge: gives EqShaders the camera pose and the weather by writing them as 16 pixels in the bottom-right corner of
// the back buffer, just before Present. ReShade (which runs after Present) reads those pixels from the image, decodes them
// in a 16x1 pass and paints the corner back over, so nothing reaches the screen.
//
// Why pixels: no call into ReShade is needed (hand-made calls into its C++ objects froze the game twice). Plain D3D9 calls only.
// READ-ONLY toward the game: it reads a few floats from the client's own memory and draws 16 pixels. It writes no game memory.
//
// Loaded by VanillaFixes through dlls.txt. Hooks like EqFog did: LoadLibraryA import -> d3d9.dll export -> CreateDevice ->
// device vtable slot 17 (Present), patched 8 s after device creation so it sits outside ComfyAtmosphere's hook.
//
// Memory (WoW.exe 1.12.1.5875): camera position float3 at 0x00C7CF20, camera matrix block at 0x00C7CF30 (4x4, row-major),
// weather manager pointer at 0x00C6326C (+0x0C grade float, +0x20 type int).
//
// Pixel row (y = height-1), x = width-1-i, i = 0..15, colour = (R,G,B), each value a 24-bit fixed point number R*65536+G*256+B:
//   0  magic A   (0xEA, 0x71, 0xB1)
//   1-3  camera x,y,z       value = (v + 20000) / 40000 for x,y ; (z + 4000) / 12000 for z
//   4-12 camera matrix 3x3 (rows 0..2 of the 4x4 block, first three columns), value = (m + 1.25) / 2.5
//   13   R = weather type (0..3), G = grade*255, B = frame counter low byte
//   14   R = 0x01 (format version), G = world valid (0xFF if the camera is not at the origin), B = 0
//   15   magic B (0x15, 0x8E, 0x4E)
// Config EqPixelBridge.ini: Enabled=1. Log: Logs\EqPixelBridge.log

#define NOMINMAX
#include <windows.h>
#include <d3d9.h>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <cstdint>
#include <cmath>
#include <string>

namespace
{
    typedef IDirect3D9 *(WINAPI *Direct3DCreate9_t)(UINT);
    typedef HRESULT(WINAPI *CreateDevice_t)(IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS *, IDirect3DDevice9 **);
    typedef HRESULT(WINAPI *Present_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
    typedef HMODULE(WINAPI *LoadLibraryA_t)(LPCSTR);

    Direct3DCreate9_t g_real_create = nullptr;
    CreateDevice_t g_real_createdevice = nullptr;
    Present_t g_real_present = nullptr;
    LoadLibraryA_t g_real_ll = nullptr;
    bool g_eat_patched = false, g_device_scheduled = false;
    void **g_vtable = nullptr;
    FILE *g_log = nullptr;
    std::string g_dir;
    bool g_enabled = true;
    uint8_t g_frame = 0;
    unsigned g_logged = 0;

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

    D3DCOLOR enc24(float t)
    {
        if (!(t > 0.0f)) t = 0.0f;
        if (t > 1.0f) t = 1.0f;
        const uint32_t v = static_cast<uint32_t>(t * 16777215.0f + 0.5f);
        return D3DCOLOR_XRGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    }

    void write_strip(IDirect3DDevice9 *dev)
    {
        IDirect3DSurface9 *rt = nullptr;
        if (FAILED(dev->GetRenderTarget(0, &rt)) || !rt) return;
        D3DSURFACE_DESC sd; rt->GetDesc(&sd); rt->Release();
        if (sd.Width < 64 || sd.Height < 64) return;

        float cam[3] = {}; float m[16] = {};
        const bool cam_ok = read_mem(0x00C7CF20, cam, sizeof cam) && read_mem(0x00C7CF30, m, sizeof m);
        uint32_t wptr = 0; float grade = 0; int32_t wtype = 0;
        if (read_mem(0x00C6326C, &wptr, 4) && wptr > 0x10000)
        {
            uint8_t w[0x28];
            if (read_mem(wptr, w, sizeof w)) { memcpy(&grade, w + 0x0C, 4); memcpy(&wtype, w + 0x20, 4); }
        }
        if (wtype < 0 || wtype > 3) wtype = 0;
        if (!(grade >= 0.0f && grade <= 1.0f)) grade = 0.0f;
        const bool world = cam_ok && (fabsf(cam[0]) + fabsf(cam[1]) + fabsf(cam[2]) > 1.0f);

        D3DCOLOR px[16] = {};
        px[0] = D3DCOLOR_XRGB(0xEA, 0x71, 0xB1);
        px[1] = enc24((cam[0] + 20000.0f) / 40000.0f);
        px[2] = enc24((cam[1] + 20000.0f) / 40000.0f);
        px[3] = enc24((cam[2] + 4000.0f) / 12000.0f);
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c)
                px[4 + r * 3 + c] = enc24((m[r * 4 + c] + 1.25f) / 2.5f);
        px[13] = D3DCOLOR_XRGB(static_cast<int>(wtype), static_cast<int>(grade * 255.0f + 0.5f), g_frame++);
        px[14] = D3DCOLOR_XRGB(0x01, world ? 0xFF : 0x00, 0);
        px[15] = D3DCOLOR_XRGB(0x15, 0x8E, 0x4E);

        // make the clears land: whole-surface viewport, no scissor
        D3DVIEWPORT9 vp = {}; dev->GetViewport(&vp);
        DWORD scissor = 0; dev->GetRenderState(D3DRS_SCISSORTESTENABLE, &scissor);
        D3DVIEWPORT9 full = { 0, 0, sd.Width, sd.Height, 0.0f, 1.0f };
        dev->SetViewport(&full);
        if (scissor) dev->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);

        const LONG y = static_cast<LONG>(sd.Height) - 1;
        for (int i = 0; i < 16; ++i)
        {
            const LONG x = static_cast<LONG>(sd.Width) - 1 - i;
            D3DRECT r = { x, y, x + 1, y + 1 };
            dev->Clear(1, &r, D3DCLEAR_TARGET, px[i], 1.0f, 0);
        }

        dev->SetViewport(&vp);
        if (scissor) dev->SetRenderState(D3DRS_SCISSORTESTENABLE, TRUE);

        if (g_logged < 6 && world)
        {
            ++g_logged;
            logf("strip written %lux%lu: cam (%.2f %.2f %.2f) weather type %d grade %.2f m0 (%.3f %.3f %.3f) m1 (%.3f %.3f %.3f) m2 (%.3f %.3f %.3f)",
                 sd.Width, sd.Height, cam[0], cam[1], cam[2], wtype, grade, m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]);
        }
    }

    HRESULT WINAPI my_present(IDirect3DDevice9 *dev, const RECT *a, const RECT *b, HWND c, const RGNDATA *d)
    {
        if (g_enabled) write_strip(dev);
        return g_real_present(dev, a, b, c, d);
    }

    void patch_vtable_slot(void **vtable, int index, void *replacement, void **original)
    {
        DWORD old;
        if (!VirtualProtect(&vtable[index], sizeof(void *), PAGE_READWRITE, &old)) return;
        *original = vtable[index];
        vtable[index] = replacement;
        VirtualProtect(&vtable[index], sizeof(void *), old, &old);
    }

    DWORD WINAPI late_patch(LPVOID)
    {
        Sleep(8000);
        patch_vtable_slot(g_vtable, 17, reinterpret_cast<void *>(my_present), reinterpret_cast<void **>(&g_real_present));
        logf("Present hooked (vtable %p, previous %p)", (void *)g_vtable, (void *)g_real_present);
        return 0;
    }

    HRESULT WINAPI my_create_device(IDirect3D9 *d3d, UINT adapter, D3DDEVTYPE type, HWND wnd, DWORD flags, D3DPRESENT_PARAMETERS *pp, IDirect3DDevice9 **out)
    {
        const HRESULT hr = g_real_createdevice(d3d, adapter, type, wnd, flags, pp, out);
        if (SUCCEEDED(hr) && out && *out && !g_device_scheduled)
        {
            g_device_scheduled = true;
            g_vtable = *reinterpret_cast<void ***>(*out);
            CreateThread(nullptr, 0, late_patch, nullptr, 0, nullptr);
            logf("device %p created: Present hook scheduled", (void *)*out);
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
            logf("Direct3DCreate9: CreateDevice hooked");
        }
        return d3d;
    }

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
            logf("d3d9.dll export Direct3DCreate9 redirected");
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
        if (HMODULE m = GetModuleHandleA("d3d9.dll")) g_eat_patched = patch_export(m);
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
        g_log = fopen((g_dir + "Logs\\EqPixelBridge.log").c_str(), "w");
        g_enabled = GetPrivateProfileIntA("EqPixelBridge", "Enabled", 1, (g_dir + "EqPixelBridge.ini").c_str()) != 0;
        logf("EqPixelBridge loaded in %s, Enabled=%d", path, g_enabled);
        logf(patch_iat() ? "LoadLibraryA import patched" : "WARNING: could not patch the LoadLibraryA import");
    }
    return TRUE;
}
