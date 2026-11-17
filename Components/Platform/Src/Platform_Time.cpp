#include "Platform_Time.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

Clock::Clock()
{
    LARGE_INTEGER frequency = {};
    QueryPerformanceFrequency(&frequency);
    m_frequency = frequency.QuadPart > 0 ? frequency.QuadPart : 1;
    Reset();
}

double Clock::SecondsNow() const
{
    LARGE_INTEGER counter = {};
    QueryPerformanceCounter(&counter);
    return static_cast<double>(counter.QuadPart) /
           static_cast<double>(m_frequency);
}

double Clock::Reset()
{
    LARGE_INTEGER counter = {};
    QueryPerformanceCounter(&counter);
    m_start = counter.QuadPart;
    m_last = counter.QuadPart;
    return 0.0;
}

float Clock::Tick()
{
    LARGE_INTEGER counter = {};
    QueryPerformanceCounter(&counter);
    const std::int64_t delta = counter.QuadPart - m_last;
    m_last = counter.QuadPart;
    float seconds = static_cast<float>(static_cast<double>(delta) /
                                       static_cast<double>(m_frequency));
    if (seconds < 0.0f) {
        seconds = 0.0f;
    }
    if (seconds > 0.1f) {
        seconds = 0.1f;
    }
    return seconds;
}

double Clock::TotalSeconds() const
{
    LARGE_INTEGER counter = {};
    QueryPerformanceCounter(&counter);
    return static_cast<double>(counter.QuadPart - m_start) /
           static_cast<double>(m_frequency);
}

} // namespace fc
