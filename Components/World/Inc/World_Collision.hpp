#ifndef __WORLD_COLLISION_HPP__
#define __WORLD_COLLISION_HPP__

#include "Shared_Types.hpp"

#include <vector>

namespace fc {

/**
 * @brief 静态碰撞世界：以 AABB 表示墙、道具与货箱。
 *
 * 角色使用竖直圆柱（XZ 圆 + 高度区间）进行碰撞；子弹使用线段与 AABB 求交。
 */
class CollisionWorld {
public:
    /**
     * @brief 清空全部碰撞体。
     */
    void Clear();

    /**
     * @brief 添加一个碰撞盒。
     * @param [IN] box 包围盒。
     */
    void AddBox(const AABB& box);

    /**
     * @brief 碰撞体数量。
     * @return 数量。
     */
    int Count() const { return static_cast<int>(m_boxes.size()); }

    /**
     * @brief 圆是否与任何碰撞体相交。
     * @param [IN] center 圆心。
     * @param [IN] radius 半径。
     * @return 相交返回 true。
     */
    bool Blocked(const Vec3& center, float radius) const;

    /**
     * @brief 轴分离移动（先 X 后 Z），遇阻沿另一轴滑动。
     * @param [IN/OUT] position 位置。
     * @param [IN] delta 位移。
     * @param [IN] radius 半径。
     * @return 发生移动返回 true。
     */
    bool Move(Vec3& position, const Vec3& delta, float radius) const;

    /**
     * @brief 线段是否被遮挡。
     * @param [IN] from 起点。
     * @param [IN] to 终点。
     * @param [OUT] hitT 命中参数（0–1）。
     * @return 被遮挡返回 true。
     */
    bool SegmentBlocked(const Vec3& from, const Vec3& to, float& hitT) const;

    /**
     * @brief 带半径的线段检测：把包围盒向外扩张后求交。
     *
     * 用于子弹：即使弹道贴着箱子边缘擦过，也会被判为命中，避免出现
     * “子弹穿过障碍物”的视觉错觉。
     * @param [IN] from 起点。
     * @param [IN] to 终点。
     * @param [IN] dilation 扩张量（米）。
     * @param [OUT] hitT 命中参数（0–1）。
     * @return 命中返回 true。
     */
    bool SegmentBlockedDilated(const Vec3& from, const Vec3& to,
                               float dilation, float& hitT) const;

    /**
     * @brief 线段是否被遮挡（忽略高度为 0 的薄片）。
     * @param [IN] from 起点。
     * @param [IN] to 终点。
     * @return 被遮挡返回 true。
     */
    bool LineBlocked(const Vec3& from, const Vec3& to) const;

private:
    std::vector<AABB> m_boxes;
};

} // namespace fc

#endif // __WORLD_COLLISION_HPP__
