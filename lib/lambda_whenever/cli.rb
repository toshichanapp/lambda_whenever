# frozen_string_literal: true

module LambdaWhenever
  # The CLI class handles command-line interface interactions for the Lambda Whenever tool.
  class CLI
    SUCCESS_EXIT_CODE = 0
    ERROR_EXIT_CODE = 1

    attr_reader :args, :option

    def initialize(args)
      @args = args
      @option = Option.new(args)
    end

    def run
      case option.mode
      when Option::DRYRUN_MODE
        option.validate!
        print_tasks
        Logger.instance.message("Above is your schedule file converted to scheduled tasks; your scheduled tasks was not updated.")
        Logger.instance.message("Run `lambda_whenever --help' for more options.")
      when Option::UPDATE_MODE
        option.validate!
        with_concurrent_modification_handling do
          update_eb_schedules
        end
        Logger.instance.log("write", "scheduled tasks updated")
      when Option::SYNC_MODE
        option.validate!
        with_concurrent_modification_handling do
          sync_eb_schedules
        end
        Logger.instance.log("write", "scheduled tasks updated")
      when Option::CLEAR_MODE
        with_concurrent_modification_handling do
          clear_tasks
        end
        Logger.instance.log("write", "scheduled tasks cleared")
      when Option::LIST_MODE
        list_tasks
        Logger.instance.message("Above is your scheduled tasks.")
      when Option::PRINT_VERSION_MODE
        print_version
      end

      SUCCESS_EXIT_CODE
    rescue Aws::Errors::MissingRegionError
      Logger.instance.fail("missing region error occurred; please use `--region` option or export `AWS_REGION` environment variable.")
      ERROR_EXIT_CODE
    rescue Aws::Errors::MissingCredentialsError
      Logger.instance.fail("missing credential error occurred; please specify it with arguments, use shared credentials, or export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variable")
      ERROR_EXIT_CODE
    rescue OptionParser::MissingArgument,
           Option::InvalidOptionException => e

      Logger.instance.fail(e.message)
      ERROR_EXIT_CODE
    end

    private

    def update_eb_schedules
      schedule = Schedule.new(option.schedule_file, option.verbose, option.variables)
      scheduler = EventBridgeScheduler.new(option.scheduler_client, schedule.timezone)
      scheduler.create_schedule_group(option.scheduler_group)
      scheduler.clean_up_schedules(option.scheduler_group)

      lambda_arn = TargetLambda.fetch_arn(option.lambda_name, option.lambda_client)
      schedule.tasks.map do |task|
        target = TargetLambda.new(arn: lambda_arn, task: task)

        scheduler.create_schedule(target, option)
      end
    end

    def sync_eb_schedules
      schedule = Schedule.new(option.schedule_file, option.verbose, option.variables)
      scheduler = EventBridgeScheduler.new(option.scheduler_client, schedule.timezone)

      scheduler.create_schedule_group(option.scheduler_group)

      current_schedules = scheduler.list_schedules(option.scheduler_group)
      lambda_arn = TargetLambda.fetch_arn(option.lambda_name, option.lambda_client)
      desired_schedules = schedule.tasks.map do |task|
        target = TargetLambda.new(arn: lambda_arn, task: task)
        {
          name: scheduler.schedule_name(task, option),
          target: target,
          task: task
        }
      end

      scheduler.sync_schedules(desired_schedules, current_schedules, option)
    end

    def clear_tasks
      scheduler = EventBridgeScheduler.new(option.scheduler_client)
      scheduler.clean_up_schedules(option.scheduler_group)
    end

    def list_tasks
      scheduler = EventBridgeScheduler.new(option.scheduler_client)
      scheduler.list_schedules(option.scheduler_group)
    end

    def print_version
      puts "Lambda Whenever v#{LambdaWhenever::VERSION}"
    end

    def print_tasks
      schedule = Schedule.new(option.schedule_file, option.verbose, option.variables)
      schedule.print_tasks
    end

    def with_concurrent_modification_handling
      Retryable.retryable(
        tries: 5,
        on: Aws::Scheduler::Errors::ConflictException,
        sleep: ->(_n) { rand(1..10) }
      ) do |retries, _exn|
        Logger.instance.warn("concurrent modification detected; Retrying...") if retries.positive?
        yield
      end
    end
  end
end
