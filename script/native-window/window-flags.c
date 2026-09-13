#include <windows.h>
#include <stdio.h>
#include <wchar.h>
static const wchar_t *title;
static unsigned matches;
static DWORD game_pid;
static BOOL matches_title(const wchar_t *name) {
    const wchar_t *start=title;
    while (*start) {
        const wchar_t *end=wcschr(start,L'|');
        size_t length=end?(size_t)(end-start):wcslen(start);
        if (wcslen(name)==length && !wcsncmp(name,start,length)) return TRUE;
        if (!end) break;
        start=end+1;
    }
    return FALSE;
}
static BOOL CALLBACK visit(HWND window, LPARAM unused) {
    (void)unused;
    wchar_t name[256]; GetWindowTextW(window,name,256);
    if (!IsWindowVisible(window) || !matches_title(name)) return TRUE;
    DWORD pid; GetWindowThreadProcessId(window,&pid);
    if (game_pid && game_pid!=pid) return TRUE;
    LONG_PTR old=GetWindowLongPtrW(window,GWL_STYLE);
    // Only an already-windowed top-level window, never a popup/fullscreen window.
    if (!(old & WS_CAPTION) || (old & (WS_CHILD|WS_POPUP))) return TRUE;
    LONG_PTR updated=old|WS_THICKFRAME|WS_MAXIMIZEBOX;
    if (updated==old) { game_pid=pid; matches++; return FALSE; }
    SetLastError(0);
    SetWindowLongPtrW(window,GWL_STYLE,updated);
    if (GetLastError()) return TRUE;
    if (!SetWindowPos(window,NULL,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED)) return TRUE;
    game_pid=pid; matches++;
    printf("MGB_WINDOW style before=%llx after=%llx\n",(unsigned long long)old,(unsigned long long)GetWindowLongPtrW(window,GWL_STYLE));
    return FALSE;
}
int wmain(int argc,wchar_t **argv) {
    BOOL watch=argc==3 && !wcscmp(argv[2],L"--watch");
    if ((argc!=2 && !watch) || !argv[1][0]) return 2;
    title=argv[1];
    HANDLE game=NULL;
    for (unsigned attempt=0; ; attempt++) {
        matches=0; EnumWindows(visit,0); fflush(stdout);
        if (!watch) return matches==1?0:1;
        if (!game && game_pid) {
            game=OpenProcess(SYNCHRONIZE,FALSE,game_pid);
            if (!game) return 1;
        }
        if (game) {
            DWORD result=WaitForSingleObject(game,1000);
            if (result!=WAIT_TIMEOUT) { CloseHandle(game); return result==WAIT_OBJECT_0?0:1; }
        } else {
            if (attempt>=120) return 1;
            Sleep(1000);
        }
    }
}
