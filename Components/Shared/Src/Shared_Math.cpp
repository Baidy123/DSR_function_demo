#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>

namespace fc {

float Clamp(float value, float lo, float hi)
{
    if (lo > hi) {
        return lo;
    }
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

int ClampInt(int value, int lo, int hi)
{
    if (lo > hi) {
        return lo;
    }
    return value < lo ? lo : (value > hi ? hi : value);
}

float Lerp(float a, float b, float t)
{
    return a + (b - a) * t;
}

float Length(const Vec2& v)
{
    return std::sqrt(v.x * v.x + v.y * v.y);
}

float Distance(const Vec2& a, const Vec2& b)
{
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

Vec2 Normalize(const Vec2& v)
{
    const float len = Length(v);
    if (len <= 0.00001f) {
        return Vec2();
    }
    return Vec2(v.x / len, v.y / len);
}

float AngleBetween(const Vec2& from, const Vec2& to)
{
    const Vec2 a = Normalize(from);
    const Vec2 b = Normalize(to);
    if ((a.x == 0.0f && a.y == 0.0f) || (b.x == 0.0f && b.y == 0.0f)) {
        return 0.0f;
    }
    float dot = a.x * b.x + a.y * b.y;
    dot = Clamp(dot, -1.0f, 1.0f);
    return std::acos(dot);
}

int DirectionFromAngle(float radians)
{
    const float pi = 3.14159265358979323846f;
    float angle = radians;
    while (angle < -pi) {
        angle += 2.0f * pi;
    }
    while (angle > pi) {
        angle -= 2.0f * pi;
    }
    // 0 = 东，π/2 = 南（屏幕 y 向下），π = 西，-π/2 = 北。
    if (angle >= -pi * 0.75f && angle < -pi * 0.25f) {
        return 1; // N
    }
    if (angle >= -pi * 0.25f && angle < pi * 0.25f) {
        return 2; // E
    }
    if (angle >= pi * 0.25f && angle < pi * 0.75f) {
        return 0; // S
    }
    return 3;     // W
}

bool PointInRect(const RectF& rect, const Vec2& point)
{
    return point.x >= rect.x && point.x <= rect.Right() &&
           point.y >= rect.y && point.y <= rect.Bottom();
}

bool RectIntersects(const RectF& a, const RectF& b)
{
    return a.x < b.Right() && a.Right() > b.x &&
           a.y < b.Bottom() && a.Bottom() > b.y;
}

bool CircleIntersectsRect(const Vec2& center, float radius, const RectF& rect)
{
    const float closestX = Clamp(center.x, rect.x, rect.Right());
    const float closestY = Clamp(center.y, rect.y, rect.Bottom());
    const float dx = center.x - closestX;
    const float dy = center.y - closestY;
    return dx * dx + dy * dy <= radius * radius;
}

bool ResolveCircleRect(Vec2& center, float radius, const RectF& rect)
{
    const float closestX = Clamp(center.x, rect.x, rect.Right());
    const float closestY = Clamp(center.y, rect.y, rect.Bottom());
    float dx = center.x - closestX;
    float dy = center.y - closestY;
    const float dist2 = dx * dx + dy * dy;
    if (dist2 > radius * radius) {
        return false;
    }
    if (dist2 > 0.00001f) {
        const float dist = std::sqrt(dist2);
        const float push = radius - dist;
        center.x += (dx / dist) * push;
        center.y += (dy / dist) * push;
        return true;
    }
    // 圆心在矩形内部：选择最短的推出方向。
    const float left = center.x - rect.x;
    const float right = rect.Right() - center.x;
    const float top = center.y - rect.y;
    const float bottom = rect.Bottom() - center.y;
    const float minPen = std::min(std::min(left, right), std::min(top, bottom));
    if (minPen == left) {
        center.x = rect.x - radius;
    } else if (minPen == right) {
        center.x = rect.Right() + radius;
    } else if (minPen == top) {
        center.y = rect.y - radius;
    } else {
        center.y = rect.Bottom() + radius;
    }
    return true;
}

float MoveTowards(float current, float target, float maxDelta)
{
    if (current < target) {
        return std::min(current + maxDelta, target);
    }
    return std::max(current - maxDelta, target);
}

int ManhattanDistance(int ax, int ay, int bx, int by)
{
    return std::abs(ax - bx) + std::abs(ay - by);
}

} // namespace fc
