# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::CLI do
  let(:args) { [] }
  let(:cli) { described_class.new(args) }

  describe "#initialize" do
    it "initializes with given args" do
      expect(cli.args).to eq(args)
      expect(cli.option).to be_an_instance_of(LambdaWhenever::Option)
    end
  end

  describe "#run" do
    let(:schedule) { double("Schedule", print_tasks: nil, tasks: [task], timezone: "UTC") }
    let(:task) do
      LambdaWhenever::Task.new("production", false, "bundle exec", "cron(0 0 * * ? *)").tap do |task|
        task.runner("Hoge.run")
      end
    end
    let(:scheduler) do
      double("EventBridgeScheduler", clean_up_schedules: nil, create_schedule_group: nil, create_schedule: nil,
                                     list_schedules: nil)
    end
    let(:lambda_client) { double("Aws::Lambda::Client") }
    let(:lambda_arn) { "arn:aws:lambda:us-east-1:123456789:function:my-function" }

    before do
      allow(LambdaWhenever::Schedule).to receive(:new).and_return(schedule)
      allow(LambdaWhenever::EventBridgeScheduler).to receive(:new).and_return(scheduler)
      allow(LambdaWhenever::TargetLambda).to receive(:fetch_arn).and_return(lambda_arn)
      allow(cli.option).to receive(:lambda_client).and_return(lambda_client)
    end

    context "with dry run mode" do
      let(:args) do
        %W[
          --dryrun
          -f #{Pathname(__dir__).join("fixtures/schedule.rb")}
          --lambda-name my-function
          --iam-role my-role
        ]
      end

      before { cli.option.instance_variable_set(:@mode, LambdaWhenever::Option::DRYRUN_MODE) }

      it "prints tasks and returns success status code" do
        expect(schedule).to receive(:print_tasks)
        expect do
          cli.run
        end.to output(/Above is your schedule file converted to scheduled tasks/).to_stdout
        expect(cli.run).to eq(LambdaWhenever::CLI::SUCCESS_EXIT_CODE)
      end
    end

    context "with update mode" do
      let(:args) do
        %W[
          --dryrun
          -f #{Pathname(__dir__).join("fixtures/schedule.rb")}
          --lambda-name my-function
          --iam-role my-role
        ]
      end

      before { cli.option.instance_variable_set(:@mode, LambdaWhenever::Option::UPDATE_MODE) }

      it "updates schedules and returns success status code" do
        expect(scheduler).to receive(:clean_up_schedules)
        expect(scheduler).to receive(:create_schedule).with(instance_of(LambdaWhenever::TargetLambda),
                                                            cli.option)
        expect(cli.run).to eq(LambdaWhenever::CLI::SUCCESS_EXIT_CODE)
      end
    end

    context "with clear mode" do
      let(:args) { %w[--clear --lambda-name my-function --iam-role my-role] }

      before { cli.option.instance_variable_set(:@mode, LambdaWhenever::Option::CLEAR_MODE) }

      it "clears tasks and returns success status code" do
        expect(scheduler).to receive(:clean_up_schedules)
        expect(cli.run).to eq(LambdaWhenever::CLI::SUCCESS_EXIT_CODE)
      end
    end

    context "with list mode" do
      let(:args) do
        %W[
          --list
          -f #{Pathname(__dir__).join("fixtures/schedule.rb")}
          --lambda-name my-function
          --iam-role my-role
        ]
      end

      before { cli.option.instance_variable_set(:@mode, LambdaWhenever::Option::LIST_MODE) }

      it "lists tasks and returns success status code" do
        expect(scheduler).to receive(:list_schedules)
        expect do
          cli.run
        end.to output(/Above is your scheduled tasks/).to_stdout
        expect(cli.run).to eq(LambdaWhenever::CLI::SUCCESS_EXIT_CODE)
      end
    end

    context "with print version mode" do
      let(:args) { %w[--version] }

      before { cli.option.instance_variable_set(:@mode, LambdaWhenever::Option::PRINT_VERSION_MODE) }

      it "prints version and returns success status code" do
        expect do
          cli.run
        end.to output("Lambda Whenever v#{LambdaWhenever::VERSION}\n").to_stdout
        expect(cli.run).to eq(LambdaWhenever::CLI::SUCCESS_EXIT_CODE)
      end
    end

    context "with invalid options" do
      it "raises an invalid option exception" do
        expect do
          described_class.new(%w[--invalid])
        end.to raise_error(OptionParser::InvalidOption)
      end
    end

    context "when Aws::Errors::MissingRegionError is raised" do
      before do
        allow(cli.option).to receive(:validate!).and_raise(Aws::Errors::MissingRegionError.new(nil, "Missing region"))
      end

      it "logs the error and returns error status code" do
        expect do
          cli.run
        end.to output(/missing region error occurred; please use `--region` option or export `AWS_REGION` environment variable./).to_stderr

        expect(cli.run).to eq(LambdaWhenever::CLI::ERROR_EXIT_CODE)
      end
    end

    context "when Aws::Errors::MissingCredentialsError is raised" do
      before do
        allow(cli.option).to receive(:validate!).and_raise(Aws::Errors::MissingCredentialsError.new(nil,
                                                                                                    "Missing credentials"))
      end

      it "logs the error and returns error status code" do
        expect do
          cli.run
        end.to output(/missing credential error occurred; please specify it with arguments, use shared credentials, or export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variable/).to_stderr

        expect(cli.run).to eq(LambdaWhenever::CLI::ERROR_EXIT_CODE)
      end
    end

    context "when OptionParser::MissingArgument is raised" do
      before do
        allow(cli.option).to receive(:validate!).and_raise(OptionParser::MissingArgument.new("Missing argument"))
      end

      it "logs the error and returns error status code" do
        expect do
          cli.run
        end.to output(/\[fail\] missing argument: Missing argument/).to_stderr

        expect(cli.run).to eq(LambdaWhenever::CLI::ERROR_EXIT_CODE)
      end
    end

    context "when Option::InvalidOptionException is raised" do
      before do
        allow(cli.option).to receive(:validate!).and_raise(LambdaWhenever::Option::InvalidOptionException.new("Invalid option"))
      end

      it "logs the error and returns error status code" do
        expect do
          cli.run
        end.to output(/\[fail\] Invalid option/).to_stderr
        expect(cli.run).to eq(LambdaWhenever::CLI::ERROR_EXIT_CODE)
      end
    end
  end
end
