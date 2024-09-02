# frozen_string_literal: true

module LambdaWhenever
  class Task
    attr_reader :commands, :expression

    def initialize(environment, verbose, bundle_command, expression)
      @environment = environment
      @verbose_mode = verbose ? nil : "--silent"
      @bundle_command = bundle_command.split(" ")
      @expression = expression
      @commands = []
    end

    def command(task)
      @commands << task.split(" ")
    end

    def rake(task)
      @commands << [@bundle_command, "rake", task, @verbose_mode].flatten.compact
    end

    def runner(src)
      @commands << [@bundle_command, "rails", "runner", "-e", @environment, src].flatten
    end

    def script(script)
      @commands << [@bundle_command, "script/#{script}"].flatten
    end

    def method_missing(name, *_args)
      Logger.instance.warn("Skipping unsupported method: #{name}")
    end
  end
end
