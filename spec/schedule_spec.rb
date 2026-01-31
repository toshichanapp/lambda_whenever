# frozen_string_literal: true

require "spec_helper"
require "lambda_whenever/whenever_numeric"
require "tempfile"

RSpec.describe LambdaWhenever::Schedule do
  using LambdaWhenever::WheneverNumeric
  let(:schedule) { LambdaWhenever::Schedule.new(Pathname(__dir__).join("fixtures/schedule.rb").to_s, false, []) }

  describe "#initialize" do
    it "has attributes" do
      expect(schedule).to have_attributes(chronic_options: {})
    end

    context "when received variables from CLI" do
      let(:schedule) do
        LambdaWhenever::Schedule.new(Pathname(__dir__).join("fixtures/schedule.rb").to_s, false,
                                     [{ key: "environment", value: "staging" }])
      end

      it "overrides attributes" do
        expect(schedule.instance_variable_get(:@environment)).to eq "staging"
      end
    end

    context "when received verbose from CLI" do
      let(:schedule) { LambdaWhenever::Schedule.new(Pathname(__dir__).join("fixtures/schedule.rb").to_s, true, []) }

      it "sets verbose flag" do
        expect(schedule.instance_variable_get(:@verbose)).to be true
      end
    end

    it "has tasks" do
      expect(schedule.tasks.count).to eq(2)
      expect(schedule.tasks[0]).to have_attributes(
        expression: "cron(0 3 * * ? *)",
        commands: [
          %w[bundle exec rails runner -e production Hoge.run]
        ]
      )
      expect(schedule.tasks[1]).to have_attributes(
        expression: "cron(0 0 1 * ? *)",
        commands: [
          %w[bundle exec rake hoge:run --silent],
          %w[bundle exec rails runner -e production Fuga.run]
        ]
      )
    end

    context "when using unsupported method" do
      let(:schedule) do
        LambdaWhenever::Schedule.new(Pathname(__dir__).join("fixtures/unsupported_schedule.rb").to_s, false, [])
      end

      it "does not have tasks" do
        expect(schedule.tasks.count).to eq(0)
      end
    end
  end

  describe "WheneverNumeric" do
    before do
      allow(File).to receive(:read).and_return(file)
    end

    context "when using 1.minute" do
      let(:file) do
        <<~FILE
          every 1.minute do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(* * * * ? *)")
      end
    end

    context "when using 5.minutes" do
      let(:file) do
        <<~FILE
          every 5.minutes do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0,5,10,15,20,25,30,35,40,45,50,55 * * * ? *)")
      end
    end

    context "when using 1.hour" do
      let(:file) do
        <<~FILE
          every 1.hour do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0 * * * ? *)")
      end
    end

    context "when using 1.day" do
      let(:file) do
        <<~FILE
          every 1.day do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0 0 * * ? *)")
      end
    end

    context "when using 1.week" do
      let(:file) do
        <<~FILE
          every 1.week do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0 0 1,8,15,22,29 * ? *)")
      end
    end

    context "when using 1.month" do
      let(:file) do
        <<~FILE
          every 1.month do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0 0 1 * ? *)")
      end
    end

    context "when using 1.year" do
      let(:file) do
        <<~FILE
          every 1.year do
            rake "hoge:run"
          end
        FILE
      end

      it "has expression" do
        expect(schedule.tasks.first).to have_attributes(expression: "cron(0 0 1 1 ? *)")
      end
    end
  end

  describe "#set" do
    it "sets allowed key value" do
      expect do
        schedule.set("environment", "staging")
      end.to change { schedule.instance_variable_get("@environment") }.from("production").to("staging")
    end

    it "does not set `tasks` value" do
      expect do
        schedule.set("tasks", "some value")
      end.not_to(change { schedule.tasks })
    end

    it "sets non-standard key with warning" do
      logger = LambdaWhenever::Logger.instance
      expect(logger).to receive(:warn).with(/non-standard key/)
      schedule.set("foo", "bar")
      expect(schedule.instance_variable_get("@foo")).to eq("bar")
    end

    it "accepts symbol keys" do
      schedule.set(:environment, "staging")
      expect(schedule.environment).to eq("staging")
    end
  end

  describe "#schedule_expressions" do
    it "converts from cron syntax" do
      expect(schedule.schedule_expressions("0 0 * * *", {})).to eq ["cron(0 0 * * ? *)"]
    end

    it "converts from cron syntax specified week" do
      expect(schedule.schedule_expressions("0 0 * * 0,1,2,3,4,5,6", {})).to eq ["cron(0 0 ? * 1,2,3,4,5,6,7 *)"]
    end

    it "converts from day shortcuts" do
      expect(schedule.schedule_expressions(:day, {})).to eq ["cron(0 0 * * ? *)"]
    end

    it "converts from day shortcuts with `at` option" do
      schedule.set("chronic_options", { hours24: true })
      expect(schedule.schedule_expressions(:day, at: "2:00")).to eq ["cron(0 2 * * ? *)"]
    end

    it "handles multiple times in `at` option" do
      expect(schedule.schedule_expressions(:day, at: ["12:00", "18:00"])).to eq ["cron(00 12,18 * * ? *)"]
    end

    it "handles multiple times with different minutes in `at` option" do
      expect(schedule.schedule_expressions(:day,
                                           at: ["12:00", "18:10"])).to eq ["cron(00 12 * * ? *)", "cron(10 18 * * ? *)"]
    end

    it "raises an exception when specified unsupported shortcuts" do
      expect do
        schedule.schedule_expressions(:reboot, {})
      end.to raise_error(LambdaWhenever::Schedule::UnsupportedFrequencyException)
    end
  end

  describe "#expression_by_frequency" do
    it "handles :sunday shortcut" do
      expect(schedule.expression_by_frequency(:sunday, {})).to eq ["0", "0", "?", "*", "SUN", "*"]
    end

    it "handles :monday shortcut" do
      expect(schedule.expression_by_frequency(:monday, {})).to eq ["0", "0", "?", "*", "MON", "*"]
    end

    it "handles :tuesday shortcut" do
      expect(schedule.expression_by_frequency(:tuesday, {})).to eq ["0", "0", "?", "*", "TUE", "*"]
    end

    it "handles :wednesday shortcut" do
      expect(schedule.expression_by_frequency(:wednesday, {})).to eq ["0", "0", "?", "*", "WED", "*"]
    end

    it "handles :thursday shortcut" do
      expect(schedule.expression_by_frequency(:thursday, {})).to eq ["0", "0", "?", "*", "THU", "*"]
    end

    it "handles :friday shortcut" do
      expect(schedule.expression_by_frequency(:friday, {})).to eq ["0", "0", "?", "*", "FRI", "*"]
    end

    it "handles :saturday shortcut" do
      expect(schedule.expression_by_frequency(:saturday, {})).to eq ["0", "0", "?", "*", "SAT", "*"]
    end

    it "handles :weekend shortcut" do
      expect(schedule.expression_by_frequency(:weekend, {})).to eq ["0", "0", "?", "*", "SUN,SAT", "*"]
    end

    it "handles :weekday shortcut" do
      expect(schedule.expression_by_frequency(:weekday, {})).to eq ["0", "0", "?", "*", "MON-FRI", "*"]
    end

    it "raises exception for frequencies less than a minute" do
      expect do
        schedule.expression_by_frequency(30.seconds, {})
      end.to raise_error(LambdaWhenever::Schedule::UnsupportedFrequencyException,
                         "Time must be in minutes or higher. Ignore this task.")
    end

    it "raises exception for frequencies of 12 months or more" do
      expect do
        schedule.expression_by_frequency(12.months, {})
      end.to raise_error(LambdaWhenever::Schedule::UnsupportedFrequencyException,
                         "Time must be in months or lower. Ignore this task.")
    end

    it "handles complex cron expressions with year field" do
      expect(schedule.expression_by_frequency("0 0 1 * ? 2023", {})).to eq ["0", "0", "1", "*", "?", "2023"]
    end

    it "handles specific cron expressions with L, W, and ?" do
      expect(schedule.expression_by_frequency("0 12 L * ? *", {})).to eq ["0", "12", "L", "*", "?", "*"]
    end
  end

  describe "#print_tasks" do
    it "prints tasks to stdout" do
      expect { schedule.print_tasks }.to output(
        "cron(0 3 * * ? *) { commands: [[\"bundle\", \"exec\", \"rails\", \"runner\", \"-e\", \"production\", \"Hoge.run\"]] }\n" \
        "cron(0 0 1 * ? *) { commands: [[\"bundle\", \"exec\", \"rake\", \"hoge:run\", \"--silent\"], [\"bundle\", \"exec\", \"rails\", \"runner\", \"-e\", \"production\", \"Fuga.run\"]] }\n"
      ).to_stdout
    end
  end

  describe "#set security" do
    it "rejects reserved key 'tasks'" do
      original_tasks = schedule.tasks
      schedule.set("tasks", "malicious")
      expect(schedule.tasks).to eq(original_tasks)
    end

    it "allows verbose to be set" do
      schedule.set("verbose", true)
      expect(schedule.instance_variable_get(:@verbose)).to be true
    end

    it "warns about non-standard keys" do
      logger = LambdaWhenever::Logger.instance
      expect(logger).to receive(:warn).with(/non-standard key/)
      schedule.set("custom_key", "value")
    end

    it "allows standard keys without warning" do
      logger = LambdaWhenever::Logger.instance
      expect(logger).not_to receive(:warn)
      schedule.set("environment", "staging")
      expect(schedule.environment).to eq("staging")
    end
  end

  describe "file validation" do
    it "raises error for non-existent file" do
      expect do
        LambdaWhenever::Schedule.new("/nonexistent/file.rb", false, [])
      end.to raise_error(ArgumentError, /does not exist/)
    end

    it "raises error for non-.rb file" do
      Tempfile.create(["schedule", ".txt"]) do |tmpfile|
        expect do
          LambdaWhenever::Schedule.new(tmpfile.path, false, [])
        end.to raise_error(ArgumentError, /must have .rb extension/)
      end
    end

    it "raises error for directory path with .rb extension" do
      Dir.mktmpdir("schedule.rb") do |dir|
        expect do
          LambdaWhenever::Schedule.new(dir, false, [])
        end.to raise_error(ArgumentError, /must be a regular file/)
      end
    end
  end
end
