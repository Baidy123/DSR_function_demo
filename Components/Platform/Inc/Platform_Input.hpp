#ifndef __PLATFORM_INPUT_HPP__
#define __PLATFORM_INPUT_HPP__

#include "Shared_Types.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

/**
 * @brief 全局输入状态：键盘、鼠标位置与按键边沿。
 *
 * 使用方式：窗口过程把消息转发给 OnMessage；每帧结束时调用 EndFrame。
 */
class Input {
public:
    /**
     * @brief 获取全局单例。
     * @return 输入状态引用。
     */
    static Input& Get();

    /**
     * @brief 处理窗口消息。
     * @param [IN] msg 消息 ID。
     * @param [IN] wParam 消息参数。
     * @param [IN] lParam 消息参数。
     * @return 已处理返回 true。
     */
    bool OnMessage(UINT msg, WPARAM wParam, LPARAM lParam);

    /**
     * @brief 结束一帧，更新边沿状态。
     */
    void EndFrame();

    /**
     * @brief 清空全部状态（失焦时调用）。
     */
    void Reset();

    /**
     * @brief 查询按键是否按下。
     * @param [IN] vk 虚拟键码。
     * @return 按下返回 true。
     */
    bool Down(int vk) const;

    /**
     * @brief 查询按键是否在本帧刚按下。
     * @param [IN] vk 虚拟键码。
     * @return 刚按下返回 true。
     */
    bool Pressed(int vk) const;

    /**
     * @brief 查询按键是否在本帧刚抬起。
     * @param [IN] vk 虚拟键码。
     * @return 刚抬起返回 true。
     */
    bool Released(int vk) const;

    /**
     * @brief 查询鼠标按键是否按下。
     * @param [IN] button 0 左键、1 右键、2 中键。
     * @return 按下返回 true。
     */
    bool MouseDown(int button) const;

    /**
     * @brief 查询鼠标按键是否在本帧刚按下。
     * @param [IN] button 0 左键、1 右键、2 中键。
     * @return 刚按下返回 true。
     */
    bool MousePressed(int button) const;

    /**
     * @brief 获取鼠标客户区坐标。
     * @return 像素坐标。
     */
    Vec2 MousePosition() const { return Vec2(static_cast<float>(m_mouseX),
                                             static_cast<float>(m_mouseY)); }

    /**
     * @brief 获取鼠标滚轮累计增量（每格 120）。
     * @return 滚轮增量。
     */
    int WheelDelta() const { return m_wheelDelta; }

    /**
     * @brief 清空滚轮增量（消费后调用）。
     */
    void ConsumeWheel() { m_wheelDelta = 0; }

    /**
     * @brief 窗口是否拥有焦点。
     * @return 拥有焦点返回 true。
     */
    bool HasFocus() const { return m_hasFocus; }

private:
    Input() = default;

    bool m_down[256] = {false};
    bool m_prev[256] = {false};
    bool m_mouseDown[3] = {false};
    bool m_mousePrev[3] = {false};
    int m_mouseX = 0;
    int m_mouseY = 0;
    int m_wheelDelta = 0;
    bool m_hasFocus = true;
};

} // namespace fc

#endif // __PLATFORM_INPUT_HPP__
