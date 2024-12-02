# frozen_string_literal: true

module LambdaWhenever
  # The EventBridgeScheduler class is responsible for managing schedules in AWS EventBridge.
  class EventBridgeScheduler
    attr_reader :timezone

    def initialize(client, timezone = "UTC")
      @scheduler_client = client
      @timezone = timezone
    end

    def list_schedules(group_name)
      Logger.instance.message("Schedules in group '#{group_name}':")
      response = @scheduler_client.list_schedules({ group_name: group_name })
      response.schedules.map do |schedule|
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
      desired_names = desired_schedules.map { |s| s[:name] }.to_set
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

      Logger.instance.message("Deleting #{to_delete.length} schedules...")
      to_delete.each do |name|
        Logger.instance.message "delete schedule: #{name}"
        delete_schedule(name, option.scheduler_group)
      end

      Logger.instance.message("Creating #{to_add.length} schedules...")
      to_add.each do |schedule|
        Logger.instance.message "create schedule: #{schedule[:name]}"
        create_schedule(schedule[:target], option)
      end

      Logger.instance.message("Updating #{to_update.length} schedules...")
      to_update.each do |desired|
        Logger.instance.message("Updating schedule: #{desired[:name]}")
        delete_schedule(desired[:name], option.scheduler_group)
        create_schedule(desired[:target], option)
      end
    end

    def create_schedule_group(group_name)
      @scheduler_client.create_schedule_group({ name: group_name })
      Logger.instance.message "Schedule group '#{group_name}' created."
    rescue Aws::Scheduler::Errors::ConflictException
      Logger.instance.message "Schedule group '#{group_name}' already exists."
    end

    # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/Scheduler/Client.html#create_schedule-instance_method
    def create_schedule(target, option)
      task = target.task
      @scheduler_client.create_schedule({
                                          name: schedule_name(task, option),
                                          schedule_expression: task.expression,
                                          schedule_expression_timezone: timezone,
                                          flexible_time_window: {
                                            maximum_window_in_minutes: 5,
                                            mode: "FLEXIBLE"
                                          },
                                          target: {
                                            arn: target.arn,
                                            role_arn: IamRole.new(option).arn,
                                            input: target.input
                                          },
                                          group_name: option.scheduler_group,
                                          state: option.rule_state,
                                          description: schedule_description(task)
                                        })
    end

    def schedule_name(task, option)
      input = "#{task.name}-#{Digest::SHA1.hexdigest([option.key, task.expression, *task.commands].join("-"))}"
      sanitize_and_trim(input)
    end

    def schedule_description(task)
      task.commands.to_s
    end

    def clean_up_schedules(schedule_group)
      response = @scheduler_client.list_schedules({ group_name: schedule_group })
      response.schedules.each do |schedule|
        delete_schedule(schedule.name, schedule_group)
      end
    end

    private

    def sanitize_and_trim(input)
      sanitized = input.gsub(/[^a-zA-Z0-9\-._]/, "_")
      sanitized[0, 64]
    end

    def schedules_differ?(current, desired, option)
      task = desired[:target].task
      current[:expression] != task.expression ||
        current[:description] != schedule_description(task) ||
        current[:state] != option.rule_state
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
