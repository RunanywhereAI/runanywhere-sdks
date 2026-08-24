// SPDX-License-Identifier: Apache-2.0

#include "cron.h"

#include <array>
#include <cctype>
#include <cstddef>
#include <vector>

namespace rac::agent {
namespace {

struct FieldRange {
    int min;
    int max;
    const char* name;
};

constexpr FieldRange kMinuteField{0, 59, "minute"};
constexpr FieldRange kHourField{0, 23, "hour"};
constexpr FieldRange kDayField{1, 31, "day-of-month"};
constexpr FieldRange kMonthField{1, 12, "month"};
constexpr FieldRange kWeekdayField{0, 7, "day-of-week"};

bool is_leap(int year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

int days_in_month(int year, int month) {
    static constexpr std::array<int, 13> kLengths{0,  31, 28, 31, 30, 31, 30,
                                                  31, 31, 30, 31, 30, 31};
    if (month == 2 && is_leap(year))
        return 29;
    return kLengths[static_cast<size_t>(month)];
}

/// Howard Hinnant's days_from_civil: days since 1970-01-01, valid for any
/// proleptic Gregorian date, with no dependence on the platform's time
/// functions.
int64_t days_from_civil(int year, int month, int day) {
    const int64_t y = year - (month <= 2 ? 1 : 0);
    const int64_t era = (y >= 0 ? y : y - 399) / 400;
    const int64_t year_of_era = y - era * 400;
    const int64_t day_of_year = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    const int64_t day_of_era =
        year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    return era * 146097 + day_of_era - 719468;
}

void civil_from_days(int64_t days, int* out_year, int* out_month, int* out_day) {
    days += 719468;
    const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const int64_t day_of_era = days - era * 146097;
    const int64_t year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    const int64_t y = year_of_era + era * 400;
    const int64_t day_of_year =
        day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    const int64_t mp = (5 * day_of_year + 2) / 153;
    const int64_t d = day_of_year - (153 * mp + 2) / 5 + 1;
    const int64_t m = mp + (mp < 10 ? 3 : -9);
    *out_year = static_cast<int>(y + (m <= 2 ? 1 : 0));
    *out_month = static_cast<int>(m);
    *out_day = static_cast<int>(d);
}

/// 0 is Sunday, matching the day-of-week field.
int weekday_of(const CronTime& time) {
    const int64_t days = days_from_civil(time.year, time.month, time.day);
    return static_cast<int>(((days % 7) + 11) % 7);
}

int64_t floor_div(int64_t value, int64_t divisor) {
    const int64_t quotient = value / divisor;
    return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient;
}

void roll_day(CronTime* time) {
    time->day += 1;
    if (time->day <= days_in_month(time->year, time->month))
        return;
    time->day = 1;
    time->month += 1;
    if (time->month <= 12)
        return;
    time->month = 1;
    time->year += 1;
}

void start_of_next_day(CronTime* time) {
    roll_day(time);
    time->hour = 0;
    time->minute = 0;
}

void start_of_next_month(CronTime* time) {
    time->day = 1;
    time->hour = 0;
    time->minute = 0;
    time->month += 1;
    if (time->month > 12) {
        time->month = 1;
        time->year += 1;
    }
}

void step_minute(CronTime* time) {
    time->minute += 1;
    if (time->minute < 60)
        return;
    time->minute = 0;
    time->hour += 1;
    if (time->hour < 24)
        return;
    time->hour = 0;
    roll_day(time);
}

/// Lowest set bit at or above @p from, or -1 when the field has none left.
int next_bit(uint64_t bits, int from, int max) {
    for (int candidate = from; candidate <= max; ++candidate) {
        if ((bits >> candidate) & 1u)
            return candidate;
    }
    return -1;
}

std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> parts;
    size_t start = 0;
    while (true) {
        const size_t found = text.find(separator, start);
        if (found == std::string::npos) {
            parts.push_back(text.substr(start));
            return parts;
        }
        parts.push_back(text.substr(start, found - start));
        start = found + 1;
    }
}

std::vector<std::string> split_whitespace(const std::string& text) {
    std::vector<std::string> parts;
    size_t cursor = 0;
    while (cursor < text.size()) {
        while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor])))
            ++cursor;
        const size_t start = cursor;
        while (cursor < text.size() && !std::isspace(static_cast<unsigned char>(text[cursor])))
            ++cursor;
        if (cursor > start)
            parts.push_back(text.substr(start, cursor - start));
    }
    return parts;
}

