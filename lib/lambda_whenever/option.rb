# frozen_string_literal: true

module LambdaWhenever
  # The Option class handles parsing and validation of command-line options.
  class Option
    POSSIBLE_RULE_STATES = %w[ENABLED DISABLED].freeze

    DRYRUN_MODE = 1
    UPDATE_MODE = 2
    CLEAR_MODE = 3
    LIST_MODE = 4
    PRINT_VERSION_MODE = 5

    attr_reader :mode, :verbose, :variables, :schedule_file, :iam_role, :rule_state,
                :lambda_name, :scheduler_group

    class InvalidOptionException < StandardError; end

    def initialize(args)
      @mode = DRYRUN_MODE
      @verbose = false
      @variables = []
      @schedule_file = "config/schedule.rb"
      @iam_role = nil
      @rule_state = "ENABLED"
      @lambda_name = nil
      @scheduler_group = "lambda-whenever-dev-group"
      @region = nil

      OptionParser.new do |opts|
        opts.on("--dryrun", "dry-run") do
          @mode = DRYRUN_MODE
        end
        opts.on("--update", "Creates and deletes tasks as needed by schedule file") do
          @mode = UPDATE_MODE
        end
        opts.on("-c", "--clear", "Clear scheduled tasks") do
          @mode = CLEAR_MODE
        end
        opts.on("-l", "--list", "List scheduled tasks") do
          @mode = LIST_MODE
        end
        opts.on("-v", "--version", "Print version") do
          @mode = PRINT_VERSION_MODE
        end
        opts.on("-s", "--set variables", "Example: --set 'environment=staging'") do |set|
          pairs = set.split("&")
          pairs.each do |pair|
            unless pair.include?("=")
              Logger.instance.warn("Ignore variable set: #{pair}")
              next
            end
            key, value = pair.split("=")
            @variables << { key: key, value: value }
          end
        end
        opts.on("--lambda-name name", "Lambda function name") do |name|
          @lambda_name = name
        end
        opts.on("--scheduler-group group_name",
                "Optionally specify event bridge scheduler group name") do |group|
          @scheduler_group = group
        end
        opts.on("-f", "--file schedule_file", "Default: config/schedule.rb") do |file|
          @schedule_file = file
        end
        opts.on("--iam-role name", "IAM role name used by EventBridgeScheduler.") do |role|
          @iam_role = role
        end
        opts.on("--rule-state state", "The state of the EventBridgeScheduler Rule. Default: ENABLED") do |state|
          @rule_state = state
        end
        opts.on("--region region", "AWS region") do |region|
          @region = region
        end
        opts.on("-V", "--verbose", "Run rake jobs without --silent") do
          @verbose = true
        end
      end.parse(args)
    end

    def validate!
      raise InvalidOptionException, "Can't find file: #{schedule_file}" unless File.exist?(schedule_file)
      raise InvalidOptionException, "You must set lambda-name" unless lambda_name
      raise InvalidOptionException, "You must set iam-role" unless iam_role
      return if POSSIBLE_RULE_STATES.include?(rule_state)

      raise InvalidOptionException, "Invalid rule state. Possible values are #{POSSIBLE_RULE_STATES.join(", ")}"
    end

    def aws_config
      @aws_config ||= { region: region }.delete_if { |_k, v| v.nil? }
    end

    def iam_client
      @iam_client ||= Aws::IAM::Client.new(aws_config)
    end

    def lambda_client
      @lambda_client ||= Aws::Lambda::Client.new(aws_config)
    end

    def scheduler_client
      @scheduler_client ||= Aws::Scheduler::Client.new(aws_config)
    end

    def key
      Digest::SHA1.hexdigest(
        [
          variables,
          iam_role,
          rule_state,
          lambda_name,
          scheduler_group
        ].join
      )
    end

    private

    attr_reader :region
  end
end
