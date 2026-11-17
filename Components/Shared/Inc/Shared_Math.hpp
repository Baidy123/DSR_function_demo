#ifndef __SHARED_MATH_HPP__
#define __SHARED_MATH_HPP__

#include "Shared_Types.hpp"

namespace fc {

/** @brief 圆周率。 */
constexpr float PI = 3.14159265358979323846f;

/**
 * @brief 将数值限制在闭区间内。
 * @param [IN] value 输入值。
 * @param [IN] lo 下界。
 * @param [IN] hi 上界。
 * @return 限制后的值。
 */
float Clamp(float value, float lo, float hi);

/**
 * @brief 将整数限制在闭区间内。
 * @param [IN] value 输入值。
 * @param [IN] lo 下界。
 * @param [IN] hi 上界。
 * @return 限制后的值。
 */
int ClampInt(int value, int lo, int hi);

/**
 * @brief 线性插值。
 * @param [IN] a 起点。
 * @param [IN] b 终点。
 * @param [IN] t 插值系数。
 * @return 插值结果。
 */
float Lerp(float a, float b, float t);

/**
 * @brief 平滑靠近目标值。
 * @param [IN] current 当前值。
 * @param [IN] target 目标值。
 * @param [IN] maxDelta 单帧最大变化量。
 * @return 新值。
 */
float MoveTowards(float current, float target, float maxDelta);

/**
 * @brief 将角度归一化到 [-π, π]。
 * @param [IN] radians 角度。
 * @return 归一化角度。
 */
float WrapAngle(float radians);

/**
 * @brief 按最短路径插值角度。
 * @param [IN] current 当前角度。
 * @param [IN] target 目标角度。
 * @param [IN] maxDelta 单帧最大变化量。
 * @return 新角度。
 */
float MoveTowardsAngle(float current, float target, float maxDelta);

/**
 * @brief 二维向量长度。
 * @param [IN] v 输入向量。
 * @return 长度。
 */
float Length(const Vec2& v);

/**
 * @brief 三维向量长度。
 * @param [IN] v 输入向量。
 * @return 长度。
 */
float Length(const Vec3& v);

/**
 * @brief 三维平面距离（仅 XZ）。
 * @param [IN] a 点 A。
 * @param [IN] b 点 B。
 * @return 距离。
 */
float DistanceXZ(const Vec3& a, const Vec3& b);

/**
 * @brief 三维距离。
 * @param [IN] a 点 A。
 * @param [IN] b 点 B。
 * @return 距离。
 */
float Distance(const Vec3& a, const Vec3& b);

/**
 * @brief 归一化二维向量。
 * @param [IN] v 输入向量。
 * @return 单位向量或零向量。
 */
Vec2 Normalize(const Vec2& v);

/**
 * @brief 归一化三维向量。
 * @param [IN] v 输入向量。
 * @return 单位向量或零向量。
 */
Vec3 Normalize(const Vec3& v);

/**
 * @brief 三维点积。
 * @param [IN] a 向量 A。
 * @param [IN] b 向量 B。
 * @return 点积。
 */
float Dot(const Vec3& a, const Vec3& b);

/**
 * @brief 三维叉积。
 * @param [IN] a 向量 A。
 * @param [IN] b 向量 B。
 * @return 叉积。
 */
Vec3 Cross(const Vec3& a, const Vec3& b);

/**
 * @brief 将向量限制在 XZ 平面并归一化。
 * @param [IN] v 输入向量。
 * @return XZ 单位向量；零向量返回 (0,0,1)。
 */
Vec3 NormalizeXZ(const Vec3& v);

/**
 * @brief 由方向得到朝向角（绕 Y 轴，0 为 +Z）。
 * @param [IN] direction 方向（仅 XZ 有效）。
 * @return 弧度。
 */
float YawFromDirection(const Vec3& direction);

/**
 * @brief 由朝向角构造 XZ 方向。
 * @param [IN] yaw 弧度。
 * @return 方向。
 */
Vec3 DirectionFromYaw(float yaw);

/**
 * @brief 点是否在矩形内。
 * @param [IN] rect 矩形。
 * @param [IN] point 点。
 * @return 在内部返回 true。
 */
bool PointInRect(const RectF& rect, const Vec2& point);

/**
 * @brief 圆与 AABB 在 XZ 平面是否相交（并检查高度重叠）。
 * @param [IN] center 圆心。
 * @param [IN] radius 半径。
 * @param [IN] rect 包围盒。
 * @return 相交返回 true。
 */
bool CircleIntersectsBox(const Vec3& center, float radius, const AABB& rect);

/**
 * @brief 将圆从 AABB 中推出（仅 XZ）。
 * @param [IN/OUT] center 圆心，会被修改。
 * @param [IN] radius 半径。
 * @param [IN] rect 包围盒。
 * @return 发生推出返回 true。
 */
bool ResolveCircleBox(Vec3& center, float radius, const AABB& rect);

/**
 * @brief 线段与 AABB 的相交测试。
 * @param [IN] from 起点。
 * @param [IN] to 终点。
 * @param [IN] box 包围盒。
 * @param [OUT] tMin 最近交点参数（0–1）。
 * @return 相交返回 true。
 */
bool SegmentAABB(const Vec3& from, const Vec3& to, const AABB& box,
                 float& tMin);

/**
 * @brief 二维射线与圆的相交测试（XZ）。
 * @param [IN] origin 起点。
 * @param [IN] direction 单位方向（XZ）。
 * @param [IN] center 圆心（XZ）。
 * @param [IN] radius 半径。
 * @param [OUT] distance 命中距离。
 * @return 命中返回 true。
 */
bool RayCircleXZ(const Vec3& origin, const Vec3& direction, const Vec3& center,
                 float radius, float& distance);

/**
 * @brief 计算地面平面（y = height）上的交点。
 * @param [IN] origin 射线起点。
 * @param [IN] direction 射线方向。
 * @param [IN] height 地面高度。
 * @param [OUT] hit 交点。
 * @return 相交返回 true。
 */
bool RayPlaneY(const Vec3& origin, const Vec3& direction, float height,
               Vec3& hit);

/**
 * @brief 由 0–255 颜色分量转 Color。
 * @param [IN] r 红。
 * @param [IN] g 绿。
 * @param [IN] b 蓝。
 * @return 颜色。
 */
Color ColorFromBytes(int r, int g, int b);

/**
 * @brief 颜色相乘。
 * @param [IN] a 颜色 A。
 * @param [IN] b 颜色 B。
 * @return 分量乘积。
 */
Color ColorMultiply(const Color& a, const Color& b);

/**
 * @brief 颜色按标量缩放。
 * @param [IN] a 颜色。
 * @param [IN] scalar 缩放。
 * @return 结果颜色。
 */
Color ColorScale(const Color& a, float scalar);

/**
 * @brief 颜色线性插值。
 * @param [IN] a 起点。
 * @param [IN] b 终点。
 * @param [IN] t 系数。
 * @return 插值颜色。
 */
Color ColorLerp(const Color& a, const Color& b, float t);

/**
 * @brief 由十六进制 0xRRGGBB 构造颜色。
 * @param [IN] rgb 十六进制值。
 * @return 颜色。
 */
Color ColorFromHex(unsigned int rgb);

} // namespace fc

#endif // __SHARED_MATH_HPP__
