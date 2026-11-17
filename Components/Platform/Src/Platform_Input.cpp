#include "Platform_Input.hpp"

#include <cstring>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windowsx.h>

namespace fc {

Input& Input::Get()
{
    static Input instance;
    return instance;
}

bool Input::OnMessage(UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN: {
        const int vk = static_cast<int>(wParam) & 0xFF;
        if (vk >= 0 && vk < 256) {
            if ((lParam & (1 << 30)) == 0) {
                m_down[vk] = true;
            }
        }
        return true;
    }
    case WM_KEYUP:
    case WM_SYSKEYUP: {
        const int vk = static_cast<int>(wParam) & 0xFF;
        if (vk >= 0 && vk < 256) {
            m_down[vk] = false;
        }
        return true;
    }
    case WM_MOUSEMOVE: {
        m_mouseX = GET_X_LPARAM(lParam);
        m_mouseY = GET_Y_LPARAM(lParam);
        return true;
    }
    case WM_LBUTTONDOWN:
        m_mouseDown[0] = true;
        return true;
    case WM_LBUTTONUP:
        m_mouseDown[0] = false;
        return true;
    case WM_RBUTTONDOWN:
        m_mouseDown[1] = true;
        return true;
    case WM_RBUTTONUP:
        m_mouseDown[1] = false;
        return true;
    case WM_MBUTTONDOWN:
        m_mouseDown[2] = true;
        return true;
    case WM_MBUTTONUP:
        m_mouseDown[2] = false;
        return true;
    case WM_MOUSEWHEEL:
        m_wheelDelta += GET_WHEEL_DELTA_WPARAM(wParam);
        return true;
    case WM_SETFOCUS:
        m_hasFocus = true;
        return true;
    case WM_KILLFOCUS:
        m_hasFocus = false;
        Reset();
        return true;
    default:
        return false;
    }
}

void Input::EndFrame()
{
    std::memcpy(m_prev, m_down, sizeof(m_down));
    std::memcpy(m_mousePrev, m_mouseDown, sizeof(m_mouseDown));
    m_wheelDelta = 0;
}

void Input::Reset()
{
    std::memset(m_down, 0, sizeof(m_down));
    std::memset(m_prev, 0, sizeof(m_prev));
    std::memset(m_mouseDown, 0, sizeof(m_mouseDown));
    std::memset(m_mousePrev, 0, sizeof(m_mousePrev));
    m_wheelDelta = 0;
}

bool Input::Down(int vk) const
{
    if (vk < 0 || vk >= 256) {
        return false;
    }
    return m_down[vk];
}

bool Input::Pressed(int vk) const
{
    if (vk < 0 || vk >= 256) {
        return false;
    }
    return m_down[vk] && !m_prev[vk];
}

bool Input::Released(int vk) const
{
    if (vk < 0 || vk >= 256) {
        return false;
    }
    return !m_down[vk] && m_prev[vk];
}

bool Input::MouseDown(int button) const
{
    if (button < 0 || button > 2) {
        return false;
    }
    return m_mouseDown[button];
}

bool Input::MousePressed(int button) const
{
    if (button < 0 || button > 2) {
        return false;
    }
    return m_mouseDown[button] && !m_mousePrev[button];
}

} // namespace fc
