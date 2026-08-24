// SPDX-License-Identifier: Apache-2.0
//
// test_cron.cpp — five-field cron parsing and next-fire computation.
//
// Every case is a pure function of an expression and a starting instant, so
// nothing here needs a platform adapter or a stored workflow. The last few
// tests cover the validator's use of the parser, which is where a bad cron on
// a Schedule Trigger becomes a document issue.

#include <cstdio>
#include <optional>
#include <string>

#if defined(RAC_HAVE_PROTOBUF)
#include "agent_workflow.pb.h"

#include "../src/agent/cron.h"
#include "../src/agent/workflow_validator.h"
#include "rac/agent/rac_agent_workflow.h"

namespace {

int g_failed = 0;
int g_passed = 0;

#define CHECK(cond)                                                               \
    do {                                                                          \
        if (!(cond)) {                                                            \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                           \
            return;                                                               \
        }                                                                         \
    } while (0)

#define TEST(name)                                      \
    static void test_##name();                          \
    static void run_test_##name() {                     \
        std::fprintf(stderr, "[RUN ] %s\n", #name);     \
        int before_failed = g_failed;                   \
        test_##name();                                  \
        if (g_failed == before_failed) {                \
            std::fprintf(stderr, "[  OK] %s\n", #name); \
            g_passed++;                                 \
        }                                               \
    }                                                   \
    static void test_##name()

using rac::agent::cron_time_from_unix;
using rac::agent::cron_time_to_unix;
using rac::agent::CronExpression;
using rac::agent::CronTime;
using rac::agent::validate_document;
using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowNode;
using runanywhere::v1::WorkflowValidationResult;

CronTime at(int year, int month, int day, int hour, int minute) {
    return CronTime{year, month, day, hour, minute};
}

void describe(const char* label, const CronTime& time) {
    std::fprintf(stderr, "       %s %04d-%02d-%02d %02d:%02d\n", label, time.year, time.month,
                 time.day, time.hour, time.minute);
}

bool next_is(const std::string& expression, const CronTime& from, const CronTime& expected) {
    std::string error;
    const std::optional<CronExpression> parsed = CronExpression::parse(expression, &error);
    if (!parsed.has_value()) {
        std::fprintf(stderr, "       '%s' did not parse: %s\n", expression.c_str(), error.c_str());
        return false;
    }
    const std::optional<CronTime> next = parsed->next_after(from);
    if (!next.has_value()) {
        std::fprintf(stderr, "       '%s' has no next firing\n", expression.c_str());
        return false;
    }
    if (!(*next == expected)) {
        std::fprintf(stderr, "       '%s'\n", expression.c_str());
        describe("got   ", *next);
        describe("wanted", expected);
        return false;
    }
    return true;
}

bool has_no_next(const std::string& expression, const CronTime& from) {
    const std::optional<CronExpression> parsed = CronExpression::parse(expression, nullptr);
    return parsed.has_value() && !parsed->next_after(from).has_value();
}

/// A malformed expression must be refused with a reason, not accepted quietly.
bool rejects(const std::string& expression) {
    std::string error;
    const std::optional<CronExpression> parsed = CronExpression::parse(expression, &error);
    if (parsed.has_value()) {
        std::fprintf(stderr, "       '%s' parsed but should not have\n", expression.c_str());
        return false;
    }
    return !error.empty();
}

WorkflowValidationResult validate_cron_trigger(const std::string& expression,
                                               runanywhere::v1::ScheduleKind kind) {
    WorkflowDocument document;
    WorkflowNode* node = document.add_nodes();
    node->set_id("trigger");
    node->set_name("Every so often");
    node->mutable_schedule_trigger()->set_kind(kind);
    node->mutable_schedule_trigger()->set_cron(expression);

    WorkflowValidationResult result;
    validate_document(document, &result);
    return result;
}

// MARK: - Field syntax

TEST(star_fields_fire_the_very_next_minute) {
    CHECK(next_is("* * * * *", at(2024, 3, 10, 12, 34), at(2024, 3, 10, 12, 35)));
    CHECK(next_is("* * * * *", at(2024, 3, 10, 23, 59), at(2024, 3, 11, 0, 0)));
}

TEST(a_fixed_minute_and_hour_fires_once_a_day) {
    CHECK(next_is("30 4 * * *", at(2024, 3, 10, 4, 30), at(2024, 3, 11, 4, 30)));
    CHECK(next_is("30 4 * * *", at(2024, 3, 10, 3, 0), at(2024, 3, 10, 4, 30)));
    CHECK(next_is("30 4 * * *", at(2024, 3, 10, 4, 29), at(2024, 3, 10, 4, 30)));
}

TEST(a_list_fires_at_each_of_its_values) {
    CHECK(next_is("0 0,12 * * *", at(2024, 3, 10, 0, 0), at(2024, 3, 10, 12, 0)));
    CHECK(next_is("0 0,12 * * *", at(2024, 3, 10, 12, 0), at(2024, 3, 11, 0, 0)));
    CHECK(next_is("0,15,30,45 * * * *", at(2024, 3, 10, 12, 16), at(2024, 3, 10, 12, 30)));
}

TEST(a_range_covers_both_ends) {
    CHECK(next_is("0 9-17 * * *", at(2024, 3, 10, 8, 0), at(2024, 3, 10, 9, 0)));
    CHECK(next_is("0 9-17 * * *", at(2024, 3, 10, 17, 0), at(2024, 3, 11, 9, 0)));
}

TEST(a_step_over_a_star_divides_the_field) {
    CHECK(next_is("*/15 * * * *", at(2024, 3, 10, 12, 0), at(2024, 3, 10, 12, 15)));
    CHECK(next_is("*/15 * * * *", at(2024, 3, 10, 12, 46), at(2024, 3, 10, 13, 0)));
}

TEST(a_step_over_a_range_stops_at_the_range_end) {
    CHECK(next_is("0-30/5 * * * *", at(2024, 3, 10, 12, 26), at(2024, 3, 10, 12, 30)));
    CHECK(next_is("0-30/5 * * * *", at(2024, 3, 10, 12, 30), at(2024, 3, 10, 13, 0)));
}

TEST(a_step_from_a_single_value_runs_to_the_field_end) {
    CHECK(next_is("5/15 * * * *", at(2024, 3, 10, 12, 0), at(2024, 3, 10, 12, 5)));
    CHECK(next_is("5/15 * * * *", at(2024, 3, 10, 12, 5), at(2024, 3, 10, 12, 20)));
    CHECK(next_is("5/15 * * * *", at(2024, 3, 10, 12, 50), at(2024, 3, 10, 13, 5)));
}

TEST(fields_combine_rather_than_override) {
    // Weekday mornings only: minute, hour and weekday all have to agree.
    CHECK(next_is("0 9 * * 1-5", at(2024, 3, 8, 10, 0), at(2024, 3, 11, 9, 0)));
    CHECK(next_is("0 9 * * 1-5", at(2024, 3, 11, 9, 0), at(2024, 3, 12, 9, 0)));
}

// MARK: - Day of week

TEST(sunday_is_both_zero_and_seven) {
    // 2024-03-10 is a Sunday.
    CHECK(next_is("0 0 * * 0", at(2024, 3, 5, 0, 0), at(2024, 3, 10, 0, 0)));
    CHECK(next_is("0 0 * * 7", at(2024, 3, 5, 0, 0), at(2024, 3, 10, 0, 0)));
    CHECK(next_is("0 0 * * 0,7", at(2024, 3, 5, 0, 0), at(2024, 3, 10, 0, 0)));
}

TEST(a_weekday_range_wraps_to_the_following_week) {
    CHECK(next_is("0 0 * * 1", at(2024, 3, 4, 0, 0), at(2024, 3, 11, 0, 0)));
}

// MARK: - Day-of-month versus day-of-week

TEST(restricting_both_day_fields_matches_either_one) {
    // March 2024: the 13th is a Wednesday, Fridays are the 1st, 8th, 15th, 22nd
    // and 29th. Both fields restricted, so every one of those days fires.
    CHECK(next_is("0 0 13 * 5", at(2024, 3, 9, 0, 0), at(2024, 3, 13, 0, 0)));
    CHECK(next_is("0 0 13 * 5", at(2024, 3, 13, 0, 0), at(2024, 3, 15, 0, 0)));
    CHECK(next_is("0 0 13 * 5", at(2024, 3, 2, 0, 0), at(2024, 3, 8, 0, 0)));
}

TEST(restricting_only_the_day_of_month_ignores_the_weekday) {
    CHECK(next_is("0 0 13 * *", at(2024, 3, 9, 0, 0), at(2024, 3, 13, 0, 0)));
    CHECK(next_is("0 0 13 * *", at(2024, 3, 13, 0, 0), at(2024, 4, 13, 0, 0)));
}

TEST(restricting_only_the_weekday_ignores_the_day_of_month) {
    CHECK(next_is("0 0 * * 5", at(2024, 3, 9, 0, 0), at(2024, 3, 15, 0, 0)));
    CHECK(next_is("0 0 * * 5", at(2024, 3, 15, 0, 0), at(2024, 3, 22, 0, 0)));
}

TEST(a_starred_day_field_with_a_step_still_counts_as_unrestricted) {
    // `*/2` begins with a star, so the day-of-week alone decides which days
    // fire and the either-or rule does not apply.
    CHECK(next_is("0 0 */2 * 5", at(2024, 3, 2, 0, 0), at(2024, 3, 8, 0, 0)));
}

// MARK: - Aliases

TEST(aliases_expand_to_their_standard_expressions) {
    CHECK(next_is("@hourly", at(2024, 3, 10, 12, 34), at(2024, 3, 10, 13, 0)));
    CHECK(next_is("@daily", at(2024, 3, 10, 12, 34), at(2024, 3, 11, 0, 0)));
    CHECK(next_is("@midnight", at(2024, 3, 10, 12, 34), at(2024, 3, 11, 0, 0)));
    CHECK(next_is("@weekly", at(2024, 3, 10, 12, 34), at(2024, 3, 17, 0, 0)));
    CHECK(next_is("@monthly", at(2024, 3, 10, 12, 34), at(2024, 4, 1, 0, 0)));
    CHECK(next_is("@yearly", at(2024, 3, 10, 12, 34), at(2025, 1, 1, 0, 0)));
    CHECK(next_is("@annually", at(2024, 3, 10, 12, 34), at(2025, 1, 1, 0, 0)));
}

TEST(an_alias_is_case_insensitive_and_survives_surrounding_space) {
    CHECK(next_is("  @Daily  ", at(2024, 3, 10, 12, 34), at(2024, 3, 11, 0, 0)));
}

TEST(reboot_is_not_an_alias_this_parser_knows) {
    CHECK(rejects("@reboot"));
    CHECK(rejects("@fortnightly"));
}

// MARK: - Calendar boundaries

TEST(a_firing_crosses_a_month_boundary) {
    CHECK(next_is("0 0 1 * *", at(2024, 1, 31, 12, 0), at(2024, 2, 1, 0, 0)));
    CHECK(next_is("0 0 * * *", at(2024, 4, 30, 12, 0), at(2024, 5, 1, 0, 0)));
}

TEST(a_firing_crosses_a_year_boundary) {
    CHECK(next_is("59 23 31 12 *", at(2024, 12, 31, 23, 59), at(2025, 12, 31, 23, 59)));
    CHECK(next_is("0 0 1 1 *", at(2024, 6, 1, 0, 0), at(2025, 1, 1, 0, 0)));
}

TEST(a_day_of_month_that_some_months_lack_skips_those_months) {
    CHECK(next_is("0 0 31 * *", at(2024, 4, 1, 0, 0), at(2024, 5, 31, 0, 0)));
    CHECK(next_is("0 0 30 * *", at(2024, 1, 31, 0, 0), at(2024, 3, 30, 0, 0)));
}

TEST(february_29_only_fires_in_a_leap_year) {
    CHECK(next_is("0 0 29 2 *", at(2023, 3, 1, 0, 0), at(2024, 2, 29, 0, 0)));
    CHECK(next_is("0 0 29 2 *", at(2024, 3, 1, 0, 0), at(2028, 2, 29, 0, 0)));
    // February-only, so a non-leap year runs out on the 28th and waits a year.
    CHECK(next_is("0 0 * 2 *", at(2023, 2, 28, 0, 0), at(2024, 2, 1, 0, 0)));
    CHECK(next_is("0 0 * 2 *", at(2024, 2, 28, 0, 0), at(2024, 2, 29, 0, 0)));
}

TEST(a_century_year_that_is_not_a_leap_year_has_no_february_29) {
    // 2100 is divisible by 4 but not by 400, so the leap day skips from 2096 to
    // 2104 and the gap is wider than the four-year search horizon.
    CHECK(has_no_next("0 0 29 2 *", at(2096, 3, 1, 0, 0)));
    CHECK(next_is("0 0 29 2 *", at(2100, 3, 1, 0, 0), at(2104, 2, 29, 0, 0)));
}

// MARK: - Expressions that never fire

TEST(february_30_never_fires) {
    CHECK(has_no_next("0 0 30 2 *", at(2024, 1, 1, 0, 0)));

    const std::optional<CronExpression> parsed = CronExpression::parse("0 0 30 2 *", nullptr);
    CHECK(parsed.has_value());
    CHECK(!parsed->ever_fires());
}

TEST(an_expression_that_can_fire_reports_that_it_can) {
    const std::optional<CronExpression> parsed = CronExpression::parse("0 0 29 2 *", nullptr);
    CHECK(parsed.has_value());
    CHECK(parsed->ever_fires());
}

// MARK: - Malformed input

TEST(a_wrong_field_count_is_rejected) {
    CHECK(rejects(""));
    CHECK(rejects("   "));
    CHECK(rejects("* * * *"));
    CHECK(rejects("* * * * * *"));
}

TEST(a_value_outside_its_field_is_rejected) {
    CHECK(rejects("60 * * * *"));
    CHECK(rejects("* 24 * * *"));
    CHECK(rejects("0 0 0 * *"));
    CHECK(rejects("0 0 32 * *"));
    CHECK(rejects("0 0 * 0 *"));
    CHECK(rejects("0 0 * 13 *"));
    CHECK(rejects("0 0 * * 8"));
}

TEST(a_malformed_field_is_rejected) {
    CHECK(rejects("a * * * *"));
    CHECK(rejects("* * * * mon"));
    CHECK(rejects("0 0 * jan *"));
    CHECK(rejects("5-1 * * * *"));
    CHECK(rejects("*/0 * * * *"));
    CHECK(rejects("*/ * * * *"));
    CHECK(rejects("*/1/2 * * * *"));
    CHECK(rejects("1-2-3 * * * *"));
    CHECK(rejects("0,, * * * *"));
    CHECK(rejects("-5 * * * *"));
}

// MARK: - matches

TEST(matches_agrees_with_the_fields) {
    const std::optional<CronExpression> parsed = CronExpression::parse("30 9 * * 1-5", nullptr);
    CHECK(parsed.has_value());
    CHECK(parsed->matches(at(2024, 3, 11, 9, 30)));   // Monday
    CHECK(!parsed->matches(at(2024, 3, 10, 9, 30)));  // Sunday
    CHECK(!parsed->matches(at(2024, 3, 11, 9, 31)));
    CHECK(!parsed->matches(at(2024, 2, 30, 9, 30)));  // not a real date
}

// MARK: - Unix conversion

TEST(unix_conversion_round_trips) {
    CHECK(cron_time_to_unix(at(1970, 1, 1, 0, 0), 0) == 0);
    CHECK(cron_time_to_unix(at(2024, 3, 10, 12, 34), 0) == 1710074040);
    CHECK(cron_time_from_unix(1710074040, 0) == at(2024, 3, 10, 12, 34));
}

TEST(unix_conversion_honours_the_offset) {
    // 09:30 in a zone 5h30m east of UTC is 04:00 UTC.
    const int32_t offset = 5 * 3600 + 30 * 60;
    const int64_t unix_seconds = cron_time_to_unix(at(2024, 3, 10, 9, 30), offset);
    const CronTime utc = cron_time_from_unix(unix_seconds, 0);
    CHECK(utc == at(2024, 3, 10, 4, 0));

    const CronTime local = cron_time_from_unix(unix_seconds, offset);
    CHECK(local == at(2024, 3, 10, 9, 30));
}

TEST(unix_conversion_handles_instants_before_the_epoch) {
    const CronTime before = cron_time_from_unix(-1, 0);
    CHECK(before == at(1969, 12, 31, 23, 59));
    CHECK(cron_time_to_unix(before, 0) == -60);
}

// MARK: - Validator wiring

TEST(a_valid_cron_trigger_passes_validation) {
    const WorkflowValidationResult result =
        validate_cron_trigger("0 9 * * 1-5", runanywhere::v1::SCHEDULE_KIND_CRON);
    CHECK(result.valid());
}

TEST(an_unparseable_cron_trigger_fails_validation) {
    const WorkflowValidationResult result =
        validate_cron_trigger("0 9 * *", runanywhere::v1::SCHEDULE_KIND_CRON);
    CHECK(!result.valid());
    CHECK(result.issues_size() == 1);
    CHECK(result.issues(0).node_id() == "trigger");
    CHECK(result.issues(0).message().find("is invalid") != std::string::npos);
}

TEST(a_cron_trigger_that_never_fires_fails_validation) {
    const WorkflowValidationResult result =
        validate_cron_trigger("0 0 30 2 *", runanywhere::v1::SCHEDULE_KIND_CRON);
    CHECK(!result.valid());
    CHECK(result.issues_size() == 1);
    CHECK(result.issues(0).message().find("never fires") != std::string::npos);
}

TEST(an_empty_cron_expression_fails_validation) {
    const WorkflowValidationResult result =
        validate_cron_trigger("", runanywhere::v1::SCHEDULE_KIND_CRON);
    CHECK(!result.valid());
    CHECK(result.issues_size() == 1);
    CHECK(result.issues(0).message().find("no expression") != std::string::npos);
}

TEST(a_non_cron_schedule_is_not_checked_for_a_cron_expression) {
    const WorkflowValidationResult result =
        validate_cron_trigger("nonsense", runanywhere::v1::SCHEDULE_KIND_DAILY);
    CHECK(result.valid());
}

// MARK: - C ABI

TEST(the_abi_returns_the_next_firing_in_unix_seconds) {
    int64_t next = 0;
    // 2024-03-10 12:34 UTC, asked for in a zone 5h30m east of UTC, where the
    // local time is 18:04 and the next 09:00 is the following morning.
    const int32_t offset = 5 * 3600 + 30 * 60;
    CHECK(rac_agent_schedule_next_fire("0 9 * * *", 1710074040, offset, &next) == RAC_SUCCESS);
    CHECK(cron_time_from_unix(next, offset) == at(2024, 3, 11, 9, 0));
}

TEST(the_abi_reports_a_malformed_expression_separately_from_one_that_never_fires) {
    int64_t next = 1;
    CHECK(rac_agent_schedule_next_fire("nonsense", 0, 0, &next) == RAC_ERROR_INVALID_CONFIGURATION);
    CHECK(next == 0);

    CHECK(rac_agent_schedule_next_fire("0 0 30 2 *", 0, 0, &next) == RAC_ERROR_NOT_FOUND);
}

TEST(the_abi_rejects_null_arguments) {
    int64_t next = 0;
    CHECK(rac_agent_schedule_next_fire(nullptr, 0, 0, &next) == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(rac_agent_schedule_next_fire("* * * * *", 0, 0, nullptr) == RAC_ERROR_INVALID_ARGUMENT);
}

}  // namespace

int main() {
    run_test_star_fields_fire_the_very_next_minute();
    run_test_a_fixed_minute_and_hour_fires_once_a_day();
    run_test_a_list_fires_at_each_of_its_values();
    run_test_a_range_covers_both_ends();
    run_test_a_step_over_a_star_divides_the_field();
    run_test_a_step_over_a_range_stops_at_the_range_end();
    run_test_a_step_from_a_single_value_runs_to_the_field_end();
    run_test_fields_combine_rather_than_override();
    run_test_sunday_is_both_zero_and_seven();
    run_test_a_weekday_range_wraps_to_the_following_week();
    run_test_restricting_both_day_fields_matches_either_one();
    run_test_restricting_only_the_day_of_month_ignores_the_weekday();
    run_test_restricting_only_the_weekday_ignores_the_day_of_month();
    run_test_a_starred_day_field_with_a_step_still_counts_as_unrestricted();
    run_test_aliases_expand_to_their_standard_expressions();
    run_test_an_alias_is_case_insensitive_and_survives_surrounding_space();
    run_test_reboot_is_not_an_alias_this_parser_knows();
    run_test_a_firing_crosses_a_month_boundary();
    run_test_a_firing_crosses_a_year_boundary();
    run_test_a_day_of_month_that_some_months_lack_skips_those_months();
    run_test_february_29_only_fires_in_a_leap_year();
    run_test_a_century_year_that_is_not_a_leap_year_has_no_february_29();
    run_test_february_30_never_fires();
    run_test_an_expression_that_can_fire_reports_that_it_can();
    run_test_a_wrong_field_count_is_rejected();
    run_test_a_value_outside_its_field_is_rejected();
    run_test_a_malformed_field_is_rejected();
    run_test_matches_agrees_with_the_fields();
    run_test_unix_conversion_round_trips();
    run_test_unix_conversion_honours_the_offset();
    run_test_unix_conversion_handles_instants_before_the_epoch();
    run_test_a_valid_cron_trigger_passes_validation();
    run_test_an_unparseable_cron_trigger_fails_validation();
    run_test_a_cron_trigger_that_never_fires_fails_validation();
    run_test_an_empty_cron_expression_fails_validation();
    run_test_a_non_cron_schedule_is_not_checked_for_a_cron_expression();
    run_test_the_abi_returns_the_next_firing_in_unix_seconds();
    run_test_the_abi_reports_a_malformed_expression_separately_from_one_that_never_fires();
    run_test_the_abi_rejects_null_arguments();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
