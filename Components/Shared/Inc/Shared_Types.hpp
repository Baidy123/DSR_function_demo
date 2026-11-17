#ifndef __SHARED_TYPES_HPP__
#define __SHARED_TYPES_HPP__

#include <cstdint>

namespace fc {

/** @brief 内部渲染宽度（像素），所有 UI 与玩法坐标以此为基准。 */
constexpr int INTERNAL_WIDTH = 480;

/** @brief 内部渲染高度（像素）。 */
constexpr int INTERNAL_HEIGHT = 270;

/** @brief 单个瓷砖边长（像素）。 */
constexpr int TILE_SIZE = 16;

/** @brief 游戏默认窗口客户区宽度。 */
constexpr int WINDOW_WIDTH = 1440;

/** @brief 游戏默认窗口客户区高度。 */
constexpr int WINDOW_HEIGHT = 810;

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
 * @brief 带 UV 与尺寸的精灵引用，由渲染设备在加载资产包时建立。
 */
struct Sprite {
    const void* texture = nullptr;  ///< 实际类型为 Texture*，避免 Shared 依赖 D3D。
    int width = 0;
    int height = 0;
    float u0 = 0.0f;
    float v0 = 0.0f;
    float u1 = 1.0f;
    float v1 = 1.0f;
};

/**
 * @brief 摄像机状态。
 */
struct Camera {
    Vec2 position;
    int viewWidth = INTERNAL_WIDTH;
    int viewHeight = INTERNAL_HEIGHT;
    bool following = false;

    /**
     * @brief 将摄像机限制在地图范围内。
     * @param [IN] mapWidth 地图像素宽度。
     * @param [IN] mapHeight 地图像素高度。
     */
    void ClampToMap(int mapWidth, int mapHeight)
    {
        float maxX = static_cast<float>(mapWidth - viewWidth);
        float maxY = static_cast<float>(mapHeight - viewHeight);
        if (maxX < 0.0f) {
            maxX = 0.0f;
        }
        if (maxY < 0.0f) {
            maxY = 0.0f;
        }
        if (position.x < 0.0f) {
            position.x = 0.0f;
        }
        if (position.y < 0.0f) {
            position.y = 0.0f;
        }
        if (position.x > maxX) {
            position.x = maxX;
        }
        if (position.y > maxY) {
            position.y = maxY;
        }
    }
};

} // namespace fc

#endif // __SHARED_TYPES_HPP__
