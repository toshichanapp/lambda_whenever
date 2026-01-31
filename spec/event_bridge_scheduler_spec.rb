# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe LambdaWhenever::EventBridgeScheduler do
  let(:scheduler_client) { double("Aws::Scheduler::Client") }
  let(:scheduler) { described_class.new(scheduler_client) }

  describe "#schedule_name" do
    let(:option) { double("Option", key: "test-key") }

    def build_task(name, expression, commands)
      double("Task", name: name, expression: expression, commands: commands)
    end

    context "with a normal task name" do
      it "fits within 64 characters" do
        task = build_task("my_task", "cron(0 0 * * ? *)", [%w[bundle exec rake db:migrate]])
        name = scheduler.schedule_name(task, option)

        expect(name.length).to be <= 64
      end

      it "preserves the full SHA1 hash (40 chars)" do
        task = build_task("my_task", "cron(0 0 * * ? *)", [%w[bundle exec rake db:migrate]])
        name = scheduler.schedule_name(task, option)
        hash_part = name.split("-", 2).last

        expect(hash_part).to match(/\A[a-f0-9]{40}\z/)
      end

      it "includes the sanitized task name as prefix" do
        task = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        name = scheduler.schedule_name(task, option)

        expect(name).to start_with("deploy-")
      end
    end

    context "with a long task name" do
      it "truncates the prefix to PREFIX_MAX_LENGTH characters" do
        long_name = "a" * 50
        task = build_task(long_name, "cron(0 0 * * ? *)", [%w[rake run]])
        name = scheduler.schedule_name(task, option)

        prefix = name.split("-", 2).first
        expect(prefix.length).to eq(described_class::PREFIX_MAX_LENGTH)
        expect(name.length).to eq(64)
      end
    end

    context "with an empty task name" do
      it "uses the default prefix" do
        task = build_task("", "cron(0 0 * * ? *)", [%w[echo hello]])
        name = scheduler.schedule_name(task, option)

        expect(name).to start_with("#{described_class::DEFAULT_SCHEDULE_PREFIX}-")
        expect(name.length).to be <= 64
      end
    end

    context "with special characters in task name" do
      it "sanitizes non-alphanumeric characters to underscores" do
        task = build_task("my task@v2!", "cron(0 0 * * ? *)", [%w[run]])
        name = scheduler.schedule_name(task, option)

        prefix = name.split("-", 2).first
        expect(prefix).to eq("my_task_v2_")
      end
    end

    context "with the same inputs" do
      it "produces deterministic names" do
        task = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        name1 = scheduler.schedule_name(task, option)
        name2 = scheduler.schedule_name(task, option)

        expect(name1).to eq(name2)
      end
    end

    context "with different inputs" do
      it "produces different hashes" do
        task1 = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        task2 = build_task("deploy", "cron(0 12 * * ? *)", [%w[deploy run]])
        name1 = scheduler.schedule_name(task1, option)
        name2 = scheduler.schedule_name(task2, option)

        expect(name1).not_to eq(name2)
      end
    end
  end

  describe "#fetch_all_schedules (private)" do
    def fetch_all_schedules(group_name)
      scheduler.send(:fetch_all_schedules, group_name)
    end

    context "when all schedules fit in a single page" do
      it "returns all schedules without pagination" do
        schedules = Array.new(5) { |i| double("Schedule#{i}") }
        page = double(schedules: schedules, next_token: nil)

        expect(scheduler_client).to receive(:list_schedules)
          .with({ group_name: "test-group", max_results: described_class::PAGINATION_MAX_RESULTS })
          .once
          .and_return(page)

        result = fetch_all_schedules("test-group")
        expect(result).to eq(schedules)
        expect(result.length).to eq(5)
      end
    end

    context "when schedules span multiple pages" do
      it "fetches all schedules across pages" do
        page1_schedules = Array.new(100) { |i| double("ScheduleP1_#{i}") }
        page2_schedules = Array.new(50) { |i| double("ScheduleP2_#{i}") }
        page1 = double(schedules: page1_schedules, next_token: "token1")
        page2 = double(schedules: page2_schedules, next_token: nil)

        expect(scheduler_client).to receive(:list_schedules)
          .with({ group_name: "test-group", max_results: described_class::PAGINATION_MAX_RESULTS })
          .once
          .and_return(page1)
        expect(scheduler_client).to receive(:list_schedules)
          .with({ group_name: "test-group", max_results: described_class::PAGINATION_MAX_RESULTS, next_token: "token1" })
          .once
          .and_return(page2)

        result = fetch_all_schedules("test-group")
        expect(result.length).to eq(150)
        expect(result).to eq(page1_schedules + page2_schedules)
      end
    end

    context "when there are no schedules" do
      it "returns an empty array" do
        page = double(schedules: [], next_token: nil)

        expect(scheduler_client).to receive(:list_schedules)
          .with({ group_name: "test-group", max_results: described_class::PAGINATION_MAX_RESULTS })
          .once
          .and_return(page)

        result = fetch_all_schedules("test-group")
        expect(result).to eq([])
      end
    end

    context "when pagination exceeds maximum pages" do
      it "raises an error" do
        infinite_page = double(schedules: [double("Schedule")], next_token: "next")

        allow(scheduler_client).to receive(:list_schedules).and_return(infinite_page)
        stub_const("#{described_class}::PAGINATION_MAX_PAGES", 3)

        expect { fetch_all_schedules("test-group") }
          .to raise_error(RuntimeError, /Exceeded maximum pagination pages/)
      end
    end
  end

  describe "#create_schedule" do
    let(:option) do
      double("Option", key: "test-key", scheduler_group: "test-group", rule_state: "ENABLED", iam_role: "test-role")
    end
    let(:task) { double("Task", name: "my_task", expression: "cron(0 0 * * ? *)", commands: [%w[rake run]]) }
    let(:target) { double("TargetLambda", task: task, arn: "arn:aws:lambda:us-east-1:123:function:test", input: "{}") }
    let(:iam_role) { double("IamRole", arn: "arn:aws:iam::123:role/test") }

    before do
      allow(LambdaWhenever::IamRole).to receive(:new).and_return(iam_role)
    end

    context "when the API call succeeds" do
      it "creates a schedule with correct parameters" do
        expect(scheduler_client).to receive(:create_schedule).with(hash_including(
                                                                     name: anything,
                                                                     schedule_expression: "cron(0 0 * * ? *)",
                                                                     schedule_expression_timezone: "UTC",
                                                                     flexible_time_window: described_class::FLEXIBLE_TIME_WINDOW,
                                                                     group_name: "test-group",
                                                                     state: "ENABLED"
                                                                   ))

        scheduler.create_schedule(target, option)
      end
    end

    context "when ValidationException is raised" do
      it "logs the error and re-raises" do
        allow(scheduler_client).to receive(:create_schedule)
          .and_raise(Aws::Scheduler::Errors::ValidationException.new(nil, "Invalid cron expression"))

        expect(LambdaWhenever::Logger.instance).to receive(:fail)
          .with(/Invalid schedule parameters.*Invalid cron expression/)

        expect do
          scheduler.create_schedule(target, option)
        end.to raise_error(Aws::Scheduler::Errors::ValidationException)
      end
    end

    context "when ConflictException is raised" do
      it "does not catch the error (lets it bubble to CLI retry handler)" do
        allow(scheduler_client).to receive(:create_schedule)
          .and_raise(Aws::Scheduler::Errors::ConflictException.new(nil, "Concurrent modification"))

        expect(LambdaWhenever::Logger.instance).not_to receive(:fail)

        expect do
          scheduler.create_schedule(target, option)
        end.to raise_error(Aws::Scheduler::Errors::ConflictException)
      end
    end
  end

  describe "#update_schedule" do
    let(:option) do
      double("Option", key: "test-key", scheduler_group: "test-group", rule_state: "ENABLED", iam_role: "test-role")
    end
    let(:task) { double("Task", name: "my_task", expression: "cron(0 0 * * ? *)", commands: [%w[rake run]]) }
    let(:target) { double("TargetLambda", task: task, arn: "arn:aws:lambda:us-east-1:123:function:test", input: "{}") }
    let(:iam_role) { double("IamRole", arn: "arn:aws:iam::123:role/test") }

    before do
      allow(LambdaWhenever::IamRole).to receive(:new).and_return(iam_role)
    end

    context "when the API call succeeds" do
      it "updates a schedule with correct parameters" do
        expect(scheduler_client).to receive(:update_schedule).with(hash_including(
                                                                     name: anything,
                                                                     schedule_expression: "cron(0 0 * * ? *)",
                                                                     schedule_expression_timezone: "UTC",
                                                                     flexible_time_window: described_class::FLEXIBLE_TIME_WINDOW,
                                                                     group_name: "test-group",
                                                                     state: "ENABLED"
                                                                   ))

        scheduler.update_schedule(target, option)
      end
    end

    context "when ValidationException is raised" do
      it "logs the error and re-raises" do
        allow(scheduler_client).to receive(:update_schedule)
          .and_raise(Aws::Scheduler::Errors::ValidationException.new(nil, "Invalid cron expression"))

        expect(LambdaWhenever::Logger.instance).to receive(:fail)
          .with(/Invalid schedule parameters.*Invalid cron expression/)

        expect do
          scheduler.update_schedule(target, option)
        end.to raise_error(Aws::Scheduler::Errors::ValidationException)
      end
    end

    context "when ConflictException is raised" do
      it "does not catch the error (lets it bubble to CLI retry handler)" do
        allow(scheduler_client).to receive(:update_schedule)
          .and_raise(Aws::Scheduler::Errors::ConflictException.new(nil, "Concurrent modification"))

        expect(LambdaWhenever::Logger.instance).not_to receive(:fail)

        expect do
          scheduler.update_schedule(target, option)
        end.to raise_error(Aws::Scheduler::Errors::ConflictException)
      end
    end
  end

  describe "#list_schedules" do
    context "with pagination" do
      it "retrieves all schedules across multiple pages" do
        schedule1 = double("S1", name: "sched1", state: "ENABLED")
        schedule2 = double("S2", name: "sched2", state: "ENABLED")
        page1 = double(schedules: [schedule1], next_token: "token")
        page2 = double(schedules: [schedule2], next_token: nil)

        allow(scheduler_client).to receive(:list_schedules).and_return(page1, page2)

        detail1 = double(schedule_expression: "cron(0 0 * * ? *)", description: "task1")
        detail2 = double(schedule_expression: "cron(0 12 * * ? *)", description: "task2")
        allow(scheduler_client).to receive(:get_schedule)
          .with({ group_name: "test-group", name: "sched1" }).and_return(detail1)
        allow(scheduler_client).to receive(:get_schedule)
          .with({ group_name: "test-group", name: "sched2" }).and_return(detail2)

        result = scheduler.list_schedules("test-group")
        expect(result.length).to eq(2)
        expect(result[0]).to eq({ name: "sched1", state: "ENABLED",
                                  expression: "cron(0 0 * * ? *)", description: "task1" })
        expect(result[1]).to eq({ name: "sched2", state: "ENABLED",
                                  expression: "cron(0 12 * * ? *)", description: "task2" })
      end
    end

    context "with a single page" do
      it "retrieves schedules without pagination" do
        schedule = double("S", name: "sched1", state: "ENABLED")
        page = double(schedules: [schedule], next_token: nil)

        allow(scheduler_client).to receive(:list_schedules).and_return(page)

        detail = double(schedule_expression: "cron(0 0 * * ? *)", description: "task1")
        allow(scheduler_client).to receive(:get_schedule)
          .with({ group_name: "test-group", name: "sched1" }).and_return(detail)

        result = scheduler.list_schedules("test-group")
        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq("sched1")
      end
    end
  end

  describe "#clean_up_schedules" do
    context "with pagination" do
      it "deletes all schedules across multiple pages" do
        schedule1 = double("S1", name: "sched1")
        schedule2 = double("S2", name: "sched2")
        page1 = double(schedules: [schedule1], next_token: "token")
        page2 = double(schedules: [schedule2], next_token: nil)

        allow(scheduler_client).to receive(:list_schedules).and_return(page1, page2)
        expect(scheduler_client).to receive(:delete_schedule)
          .with({ name: "sched1", group_name: "test-group" })
        expect(scheduler_client).to receive(:delete_schedule)
          .with({ name: "sched2", group_name: "test-group" })

        scheduler.clean_up_schedules("test-group")
      end
    end

    context "with no schedules" do
      it "does not call delete_schedule" do
        page = double(schedules: [], next_token: nil)

        allow(scheduler_client).to receive(:list_schedules).and_return(page)
        expect(scheduler_client).not_to receive(:delete_schedule)

        scheduler.clean_up_schedules("test-group")
      end
    end
  end

  describe "#sync_schedules" do
    let(:option) do
      double("Option", key: "test-key", scheduler_group: "test-group", rule_state: "ENABLED", iam_role: "test-role")
    end
    let(:iam_role) { double("IamRole", arn: "arn:aws:iam::123:role/test") }

    before do
      allow(LambdaWhenever::IamRole).to receive(:new).and_return(iam_role)
    end

    context "when create_schedule fails with a non-ConflictException" do
      it "collects errors, continues processing, and raises after all attempts" do
        task1 = double("Task1", name: "task1", expression: "cron(0 0 * * ? *)", commands: [%w[rake run1]])
        task2 = double("Task2", name: "task2", expression: "cron(0 12 * * ? *)", commands: [%w[rake run2]])
        target1 = double("Target1", task: task1, arn: "arn1", input: "{}")
        target2 = double("Target2", task: task2, arn: "arn2", input: "{}")

        desired = [
          { name: "task1-hash1", target: target1 },
          { name: "task2-hash2", target: target2 }
        ]
        current = []

        call_count = 0
        allow(scheduler_client).to receive(:create_schedule) do
          call_count += 1
          raise Aws::Scheduler::Errors::ValidationException.new(nil, "Invalid") if call_count == 1
        end

        expect do
          scheduler.sync_schedules(desired, current, option)
        end.to raise_error(Aws::Scheduler::Errors::ValidationException)
        expect(call_count).to eq(2)
      end
    end

    context "when create_schedule fails with ConflictException" do
      it "immediately re-raises for CLI retry handler" do
        task = double("Task", name: "task1", expression: "cron(0 0 * * ? *)", commands: [%w[rake run]])
        target = double("Target", task: task, arn: "arn1", input: "{}")

        desired = [{ name: "task1-hash1", target: target }]
        current = []

        allow(scheduler_client).to receive(:create_schedule)
          .and_raise(Aws::Scheduler::Errors::ConflictException.new(nil, "Concurrent modification"))

        expect do
          scheduler.sync_schedules(desired, current, option)
        end.to raise_error(Aws::Scheduler::Errors::ConflictException)
      end
    end

    context "when all operations succeed" do
      it "does not raise any error" do
        task = double("Task", name: "task1", expression: "cron(0 0 * * ? *)", commands: [%w[rake run]])
        target = double("Target", task: task, arn: "arn1", input: "{}")

        desired = [{ name: "task1-hash1", target: target }]
        current = []

        allow(scheduler_client).to receive(:create_schedule)

        expect do
          scheduler.sync_schedules(desired, current, option)
        end.not_to raise_error
      end
    end

    context "when an existing schedule differs" do
      it "calls update_schedule instead of delete+create" do
        task = double("Task", name: "task1", expression: "cron(0 12 * * ? *)", commands: [%w[rake run]])
        target = double("Target", task: task, arn: "arn1", input: "{}")

        desired = [{ name: "task1-hash1", target: target }]
        current = [{ name: "task1-hash1", expression: "cron(0 0 * * ? *)",
                     description: task.commands.to_s, state: "ENABLED" }]

        expect(scheduler_client).to receive(:update_schedule).once
        expect(scheduler_client).not_to receive(:create_schedule)
        expect(scheduler_client).not_to receive(:delete_schedule)

        scheduler.sync_schedules(desired, current, option)
      end
    end

    context "when update_schedule fails with a non-ConflictException" do
      it "collects errors, continues processing, and raises after all attempts" do
        task1 = double("Task1", name: "task1", expression: "cron(0 12 * * ? *)", commands: [%w[rake run1]])
        task2 = double("Task2", name: "task2", expression: "cron(0 18 * * ? *)", commands: [%w[rake run2]])
        target1 = double("Target1", task: task1, arn: "arn1", input: "{}")
        target2 = double("Target2", task: task2, arn: "arn2", input: "{}")

        desired = [
          { name: "task1-hash1", target: target1 },
          { name: "task2-hash2", target: target2 }
        ]
        current = [
          { name: "task1-hash1", expression: "cron(0 0 * * ? *)",
            description: task1.commands.to_s, state: "ENABLED" },
          { name: "task2-hash2", expression: "cron(0 0 * * ? *)",
            description: task2.commands.to_s, state: "ENABLED" }
        ]

        call_count = 0
        allow(scheduler_client).to receive(:update_schedule) do
          call_count += 1
          raise Aws::Scheduler::Errors::ValidationException.new(nil, "Invalid") if call_count == 1
        end

        expect do
          scheduler.sync_schedules(desired, current, option)
        end.to raise_error(Aws::Scheduler::Errors::ValidationException)
        expect(call_count).to eq(2)
      end
    end

    context "when update_schedule fails with ConflictException" do
      it "immediately re-raises for CLI retry handler" do
        task = double("Task", name: "task1", expression: "cron(0 12 * * ? *)", commands: [%w[rake run]])
        target = double("Target", task: task, arn: "arn1", input: "{}")

        desired = [{ name: "task1-hash1", target: target }]
        current = [{ name: "task1-hash1", expression: "cron(0 0 * * ? *)",
                     description: task.commands.to_s, state: "ENABLED" }]

        allow(scheduler_client).to receive(:update_schedule)
          .and_raise(Aws::Scheduler::Errors::ConflictException.new(nil, "Concurrent modification"))

        expect do
          scheduler.sync_schedules(desired, current, option)
        end.to raise_error(Aws::Scheduler::Errors::ConflictException)
      end
    end
  end
end