bool parse_number(const std::string& text, int* out_value) {
    if (text.empty() || text.size() > 3)
        return false;
    int value = 0;
    for (const char character : text) {
        if (character < '0' || character > '9')
            return false;
        value = value * 10 + (character - '0');
    }
    *out_value = value;
    return true;
}

void fail(std::string* out_error, const FieldRange& field, const std::string& item,
          const char* reason) {
    if (out_error != nullptr)
        *out_error = std::string(field.name) + " field '" + item + "' " + reason;
}

bool parse_field(const std::string& text, const FieldRange& field, uint64_t* out_bits,
                 bool* out_starts_with_star, std::string* out_error) {
    if (text.empty()) {
        fail(out_error, field, text, "is empty");
        return false;
    }
    *out_starts_with_star = text[0] == '*';
    *out_bits = 0;

    for (const std::string& item : split(text, ',')) {
        const std::vector<std::string> stepped = split(item, '/');
        if (stepped.size() > 2) {
            fail(out_error, field, item, "has more than one step");
            return false;
        }

        int step = 1;
        if (stepped.size() == 2 && (!parse_number(stepped[1], &step) || step < 1)) {
            fail(out_error, field, item, "has an invalid step");
            return false;
        }

        const std::string& base = stepped[0];
        int low = 0;
        int high = 0;
        if (base == "*") {
            low = field.min;
            high = field.max;
        } else if (base.find('-') != std::string::npos) {
            const std::vector<std::string> bounds = split(base, '-');
            if (bounds.size() != 2 || !parse_number(bounds[0], &low) ||
                !parse_number(bounds[1], &high)) {
                fail(out_error, field, item, "is not a range");
                return false;
            }
            if (low > high) {
                fail(out_error, field, item, "ends before it starts");
                return false;
            }
        } else if (parse_number(base, &low)) {
            // `5/15` means "from 5 to the end of the field, every 15", the same
            // reading every cron with a step operator gives it.
            high = stepped.size() == 2 ? field.max : low;
        } else {
            fail(out_error, field, item, "is not a number");
            return false;
        }

        if (low < field.min || high > field.max) {
            fail(out_error, field, item, "is out of range");
            return false;
        }

        for (int value = low; value <= high; value += step) {
            // Sunday is both 0 and 7 in the day-of-week field.
            const int bit = (field.max == 7 && value == 7) ? 0 : value;
            *out_bits |= uint64_t{1} << bit;
        }
    }
    return true;
}

std::string expand_alias(const std::string& text) {
    std::string name;
    for (const char character : text)
        name.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(character))));

    if (name == "@hourly")
        return "0 * * * *";
    if (name == "@daily" || name == "@midnight")
        return "0 0 * * *";
    if (name == "@weekly")
        return "0 0 * * 0";
    if (name == "@monthly")
        return "0 0 1 * *";
    if (name == "@yearly" || name == "@annually")
        return "0 0 1 1 *";
    return {};
}

}  // namespace

bool operator==(const CronTime& lhs, const CronTime& rhs) {
    return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day &&
           lhs.hour == rhs.hour && lhs.minute == rhs.minute;
}

