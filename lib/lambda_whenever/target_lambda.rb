# frozen_string_literal: true

module LambdaWhenever
  # The TargetLambda class represents a Lambda function as a target for scheduling.
  class TargetLambda
    attr_reader :role_arn, :arn, :input, :name, :task

    class << self
      def fetch_arn(function_name, client)
        response = client.get_function({
                                         function_name: function_name
                                       })
        response.configuration.function_arn
      end
    end

    def initialize(arn:, task:)
      @arn = arn
      @task = task
      @input = input_json
    end

    # https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-schedule-context-attributes.html
    def input_json
      {
        execution_id: "<aws.scheduler.execution-id>",
        scheduled_time: "<aws.scheduler.scheduled-time>",
        schedule_arn: "<aws.scheduler.schedule-arn>",
        attempt_number: "<aws.scheduler.attempt-number>",
        commands: task.commands
      }.to_json
    end
  end
end
