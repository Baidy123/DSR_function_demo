#include "Shared_String.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <sstream>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace fc {

std::wstring Utf8ToWide(const std::string& utf8)
{
    if (utf8.empty()) {
        return std::wstring();
    }
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                           utf8.c_str(),
                                           static_cast<int>(utf8.size()),
                                           nullptr, 0);
    if (length <= 0) {
        return std::wstring();
    }
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.c_str(),
                        static_cast<int>(utf8.size()), &result[0], length);
    return result;
}

std::string WideToUtf8(const std::wstring& wide)
{
    if (wide.empty()) {
        return std::string();
    }
    const int length = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                           static_cast<int>(wide.size()),
                                           nullptr, 0, nullptr, nullptr);
    if (length <= 0) {
        return std::string();
    }
    std::string result(static_cast<size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                        &result[0], length, nullptr, nullptr);
    return result;
}

std::string ToString(int value)
{
    char buffer[32] = {0};
    std::snprintf(buffer, sizeof(buffer), "%d", value);
    return std::string(buffer);
}

std::string ToString(float value, int decimals)
{
    char buffer[64] = {0};
    if (decimals < 0) {
        decimals = 0;
    }
    if (decimals > 6) {
        decimals = 6;
    }
    std::snprintf(buffer, sizeof(buffer), "%.*f", decimals,
                  static_cast<double>(value));
    return std::string(buffer);
}

std::string Join(const std::string* parts, int count, const char* separator)
{
    if (parts == nullptr || count <= 0) {
        return std::string();
    }
    std::string result;
    for (int i = 0; i < count; ++i) {
        if (i > 0) {
            result += separator != nullptr ? separator : "";
        }
        result += parts[i];
    }
    return result;
}

std::string TruncateUtf8(const std::string& text, int maxBytes)
{
    if (maxBytes <= 0) {
        return std::string();
    }
    if (static_cast<int>(text.size()) <= maxBytes) {
        return text;
    }
    int cut = maxBytes;
    while (cut > 0 &&
           (static_cast<unsigned char>(text[static_cast<size_t>(cut)]) & 0xC0) == 0x80) {
        --cut;
    }
    return text.substr(0, static_cast<size_t>(cut));
}

} // namespace fc
