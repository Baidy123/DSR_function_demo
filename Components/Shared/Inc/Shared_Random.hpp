#ifndef __SHARED_RANDOM_HPP__
#define __SHARED_RANDOM_HPP__

#include <cstdint>

namespace fc {

/**
 * @brief 确定性伪随机数生成器（xorshift32），用于玩法与视觉抖动。
 */
class Rng {
public:
    /**
     * @brief 构造随机数生成器。
     * @param [IN] seed 初始种子；0 会被替换为 1。
     */
    explicit Rng(uint32_t seed = 0x9E3779B9u) : m_state(seed == 0 ? 1u : seed) {}

    /**
     * @brief 重新设置种子。
     * @param [IN] seed 新种子。
     */
    void Seed(uint32_t seed)
    {
        m_state = (seed == 0u) ? 1u : seed;
    }

    /**
     * @brief 生成下一个 32 位随机数。
     * @return 随机数。
     */
    uint32_t Next()
    {
        uint32_t x = m_state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        m_state = x;
        return x;
    }

    /**
     * @brief 生成闭区间随机整数。
     * @param [IN] lo 下界。
     * @param [IN] hi 上界。
     * @return [lo, hi] 内的整数。
     */
    int Range(int lo, int hi)
    {
        if (hi <= lo) {
            return lo;
        }
        return lo + static_cast<int>(Next() % static_cast<uint32_t>(hi - lo + 1));
    }

    /**
     * @brief 生成 [0,1) 浮点数。
     * @return 随机浮点数。
     */
    float Unit()
    {
        return static_cast<float>(Next() & 0x00FFFFFFu) / 16777216.0f;
    }

    /**
     * @brief 生成 [lo, hi) 浮点数。
     * @param [IN] lo 下界。
     * @param [IN] hi 上界。
     * @return 随机浮点数。
     */
    float Float(float lo, float hi)
    {
        return lo + (hi - lo) * Unit();
    }

    /**
     * @brief 以给定百分比概率返回 true。
     * @param [IN] percent 概率（0–100）。
     * @return 命中返回 true。
     */
    bool Chance(int percent)
    {
        return Range(0, 99) < percent;
    }

private:
    uint32_t m_state;
};

} // namespace fc

#endif // __SHARED_RANDOM_HPP__
