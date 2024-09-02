# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::IamRole do
  let(:resource) { double("resource") }
  let(:option) { LambdaWhenever::Option.new(%w[--iam-role ecsEventsRole]) }
  let(:role_name) { "ecsEventsRole" }
  let(:role) { double(arn: "arn:aws:iam::123456789:role/#{role_name}") }

  before do
    allow(Aws::IAM::Resource).to receive(:new).and_return(resource)
    allow(resource).to receive(:role).with(role_name).and_return(role)
  end

  describe "#initialize" do
    it "has role" do
      expect(LambdaWhenever::IamRole.new(option)).to have_attributes(arn: "arn:aws:iam::123456789:role/ecsEventsRole")
    end

    context "with custom role name" do
      let(:role_name) { "cloudwatch-events-ecs" }
      let(:option) { LambdaWhenever::Option.new(%w[--iam-role cloudwatch-events-ecs]) }

      it "has role" do
        expect(LambdaWhenever::IamRole.new(option)).to have_attributes(arn: "arn:aws:iam::123456789:role/cloudwatch-events-ecs")
      end
    end
  end

  describe "#exists?" do
    it "returns true" do
      expect(LambdaWhenever::IamRole.new(option)).to be_exists
    end

    context "when role not found" do
      before do
        allow(role).to receive(:arn).and_raise(Aws::IAM::Errors::NoSuchEntity.new("context", "error"))
      end

      it "returns false" do
        expect(LambdaWhenever::IamRole.new(option)).not_to be_exists
      end
    end
  end
end
