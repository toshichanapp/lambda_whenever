# frozen_string_literal: true

module LambdaWhenever
  # The EventBridgeScheduler class is responsible for managing schedules in AWS EventBridge.
  class EventBridgeScheduler
    # With frozen_string_literal, all string values are frozen. Integer is always frozen.
    FLEXIBLE_TIME_WINDOW = { maximum_window_in_minutes: 5, mode: "FLEXIBLE" }.freeze
    PAGINATION_MAX_RESULTS = 100
    PAGINATION_MAX_PAGES = 1000
    # SHA1 hex digest is 40 chars, separator is 1 char, so prefix max is 64 - 41 = 23 chars.
    # Prefix may be truncated mid-word; multibyte characters are sanitized to underscores.
    SCHEDULE_NAME_MAX_LENGTH = 64
    SHA1_HEX_LENGTH = 40
    PREFIX_MAX_LENGTH = SCHEDULE_NAME_MAX_LENGTH - SHA1_HEX_LENGTH - 1
    DEFAULT_SCHEDULE_PREFIX = "task"

    attr_reader :timezone

    def initialize(client, timezone = "UTC")
      @scheduler_client = client
      @timezone = timezone
    end

    # NOTE: Calls get_schedule per entry because the ListSchedules API does not return
    # schedule_expression or description. This results in N+1 API calls but is unavoidable.
    def list_schedules(group_name)
      Logger.instance.message("Schedules in group '#{group_name}':")
      fetch_all_schedules(group_name).map do |schedule|
        detail = @scheduler_client.get_schedule({ group_name: group_name, name: schedule.name })
        Logger.instance.message "#{schedule.state} #{schedule.name} #{detail.schedule_expression} #{detail.description}"
        {
          name: schedule.name,
          state: schedule.state,
          expression: detail.schedule_expression,
          description: detail.description
        }
      end
    end

    def sync_schedules(desired_schedules, current_schedules, option)
      desired_names = desired_schedules.to_set { |s| s[:name] }
      current_schedules_hash = current_schedules.to_h do |schedule|
        [schedule[:name], schedule]
      end
      current_names = current_schedules_hash.keys.to_set
      to_delete = current_names - desired_names

      to_add, to_update = desired_schedules.each_with_object([[], []]) do |desired, (add, update)|
        current = current_schedules_hash[desired[:name]]
        if current.nil?
          add << desired
        elsif schedules_differ?(current, desired, option)
          update << desired
        end
      end

      errors = []

      Logger.instance.message("Deleting #{to_delete.length} schedules...")
      to_delete.each do |name|
        Logger.instance.message "delete schedule: #{name}"
        delete_schedule(name, option.scheduler_group)
      end

      Logger.instance.message("Creating #{to_add.length} schedules...")
      to_add.each do |schedule|
        Logger.instance.message "create schedule: #{schedule[:name]}"
        create_schedule(schedule[:target], option)
      rescue Aws::Scheduler::Errors::ConflictException
        raise
      rescue Aws::Scheduler::Errors::ServiceError => e
        Logger.instance.warn("Schedule creation failed, continuing: #{e.message}.")
        errors << e
      end

      Logger.instance.message("Updating #{to_update.length} schedules...")
      to_update.each do |desired|
        Logger.instance.message("Updating schedule: #{desired[:name]}")
        update_schedule(desired[:target], option)
      rescue Aws::Scheduler::Errors::ConflictException
        raise
      rescue Aws::Scheduler::Errors::ServiceError => e
        Logger.instance.warn("Schedule update failed, continuing: #{e.message}.")
        errors << e
      end

      raise errors.first if errors.any?
    end

    def create_schedule_group(group_name)
      @scheduler_client.create_schedule_group({ name: group_name })
      Logger.instance.message "Schedule group '#{group_name}' created."
    rescue Aws::Scheduler::Errors::ConflictException
      Logger.instance.message "Schedule group '#{group_name}' already exists."
    end

    # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/Scheduler/Client.html#create_schedule-instance_method
    def create_schedule(target, option)
      upsert_schedule(:create_schedule, target, option)
    end

    def update_schedule(target, option)
      upsert_schedule(:update_schedule, target, option)
    end

    def schedule_name(task, option)
      hash = Digest::SHA1.hexdigest([option.key, task.expression, *task.commands].join("-"))
      raw_prefix = task.name.to_s.empty? ? DEFAULT_SCHEDULE_PREFIX : task.name
      prefix = sanitize(raw_prefix)[0, PREFIX_MAX_LENGTH]
      "#{prefix}-#{hash}"
    end

    def clean_up_schedules(schedule_group)
      fetch_all_schedules(schedule_group).each do |schedule|
        delete_schedule(schedule.name, schedule_group)
      end
    end

    private

    # Fetches all schedules from the specified group, handling pagination automatically.
    #
    # @param group_name [String] the name of the schedule group
    # @return [Array<Aws::Scheduler::Types::ScheduleSummary>] all schedules in the group
    def fetch_all_schedules(group_name)
      all_schedules = []
      next_token = nil
      pages = 0
      loop do
        raise "Exceeded maximum pagination pages (#{PAGINATION_MAX_PAGES})." if pages >= PAGINATION_MAX_PAGES

        params = { group_name: group_name, max_results: PAGINATION_MAX_RESULTS }
        params[:next_token] = next_token if next_token
        response = @scheduler_client.list_schedules(params)
        all_schedules.concat(response.schedules)
        next_token = response.next_token
        pages += 1
        break if next_token.nil?
      end
      all_schedules
    end

    def schedule_description(task)
      task.commands.to_s
    end

    def sanitize(input)
      input.gsub(/[^a-zA-Z0-9\-._]/, "_")
    end

    def schedules_differ?(current, desired, option)
      task = desired[:target].task
      current[:expression] != task.expression ||
        current[:description] != schedule_description(task) ||
        current[:state] != option.rule_state
    end

    def upsert_schedule(api_method, target, option)
      task = target.task
      name = schedule_name(task, option)
      @scheduler_client.public_send(api_method, {
                                      name: name,
                                      schedule_expression: task.expression,
                                      schedule_expression_timezone: timezone,
                                      flexible_time_window: FLEXIBLE_TIME_WINDOW,
                                      target: {
                                        arn: target.arn,
                                        role_arn: IamRole.new(option).arn,
                                        input: target.input
                                      },
                                      group_name: option.scheduler_group,
                                      state: option.rule_state,
                                      description: schedule_description(task)
                                    })
    rescue Aws::Scheduler::Errors::ValidationException => e
      Logger.instance.fail("Invalid schedule parameters for '#{name}': #{e.message}.")
      raise
    end

    def delete_schedule(name, group_name)
      @scheduler_client.delete_schedule({
                                          name: name,
                                          group_name: group_name
                                        })
    rescue Aws::Scheduler::Errors::ResourceNotFoundException
      Logger.instance.message("Schedule '#{name}' does not exist.")
    end
  end
end
