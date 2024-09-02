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
      response.schedules.each do |schedule|
        detail = @scheduler_client.get_schedule({ group_name: group_name, name: schedule.name })
        puts "#{schedule.state} #{schedule.name} #{detail.schedule_expression} #{detail.description}"
      end
    end

    def create_schedule_group(group_name)
      @scheduler_client.create_schedule_group({ name: group_name })
      puts "Schedule group '#{group_name}' created."
    rescue Aws::Scheduler::Errors::ConflictException
      puts "Schedule group '#{group_name}' already exists."
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
      Digest::SHA1.hexdigest([option.key, task.expression, *task.commands].join("-")).to_s[0, 64]
    end

    def schedule_description(task)
      task.commands.to_s
    end

    def clean_up_schedules(schedule_group)
      response = @scheduler_client.list_schedules({ group_name: schedule_group })
      response.schedules.each do |schedule|
        @scheduler_client.delete_schedule({
                                            name: schedule.name,
                                            group_name: schedule_group
                                          })
      end
    rescue Aws::Scheduler::Errors::ResourceNotFoundException
      puts "Schedule group '#{schedule_group}' does not exist."
    end
  end
end
