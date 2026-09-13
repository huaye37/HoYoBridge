/*
 * MacGameBridge Genshin compatibility shim.
 *
 * YuanShen's Unity 2017.4 startup probes multisample support through
 * ID3D11Device::CheckMultisampleQualityLevels. GPTK 4.0 beta 2 crashes in
 * that COM call. This proxy preserves Wine's version.dll exports and changes
 * only the affected capability query, conservatively reporting MSAA disabled.
 * When MGB_FPS_LIMIT is 120 or 144, it also applies the opt-in FPS unlock used
 * by MacGameBridge. The unlock follows the open-source genshin-fps-unlock
 * strategy: find the single writable target-framerate variable from the
 * il2cpp section and keep the selected value active while the process runs.
 *
 * Copyright 2026 MacGameBridge contributors. MIT licensed; see LICENSE.
 */
#define COBJMACROS
#define USE_WS_PREFIX
#include <windows.h>
#include <d3d11.h>
#include <stdint.h>

typedef FARPROC (WINAPI *GetProcAddressProc)(HMODULE, LPCSTR);
typedef HRESULT (WINAPI *D3D11CreateDeviceProc)(
    IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
    const D3D_FEATURE_LEVEL *, UINT, UINT,
    ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *D3D11CreateDeviceAndSwapChainProc)(
    IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
    const D3D_FEATURE_LEVEL *, UINT, UINT, const DXGI_SWAP_CHAIN_DESC *,
    IDXGISwapChain **, ID3D11Device **, D3D_FEATURE_LEVEL *,
    ID3D11DeviceContext **);

static GetProcAddressProc real_get_proc_address;
static D3D11CreateDeviceProc real_create_device;
static D3D11CreateDeviceAndSwapChainProc real_create_device_and_swap_chain;
static HMODULE real_version_module;
static void *patched_device_vtable[43];
static LONG device_vtable_ready;

static const char *fps_status_path =
    "C:\\windows\\temp\\mgb-fps-unlock.status";

static BOOL strings_equal(const char *left, const char *right)
{
    while (*left && *right && *left == *right) {
        ++left;
        ++right;
    }
    return *left == *right;
}

static char lowercase_ascii(char value)
{
    if (value >= 'A' && value <= 'Z') return value + ('a' - 'A');
    return value;
}

static BOOL ends_with_case_insensitive(const char *value, const char *suffix)
{
    SIZE_T value_length = 0;
    SIZE_T suffix_length = 0;
    SIZE_T index;
    while (value[value_length]) ++value_length;
    while (suffix[suffix_length]) ++suffix_length;
    if (suffix_length > value_length) return FALSE;
    value += value_length - suffix_length;
    for (index = 0; index < suffix_length; ++index) {
        if (lowercase_ascii(value[index]) != lowercase_ascii(suffix[index])) {
            return FALSE;
        }
    }
    return TRUE;
}

static BOOL is_genshin_process(void)
{
    char path[MAX_PATH];
    DWORD length = GetModuleFileNameA(NULL, path, MAX_PATH);
    if (!length || length >= MAX_PATH) return FALSE;
    return ends_with_case_insensitive(path, "\\YuanShen.exe") ||
        ends_with_case_insensitive(path, "\\GenshinImpact.exe");
}

