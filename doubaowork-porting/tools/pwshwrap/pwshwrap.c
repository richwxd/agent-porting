/* pwshwrap: 给真正的 pwsh 分配一个 ConPTY，并把管道与伪控制台之间双向转发。
 * 适用于 Wine 下 .NET ConsoleHost 在非终端 stdio 时不执行命令的问题。
 */
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

static HANDLE g_out_read = INVALID_HANDLE_VALUE;
static DWORD WINAPI stdout_thread(LPVOID unused) {
    char buf[8192];
    DWORD n;
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    while (ReadFile(g_out_read, buf, sizeof buf, &n, NULL) && n > 0) {
        DWORD w = 0;
        if (!WriteFile(out, buf, n, &w, NULL)) break;
    }
    return 0;
}

static DWORD WINAPI stdin_thread(LPVOID arg) {
    HANDLE in = (HANDLE)arg;
    char buf[4096];
    DWORD n;
    HANDLE stdin_h = GetStdHandle(STD_INPUT_HANDLE);
    while (ReadFile(stdin_h, buf, sizeof buf, &n, NULL) && n > 0) {
        DWORD w = 0;
        if (!WriteFile(in, buf, n, &w, NULL)) break;
    }
    CloseHandle(in);
    return 0;
}

static void dir_of_module(wchar_t *out, DWORD cch) {
    DWORD n = GetModuleFileNameW(NULL, out, cch);
    if (n == 0 || n >= cch) { out[0] = 0; return; }
    wchar_t *slash = wcsrchr(out, L'\\');
    if (slash) *slash = 0;
}

int main(void) {
    wchar_t dir[MAX_PATH];
    wchar_t real[MAX_PATH];
    dir_of_module(dir, MAX_PATH);
    if (dir[0])
        _snwprintf(real, MAX_PATH, L"%ls\\pwsh-real.exe", dir);
    else
        wcscpy(real, L"pwsh-real.exe");

    if (GetFileAttributesW(real) == INVALID_FILE_ATTRIBUTES) {
        DWORD n = GetEnvironmentVariableW(L"DOUBAOWORK_PWSH_REAL", real, MAX_PATH);
        if (n == 0 || n >= MAX_PATH) {
            fwprintf(stderr, L"pwshwrap: cannot find pwsh-real.exe\n");
            return 127;
        }
    }

    /* 取原始命令行中程序名之后的部分 */
    const wchar_t *cl = GetCommandLineW();
    const wchar_t *p = cl;
    if (*p == L'"') { p++; while (*p && *p != L'"') p++; if (*p) p++; }
    else while (*p && *p != L' ' && *p != L'\t') p++;
    while (*p == L' ' || *p == L'\t') p++;

    size_t cap = wcslen(real) + wcslen(p) + 16;
    wchar_t *cmd = (wchar_t *)malloc(cap * sizeof(wchar_t));
    if (!cmd) return 127;
    _snwprintf(cmd, cap, L"\"%ls\" %ls", real, p);

    HANDLE in_read = INVALID_HANDLE_VALUE, in_write = INVALID_HANDLE_VALUE;
    HANDLE out_read = INVALID_HANDLE_VALUE, out_write = INVALID_HANDLE_VALUE;
    if (!CreatePipe(&in_read, &in_write, NULL, 0) ||
        !CreatePipe(&out_read, &out_write, NULL, 0)) {
        fwprintf(stderr, L"pwshwrap: CreatePipe failed\n");
        return 127;
    }

    int dbg = 0;
    { wchar_t v[8]; dbg = GetEnvironmentVariableW(L"PWSHWRAP_DEBUG", v, 8) > 0; }

    HPCON pc = NULL;
    HRESULT hr = CreatePseudoConsole((COORD){120, 30}, in_read, out_write, 0, &pc);
    if (dbg) { fwprintf(stderr, L"pwshwrap: hr=0x%08lx pc=%p err=%lu\n",(unsigned long)hr,(void *)pc,GetLastError()); fflush(stderr); }

    STARTUPINFOEXW si;
    ZeroMemory(&si, sizeof si);
    si.StartupInfo.cb = sizeof si;
    LPPROC_THREAD_ATTRIBUTE_LIST attr = NULL;
    DWORD flags = 0;
    if (SUCCEEDED(hr)) {
        SIZE_T attr_size = 0;
        InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
        attr = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_size);
        if (attr && InitializeProcThreadAttributeList(attr, 1, 0, &attr_size) &&
            UpdateProcThreadAttribute(attr, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                      pc, sizeof pc, NULL, NULL)) {
            si.lpAttributeList = attr;
            flags = EXTENDED_STARTUPINFO_PRESENT;
        } else {
            ClosePseudoConsole(pc);
            pc = NULL;
            hr = E_FAIL;
        }
    }
    if (dbg) { fwprintf(stderr, L"pwshwrap: attr=%p flags=0x%lx\n",(void *)attr,(unsigned long)flags); fflush(stderr); }
    if (!pc && attr) { free(attr); attr = NULL; }

    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof pi);
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, flags, NULL, NULL,
                        &si.StartupInfo, &pi)) {
        fwprintf(stderr, L"pwshwrap: CreateProcess failed: %lu\n", GetLastError());
        return 127;
    }
    free(cmd);
    if (attr) { DeleteProcThreadAttributeList(attr); free(attr); }

    if (pc) {
        /* 父进程不再需要这两端 */
        CloseHandle(in_read);
        CloseHandle(out_write);
        g_out_read = out_read;
        HANDLE th_out = CreateThread(NULL, 0, stdout_thread, NULL, 0, NULL);
        HANDLE th_in = CreateThread(NULL, 0, stdin_thread, in_write, 0, NULL);
        WaitForSingleObject(pi.hProcess, INFINITE);
        DWORD code = 0;
        GetExitCodeProcess(pi.hProcess, &code);
        ClosePseudoConsole(pc);
        if (th_out) { WaitForSingleObject(th_out, 3000); CloseHandle(th_out); }
        if (th_in) { WaitForSingleObject(th_in, 1000); CloseHandle(th_in); }
        CloseHandle(out_read);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return (int)code;
    }

    /* ConPTY 不可用：退化为直接继承 stdio */
    CloseHandle(in_read); CloseHandle(in_write);
    CloseHandle(out_read); CloseHandle(out_write);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
