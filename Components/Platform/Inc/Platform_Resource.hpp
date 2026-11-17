#ifndef __PLATFORM_RESOURCE_HPP__
#define __PLATFORM_RESOURCE_HPP__

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

/**
 * @brief 从当前模块的 RCDATA 资源读取二进制数据。
 * @param [IN] name 资源名称（宽字符）。
 * @param [OUT] data 输出字节数组；失败时清空。
 * @return 成功返回 true。
 */
bool LoadEmbeddedResource(const wchar_t* name, std::vector<uint8_t>& data);

/**
 * @brief 从文件读取全部字节。
 * @param [IN] path 文件路径（UTF-8，可为相对路径）。
 * @param [OUT] data 输出字节数组；失败时清空。
 * @return 成功返回 true。
 */
bool LoadFileBytes(const std::string& path, std::vector<uint8_t>& data);

/**
 * @brief 获取可执行文件所在目录（以反斜杠结尾）。
 * @return UTF-8 目录字符串。
 */
std::string GetExecutableDirectory();

/**
 * @brief 获取当前工作目录。
 * @return UTF-8 目录字符串。
 */
std::string GetWorkingDirectory();

} // namespace fc

#endif // __PLATFORM_RESOURCE_HPP__