static void write_fps_status(const char *status)
{
    HANDLE file = CreateFileA(
        fps_status_path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD written;
    SIZE_T length = 0;
    if (file == INVALID_HANDLE_VALUE) return;
    while (status[length]) ++length;
    WriteFile(file, status, (DWORD)length, &written, NULL);
    FlushFileBuffers(file);
    CloseHandle(file);
}

static BOOL address_in_image(
    const BYTE *address,
    const BYTE *image_base,
    SIZE_T image_size,
    SIZE_T required_size)
{
    SIZE_T offset;
    if (address < image_base) return FALSE;
    offset = (SIZE_T)(address - image_base);
    return offset <= image_size && required_size <= image_size - offset;
}

static LONG read_little_endian_long(const BYTE *bytes)
{
    uint32_t value = (uint32_t)bytes[0] |
        ((uint32_t)bytes[1] << 8) |
        ((uint32_t)bytes[2] << 16) |
        ((uint32_t)bytes[3] << 24);
    return (LONG)value;
}

static BYTE *relative_branch_target(
    BYTE *instruction,
    BYTE *image_base,
    SIZE_T image_size)
{
    LONG displacement;
    BYTE *target;
    if (!address_in_image(instruction, image_base, image_size, 5)) return NULL;
    displacement = read_little_endian_long(instruction + 1);
    target = instruction + 5 + displacement;
    if (!address_in_image(target, image_base, image_size, 1)) return NULL;
    return target;
}

static BOOL page_is_writable(const void *address)
{
    MEMORY_BASIC_INFORMATION memory;
    DWORD protection;
    if (!VirtualQuery(address, &memory, sizeof(memory))) return FALSE;
    if (memory.State != MEM_COMMIT || (memory.Protect & PAGE_GUARD)) return FALSE;
    protection = memory.Protect & 0xff;
    return protection == PAGE_READWRITE || protection == PAGE_WRITECOPY ||
        protection == PAGE_EXECUTE_READWRITE ||
        protection == PAGE_EXECUTE_WRITECOPY;
}

static int32_t *find_framerate_target(void)
{
    static const BYTE pattern[] = {0xB9, 0x3C, 0x00, 0x00, 0x00, 0xE8};
    BYTE *image_base = (BYTE *)GetModuleHandleW(NULL);
    IMAGE_DOS_HEADER *dos;
    IMAGE_NT_HEADERS64 *nt;
    IMAGE_SECTION_HEADER *sections;
    BYTE *section_base = NULL;
    SIZE_T section_size = 0;
    SIZE_T image_size;
    WORD section_index;
    SIZE_T offset;
    int32_t *unique_target = NULL;

    if (!image_base) return NULL;
    dos = (IMAGE_DOS_HEADER *)image_base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return NULL;
    nt = (IMAGE_NT_HEADERS64 *)(image_base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return NULL;
    image_size = nt->OptionalHeader.SizeOfImage;
    sections = IMAGE_FIRST_SECTION(nt);
    for (section_index = 0;
         section_index < nt->FileHeader.NumberOfSections;
         ++section_index) {
        const BYTE *name = sections[section_index].Name;
        if (name[0] == 'i' && name[1] == 'l' && name[2] == '2' &&
            name[3] == 'c' && name[4] == 'p' && name[5] == 'p' &&
            name[6] == 0) {
            section_base = image_base + sections[section_index].VirtualAddress;
            section_size = sections[section_index].Misc.VirtualSize;
            break;
        }
    }
    if (!section_base || section_size < sizeof(pattern) + 5) return NULL;

    for (offset = 0; offset + sizeof(pattern) + 5 <= section_size; ++offset) {
        BYTE *match = section_base + offset;
        BYTE *instruction;
        BYTE *target;
        LONG displacement;
        int32_t *candidate;
        int branch_count = 0;
        SIZE_T pattern_index;

        for (pattern_index = 0; pattern_index < sizeof(pattern); ++pattern_index) {
            if (match[pattern_index] != pattern[pattern_index]) break;
        }
        if (pattern_index != sizeof(pattern)) continue;

        instruction = match + 5;
        target = relative_branch_target(instruction, image_base, image_size);
        if (!target || target[0] != 0xE9) continue;
        while ((target[0] == 0xE8 || target[0] == 0xE9) && branch_count < 8) {
            target = relative_branch_target(target, image_base, image_size);
            if (!target) break;
            ++branch_count;
        }
        if (!target || branch_count == 8 ||
            !address_in_image(target, image_base, image_size, 6) ||
            target[0] != 0x89 || target[1] != 0x0D) {
            continue;
        }
        displacement = read_little_endian_long(target + 2);
        candidate = (int32_t *)(target + 6 + displacement);
        if (!address_in_image(
                (BYTE *)candidate, image_base, image_size, sizeof(*candidate)) ||
            !page_is_writable(candidate)) {
            continue;
        }
        if (unique_target && unique_target != candidate) {
            return NULL;
        }
        unique_target = candidate;
    }
    return unique_target;
}

static int requested_fps_limit(void)
{
    char value[8];
    DWORD length = GetEnvironmentVariableA("MGB_FPS_LIMIT", value, sizeof(value));
    if (!length || length >= sizeof(value)) return 0;
    if (strings_equal(value, "120")) return 120;
    if (strings_equal(value, "144")) return 144;
    return 0;
}

static BOOL environment_flag_enabled(const char *name)
{
    char value[2] = {0};
    return GetEnvironmentVariableA(name, value, sizeof(value)) == 1 &&
        value[0] == '1';
}

static DWORD WINAPI fps_unlock_thread(LPVOID parameter)
{
    int target_fps = (int)(INT_PTR)parameter;
    int32_t *framerate;
    write_fps_status("scanning");
    framerate = find_framerate_target();
    if (!framerate) {
        write_fps_status("failed:pattern");
        OutputDebugStringA("MGB_FPS_UNLOCK failed to resolve a unique target\n");
        return 1;
    }
    *framerate = target_fps;
    write_fps_status(target_fps == 120 ? "active:120" : "active:144");
    OutputDebugStringA("MGB_FPS_UNLOCK active\n");
    for (;;) {
        *framerate = target_fps;
        Sleep(62);
    }
}

static HRESULT WINAPI conservative_msaa_query(
    ID3D11Device *device,
    DXGI_FORMAT format,
    UINT sample_count,
    UINT *quality_levels)
{
    (void)device;
    (void)format;
    if (!quality_levels) return E_INVALIDARG;
    *quality_levels = sample_count == 1 ? 1 : 0;
    return S_OK;
}

static void patch_device(ID3D11Device *device)
{
    void ***object;
    void **vtable;
    UINT index;

    if (!device) return;
    object = (void ***)device;
    vtable = *object;
    if (InterlockedCompareExchange(&device_vtable_ready, 1, 0) == 0) {
        for (index = 0; index < 43; ++index) {
            patched_device_vtable[index] = vtable[index];
        }
        patched_device_vtable[30] = (void *)conservative_msaa_query;
        InterlockedExchange(&device_vtable_ready, 2);
    } else {
        while (InterlockedCompareExchange(&device_vtable_ready, 2, 2) != 2) {
            Sleep(0);
        }
    }
    *object = patched_device_vtable;
    OutputDebugStringA("MGB_D3D11_HOOK patched CheckMultisampleQualityLevels\n");
}

static HRESULT WINAPI hooked_create_device(
    IDXGIAdapter *adapter,
    D3D_DRIVER_TYPE driver_type,
    HMODULE software,
    UINT flags,
    const D3D_FEATURE_LEVEL *feature_levels,
    UINT feature_level_count,
    UINT sdk_version,
    ID3D11Device **device,
    D3D_FEATURE_LEVEL *selected_feature_level,
    ID3D11DeviceContext **immediate_context)
{
    HRESULT result = real_create_device(
        adapter, driver_type, software, flags, feature_levels,
        feature_level_count, sdk_version, device, selected_feature_level,
        immediate_context);
    if (SUCCEEDED(result) && device) patch_device(*device);
    return result;
}

static HRESULT WINAPI hooked_create_device_and_swap_chain(
    IDXGIAdapter *adapter,
    D3D_DRIVER_TYPE driver_type,
    HMODULE software,
    UINT flags,
    const D3D_FEATURE_LEVEL *feature_levels,
    UINT feature_level_count,
    UINT sdk_version,
    const DXGI_SWAP_CHAIN_DESC *swap_chain_desc,
    IDXGISwapChain **swap_chain,
    ID3D11Device **device,
    D3D_FEATURE_LEVEL *selected_feature_level,
    ID3D11DeviceContext **immediate_context)
{
    HRESULT result = real_create_device_and_swap_chain(
        adapter, driver_type, software, flags, feature_levels,
        feature_level_count, sdk_version, swap_chain_desc, swap_chain,
        device, selected_feature_level, immediate_context);
    if (SUCCEEDED(result) && device) patch_device(*device);
    return result;
}

static FARPROC WINAPI hooked_get_proc_address(HMODULE module, LPCSTR name)
{
    FARPROC result = real_get_proc_address(module, name);
    if (!name) return result;
    if (strings_equal(name, "D3D11CreateDevice")) {
        real_create_device = (D3D11CreateDeviceProc)result;
        OutputDebugStringA("MGB_D3D11_HOOK intercepted D3D11CreateDevice\n");
        return (FARPROC)hooked_create_device;
    }
    if (strings_equal(name, "D3D11CreateDeviceAndSwapChain")) {
        real_create_device_and_swap_chain = (D3D11CreateDeviceAndSwapChainProc)result;
        OutputDebugStringA("MGB_D3D11_HOOK intercepted D3D11CreateDeviceAndSwapChain\n");
        return (FARPROC)hooked_create_device_and_swap_chain;
    }
    return result;
}

static BOOL patch_main_module_iat(void)
{
    BYTE *base = (BYTE *)GetModuleHandleW(NULL);
    IMAGE_DOS_HEADER *dos;
    IMAGE_NT_HEADERS64 *nt;
    IMAGE_IMPORT_DESCRIPTOR *descriptor;
    DWORD old_protection;

    if (!base) return FALSE;
    dos = (IMAGE_DOS_HEADER *)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return FALSE;
    nt = (IMAGE_NT_HEADERS64 *)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return FALSE;
    if (!nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress) {
        return FALSE;
    }
    descriptor = (IMAGE_IMPORT_DESCRIPTOR *)(base +
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    for (; descriptor->Name; ++descriptor) {
        IMAGE_THUNK_DATA64 *names;
        IMAGE_THUNK_DATA64 *imports;
        if (!descriptor->OriginalFirstThunk) continue;
        names = (IMAGE_THUNK_DATA64 *)(base + descriptor->OriginalFirstThunk);
        imports = (IMAGE_THUNK_DATA64 *)(base + descriptor->FirstThunk);
        for (; names->u1.AddressOfData; ++names, ++imports) {
            IMAGE_IMPORT_BY_NAME *import_name;
            if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) continue;
            import_name = (IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData);
            if (!strings_equal((const char *)import_name->Name, "GetProcAddress")) continue;
            real_get_proc_address = (GetProcAddressProc)(ULONG_PTR)imports->u1.Function;
            if (!VirtualProtect(
                    &imports->u1.Function, sizeof(imports->u1.Function),
                    PAGE_READWRITE, &old_protection)) {
                return FALSE;
            }
            imports->u1.Function = (ULONGLONG)(ULONG_PTR)hooked_get_proc_address;
            VirtualProtect(
                &imports->u1.Function, sizeof(imports->u1.Function),
                old_protection, &old_protection);
            OutputDebugStringA("MGB_D3D11_HOOK installed GetProcAddress IAT hook\n");
            return TRUE;
        }
    }
    return FALSE;
}

static FARPROC version_export(const char *name)
{
    if (!real_version_module) {
        real_version_module = LoadLibraryW(L"C:\\windows\\system32\\versi0n.dll");
        if (!real_version_module) {
            OutputDebugStringA("MGB_D3D11_HOOK failed to load versi0n.dll\n");
            return NULL;
        }
    }
    return GetProcAddress(real_version_module, name);
}

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeA(
    LPCSTR filename,
    LPDWORD handle)
{
    typedef DWORD (WINAPI *Proc)(LPCSTR, LPDWORD);
    Proc proc = (Proc)version_export("GetFileVersionInfoSizeA");
    return proc ? proc(filename, handle) : 0;
}

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeW(
    LPCWSTR filename,
    LPDWORD handle)
{
    typedef DWORD (WINAPI *Proc)(LPCWSTR, LPDWORD);
    Proc proc = (Proc)version_export("GetFileVersionInfoSizeW");
    return proc ? proc(filename, handle) : 0;
}

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoA(
    LPCSTR filename,
    DWORD handle,
    DWORD length,
    LPVOID data)
{
    typedef BOOL (WINAPI *Proc)(LPCSTR, DWORD, DWORD, LPVOID);
    Proc proc = (Proc)version_export("GetFileVersionInfoA");
    return proc ? proc(filename, handle, length, data) : FALSE;
}

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoW(
    LPCWSTR filename,
    DWORD handle,
    DWORD length,
    LPVOID data)
{
    typedef BOOL (WINAPI *Proc)(LPCWSTR, DWORD, DWORD, LPVOID);
    Proc proc = (Proc)version_export("GetFileVersionInfoW");
    return proc ? proc(filename, handle, length, data) : FALSE;
}

__declspec(dllexport) BOOL WINAPI VerQueryValueA(
    LPCVOID block,
    LPCSTR sub_block,
    LPVOID *buffer,
    PUINT length)
{
    typedef BOOL (WINAPI *Proc)(LPCVOID, LPCSTR, LPVOID *, PUINT);
    Proc proc = (Proc)version_export("VerQueryValueA");
    return proc ? proc(block, sub_block, buffer, length) : FALSE;
}

__declspec(dllexport) BOOL WINAPI VerQueryValueW(
    LPCVOID block,
    LPCWSTR sub_block,
    LPVOID *buffer,
    PUINT length)
{
    typedef BOOL (WINAPI *Proc)(LPCVOID, LPCWSTR, LPVOID *, PUINT);
    Proc proc = (Proc)version_export("VerQueryValueW");
    return proc ? proc(block, sub_block, buffer, length) : FALSE;
}

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeExA(
    DWORD flags,
    LPCSTR filename,
    LPDWORD handle)
{
    typedef DWORD (WINAPI *Proc)(DWORD, LPCSTR, LPDWORD);
    Proc proc = (Proc)version_export("GetFileVersionInfoSizeExA");
    return proc ? proc(flags, filename, handle) : 0;
}

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeExW(
    DWORD flags,
    LPCWSTR filename,
    LPDWORD handle)
{
    typedef DWORD (WINAPI *Proc)(DWORD, LPCWSTR, LPDWORD);
    Proc proc = (Proc)version_export("GetFileVersionInfoSizeExW");
    return proc ? proc(flags, filename, handle) : 0;
}

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoExA(
    DWORD flags,
    LPCSTR filename,
    DWORD handle,
    DWORD length,
    LPVOID data)
{
    typedef BOOL (WINAPI *Proc)(DWORD, LPCSTR, DWORD, DWORD, LPVOID);
    Proc proc = (Proc)version_export("GetFileVersionInfoExA");
    return proc ? proc(flags, filename, handle, length, data) : FALSE;
}

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoExW(
    DWORD flags,
    LPCWSTR filename,
    DWORD handle,
    DWORD length,
    LPVOID data)
{
    typedef BOOL (WINAPI *Proc)(DWORD, LPCWSTR, DWORD, DWORD, LPVOID);
    Proc proc = (Proc)version_export("GetFileVersionInfoExW");
    return proc ? proc(flags, filename, handle, length, data) : FALSE;
}

__declspec(dllexport) DWORD WINAPI VerFindFileA(
    DWORD flags,
    LPSTR filename,
    LPSTR windows_directory,
    LPSTR app_directory,
    LPSTR current_directory,
    PUINT current_length,
    LPSTR destination_directory,
    PUINT destination_length)
{
    typedef DWORD (WINAPI *Proc)(
        DWORD, LPSTR, LPSTR, LPSTR, LPSTR, PUINT, LPSTR, PUINT);
    Proc proc = (Proc)version_export("VerFindFileA");
    return proc ? proc(
        flags, filename, windows_directory, app_directory,
        current_directory, current_length,
        destination_directory, destination_length) : 0;
}

__declspec(dllexport) DWORD WINAPI VerFindFileW(
    DWORD flags,
    LPWSTR filename,
    LPWSTR windows_directory,
    LPWSTR app_directory,
    LPWSTR current_directory,
    PUINT current_length,
    LPWSTR destination_directory,
    PUINT destination_length)
{
    typedef DWORD (WINAPI *Proc)(
        DWORD, LPWSTR, LPWSTR, LPWSTR, LPWSTR, PUINT, LPWSTR, PUINT);
    Proc proc = (Proc)version_export("VerFindFileW");
    return proc ? proc(
        flags, filename, windows_directory, app_directory,
        current_directory, current_length,
        destination_directory, destination_length) : 0;
}

__declspec(dllexport) DWORD WINAPI VerInstallFileA(
    DWORD flags,
    LPSTR source_filename,
    LPSTR destination_filename,
    LPSTR source_directory,
    LPSTR destination_directory,
    LPSTR current_directory,
    LPSTR temporary_file,
    PUINT temporary_length)
{
    typedef DWORD (WINAPI *Proc)(
        DWORD, LPSTR, LPSTR, LPSTR, LPSTR, LPSTR, LPSTR, PUINT);
    Proc proc = (Proc)version_export("VerInstallFileA");
    return proc ? proc(
        flags, source_filename, destination_filename, source_directory,
        destination_directory, current_directory,
        temporary_file, temporary_length) : 0;
}

__declspec(dllexport) DWORD WINAPI VerInstallFileW(
    DWORD flags,
    LPWSTR source_filename,
    LPWSTR destination_filename,
    LPWSTR source_directory,
    LPWSTR destination_directory,
    LPWSTR current_directory,
    LPWSTR temporary_file,
    PUINT temporary_length)
{
    typedef DWORD (WINAPI *Proc)(
        DWORD, LPWSTR, LPWSTR, LPWSTR, LPWSTR, LPWSTR, LPWSTR, PUINT);
    Proc proc = (Proc)version_export("VerInstallFileW");
    return proc ? proc(
        flags, source_filename, destination_filename, source_directory,
        destination_directory, current_directory,
        temporary_file, temporary_length) : 0;
}

__declspec(dllexport) DWORD WINAPI VerLanguageNameA(
    DWORD language,
    LPSTR buffer,
    DWORD length)
{
    typedef DWORD (WINAPI *Proc)(DWORD, LPSTR, DWORD);
    Proc proc = (Proc)version_export("VerLanguageNameA");
    return proc ? proc(language, buffer, length) : 0;
}

__declspec(dllexport) DWORD WINAPI VerLanguageNameW(
    DWORD language,
    LPWSTR buffer,
    DWORD length)
{
    typedef DWORD (WINAPI *Proc)(DWORD, LPWSTR, DWORD);
    Proc proc = (Proc)version_export("VerLanguageNameW");
    return proc ? proc(language, buffer, length) : 0;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    int target_fps;
    HANDLE thread;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        if (!is_genshin_process()) return TRUE;
        if (environment_flag_enabled("MGB_GPTK_MSAA_SHIM") &&
            !patch_main_module_iat()) {
            OutputDebugStringA("MGB_D3D11_HOOK could not patch main module IAT\n");
        }
        target_fps = requested_fps_limit();
        if (target_fps) {
            thread = CreateThread(
                NULL, 0, fps_unlock_thread, (LPVOID)(INT_PTR)target_fps, 0, NULL);
            if (thread) CloseHandle(thread);
            else write_fps_status("failed:thread");
        }
    }
    return TRUE;
}