std::optional<CronExpression> CronExpression::parse(const std::string& text,
                                                    std::string* out_error) {
    std::vector<std::string> fields = split_whitespace(text);
    if (fields.size() == 1 && fields[0][0] == '@') {
        const std::string expanded = expand_alias(fields[0]);
        if (expanded.empty()) {
            if (out_error != nullptr)
                *out_error = "unknown alias '" + fields[0] + "'";
            return std::nullopt;
        }
        fields = split_whitespace(expanded);
    }

    if (fields.size() != 5) {
        if (out_error != nullptr)
            *out_error = "expected 5 fields, got " + std::to_string(fields.size());
        return std::nullopt;
    }

    CronExpression expression;
    uint64_t bits = 0;
    bool starts_with_star = false;

    if (!parse_field(fields[0], kMinuteField, &bits, &starts_with_star, out_error))
        return std::nullopt;
    expression.minutes_ = bits;

    if (!parse_field(fields[1], kHourField, &bits, &starts_with_star, out_error))
        return std::nullopt;
    expression.hours_ = static_cast<uint32_t>(bits);

    if (!parse_field(fields[2], kDayField, &bits, &starts_with_star, out_error))
        return std::nullopt;
    expression.days_ = static_cast<uint32_t>(bits);
    expression.day_restricted_ = !starts_with_star;

    if (!parse_field(fields[3], kMonthField, &bits, &starts_with_star, out_error))
        return std::nullopt;
    expression.months_ = static_cast<uint32_t>(bits);

    if (!parse_field(fields[4], kWeekdayField, &bits, &starts_with_star, out_error))
        return std::nullopt;
    expression.weekdays_ = static_cast<uint8_t>(bits);
    expression.weekday_restricted_ = !starts_with_star;

    return expression;
}

bool CronExpression::day_matches(const CronTime& time) const {
    const bool by_day = (days_ >> time.day) & 1u;
    const bool by_weekday = (weekdays_ >> weekday_of(time)) & 1u;

    // The cron quirk: with both fields restricted the day matches when EITHER
    // does, so `0 0 13 * 5` is the 13th and every Friday, not only Friday the
    // 13th. With one field restricted, only that field decides.
    if (day_restricted_ && weekday_restricted_)
        return by_day || by_weekday;
    if (day_restricted_)
        return by_day;
    if (weekday_restricted_)
        return by_weekday;
    return true;
}

bool CronExpression::matches(const CronTime& time) const {
    if (time.month < 1 || time.month > 12 || time.day < 1 ||
        time.day > days_in_month(time.year, time.month))
        return false;
    if (time.hour < 0 || time.hour > 23 || time.minute < 0 || time.minute > 59)
        return false;
    if (((months_ >> time.month) & 1u) == 0)
        return false;
    if (((hours_ >> time.hour) & 1u) == 0)
        return false;
    if (((minutes_ >> time.minute) & 1u) == 0)
        return false;
    return day_matches(time);
}

std::optional<CronTime> CronExpression::next_after(const CronTime& after) const {
    const int last_year = after.year + kCronSearchYears;

    CronTime candidate = after;
    step_minute(&candidate);

    while (candidate.year <= last_year) {
        if (((months_ >> candidate.month) & 1u) == 0) {
            start_of_next_month(&candidate);
            continue;
        }
        if (candidate.day > days_in_month(candidate.year, candidate.month) ||
            !day_matches(candidate)) {
            start_of_next_day(&candidate);
            continue;
        }

        const int hour = next_bit(hours_, candidate.hour, 23);
        if (hour < 0) {
            start_of_next_day(&candidate);
            continue;
        }
        if (hour != candidate.hour) {
            candidate.hour = hour;
            candidate.minute = 0;
        }

        const int minute = next_bit(minutes_, candidate.minute, 59);
        if (minute < 0) {
            candidate.minute = 59;
            step_minute(&candidate);
            continue;
        }
        candidate.minute = minute;
        return candidate;
    }
    return std::nullopt;
}

bool CronExpression::ever_fires() const {
    return next_after(CronTime{}).has_value();
}

CronTime cron_time_from_unix(int64_t unix_seconds, int32_t utc_offset_seconds) {
    const int64_t local = unix_seconds + utc_offset_seconds;
    const int64_t days = floor_div(local, 86400);
    const int64_t seconds_of_day = local - days * 86400;

    CronTime time;
    civil_from_days(days, &time.year, &time.month, &time.day);
    time.hour = static_cast<int>(seconds_of_day / 3600);
    time.minute = static_cast<int>((seconds_of_day % 3600) / 60);
    return time;
}

int64_t cron_time_to_unix(const CronTime& time, int32_t utc_offset_seconds) {
    const int64_t days = days_from_civil(time.year, time.month, time.day);
    return days * 86400 + time.hour * 3600 + time.minute * 60 - utc_offset_seconds;
}

}  // namespace rac::agent
