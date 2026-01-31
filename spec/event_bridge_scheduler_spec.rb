# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::EventBridgeScheduler do
  let(:scheduler_client) { double("Aws::Scheduler::Client") }
  let(:scheduler) { described_class.new(scheduler_client, "Asia/Tokyo") }
  let(:group_name) { "test-group" }

  let(:option) do
    instance_double(
      LambdaWhenever::Option,
      scheduler_group: group_name,
      rule_state: "ENABLED",
      iam_role: "test-role",
      key: "abc123",
      iam_client: double("Aws::IAM::Client")
    )
  end

  let(:task) do
    instance_double(
      LambdaWhenever::Task,
      name: "test_task",
      expression: "cron(0 0 * * ? *)",
      commands: [%w[bundle exec rake test]]
    )
  end

  let(:target) do
    instance_double(
      LambdaWhenever::TargetLambda,
      task: task,
      arn: "arn:aws:lambda:us-east-1:123456789:function:test",
      input: '{"commands":["test"]}'
    )
  end

  let(:iam_role) { instance_double(LambdaWhenever::IamRole, arn: "arn:aws:iam::123456789:role/test-role") }

  before do
    allow(LambdaWhenever::IamRole).to receive(:new).and_return(iam_role)
  end

  describe "#initialize" do
    it "sets timezone" do
      expect(scheduler.timezone).to eq("Asia/Tokyo")
    end

    it "defaults timezone to UTC" do
      scheduler = described_class.new(scheduler_client)
      expect(scheduler.timezone).to eq("UTC")
    end
  end

  describe "#list_schedules" do
    let(:schedule_entry) { double("schedule", name: "test-schedule", state: "ENABLED") }
    let(:detail) do
      double("detail", schedule_expression: "cron(0 0 * * ? *)", description: "test desc")
    end
    let(:response) { double("response", schedules: [schedule_entry], next_token: nil) }

    before do
      allow(scheduler_client).to receive(:list_schedules).and_return(response)
      allow(scheduler_client).to receive(:get_schedule).and_return(detail)
    end

    it "returns schedule details" do
      result = scheduler.list_schedules(group_name)
      expect(result).to eq([{
                             name: "test-schedule",
                             state: "ENABLED",
                             expression: "cron(0 0 * * ? *)",
                             description: "test desc"
                           }])
    end

    context "with pagination" do
      let(:schedule1) { double("schedule1", name: "sched-1", state: "ENABLED") }
      let(:schedule2) { double("schedule2", name: "sched-2", state: "ENABLED") }
      let(:response1) { double("response1", schedules: [schedule1], next_token: "token123") }
      let(:response2) { double("response2", schedules: [schedule2], next_token: nil) }

      before do
        allow(scheduler_client).to receive(:list_schedules)
          .with({ group_name: group_name }).and_return(response1)
        allow(scheduler_client).to receive(:list_schedules)
          .with({ group_name: group_name, next_token: "token123" }).and_return(response2)
        allow(scheduler_client).to receive(:get_schedule).and_return(detail)
      end

      it "fetches all pages" do
        result = scheduler.list_schedules(group_name)
        expect(result.length).to eq(2)
      end
    end
  end

  describe "#create_schedule_group" do
    it "creates a schedule group" do
      expect(scheduler_client).to receive(:create_schedule_group).with({ name: group_name })
      scheduler.create_schedule_group(group_name)
    end

    it "handles existing group gracefully" do
      allow(scheduler_client).to receive(:create_schedule_group)
        .and_raise(Aws::Scheduler::Errors::ConflictException.new(nil, "conflict"))
      expect { scheduler.create_schedule_group(group_name) }.not_to raise_error
    end
  end

  describe "#create_schedule" do
    it "creates a schedule with correct parameters" do
      expect(scheduler_client).to receive(:create_schedule).with(hash_including(
                                                                   schedule_expression: "cron(0 0 * * ? *)",
                                                                   schedule_expression_timezone: "Asia/Tokyo",
                                                                   flexible_time_window: described_class::FLEXIBLE_TIME_WINDOW,
                                                                   group_name: group_name,
                                                                   state: "ENABLED"
                                                                 ))
      scheduler.create_schedule(target, option)
    end

    it "raises and logs on AWS error" do
      allow(scheduler_client).to receive(:create_schedule)
        .and_raise(Aws::Scheduler::Errors::ServiceException.new(nil, "service error"))
      expect { scheduler.create_schedule(target, option) }
        .to raise_error(Aws::Scheduler::Errors::ServiceException)
    end
  end

  describe "#update_schedule" do
    it "calls update_schedule on the client" do
      expect(scheduler_client).to receive(:update_schedule).with(hash_including(
                                                                   schedule_expression: "cron(0 0 * * ? *)",
                                                                   schedule_expression_timezone: "Asia/Tokyo",
                                                                   flexible_time_window: described_class::FLEXIBLE_TIME_WINDOW
                                                                 ))
      scheduler.update_schedule(target, option)
    end
  end

  describe "#schedule_name" do
    it "generates a name within 64 characters" do
      name = scheduler.schedule_name(task, option)
      expect(name.length).to be <= 64
    end

    it "contains the full SHA1 hash" do
      name = scheduler.schedule_name(task, option)
      hash_part = name.split("-").last
      expect(hash_part.length).to eq(40)
    end

    it "truncates long task names" do
      long_task = instance_double(LambdaWhenever::Task,
                                  name: "a" * 100,
                                  expression: "cron(0 0 * * ? *)",
                                  commands: [%w[test]])
      name = scheduler.schedule_name(long_task, option)
      expect(name.length).to eq(64)
    end
  end

  describe "#clean_up_schedules" do
    let(:schedule1) { double("schedule1", name: "sched-1") }
    let(:schedule2) { double("schedule2", name: "sched-2") }
    let(:response) { double("response", schedules: [schedule1, schedule2], next_token: nil) }

    before do
      allow(scheduler_client).to receive(:list_schedules).and_return(response)
    end

    it "deletes all schedules in the group" do
      expect(scheduler_client).to receive(:delete_schedule)
        .with({ name: "sched-1", group_name: group_name })
      expect(scheduler_client).to receive(:delete_schedule)
        .with({ name: "sched-2", group_name: group_name })
      scheduler.clean_up_schedules(group_name)
    end
  end

  describe "#sync_schedules" do
    let(:current_schedules) do
      [
        { name: "existing", state: "ENABLED", expression: "cron(0 0 * * ? *)", description: "old" },
        { name: "to-delete", state: "ENABLED", expression: "cron(0 1 * * ? *)", description: "delete me" }
      ]
    end

    let(:new_target) do
      instance_double(LambdaWhenever::TargetLambda,
                      task: instance_double(LambdaWhenever::Task,
                                            name: "new_task", expression: "cron(0 2 * * ? *)",
                                            commands: [%w[bundle exec rake new]]),
                      arn: "arn:aws:lambda:us-east-1:123456789:function:test",
                      input: '{"commands":["new"]}')
    end

    let(:desired_schedules) do
      [
        { name: "existing", target: target },
        { name: "new-schedule", target: new_target }
      ]
    end

    before do
      allow(scheduler_client).to receive(:create_schedule)
      allow(scheduler_client).to receive(:update_schedule)
      allow(scheduler_client).to receive(:delete_schedule)
    end

    it "deletes schedules not in desired list" do
      expect(scheduler_client).to receive(:delete_schedule)
        .with({ name: "to-delete", group_name: group_name })
      scheduler.sync_schedules(desired_schedules, current_schedules, option)
    end

    it "creates new schedules" do
      expect(scheduler_client).to receive(:create_schedule).once
      scheduler.sync_schedules(desired_schedules, current_schedules, option)
    end
  end
end
