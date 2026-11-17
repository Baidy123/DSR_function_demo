#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>

namespace fc {

Mat4 Mat4::Identity()
{
    Mat4 result;
    return result;
}

Mat4 Mat4::Translation(const Vec3& offset)
{
    Mat4 result;
    result.m[12] = offset.x;
    result.m[13] = offset.y;
    result.m[14] = offset.z;
    return result;
}

Mat4 Mat4::Scale(const Vec3& scale)
{
    Mat4 result;
    result.m[0] = scale.x;
    result.m[5] = scale.y;
    result.m[10] = scale.z;
    return result;
}

Mat4 Mat4::RotationY(float radians)
{
    const float c = std::cos(radians);
    const float s = std::sin(radians);
    Mat4 result;
    result.m[0] = c;
    result.m[2] = -s;
    result.m[8] = s;
    result.m[10] = c;
    return result;
}

Mat4 Mat4::RotationX(float radians)
{
    const float c = std::cos(radians);
    const float s = std::sin(radians);
    Mat4 result;
    result.m[5] = c;
    result.m[6] = s;
    result.m[9] = -s;
    result.m[10] = c;
    return result;
}

Mat4 Mat4::RotationZ(float radians)
{
    const float c = std::cos(radians);
    const float s = std::sin(radians);
    Mat4 result;
    result.m[0] = c;
    result.m[1] = s;
    result.m[4] = -s;
    result.m[5] = c;
    return result;
}

Mat4 Mat4::Perspective(float fovRadians, float aspect, float nearPlane,
                       float farPlane)
{
    // 与右手系 LookAt 配合的 D3D 深度映射：近平面 -> 0，远平面 -> 1。
    Mat4 result;
    const float f = 1.0f / std::tan(fovRadians * 0.5f);
    const float depth = nearPlane - farPlane;
    result.m[0] = f / aspect;
    result.m[5] = f;
    result.m[10] = farPlane / depth;
    result.m[11] = -1.0f;
    result.m[14] = (nearPlane * farPlane) / depth;
    result.m[15] = 0.0f;
    return result;
}

Mat4 Mat4::LookAt(const Vec3& eye, const Vec3& target, const Vec3& up)
{
    const Vec3 forward = Normalize(target - eye);
    Vec3 right = Cross(up, forward);
    if (Length(right) < 0.0001f) {
        right = Vec3(1.0f, 0.0f, 0.0f);
    }
    right = Normalize(right);
    const Vec3 correctedUp = Cross(forward, right);

    Mat4 result;
    result.m[0] = right.x;
    result.m[4] = right.y;
    result.m[8] = right.z;
    result.m[1] = correctedUp.x;
    result.m[5] = correctedUp.y;
    result.m[9] = correctedUp.z;
    result.m[2] = -forward.x;
    result.m[6] = -forward.y;
    result.m[10] = -forward.z;
    result.m[12] = -Dot(right, eye);
    result.m[13] = -Dot(correctedUp, eye);
    result.m[14] = Dot(forward, eye);
    return result;
}

Mat4 Mat4::operator*(const Mat4& other) const
{
    Mat4 result;
    for (int row = 0; row < 4; ++row) {
        for (int col = 0; col < 4; ++col) {
            float sum = 0.0f;
            for (int k = 0; k < 4; ++k) {
                sum += m[row * 4 + k] * other.m[k * 4 + col];
            }
            result.m[row * 4 + col] = sum;
        }
    }
    return result;
}

Vec3 Mat4::TransformPoint(const Vec3& p) const
{
    const float x = p.x * m[0] + p.y * m[4] + p.z * m[8] + m[12];
    const float y = p.x * m[1] + p.y * m[5] + p.z * m[9] + m[13];
    const float z = p.x * m[2] + p.y * m[6] + p.z * m[10] + m[14];
    const float w = p.x * m[3] + p.y * m[7] + p.z * m[11] + m[15];
    if (std::fabs(w) > 0.00001f && w != 1.0f) {
        return Vec3(x / w, y / w, z / w);
    }
    return Vec3(x, y, z);
}

Vec3 Mat4::TransformVector(const Vec3& v) const
{
    return Vec3(v.x * m[0] + v.y * m[4] + v.z * m[8],
                v.x * m[1] + v.y * m[5] + v.z * m[9],
                v.x * m[2] + v.y * m[6] + v.z * m[10]);
}

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

float MoveTowards(float current, float target, float maxDelta)
{
    if (current < target) {
        return std::min(current + maxDelta, target);
    }
    return std::max(current - maxDelta, target);
}

float WrapAngle(float radians)
{
    while (radians > PI) {
        radians -= 2.0f * PI;
    }
    while (radians < -PI) {
        radians += 2.0f * PI;
    }
    return radians;
}

float MoveTowardsAngle(float current, float target, float maxDelta)
{
    const float delta = WrapAngle(target - current);
    if (std::fabs(delta) <= maxDelta) {
        return target;
    }
    return WrapAngle(current + (delta > 0.0f ? maxDelta : -maxDelta));
}

float Length(const Vec2& v)
{
    return std::sqrt(v.x * v.x + v.y * v.y);
}

float Length(const Vec3& v)
{
    return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

float DistanceXZ(const Vec3& a, const Vec3& b)
{
    const float dx = a.x - b.x;
    const float dz = a.z - b.z;
    return std::sqrt(dx * dx + dz * dz);
}

float Distance(const Vec3& a, const Vec3& b)
{
    return Length(a - b);
}

Vec2 Normalize(const Vec2& v)
{
    const float len = Length(v);
    if (len <= 0.00001f) {
        return Vec2();
    }
    return Vec2(v.x / len, v.y / len);
}

Vec3 Normalize(const Vec3& v)
{
    const float len = Length(v);
    if (len <= 0.00001f) {
        return Vec3();
    }
    return Vec3(v.x / len, v.y / len, v.z / len);
}

float Dot(const Vec3& a, const Vec3& b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vec3 Cross(const Vec3& a, const Vec3& b)
{
    return Vec3(a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x);
}

Vec3 NormalizeXZ(const Vec3& v)
{
    const float len = std::sqrt(v.x * v.x + v.z * v.z);
    if (len <= 0.00001f) {
        return Vec3(0.0f, 0.0f, 1.0f);
    }
    return Vec3(v.x / len, 0.0f, v.z / len);
}

float YawFromDirection(const Vec3& direction)
{
    return std::atan2(direction.x, direction.z);
}

Vec3 DirectionFromYaw(float yaw)
{
    return Vec3(std::sin(yaw), 0.0f, std::cos(yaw));
}

bool PointInRect(const RectF& rect, const Vec2& point)
{
    return point.x >= rect.x && point.x <= rect.Right() &&
           point.y >= rect.y && point.y <= rect.Bottom();
}

bool CircleIntersectsBox(const Vec3& center, float radius, const AABB& rect)
{
    if (center.y + radius < rect.min.y || center.y - radius > rect.max.y) {
        return false;
    }
    const float closestX = Clamp(center.x, rect.min.x, rect.max.x);
    const float closestZ = Clamp(center.z, rect.min.z, rect.max.z);
    const float dx = center.x - closestX;
    const float dz = center.z - closestZ;
    return dx * dx + dz * dz <= radius * radius;
}

bool ResolveCircleBox(Vec3& center, float radius, const AABB& rect)
{
    if (center.y + radius < rect.min.y || center.y - radius > rect.max.y) {
        return false;
    }
    const float closestX = Clamp(center.x, rect.min.x, rect.max.x);
    const float closestZ = Clamp(center.z, rect.min.z, rect.max.z);
    float dx = center.x - closestX;
    float dz = center.z - closestZ;
    const float dist2 = dx * dx + dz * dz;
    if (dist2 > radius * radius) {
        return false;
    }
    if (dist2 > 0.00001f) {
        const float dist = std::sqrt(dist2);
        const float push = radius - dist;
        center.x += (dx / dist) * push;
        center.z += (dz / dist) * push;
        return true;
    }

    // 圆心在盒内：选择最短方向推出。
    const float left = center.x - rect.min.x;
    const float right = rect.max.x - center.x;
    const float back = center.z - rect.min.z;
    const float front = rect.max.z - center.z;
    const float minPen = std::min(std::min(left, right), std::min(back, front));
    if (minPen == left) {
        center.x = rect.min.x - radius;
    } else if (minPen == right) {
        center.x = rect.max.x + radius;
    } else if (minPen == back) {
        center.z = rect.min.z - radius;
    } else {
        center.z = rect.max.z + radius;
    }
    return true;
}

bool SegmentAABB(const Vec3& from, const Vec3& to, const AABB& box,
                 float& tMin)
{
    float t0 = 0.0f;
    float t1 = 1.0f;
    const float origin[3] = {from.x, from.y, from.z};
    const float delta[3] = {to.x - from.x, to.y - from.y, to.z - from.z};
    const float boxMin[3] = {box.min.x, box.min.y, box.min.z};
    const float boxMax[3] = {box.max.x, box.max.y, box.max.z};

    for (int axis = 0; axis < 3; ++axis) {
        if (std::fabs(delta[axis]) < 0.000001f) {
            if (origin[axis] < boxMin[axis] || origin[axis] > boxMax[axis]) {
                return false;
            }
            continue;
        }
        const float inv = 1.0f / delta[axis];
        float tNear = (boxMin[axis] - origin[axis]) * inv;
        float tFar = (boxMax[axis] - origin[axis]) * inv;
        if (tNear > tFar) {
            std::swap(tNear, tFar);
        }
        t0 = tNear > t0 ? tNear : t0;
        t1 = tFar < t1 ? tFar : t1;
        if (t0 > t1) {
            return false;
        }
    }
    tMin = t0;
    return true;
}

bool RayCircleXZ(const Vec3& origin, const Vec3& direction, const Vec3& center,
                 float radius, float& distance)
{
    const float dx = center.x - origin.x;
    const float dz = center.z - origin.z;
    const float dirLen = std::sqrt(direction.x * direction.x +
                                   direction.z * direction.z);
    if (dirLen < 0.00001f) {
        return false;
    }
    const float ndx = direction.x / dirLen;
    const float ndz = direction.z / dirLen;
    const float projection = dx * ndx + dz * ndz;
    if (projection < 0.0f) {
        return false;
    }
    const float perp2 = dx * dx + dz * dz - projection * projection;
    const float r2 = radius * radius;
    if (perp2 > r2) {
        return false;
    }
    const float offset = std::sqrt(std::max(0.0f, r2 - perp2));
    distance = projection - offset;
    if (distance < 0.0f) {
        distance = projection + offset;
    }
    return distance >= 0.0f;
}

bool RayPlaneY(const Vec3& origin, const Vec3& direction, float height,
               Vec3& hit)
{
    if (std::fabs(direction.y) < 0.00001f) {
        return false;
    }
    const float t = (height - origin.y) / direction.y;
    if (t < 0.0f) {
        return false;
    }
    hit = Vec3(origin.x + direction.x * t, height,
               origin.z + direction.z * t);
    return true;
}

Color ColorFromBytes(int r, int g, int b)
{
    return Rgba(r, g, b);
}

Color ColorMultiply(const Color& a, const Color& b)
{
    return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a);
}

Color ColorScale(const Color& a, float scalar)
{
    return Color(a.r * scalar, a.g * scalar, a.b * scalar, a.a);
}

Color ColorLerp(const Color& a, const Color& b, float t)
{
    return Color(Lerp(a.r, b.r, t), Lerp(a.g, b.g, t), Lerp(a.b, b.b, t),
                 Lerp(a.a, b.a, t));
}

Color ColorFromHex(unsigned int rgb)
{
    return Rgba(static_cast<int>((rgb >> 16) & 0xFF),
                static_cast<int>((rgb >> 8) & 0xFF),
                static_cast<int>(rgb & 0xFF));
}

} // namespace fc
