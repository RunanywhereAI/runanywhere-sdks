// SPDX-License-Identifier: Apache-2.0
//
// Five-field cron expressions for ScheduleTriggerConfig.
//
// Parsing and next-fire computation live here rather than in a host scheduler
// so every binding gets the same answer from the same expression. The host
// still owns the timer: this only says when the next firing is due.
//
// Cron describes wall-clock time, so the calendar arithmetic is done in local
// civil fields and the caller supplies the offset when it wants a Unix
// instant. No timezone database is consulted, which means a fire time inside a
// DST transition is computed against the offset the caller passed and not
// against the one in force at that instant.

#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace rac::agent {

/// Local wall-clock time, in the calendar fields cron is written against.
struct CronTime {
    int year = 1970;
    int month = 1;   // 1-12
    int day = 1;     // 1-31
    int hour = 0;    // 0-23
    int minute = 0;  // 0-59
};

bool operator==(const CronTime& lhs, const CronTime& rhs);

/// How far ahead next_after() will look before giving up. Four years so a
/// day-of-month that only exists in a leap year is still found.
inline constexpr int kCronSearchYears = 4;

/// A parsed `minute hour day-of-month month day-of-week` expression.
///
/// Each field accepts `*`, a number, a comma-separated list, a `a-b` range,
/// and a `/step` on any of those. Day-of-week takes 0 or 7 for Sunday. The
/// `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly` and
/// `@annually` aliases are accepted in place of the five fields.
///
/// Month and day names (`JAN`, `MON`), `@reboot`, and the non-standard seconds
/// and year fields are not accepted.
class CronExpression {
   public:
    /// Returns no value and fills @p out_error (when non-null) on a field count
    /// other than five, an unknown alias, or a value outside its field's range.
    static std::optional<CronExpression> parse(const std::string& text, std::string* out_error);

    bool matches(const CronTime& time) const;

    /// The first firing strictly after @p after, or no value when none falls
    /// within kCronSearchYears of it.
    std::optional<CronTime> next_after(const CronTime& after) const;

    /// False for an expression whose fields can never line up on a real
    /// calendar date, such as `0 0 30 2 *`.
    bool ever_fires() const;

   private:
    uint64_t minutes_ = 0;  // bits 0-59
    uint32_t hours_ = 0;    // bits 0-23
    uint32_t days_ = 0;     // bits 1-31
    uint32_t months_ = 0;   // bits 1-12
    uint8_t weekdays_ = 0;  // bits 0-6, Sunday is 0
    bool day_restricted_ = false;
    bool weekday_restricted_ = false;

    bool day_matches(const CronTime& time) const;
};

/// Convert between a Unix instant and the local civil time @p utc_offset_seconds
/// east of UTC. Exposed because a caller that wants Unix seconds out of
/// next_after() needs the same conversion on the way in.
CronTime cron_time_from_unix(int64_t unix_seconds, int32_t utc_offset_seconds);
int64_t cron_time_to_unix(const CronTime& time, int32_t utc_offset_seconds);

}  // namespace rac::agent
