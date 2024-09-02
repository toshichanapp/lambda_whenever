# frozen_string_literal: true

require_relative "whenever_numeric"

module LambdaWhenever
  class Schedule
    attr_reader :tasks, :chronic_options, :bundle_command, :environment, :timezone

    class UnsupportedFrequencyException < StandardError; end

    using WheneverNumeric

    def initialize(file, verbose, variables)
      @environment = "production"
      @verbose = verbose
      @tasks = []
      @chronic_options = {}
      @bundle_command = "bundle exec"

      variables.each { |var| set(var[:key], var[:value]) }
      instance_eval(File.read(file), file)
      @timezone ||= "UTC"
    end

    def set(key, value)
      instance_variable_set("@#{key}", value) unless key == "tasks"
    end

    def every(frequency, options = {}, &block)
      expressions = schedule_expressions(frequency, options)
      tasks = expressions.map do |expression|
        Task.new(@environment, @verbose, @bundle_command, expression).tap do |task|
          task.instance_eval(&block)
        end
      end
      @tasks.concat tasks
    rescue UnsupportedFrequencyException => e
      Logger.instance.warn(e.message)
    end

    def schedule_expressions(frequency, options)
      tmp_expression = expression_by_frequency(frequency, options)
      return ["cron(#{tmp_expression.join(" ")})"] unless options[:at].is_a?(Array)

      times = options[:at]
      grouped_times = times.group_by { |time| time[/\d\d?:(\d\d?)/, 1] }

      grouped_times.map do |minute, hour_list|
        hours = hour_list.map { |time| time[/^\d{1,2}/] }.join(",")
        _, __, *rest = tmp_expression
        exp = [minute, hours, *rest]
        "cron(#{exp.join(" ")})"
      end
    end

    # index minutes: 0, hours: 1, day_of_month: 2, month: 3, day_of_week: 4, year: 5
    def expression_by_frequency(frequency, options)
      opts = { now: Time.new(2017, 1, 1, 0, 0, 0) }.merge(@chronic_options)
      time = Chronic.parse(options[:at], opts) || Time.new(2017, 1, 1, 0, 0, 0)

      case frequency
      when 1.minute
        ["*", "*", "*", "*", "?", "*"]
      when :hour, 1.hour
        [time.min.to_s, "*", "*", "*", "?", "*"]
      when :day, 1.day
        [time.min.to_s, time.hour.to_s, "*", "*", "?", "*"]
      when :month, 1.month
        [time.min.to_s, time.hour.to_s, time.day, "*", "?", "*"]
      when :year, 1.year
        [time.min.to_s, time.hour.to_s, time.day, time.month, "?", "*"]
      when :sunday
        [time.min.to_s, time.hour.to_s, "?", "*", "SUN", "*"]
      when :monday
        [time.min.to_s, time.hour.to_s, "?", "*", "MON", "*"]
      when :tuesday
        [time.min.to_s, time.hour.to_s, "?", "*", "TUE", "*"]
      when :wednesday
        [time.min.to_s, time.hour.to_s, "?", "*", "WED", "*"]
      when :thursday
        [time.min.to_s, time.hour.to_s, "?", "*", "THU", "*"]
      when :friday
        [time.min.to_s, time.hour.to_s, "?", "*", "FRI", "*"]
      when :saturday
        [time.min.to_s, time.hour.to_s, "?", "*", "SAT", "*"]
      when :weekend
        [time.min.to_s, time.hour.to_s, "?", "*", "SUN,SAT", "*"]
      when :weekday
        [time.min.to_s, time.hour.to_s, "?", "*", "MON-FRI", "*"]
      when 1.second...1.minute
        raise UnsupportedFrequencyException, "Time must be in minutes or higher. Ignore this task."
      when 1.minute...1.hour
        step = (frequency / 60).round
        min = []
        ((60 % step).zero? ? 0 : step).step(59, step) { |i| min << i }
        [min.join(","), "*", "*", "*", "?", "*"]
      when 1.hour...1.day
        step = (frequency / 60 / 60).round
        hour = []
        ((24 % step).zero? ? 0 : step).step(23, step) { |i| hour << i }
        [time.min.to_s, hour.join(","), "*", "*", "?", "*"]
      when 1.day...1.month
        step = (frequency / 24 / 60 / 60).round
        day = []
        (step <= 16 ? 1 : step).step(30, step) { |i| day << i }
        [time.min.to_s, time.hour.to_s, day.join(","), "*", "?", "*"]
      when 1.month...12.months
        step = (frequency / 30 / 24 / 60 / 60).round
        month = []
        (step <= 6 ? 1 : step).step(12, step) { |i| month << i }
        [time.min.to_s, time.hour.to_s, time.day, month.join(","), "?", "*"]
      when 12.months...Float::INFINITY
        raise UnsupportedFrequencyException, "Time must be in months or lower. Ignore this task."
      when %r{^((\*?[\d/,-]*)\s*){5}$}
        min, hour, day, mon, week, year = frequency.split(" ")
        # You can't specify the Day-of-month and Day-of-week fields in the same Cron expression.
        # If you specify a value in one of the fields, you must use a ? (question mark) in the other.
        week.gsub!("*", "?") if day != "?"
        day.gsub!("*", "?") if week != "?"
        # cron syntax:          sunday -> 0
        # scheduled expression: sunday -> 1
        week.gsub!(/(\d)/) { |match| Integer(match) + 1 }
        year ||= "*"
        [min, hour, day, mon, week, year]
      when %r{^((\*?\??L?W?[\d/,-]*)\s*){6}$}
        frequency.split(" ")
      else
        raise UnsupportedFrequencyException, "`#{frequency}` is not supported option. Ignore this task."
      end
    end

    def print_tasks
      @tasks.each do |task|
        puts "#{task.expression} { commands: #{task.commands} }"
      end
    end

    def method_missing(name, *_args)
      Logger.instance.warn("Skipping unsupported method: #{name}")
    end
  end
end
