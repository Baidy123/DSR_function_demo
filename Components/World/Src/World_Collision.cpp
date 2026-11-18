#include "World_Collision.hpp"

#include "Shared_Math.hpp"

namespace fc {

void CollisionWorld::Clear()
{
    m_boxes.clear();
}

void CollisionWorld::AddBox(const AABB& box)
{
    m_boxes.push_back(box);
}

bool CollisionWorld::Blocked(const Vec3& center, float radius) const
{
    for (const AABB& box : m_boxes) {
        if (CircleIntersectsBox(center, radius, box)) {
            return true;
        }
    }
    return false;
}

bool CollisionWorld::Move(Vec3& position, const Vec3& delta, float radius) const
{
    bool moved = false;
    if (delta.x != 0.0f) {
        Vec3 next = position;
        next.x += delta.x;
        if (!Blocked(next, radius)) {
            position = next;
            moved = true;
        }
    }
    if (delta.z != 0.0f) {
        Vec3 next = position;
        next.z += delta.z;
        if (!Blocked(next, radius)) {
            position = next;
            moved = true;
        }
    }
    return moved;
}

bool CollisionWorld::SegmentBlocked(const Vec3& from, const Vec3& to,
                                    float& hitT) const
{
    bool hit = false;
    float best = 1.0f;
    for (const AABB& box : m_boxes) {
        float t = 0.0f;
        if (SegmentAABB(from, to, box, t) && t < best) {
            best = t;
            hit = true;
        }
    }
    hitT = best;
    return hit;
}

bool CollisionWorld::SegmentBlockedDilated(const Vec3& from, const Vec3& to,
                                          float dilation, float& hitT) const
{
    bool hit = false;
    float best = 1.0f;
    for (const AABB& box : m_boxes) {
        const AABB expanded(
            Vec3(box.min.x - dilation, box.min.y - dilation,
                 box.min.z - dilation),
            Vec3(box.max.x + dilation, box.max.y + dilation,
                 box.max.z + dilation));
        float t = 0.0f;
        if (SegmentAABB(from, to, expanded, t) && t < best) {
            best = t;
            hit = true;
        }
    }
    hitT = best;
    return hit;
}

bool CollisionWorld::LineBlocked(const Vec3& from, const Vec3& to) const
{
    float t = 1.0f;
    return SegmentBlocked(from, to, t);
}

} // namespace fc
