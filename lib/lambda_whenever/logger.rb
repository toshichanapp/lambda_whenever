# frozen_string_literal: true

module LambdaWhenever
  class Logger
    include Singleton

    def fail(message)
      Kernel.warn "[fail] #{message}"
    end

    def warn(message)
      Kernel.warn "[warn] #{message}"
    end

    def log(event, message)
      puts "[#{event}] #{message}"
    end

    def message(message)
      puts "## [message] #{message}"
    end
  end
end
