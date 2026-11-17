#ifndef __UNITTESTS_CONFIG_HPP__
#define __UNITTESTS_CONFIG_HPP__

namespace fc {
namespace unittests {

/** @brief 单元测试退出码：全部通过。 */
constexpr int RESULT_OK = 0;

/** @brief 单元测试退出码：存在失败用例。 */
constexpr int RESULT_FAILED = 1;

/** @brief 浮点比较容差。 */
constexpr float EPSILON = 0.001f;

} // namespace unittests
} // namespace fc

#endif // __UNITTESTS_CONFIG_HPP__
