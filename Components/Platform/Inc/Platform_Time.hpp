#ifndef __PLATFORM_TIME_HPP__
#define __PLATFORM_TIME_HPP__

#include <cstdint>

namespace fc {

/**
 * @brief 基于 QueryPerformanceCounter 的帧计时器。
 */
class Clock {
public:
    Clock();

    /**
     * @brief 重置计时起点并返回当前时间。
     * @return 秒数。
     */
    double Reset();

    /**
     * @brief 计算距上次 Tick 的秒数；首次调用返回 0。
     * @return 秒数。
     */
    float Tick();

    /**
     * @brief 获取运行总时长。
     * @return 秒数。
     */
    double TotalSeconds() const;

private:
    double SecondsNow() const;

    std::int64_t m_frequency = 0;
    std::int64_t m_start = 0;
    std::int64_t m_last = 0;
};

} // namespace fc

#endif // __PLATFORM_TIME_HPP__
