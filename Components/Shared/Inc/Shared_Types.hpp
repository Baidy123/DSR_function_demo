#ifndef __SHARED_TYPES_HPP__
#define __SHARED_TYPES_HPP__

#include <cmath>
#include <cstdint>

namespace fc {

/** @brief 3D 内部渲染宽度（像素）；低清多面体风格的基础分辨率。 */
constexpr int INTERNAL_WIDTH = 720;

/** @brief 3D 内部渲染高度（像素）。 */
constexpr int INTERNAL_HEIGHT = 405;

/** @brief UI 逻辑坐标宽度；UI 层按屏幕像素密度高清渲染。 */
constexpr int UI_WIDTH = 480;

/** @brief UI 逻辑坐标高度。 */
constexpr int UI_HEIGHT = 270;

/** @brief 游戏默认窗口客户区宽度。 */
constexpr int WINDOW_WIDTH = 1440;

/** @brief 游戏默认窗口客户区高度。 */
constexpr int WINDOW_HEIGHT = 810;

/** @brief 世界单位换算：1 米 = 40 单位，角色约 1.75 米高。 */
constexpr float UNITS_PER_METER = 40.0f;

/**
 * @brief 二维向量，坐标系为 x 向右、y 向下。
 */
struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;

    Vec2() = default;
    Vec2(float vx, float vy) : x(vx), y(vy) {}

    Vec2 operator+(const Vec2& other) const { return Vec2(x + other.x, y + other.y); }
    Vec2 operator-(const Vec2& other) const { return Vec2(x - other.x, y - other.y); }
    Vec2 operator*(float scalar) const { return Vec2(x * scalar, y * scalar); }
    Vec2 operator/(float scalar) const { return Vec2(x / scalar, y / scalar); }

    Vec2& operator+=(const Vec2& other)
    {
        x += other.x;
        y += other.y;
        return *this;
    }

    Vec2& operator-=(const Vec2& other)
    {
        x -= other.x;
        y -= other.y;
        return *this;
    }

    Vec2& operator*=(float scalar)
    {
        x *= scalar;
        y *= scalar;
        return *this;
    }
};

/**
 * @brief 三维向量；世界坐标 y 向上。
 */
struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    Vec3() = default;
    Vec3(float vx, float vy, float vz) : x(vx), y(vy), z(vz) {}

    Vec3 operator+(const Vec3& other) const { return Vec3(x + other.x, y + other.y, z + other.z); }
    Vec3 operator-(const Vec3& other) const { return Vec3(x - other.x, y - other.y, z - other.z); }
    Vec3 operator-() const { return Vec3(-x, -y, -z); }
    Vec3 operator*(float scalar) const { return Vec3(x * scalar, y * scalar, z * scalar); }
    Vec3 operator/(float scalar) const { return Vec3(x / scalar, y / scalar, z / scalar); }

    Vec3& operator+=(const Vec3& other)
    {
        x += other.x;
        y += other.y;
        z += other.z;
        return *this;
    }

    Vec3& operator-=(const Vec3& other)
    {
        x -= other.x;
        y -= other.y;
        z -= other.z;
        return *this;
    }

    Vec3& operator*=(float scalar)
    {
        x *= scalar;
        y *= scalar;
        z *= scalar;
        return *this;
    }
};

/**
 * @brief 行主序 4x4 矩阵；与 HLSL `mul(rowVector, matrix)` 约定一致。
 */
struct Mat4 {
    float m[16] = {1.0f, 0.0f, 0.0f, 0.0f,
                   0.0f, 1.0f, 0.0f, 0.0f,
                   0.0f, 0.0f, 1.0f, 0.0f,
                   0.0f, 0.0f, 0.0f, 1.0f};

    /**
     * @brief 单位矩阵。
     * @return 单位矩阵。
     */
    static Mat4 Identity();

    /**
     * @brief 平移矩阵。
     * @param [IN] offset 平移量。
     * @return 矩阵。
     */
    static Mat4 Translation(const Vec3& offset);

    /**
     * @brief 缩放矩阵。
     * @param [IN] scale 缩放量。
     * @return 矩阵。
     */
    static Mat4 Scale(const Vec3& scale);

