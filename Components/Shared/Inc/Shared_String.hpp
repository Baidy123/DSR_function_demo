#ifndef __SHARED_STRING_HPP__
#define __SHARED_STRING_HPP__

#include <string>

namespace fc {

/**
 * @brief 将 UTF-8 字符串转换为 UTF-16（Windows 宽字符）。
 * @param [IN] utf8 输入字符串。
 * @return 转换后的宽字符串；失败返回空串。
 */
std::wstring Utf8ToWide(const std::string& utf8);

/**
 * @brief 将 UTF-16 字符串转换为 UTF-8。
 * @param [IN] wide 输入宽字符串。
 * @return 转换后的 UTF-8 字符串；失败返回空串。
 */
std::string WideToUtf8(const std::wstring& wide);

/**
 * @brief 将整数转换为十进制字符串。
 * @param [IN] value 输入整数。
 * @return 十进制字符串。
 */
std::string ToString(int value);

/**
 * @brief 将浮点数转换为保留指定小数位的字符串。
 * @param [IN] value 输入浮点数。
 * @param [IN] decimals 小数位。
 * @return 格式化字符串。
 */
std::string ToString(float value, int decimals);

/**
 * @brief 用指定分隔符连接字符串列表。
 * @param [IN] parts 字符串列表。
 * @param [IN] separator 分隔符。
 * @return 连接后的字符串。
 */
std::string Join(const std::string* parts, int count, const char* separator);

/**
 * @brief 截断字符串到指定字节长度，避免破坏 UTF-8 多字节序列。
 * @param [IN] text 输入字符串。
 * @param [IN] maxBytes 最大字节数。
 * @return 截断后的字符串。
 */
std::string TruncateUtf8(const std::string& text, int maxBytes);

} // namespace fc

#endif // __SHARED_STRING_HPP__
