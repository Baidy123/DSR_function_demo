#include "Platform_Window.hpp"

#include "Platform_Input.hpp"
#include "Shared_Log.hpp"

namespace fc {

namespace {
const wchar_t* WINDOW_CLASS_NAME = L"FCEmberWindowClass";
}

Window::~Window()
{
    if (m_handle != nullptr) {
        DestroyWindow(m_handle);
        m_handle = nullptr;
    }
}

bool Window::Create(int width, int height, const wchar_t* title, bool visible)
{
    m_instance = GetModuleHandleW(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &Window::WndProc;
    wc.hInstance = m_instance;
    wc.hCursor = nullptr;
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = WINDOW_CLASS_NAME;
    if (RegisterClassExW(&wc) == 0) {
        if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            LogError("RegisterClassExW failed: %lu", GetLastError());
            return false;
        }
    }

    RECT rect = {0, 0, width, height};
    const DWORD style = WS_OVERLAPPEDWINDOW;
    AdjustWindowRectEx(&rect, style, FALSE, 0);
    const int windowW = rect.right - rect.left;
    const int windowH = rect.bottom - rect.top;

    const int screenW = GetSystemMetrics(SM_CXSCREEN);
    const int screenH = GetSystemMetrics(SM_CYSCREEN);
    const int posX = (screenW - windowW) / 2;
    const int posY = (screenH - windowH) / 2;

    m_handle = CreateWindowExW(0, WINDOW_CLASS_NAME, title, style,
                               posX, posY, windowW, windowH,
                               nullptr, nullptr, m_instance, this);
    if (m_handle == nullptr) {
        LogError("CreateWindowExW failed: %lu", GetLastError());
        return false;
    }

    UpdateClientSize();
    if (visible) {
        ShowWindow(m_handle, SW_SHOW);
        UpdateWindow(m_handle);
    } else {
        ShowWindow(m_handle, SW_HIDE);
    }
    m_running = true;
    return true;
}

bool Window::PumpMessages()
{
    MSG msg = {};
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) {
            m_running = false;
            break;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return m_running;
}

void Window::SetTitle(const wchar_t* title)
{
    if (m_handle != nullptr && title != nullptr) {
        SetWindowTextW(m_handle, title);
    }
}

void Window::ToggleFullscreen()
{
    ApplyFullscreen(!m_fullscreen);
}

void Window::ApplyFullscreen(bool enable)
{
    if (m_handle == nullptr) {
        return;
    }
    if (enable == m_fullscreen) {
        return;
    }

    if (enable) {
        m_savedStyle = GetWindowLongPtrW(m_handle, GWL_STYLE);
        GetWindowRect(m_handle, &m_savedRect);

        MONITORINFO monitorInfo = {};
        monitorInfo.cbSize = sizeof(monitorInfo);
        GetMonitorInfoW(MonitorFromWindow(m_handle, MONITOR_DEFAULTTONEAREST),
                        &monitorInfo);

        SetWindowLongPtrW(m_handle, GWL_STYLE,
                          (m_savedStyle & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
        SetWindowPos(m_handle, HWND_TOP,
                     monitorInfo.rcMonitor.left, monitorInfo.rcMonitor.top,
                     monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left,
                     monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        m_fullscreen = true;
    } else {
        SetWindowLongPtrW(m_handle, GWL_STYLE, m_savedStyle);
        SetWindowPos(m_handle, HWND_TOP,
                     m_savedRect.left, m_savedRect.top,
                     m_savedRect.right - m_savedRect.left,
                     m_savedRect.bottom - m_savedRect.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        m_fullscreen = false;
    }
    UpdateClientSize();
}

void Window::UpdateClientSize()
{
    if (m_handle == nullptr) {
        return;
    }
    RECT client = {};
    if (GetClientRect(m_handle, &client)) {
        m_clientWidth = client.right - client.left;
        m_clientHeight = client.bottom - client.top;
        if (m_clientWidth < 1) {
            m_clientWidth = 1;
        }
        if (m_clientHeight < 1) {
            m_clientHeight = 1;
        }
    }
    m_minimized = IsIconic(m_handle) != FALSE;
}

LRESULT CALLBACK Window::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_NCCREATE) {
        CREATESTRUCTW* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
        Window* window = reinterpret_cast<Window*>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
        if (window != nullptr) {
            window->m_handle = hwnd;
        }
    }

    Window* window = reinterpret_cast<Window*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (window != nullptr) {
        return window->HandleMessage(hwnd, msg, wParam, lParam);
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT Window::HandleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    Input::Get().OnMessage(msg, wParam, lParam);

    switch (msg) {
    case WM_SIZE:
        UpdateClientSize();
        return 0;
    case WM_GETMINMAXINFO: {
        MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lParam);
        RECT minRect = {0, 0, 960, 540};
        AdjustWindowRectEx(&minRect, WS_OVERLAPPEDWINDOW, FALSE, 0);
        info->ptMinTrackSize.x = minRect.right - minRect.left;
        info->ptMinTrackSize.y = minRect.bottom - minRect.top;
        return 0;
    }
    case WM_SYSKEYDOWN:
        if (wParam == VK_RETURN && (lParam & (1 << 29)) != 0) {
            ToggleFullscreen();
            return 0;
        }
        break;
    case WM_SETCURSOR:
        if (LOWORD(lParam) == HTCLIENT) {
            SetCursor(nullptr);
            return TRUE;
        }
        break;
    case WM_ACTIVATEAPP:
        if (wParam == FALSE) {
            Input::Get().Reset();
        }
        return 0;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        m_handle = nullptr;
        m_running = false;
        PostQuitMessage(0);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

} // namespace fc
