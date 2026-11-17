#ifndef __SHARED_MATH_HPP__
#define __SHARED_MATH_HPP__

#include "Shared_Types.hpp"

namespace fc {

/**
 * @brief 将数值限制在闭区间内。
 * @param [IN] value 输入值。
 * @param [IN] lo 下界。
 * @param [IN] hi 上界。
 * @return 限制后的值；若 lo > hi，返回 lo。
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
 * @param [IN] t 插值系数（0–1）。
 * @return 插值结果。
 */
float Lerp(float a, float b, float t);

/**
 * @brief 计算向量长度。
 * @param [IN] v 输入向量。
 * @return 长度。
 */
float Length(const Vec2& v);

/**
 * @brief 计算两点距离。
 * @param [IN] a 点 A。
 * @param [IN] b 点 B。
 * @return 距离。
 */
float Distance(const Vec2& a, const Vec2& b);

/**
 * @brief 归一化向量；零向量返回零向量。
 * @param [IN] v 输入向量。
 * @return 单位向量或零向量。
 */
Vec2 Normalize(const Vec2& v);

/**
 * @brief 计算两个方向之间的夹角（弧度）。
 * @param [IN] from 起始方向。
 * @param [IN] to 目标方向。
 * @return 夹角，范围 0–π。
 */
float AngleBetween(const Vec2& from, const Vec2& to);

/**
 * @brief 将角度转换为四方向索引：0=S，1=N，2=E，3=W。
 * @param [IN] radians 以屏幕坐标系（y 向下）表示的角度。
 * @return 方向索引。
 */
int DirectionFromAngle(float radians);

/**
 * @brief 判断点是否位于矩形内。
 * @param [IN] rect 矩形。
 * @param [IN] point 点。
 * @return 在内部返回 true。
 */
bool PointInRect(const RectF& rect, const Vec2& point);

/**
 * @brief 判断两个矩形是否相交。
 * @param [IN] a 矩形 A。
 * @param [IN] b 矩形 B。
 * @return 相交返回 true。
 */
bool RectIntersects(const RectF& a, const RectF& b);

/**
 * @brief 判断圆与矩形是否相交。
 * @param [IN] center 圆心。
 * @param [IN] radius 半径。
 * @param [IN] rect 矩形。
 * @return 相交返回 true。
 */
bool CircleIntersectsRect(const Vec2& center, float radius, const RectF& rect);

/**
 * @brief 将圆从矩形中推出，用于简单碰撞解算。
 * @param [IN/OUT] center 圆心，会被修改。
 * @param [IN] radius 半径。
 * @param [IN] rect 矩形。
 * @return 发生推出返回 true。
 */
bool ResolveCircleRect(Vec2& center, float radius, const RectF& rect);

/**
 * @brief 平滑靠近目标值。
 * @param [IN] current 当前值。
 * @param [IN] target 目标值。
 * @param [IN] maxDelta 单帧最大变化量。
 * @return 新值。
 */
float MoveTowards(float current, float target, float maxDelta);

/**
 * @brief 计算两个整数坐标之间的曼哈顿距离。
 * @param [IN] ax 点 A 的 x。
 * @param [IN] ay 点 A 的 y。
 * @param [IN] bx 点 B 的 x。
 * @param [IN] by 点 B 的 y。
 * @return 距离。
 */
int ManhattanDistance(int ax, int ay, int bx, int by);

} // namespace fc

#endif // __SHARED_MATH_HPP__
