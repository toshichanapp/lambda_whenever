# frozen_string_literal: true

require "spec_helper"
require "lambda_whenever/whenever_numeric"

RSpec.describe LambdaWhenever::WheneverNumeric do
  using LambdaWhenever::WheneverNumeric

  describe "seconds" do
    it "returns the value unchanged" do
      expect(30.seconds).to eq(30)
    end

    it "supports singular form" do
      expect(1.second).to eq(1)
    end
  end

  describe "minutes" do
    it "converts to seconds" do
      expect(5.minutes).to eq(300)
    end

    it "supports singular form" do
      expect(1.minute).to eq(60)
    end
  end

  describe "hours" do
    it "converts to seconds" do
      expect(2.hours).to eq(7200)
    end

    it "supports singular form" do
      expect(1.hour).to eq(3600)
    end
  end

  describe "days" do
    it "converts to seconds" do
      expect(1.day).to eq(86_400)
    end

    it "supports plural form" do
      expect(3.days).to eq(259_200)
    end
  end

  describe "weeks" do
    it "converts to seconds" do
      expect(1.week).to eq(604_800)
    end

    it "supports plural form" do
      expect(2.weeks).to eq(1_209_600)
    end
  end

  describe "months" do
    it "converts to seconds (30 days)" do
      expect(1.month).to eq(2_592_000)
    end

    it "supports plural form" do
      expect(6.months).to eq(15_552_000)
    end
  end

  describe "years" do
    it "converts to seconds (365.25 days)" do
      expect(1.year).to eq(31_557_600)
    end
  end

  describe "chaining" do
    it "allows numeric comparisons" do
      expect(1.hour).to be > 59.minutes
      expect(1.day).to be > 23.hours
    end
  end
end