    /**
     * @brief 绕 Y 轴旋转。
     * @param [IN] radians 弧度。
     * @return 矩阵。
     */
    static Mat4 RotationY(float radians);

    /**
     * @brief 绕 X 轴旋转。
     * @param [IN] radians 弧度。
     * @return 矩阵。
     */
    static Mat4 RotationX(float radians);

    /**
     * @brief 绕 Z 轴旋转。
     * @param [IN] radians 弧度。
     * @return 矩阵。
     */
    static Mat4 RotationZ(float radians);

    /**
     * @brief 透视投影矩阵（右手系，深度 0–1）。
     * @param [IN] fovRadians 垂直视场角。
     * @param [IN] aspect 宽高比。
     * @param [IN] nearPlane 近平面。
     * @param [IN] farPlane 远平面。
     * @return 矩阵。
     */
    static Mat4 Perspective(float fovRadians, float aspect, float nearPlane,
                            float farPlane);

    /**
     * @brief 视图矩阵。
     * @param [IN] eye 相机位置。
     * @param [IN] target 目标点。
     * @param [IN] up 上方向。
     * @return 矩阵。
     */
    static Mat4 LookAt(const Vec3& eye, const Vec3& target, const Vec3& up);

    Mat4 operator*(const Mat4& other) const;

    /**
     * @brief 变换点（含平移）。
     * @param [IN] p 点。
     * @return 变换后的点。
     */
    Vec3 TransformPoint(const Vec3& p) const;

    /**
     * @brief 变换方向（忽略平移）。
     * @param [IN] v 方向。
     * @return 变换后的方向。
     */
    Vec3 TransformVector(const Vec3& v) const;
};

/**
 * @brief 直通 alpha 的 RGBA 颜色，分量为 0.0–1.0。
 */
struct Color {
    float r = 1.0f;
    float g = 1.0f;
    float b = 1.0f;
    float a = 1.0f;

    Color() = default;
    Color(float cr, float cg, float cb, float ca = 1.0f)
        : r(cr), g(cg), b(cb), a(ca)
    {
    }
};

/**
 * @brief 由 0–255 分量构造颜色。
 * @param [IN] r 红色分量。
 * @param [IN] g 绿色分量。
 * @param [IN] b 蓝色分量。
 * @param [IN] a 透明度分量。
 * @return 归一化后的颜色。
 */
inline Color Rgba(int r, int g, int b, int a = 255)
{
    return Color(static_cast<float>(r) / 255.0f,
                 static_cast<float>(g) / 255.0f,
                 static_cast<float>(b) / 255.0f,
                 static_cast<float>(a) / 255.0f);
}

/**
 * @brief 浮点矩形，x/y 为左上角。
 */
struct RectF {
    float x = 0.0f;
    float y = 0.0f;
    float w = 0.0f;
    float h = 0.0f;

    RectF() = default;
    RectF(float rx, float ry, float rw, float rh) : x(rx), y(ry), w(rw), h(rh) {}

    float Right() const { return x + w; }
    float Bottom() const { return y + h; }
    float CenterX() const { return x + w * 0.5f; }
    float CenterY() const { return y + h * 0.5f; }
};

/**
 * @brief 轴对齐包围盒（世界中）。
 */
struct AABB {
    Vec3 min;
    Vec3 max;

    AABB() = default;
    AABB(const Vec3& mn, const Vec3& mx) : min(mn), max(mx) {}
};

/**
 * @brief 由中心与半径构造 AABB。
 * @param [IN] center 中心。
 * @param [IN] half 半长。
 * @return 包围盒。
 */
inline AABB MakeAABB(const Vec3& center, const Vec3& half)
{
    return AABB(Vec3(center.x - half.x, center.y - half.y, center.z - half.z),
                Vec3(center.x + half.x, center.y + half.y, center.z + half.z));
}

/**
 * @brief 摄像机姿态。
 */
struct CameraPose {
    Vec3 eye;
    Vec3 target;
    float fovDegrees = 55.0f;
    Vec3 up{0.0f, 1.0f, 0.0f};
};

} // namespace fc

#endif // __SHARED_TYPES_HPP__
