#ifndef __PLATFORM_WINDOW_HPP__
#define __PLATFORM_WINDOW_HPP__

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

/**
 * @brief Win32 窗口封装：创建、消息泵、尺寸与全屏切换。
 */
class Window {
public:
    Window() = default;
    ~Window();

    /**
     * @brief 创建窗口。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @param [IN] title 窗口标题（UTF-16）。
     * @param [IN] visible 是否显示窗口；无头测试传 false。
     * @return 成功返回 true。
     */
    bool Create(int width, int height, const wchar_t* title, bool visible);

    /**
     * @brief 处理消息队列。
     * @return 窗口仍在运行返回 true。
     */
    bool PumpMessages();

    /**
     * @brief 获取窗口句柄。
     * @return HWND。
     */
    HWND Handle() const { return m_handle; }

    /**
     * @brief 获取客户区宽度。
     * @return 像素宽度。
     */
    int ClientWidth() const { return m_clientWidth; }

    /**
     * @brief 获取客户区高度。
     * @return 像素高度。
     */
    int ClientHeight() const { return m_clientHeight; }

    /**
     * @brief 是否处于最小化状态。
     * @return 最小化返回 true。
     */
    bool IsMinimized() const { return m_minimized; }

    /**
     * @brief 切换无边框全屏。
     */
    void ToggleFullscreen();

    /**
     * @brief 查询是否全屏。
     * @return 全屏返回 true。
     */
    bool IsFullscreen() const { return m_fullscreen; }

    /**
     * @brief 请求退出消息循环。
     */
    void RequestClose() { m_running = false; }

    /**
     * @brief 设置窗口标题。
     * @param [IN] title UTF-16 标题。
     */
    void SetTitle(const wchar_t* title);

private:
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void UpdateClientSize();
    void ApplyFullscreen(bool enable);

    HWND m_handle = nullptr;
    HINSTANCE m_instance = nullptr;
    int m_clientWidth = 0;
    int m_clientHeight = 0;
    bool m_running = true;
    bool m_minimized = false;
    bool m_fullscreen = false;
    RECT m_savedRect = {0, 0, 0, 0};
    LONG_PTR m_savedStyle = 0;
};

} // namespace fc

#endif // __PLATFORM_WINDOW_HPP__
