#ifndef __SHARED_LOG_HPP__
#define __SHARED_LOG_HPP__

namespace fc {

/**
 * @brief 初始化日志系统；创建 Temp 目录并清空本进程日志。
 */
void LogInitialize();

/**
 * @brief 关闭日志文件。
 */
void LogShutdown();

/**
 * @brief 输出信息日志。
 * @param [IN] format printf 风格格式串。
 */
void LogInfo(const char* format, ...);

/**
 * @brief 输出警告日志。
 * @param [IN] format printf 风格格式串。
 */
void LogWarn(const char* format, ...);

/**
 * @brief 输出错误日志。
 * @param [IN] format printf 风格格式串。
 */
void LogError(const char* format, ...);

} // namespace fc

#endif // __SHARED_LOG_HPP__
