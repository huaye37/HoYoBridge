#include <windows.h>
#include <stdio.h>
static LRESULT CALLBACK procedure(HWND w, UINT m, WPARAM a, LPARAM b) {
    if (m==WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(w,m,a,b);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR args,int show) {
    (void)previous; (void)args;
    SetProcessDPIAware();
    HDC dc=GetDC(NULL);
    printf("MGB_DISPLAY windows=%dx%d dpi=%d\n",GetSystemMetrics(SM_CXSCREEN),GetSystemMetrics(SM_CYSCREEN),GetDeviceCaps(dc,LOGPIXELSX));
    ReleaseDC(NULL,dc);
    fflush(stdout);
    WNDCLASSW cls={0}; cls.lpfnWndProc=procedure; cls.hInstance=instance;
    cls.lpszClassName=L"MGBWindowTest"; cls.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);
    RegisterClassW(&cls);
    HWND w=CreateWindowW(cls.lpszClassName,L"MGBWindowTest",WS_OVERLAPPEDWINDOW,
        80,80,1200,700,NULL,NULL,instance,NULL);
    ShowWindow(w,show);
    MSG message;
    while (GetMessageW(&message,NULL,0,0)>0) { TranslateMessage(&message); DispatchMessageW(&message); }
    return 0;
}
