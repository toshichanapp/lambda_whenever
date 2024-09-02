# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::TargetLambda do
  let(:client) { double("Aws::Lambda::Client") }
  let(:task) do
    double("Task", commands: %w[bundle exec rake spec])
  end
  let(:function_arn) { "arn:aws:lambda:us-east-1:123456789:function:my-function" }

  before do
    allow(Aws::Lambda::Client).to receive(:new).and_return(client)
  end

  describe ".fetch_arn" do
    let(:client) { instance_double(Aws::Lambda::Client) }
    let(:function_name) { "my-function" }
    let(:response) do
      double("response",
             configuration: double("configuration",
                                   function_arn: "arn:aws:lambda:us-east-1:123456789:function:my-function"))
    end

    before do
      allow(Aws::Lambda::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_function).with({ function_name: function_name }).and_return(response)
    end

    it "fetches the lambda ARN" do
      arn = described_class.fetch_arn(function_name, client)
      expect(arn).to eq("arn:aws:lambda:us-east-1:123456789:function:my-function")
    end
  end

  describe "#initialize" do
    subject { described_class.new(arn: function_arn, task: task) }

    it "initializes with the correct attributes" do
      expect(subject.arn).to eq(function_arn)
      expect(subject.task).to eq(task)
    end
  end

  describe "#input_json" do
    subject { described_class.new(arn: function_arn, task: task) }

    it "returns the correct JSON input" do
      expected_json = {
        execution_id: "<aws.scheduler.execution-id>",
        scheduled_time: "<aws.scheduler.scheduled-time>",
        schedule_arn: "<aws.scheduler.schedule-arn>",
        attempt_number: "<aws.scheduler.attempt-number>",
        commands: %w[bundle exec rake spec]
      }.to_json

      expect(subject.input_json).to eq(expected_json)
    end
  end
end
