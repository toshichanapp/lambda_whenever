# frozen_string_literal: true

require "spec_helper"

RSpec.describe LambdaWhenever::Logger do
  let(:logger) { described_class.instance }

  describe "singleton" do
    it "returns the same instance" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#fail" do
    it "outputs fail message to stderr" do
      expect { logger.fail("something failed") }.to output("[fail] something failed\n").to_stderr
    end
  end

  describe "#warn" do
    it "outputs warn message to stderr" do
      expect { logger.warn("be careful") }.to output("[warn] be careful\n").to_stderr
    end
  end

  describe "#log" do
    it "outputs log message to stdout" do
      expect { logger.log("write", "done") }.to output("[write] done\n").to_stdout
    end
  end

  describe "#message" do
    it "outputs message to stdout" do
      expect { logger.message("hello") }.to output("## [message] hello\n").to_stdout
    end
  end
end
