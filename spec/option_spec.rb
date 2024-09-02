# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::Option do
  describe "#initialize" do
    it "has default config" do
      expect(LambdaWhenever::Option.new([])).to have_attributes(
        mode: LambdaWhenever::Option::DRYRUN_MODE,
        verbose: false,
        variables: [],
        schedule_file: "config/schedule.rb",
        iam_role: nil,
        rule_state: "ENABLED",
        lambda_name: nil,
        scheduler_group: "lambda-whenever-dev-group"
      )
    end

    it "has custom config" do
      option = LambdaWhenever::Option.new(%w[
                                            --set environment=staging&foo=bar
                                            -f custom_schedule.rb
                                            --verbose
                                            --rule-state DISABLED
                                            --iam-role customRole
                                            --lambda-name customLambda
                                            --scheduler-group customGroup
                                          ])

      expect(option).to have_attributes(
        mode: LambdaWhenever::Option::DRYRUN_MODE,
        verbose: true,
        variables: [
          { key: "environment", value: "staging" },
          { key: "foo", value: "bar" }
        ],
        schedule_file: "custom_schedule.rb",
        iam_role: "customRole",
        rule_state: "DISABLED",
        lambda_name: "customLambda",
        scheduler_group: "customGroup"
      )
    end

    it "sets update mode" do
      option = LambdaWhenever::Option.new(%w[--update])
      expect(option).to have_attributes(
        mode: LambdaWhenever::Option::UPDATE_MODE
      )
    end

    it "sets clear mode" do
      option = LambdaWhenever::Option.new(%w[-c])
      expect(option).to have_attributes(
        mode: LambdaWhenever::Option::CLEAR_MODE
      )
    end

    it "sets list mode" do
      option = LambdaWhenever::Option.new(%w[-l])
      expect(option).to have_attributes(
        mode: LambdaWhenever::Option::LIST_MODE
      )
    end

    it "sets version mode" do
      option = LambdaWhenever::Option.new(%w[-v])
      expect(option).to have_attributes(
        mode: LambdaWhenever::Option::PRINT_VERSION_MODE
      )
    end

    it "logs a warning and ignores invalid variable sets" do
      option = LambdaWhenever::Option.new(%w[
                                            --set environment=staging&foo=bar&invalid
                                          ])

      expect(option.variables).to eq([
                                       { key: "environment", value: "staging" },
                                       { key: "foo", value: "bar" }
                                     ])
    end
  end

  describe "#validate!" do
    it "raises exception when schedule file is not found" do
      expect do
        LambdaWhenever::Option.new(%w[-f invalid/file.rb]).validate!
      end.to raise_error(LambdaWhenever::Option::InvalidOptionException, "Can't find file: invalid/file.rb")
    end

    it "raises exception when lambda-name is not set" do
      expect do
        LambdaWhenever::Option.new(%W[-f #{Pathname(__dir__).join("fixtures/schedule.rb")}]).validate!
      end.to raise_error(LambdaWhenever::Option::InvalidOptionException, "You must set lambda-name")
    end

    it "raises exception when iam-role is not set" do
      expect do
        LambdaWhenever::Option.new(%W[
                                     --lambda-name test
                                     -f #{Pathname(__dir__).join("fixtures/schedule.rb")}
                                   ]).validate!
      end.to raise_error(LambdaWhenever::Option::InvalidOptionException, "You must set iam-role")
    end

    it "raises an exception if the rule state is invalid" do
      expect do
        LambdaWhenever::Option.new(%W[
                                     -f #{Pathname(__dir__).join("fixtures/schedule.rb")}
                                     --rule-state FOO
                                     --lambda-name test
                                     --iam-role schedule-test
                                   ]).validate!
      end.to raise_error(LambdaWhenever::Option::InvalidOptionException,
                         "Invalid rule state. Possible values are ENABLED, DISABLED")
    end
  end

  describe "#key" do
    let(:configuration) do
      %w[
        --set environment=staging&foo=bar
        --iam-role schedule-test
        --rule-state DISABLED
        --lambda-name test
      ].freeze
    end

    it "creates a unique key for configuration options" do
      options = [
        configuration,
        replace_item(configuration, "environment=staging&foo=bar", "environment=test&baz=qux"),
        replace_item(configuration, "DISABLED", "ENABLED")
      ].map { |conf| LambdaWhenever::Option.new(conf).key }

      expect(options.uniq).to eql(options)
      expect(options.uniq.length).to eql(3)
    end

    def replace_item(configuration, old_value, replacement_value)
      configuration.map { |val| val == old_value ? replacement_value : val }
    end
  end
end
