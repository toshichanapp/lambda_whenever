# frozen_string_literal: true

# =============================================================================
# Comprehensive schedule definition for testing all DSL features
# Covers every supported syntax of lambda_whenever
#
# Usage:
#   bundle exec lambda_whenever --dryrun -f config/schedule_all_features.rb
# =============================================================================

# ---------------------------------------------------------------------------
# 1. set options (all types)
# ---------------------------------------------------------------------------
set :timezone, "Asia/Tokyo"
set :environment, "staging"
set :bundle_command, "bundle exec"
set :chronic_options, hours24: true
set :verbose, false

# ---------------------------------------------------------------------------
# 2. Task types (rake / runner / command / script)
# ---------------------------------------------------------------------------

# 2-1. rake (basic)
every 1.day, at: "3:00" do
  rake "db:cleanup"
end

# 2-2. rake (with arguments)
every 1.day, at: "4:00" do
  rake "import:data[production]"
end

# 2-3. rake (multiple arguments)
every 1.day, at: "4:30" do
  rake "report:generate[2024,monthly,csv]"
end

# 2-4. rake (deeply nested namespace)
every 1.day, at: "5:00" do
  rake "admin:users:cleanup:inactive"
end

# 2-5. runner (basic)
every 1.day, at: "6:00" do
  runner "User.send_daily_digest"
end

# 2-6. runner (with method arguments)
every 1.day, at: "6:30" do
  runner "Analytics.aggregate('daily', Date.today)"
end

# 2-7. command (basic)
every 1.day, at: "7:00" do
  command "echo 'hello world'"
end

# 2-8. command (curl)
every 1.day, at: "7:30" do
  command "curl -X POST https://healthcheck.example.com/ping"
end

# 2-9. script (basic)
every 1.day, at: "8:00" do
  script "cleanup.rb"
end

# 2-10. script (different extension)
every 1.day, at: "8:30" do
  script "backup.sh"
end

# ---------------------------------------------------------------------------
# 3. Multiple commands in a single every block
# ---------------------------------------------------------------------------
every 1.day, at: "2:00" do
  rake "db:vacuum"
  runner "CacheWarmer.run"
  command "echo 'maintenance done'"
  script "post_maintenance.rb"
end

# ---------------------------------------------------------------------------
# 4. WheneverNumeric frequency expressions
# ---------------------------------------------------------------------------

# 4-1. Minutes
every 1.minute do
  command "echo 'every 1 minute'"
end

every 5.minutes do
  rake "queue:process"
end

every 10.minutes do
  rake "monitoring:check"
end

every 15.minutes do
  rake "cache:refresh"
end

every 30.minutes do
  rake "sync:incremental"
end

# 4-2. Hours
every 1.hour do
  rake "health:check"
end

every 2.hours do
  rake "feed:fetch"
end

every 3.hours do
  rake "stats:aggregate"
end

every 6.hours do
  rake "reports:queue"
end

every 12.hours do
  rake "digest:build"
end

# 4-3. Days
every 1.day do
  rake "daily:default_midnight"
end

every 2.days do
  rake "cleanup:every_other_day"
end

every 3.days do
  rake "archive:every_three_days"
end

# 4-4. Weeks
every 1.week do
  rake "weekly:default"
end

# 4-5. Months
every 1.month do
  rake "monthly:default"
end

every 2.months do
  rake "billing:bimonthly"
end

every 3.months do
  rake "audit:quarterly"
end

every 6.months do
  rake "review:semiannual"
end

# 4-6. Years
every 1.year do
  rake "archive:yearly"
end

# ---------------------------------------------------------------------------
# 5. Day-of-week symbols
# ---------------------------------------------------------------------------
every :sunday do
  rake "weekly:sunday_batch"
end

every :monday do
  rake "weekly:monday_start"
end

every :tuesday do
  rake "weekly:tuesday_task"
end

every :wednesday do
  rake "weekly:wednesday_task"
end

every :thursday do
  rake "weekly:thursday_task"
end

every :friday do
  rake "weekly:friday_report"
end

every :saturday do
  rake "weekly:saturday_cleanup"
end

# 5-8. Weekdays and weekends
every :weekday do
  rake "daily:weekday_only"
end

every :weekend do
  rake "daily:weekend_only"
end

# ---------------------------------------------------------------------------
# 6. Period symbols
# ---------------------------------------------------------------------------
every :day do
  rake "daily:symbol_form"
end

every :month do
  rake "monthly:symbol_form"
end

every :year do
  rake "yearly:symbol_form"
end

# ---------------------------------------------------------------------------
# 7. `at` option variations
# ---------------------------------------------------------------------------

# 7-1. Single time
every 1.day, at: "9:00" do
  rake "morning:single_time"
end

# 7-2. Multiple times (same minute -> grouped into one schedule)
every 1.day, at: ["9:00", "18:00"] do
  rake "twice:same_minute"
end

# 7-3. Multiple times (different minutes -> separate schedules)
every 1.day, at: ["9:00", "18:30"] do
  rake "twice:different_minute"
end

# 7-4. Three or more times
every 1.day, at: ["6:00", "12:00", "18:00"] do
  rake "thrice:daily"
end

# 7-5. Many times (mixed minutes)
every 1.day, at: ["08:00", "10:30", "13:00", "15:30", "18:00", "21:00"] do
  rake "frequent:mixed_minutes"
end

# 7-6. Day-of-week + at
every :friday, at: "17:00" do
  rake "weekly:friday_evening"
end

# 7-7. Week + at
every 1.week, at: "10:00" do
  rake "weekly:with_at"
end

# 7-8. Month + at
every 1.month, at: "9:00" do
  rake "monthly:with_at"
end

# ---------------------------------------------------------------------------
# 8. Raw cron expressions (5-field)
# ---------------------------------------------------------------------------

# 8-1. Daily at midnight
every "0 0 * * *" do
  rake "cron:daily_midnight"
end

# 8-2. Every hour
every "0 * * * *" do
  rake "cron:every_hour"
end

# 8-3. Every 5 minutes (*/N notation)
every "*/5 * * * *" do
  rake "cron:every_five_min"
end

# 8-4. Specific day-of-week (Friday at 10:00)
every "0 10 * * 5" do
  rake "cron:friday_10am"
end

# 8-5. First day of month
every "0 9 1 * *" do
  rake "cron:first_of_month"
end

# 8-6. Multiple days-of-week
every "0 9 * * 1,3,5" do
  rake "cron:mon_wed_fri"
end

# 8-7. Day-of-week range
every "30 18 * * 1-5" do
  rake "cron:weekdays_evening"
end

# ---------------------------------------------------------------------------
# 9. Raw cron expressions (6-field / EventBridge extended)
# ---------------------------------------------------------------------------

# 9-1. Year specification
every "0 0 1 1 ? 2025" do
  rake "cron6:new_year_2025"
end

# 9-2. L syntax (last day of month)
every "0 23 L * ? *" do
  rake "cron6:last_day_of_month"
end

# --- Unsupported syntax (for reference) ---
# 6-field with ? in day-of-month and named day-of-week is not supported:
#   every "0 12 ? * MON *" do ... end
# W syntax (nearest weekday) is not supported:
#   every "0 9 15W * ? *" do ... end

# ---------------------------------------------------------------------------
# 10. Verbose setting verification
# ---------------------------------------------------------------------------

# verbose=false (set above) -> rake runs with --silent flag
every 1.day, at: "23:00" do
  rake "verbose_test:silent_mode"
end
