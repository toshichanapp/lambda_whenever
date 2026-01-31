# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe LambdaWhenever::EventBridgeScheduler do
  let(:scheduler_client) { double("Aws::Scheduler::Client") }
  let(:scheduler) { described_class.new(scheduler_client) }

  describe "#schedule_name (via create_schedule)" do
    let(:option) { double("Option", key: "test-key") }

    def build_task(name, expression, commands)
      double("Task", name: name, expression: expression, commands: commands)
    end

    def compute_schedule_name(task, option)
      scheduler.send(:schedule_name, task, option)
    end

    context "with a normal task name" do
      it "fits within 64 characters" do
        task = build_task("my_task", "cron(0 0 * * ? *)", [%w[bundle exec rake db:migrate]])
        name = compute_schedule_name(task, option)

        expect(name.length).to be <= 64
      end

      it "preserves the full SHA1 hash (40 chars)" do
        task = build_task("my_task", "cron(0 0 * * ? *)", [%w[bundle exec rake db:migrate]])
        name = compute_schedule_name(task, option)
        hash_part = name.split("-", 2).last

        expect(hash_part).to match(/\A[a-f0-9]{40}\z/)
      end

      it "includes the sanitized task name as prefix" do
        task = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        name = compute_schedule_name(task, option)

        expect(name).to start_with("deploy-")
      end
    end

    context "with a long task name" do
      it "truncates the prefix to 23 characters" do
        long_name = "a" * 50
        task = build_task(long_name, "cron(0 0 * * ? *)", [%w[rake run]])
        name = compute_schedule_name(task, option)

        prefix = name.split("-", 2).first
        expect(prefix.length).to eq(described_class::PREFIX_MAX_LENGTH)
        expect(name.length).to eq(64)
      end
    end

    context "with an empty task name" do
      it "uses the default prefix" do
        task = build_task("", "cron(0 0 * * ? *)", [%w[echo hello]])
        name = compute_schedule_name(task, option)

        expect(name).to start_with("#{described_class::DEFAULT_SCHEDULE_PREFIX}-")
        expect(name.length).to be <= 64
      end
    end

    context "with special characters in task name" do
      it "sanitizes non-alphanumeric characters to underscores" do
        task = build_task("my task@v2!", "cron(0 0 * * ? *)", [%w[run]])
        name = compute_schedule_name(task, option)

        prefix = name.split("-", 2).first
        expect(prefix).to eq("my_task_v2_")
      end
    end

    context "with the same inputs" do
      it "produces deterministic names" do
        task = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        name1 = compute_schedule_name(task, option)
        name2 = compute_schedule_name(task, option)

        expect(name1).to eq(name2)
      end
    end

    context "with different inputs" do
      it "produces different hashes" do
        task1 = build_task("deploy", "cron(0 0 * * ? *)", [%w[deploy run]])
        task2 = build_task("deploy", "cron(0 12 * * ? *)", [%w[deploy run]])
        name1 = compute_schedule_name(task1, option)
        name2 = compute_schedule_name(task2, option)

        expect(name1).not_to eq(name2)
      end
    end
  end
end
