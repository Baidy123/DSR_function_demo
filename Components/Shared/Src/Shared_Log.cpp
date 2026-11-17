#include "Shared_Log.hpp"

#include <cstdarg>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

namespace {

std::ofstream g_logFile;
std::mutex g_logMutex;
bool g_initialized = false;

void WriteLog(const char* level, const char* format, va_list args)
{
    char buffer[2048] = {0};
    std::vsnprintf(buffer, sizeof(buffer), format, args);

    char line[2304] = {0};
    std::snprintf(line, sizeof(line), "[%s] %s\n", level, buffer);

    OutputDebugStringA(line);

    std::lock_guard<std::mutex> lock(g_logMutex);
    if (g_initialized && g_logFile.is_open()) {
        g_logFile << line;
        g_logFile.flush();
    }
}

} // namespace

void LogInitialize()
{
    std::lock_guard<std::mutex> lock(g_logMutex);
    std::error_code error;
    std::filesystem::create_directories("Temp", error);
    g_logFile.open("Temp/fc_log.txt", std::ios::out | std::ios::trunc);
    g_initialized = true;
    if (!g_logFile.is_open()) {
        g_initialized = false;
    }
}

void LogShutdown()
{
    std::lock_guard<std::mutex> lock(g_logMutex);
    if (g_logFile.is_open()) {
        g_logFile.close();
    }
    g_initialized = false;
}

void LogInfo(const char* format, ...)
{
    va_list args;
    va_start(args, format);
    WriteLog("INFO", format, args);
    va_end(args);
}

void LogWarn(const char* format, ...)
{
    va_list args;
    va_start(args, format);
    WriteLog("WARN", format, args);
    va_end(args);
}

void LogError(const char* format, ...)
{
    va_list args;
    va_start(args, format);
    WriteLog("ERROR", format, args);
    va_end(args);
}

} // namespace fc
