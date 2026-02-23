/**
 * @file rac_str_trans.h
 * @brief RunAnywhere Commons - String Transformation
 *
 * String transformation utilities for Windows.
 * This class is used to convert strings between ASCII, UTF-8, and Unicode.
 * This class need to move to runanywhere-core in the future as a common utility class.
 */

#ifndef RUNANYWHERE_STR_TRANS_H
#define RUNANYWHERE_STR_TRANS_H

#include <string>

namespace runanywhere {

// =============================================================================
// RAC STR TRANS
// =============================================================================

class RacStrTrans {
    RacStrTrans() = delete;
    ~RacStrTrans() = delete;
    RacStrTrans(const RacStrTrans&) = delete;
    RacStrTrans& operator=(const RacStrTrans&) = delete;

   public:
    /**
     * @brief Convert ASCII string to Unicode string
     * @param str The ASCII string to convert
     * @return The Unicode string
     */
    static std::wstring ascii_to_unicode(const std::string& str);

    /**
     * @brief Convert Unicode string to ASCII string
     * @param wstr The Unicode string to convert
     * @return The ASCII string
     */
    static std::string unicode_to_ascii(const std::wstring& wstr);

    /**
     * @brief Convert ASCII string to UTF-8 string
     * @param str The ASCII string to convert
     * @return The UTF-8 string
     */
    static std::string ascii_to_utf8(const std::string& str);

    /**
     * @brief Convert UTF-8 string to ASCII string
     * @param utf8 The UTF-8 string to convert
     * @return The ASCII string
     */
    static std::string utf8_to_ascii(const std::string& utf8);

    /**
     * @brief Convert Unicode string to UTF-8 string
     * @param wstr The Unicode string to convert
     * @return The UTF-8 string
     */
    static std::string unicode_to_utf8(const std::wstring& wstr);

    /**
     * @brief Convert UTF-8 string to Unicode string
     * @param utf8 The UTF-8 string to convert
     * @return The Unicode string
     */
    static std::wstring utf8_to_unicode(const std::string& utf8);
};
}  // namespace runanywhere

#endif  // RUNANYWHERE_STR_TRANS_H