# frozen_string_literal: true

require_relative "lib/lambda_whenever/version"

Gem::Specification.new do |spec|
  spec.name = "lambda_whenever"
  spec.version = LambdaWhenever::VERSION
  spec.authors = ["toshichanapp"]
  spec.email = ["toshichanapp@gmail.com"]

  spec.summary = "whenever for Amazon EventBridge Scheduler."
  spec.description = "whenever for Amazon EventBridge Scheduler."
  spec.homepage = "https://github.com/toshichanapp/lambda_whenever"
  spec.required_ruby_version = ">= 3.0.0"

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/toshichanapp/lambda_whenever"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "simplecov", "~> 0.21"

  spec.add_dependency "aws-sdk-iam", "~> 1.0"
  spec.add_dependency "aws-sdk-lambda", "~> 1.0"
  spec.add_dependency "aws-sdk-scheduler", "~> 1.0"
  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "bigdecimal", "~> 3.1"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "retryable", "~> 3.0"
  spec.add_dependency "rexml", ">= 0"
end
