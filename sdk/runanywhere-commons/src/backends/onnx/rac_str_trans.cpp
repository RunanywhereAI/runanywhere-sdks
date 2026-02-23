/**
 * @file rac_str_trans.cpp
 * @brief RunAnywhere Commons - String Transformation Implementation
 *
 * String transformation utilities for Windows.
 */

#include "rac_str_trans.h"

#include <Windows.h>

namespace runanywhere {

// =============================================================================
// RAC STR TRANS IMPLEMENTATION
// =============================================================================

std::wstring RacStrTrans::ascii_to_unicode(const std::string& str) {
    if (str.empty()) {
        return std::wstring();
    }

    int len = MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, NULL, 0);
    wchar_t* buffer = new wchar_t[len];
    MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, buffer, len);
    std::wstring wstr(buffer);
    delete[] buffer;
    return wstr;
}

std::string RacStrTrans::unicode_to_ascii(const std::wstring& wstr) {
    if (wstr.empty()) {
        return std::string();
    }

    int len = WideCharToMultiByte(CP_ACP, 0, wstr.c_str(), -1, NULL, 0, NULL, NULL);
    char* buffer = new char[len];
    WideCharToMultiByte(CP_ACP, 0, wstr.c_str(), -1, buffer, len, NULL, NULL);
    std::string str(buffer);
    delete[] buffer;
    return str;
}

std::string RacStrTrans::ascii_to_utf8(const std::string& str) {
    if (str.empty()) {
        return std::string();
    }

    int len = MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, NULL, 0);
    wchar_t* buffer = new wchar_t[len];
    MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, buffer, len);
    len = WideCharToMultiByte(CP_UTF8, 0, buffer, -1, NULL, 0, NULL, NULL);
    char* utf8 = new char[len];
    WideCharToMultiByte(CP_UTF8, 0, buffer, -1, utf8, len, NULL, NULL);
    std::string utf8_str(utf8);
    delete[] buffer;
    delete[] utf8;
    return utf8_str;
}

std::string RacStrTrans::utf8_to_ascii(const std::string& utf8) {
    if (utf8.empty()) {
        return std::string();
    }

    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, NULL, 0);
    wchar_t* buffer = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, buffer, len);
    len = WideCharToMultiByte(CP_ACP, 0, buffer, -1, NULL, 0, NULL, NULL);
    char* str = new char[len];
    WideCharToMultiByte(CP_ACP, 0, buffer, -1, str, len, NULL, NULL);
    std::string ascii(str);
    delete[] buffer;
    delete[] str;
    return ascii;
}

std::string RacStrTrans::unicode_to_utf8(const std::wstring& wstr) {
    if (wstr.empty()) {
        return std::string();
    }

    int len = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, NULL, 0, NULL, NULL);
    char* utf8 = new char[len];
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, utf8, len, NULL, NULL);
    std::string utf8_str(utf8);
    delete[] utf8;
    return utf8_str;
}

std::wstring RacStrTrans::utf8_to_unicode(const std::string& utf8) {
    if (utf8.empty()) {
        return std::wstring();
    }

    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, NULL, 0);
    wchar_t* buffer = new wchar_t[len];
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, buffer, len);
    std::wstring wstr(buffer);
    delete[] buffer;
    return wstr;
}

}  // namespace runanywhere