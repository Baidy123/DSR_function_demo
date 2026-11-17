#include "Platform_Resource.hpp"

#include "Shared_Log.hpp"

#include <fstream>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

bool LoadEmbeddedResource(const wchar_t* name, std::vector<uint8_t>& data)
{
    data.clear();
    if (name == nullptr) {
        return false;
    }

    HRSRC resource = FindResourceW(GetModuleHandleW(nullptr), name,
                                   MAKEINTRESOURCEW(10)); // RT_RCDATA
    if (resource == nullptr) {
        LogError("FindResourceW failed: %ls", name);
        return false;
    }
    const DWORD size = SizeofResource(GetModuleHandleW(nullptr), resource);
    HGLOBAL handle = LoadResource(GetModuleHandleW(nullptr), resource);
    if (handle == nullptr || size == 0) {
        LogError("LoadResource failed: %ls", name);
        return false;
    }
    const void* pointer = LockResource(handle);
    if (pointer == nullptr) {
        LogError("LockResource failed: %ls", name);
        return false;
    }
    data.assign(static_cast<const uint8_t*>(pointer),
                static_cast<const uint8_t*>(pointer) + size);
    return true;
}

bool LoadFileBytes(const std::string& path, std::vector<uint8_t>& data)
{
    data.clear();
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
        LogError("Cannot open file: %s", path.c_str());
        return false;
    }
    const std::streamsize size = file.tellg();
    if (size <= 0) {
        LogError("Empty file: %s", path.c_str());
        return false;
    }
    file.seekg(0, std::ios::beg);
    data.resize(static_cast<size_t>(size));
    if (!file.read(reinterpret_cast<char*>(data.data()), size)) {
        LogError("Cannot read file: %s", path.c_str());
        data.clear();
        return false;
    }
    return true;
}

std::string GetExecutableDirectory()
{
    wchar_t buffer[MAX_PATH] = {0};
    const DWORD length = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
    if (length == 0) {
        return std::string();
    }
    std::wstring path(buffer, buffer + length);
    const size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        path = path.substr(0, slash + 1);
    }
    const int utf8Length = WideCharToMultiByte(CP_UTF8, 0, path.c_str(),
                                               static_cast<int>(path.size()),
                                               nullptr, 0, nullptr, nullptr);
    std::string result(static_cast<size_t>(utf8Length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, path.c_str(), static_cast<int>(path.size()),
                        &result[0], utf8Length, nullptr, nullptr);
    return result;
}

std::string GetWorkingDirectory()
{
    wchar_t buffer[MAX_PATH] = {0};
    const DWORD length = GetCurrentDirectoryW(MAX_PATH, buffer);
    if (length == 0) {
        return std::string();
    }
    const int utf8Length = WideCharToMultiByte(CP_UTF8, 0, buffer,
                                               static_cast<int>(length),
                                               nullptr, 0, nullptr, nullptr);
    std::string result(static_cast<size_t>(utf8Length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, buffer, static_cast<int>(length),
                        &result[0], utf8Length, nullptr, nullptr);
    return result;
}

} // namespace fc
