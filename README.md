# LambdaWhenever

`lambda_whenever` is a Ruby gem that allows you to create schedules with AWS EventBridge Scheduler targeting Lambda functions using the same syntax as the `whenever` gem.
This gem simplifies the management of cron job configurations and enables event-driven batch processing.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lambda_whenever'
```

Or install it manually with Bundler in your Gemfile:

```shell
$ gem install lambda_whenever
```

## Usage

You can use it almost like Whenever. However, please note that you must specify a `--lambda-name` and `--iam-role`.

```shell
$ lambda_whenever --help
Usage: lambda_whenever [options]
        --dryrun                     dry-run
        --update                     Creates and deletes tasks as needed by schedule file
    -c, --clear                      Clear scheduled tasks
    -l, --list                       List scheduled tasks
    -v, --version                    Print version
    -s, --set variables              Example: --set 'environment=staging'
        --lambda-name name           Lambda function name
        --scheduler-group group_name Optionally specify event bridge scheduler group name
    -f, --file schedule_file         Default: config/schedule.rb
        --iam-role name              IAM role name used by EventBridgeScheduler.
        --rule-state state           The state of the EventBridgeScheduler Rule. Default: ENABLED
        --region region              AWS region
    -V, --verbose                    Run rake jobs without --silent
```

### Setting Variables

Lambda Whenever supports setting variables via the `--set` option, similar to [how Whenever does](https://github.com/javan/whenever/wiki/Setting-variables-on-the-fly).

Example:

```shell
lambda_whenever --set 'environment=staging&some_var=foo'
```

```ruby
if @environment == 'staging'
  every '0 1 * * *' do
    rake 'some_task_on_staging'
  end
elsif @some_var == 'foo'
  every '0 10 * * *' do
    rake 'some_task'
  end
end
```

The `@environment` variable defaults to `"production"`.

## How It Works

Lambda Whenever creates an EventBridge Scheduler schedule for each `every` block. Each schedule can have multiple commands.
For example, the following input will generate one schedule with two commands:

```ruby
every '0 0 * * *' do
  rake "hoge:run"
  command "echo 'you can use raw cron syntax too'"
end
```

This will result in:

```shell
cron(0 0 * * ? *) { commands: [["bundle", "exec", "rake", "hoge:run", "--silent"], ["echo", "'you", "can", "use", "raw", "cron", "syntax", "too'"]] }
```

In this example, one EventBridge Scheduler schedule is created, containing both the rake task and the command.
The scheduled task's name is a digest value calculated from an cron expression, commands, and other parameters.

## Prerequisites

Before using this gem, ensure that you have the necessary IAM policies set up for EventBridge to invoke your Lambda functions.

### IAM Policies for Executing the Gem

To use this gem, the executing entity (e.g., GitHub Actions, CI/CD pipelines, or other automated systems)
must have the necessary IAM policies to register schedules with EventBridge and obtain Lambda ARNs.
The following policy grants the required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "scheduler:CreateScheduleGroup",
        "scheduler:ListSchedules",
        "scheduler:GetSchedule",
        "scheduler:CreateSchedule",
        "scheduler:DeleteSchedule",
        "scheduler:UpdateSchedule",
        "lambda:ListFunctions",
        "lambda:GetFunction"
      ],
      "Resource": "*"
    }
  ]
}
```

### Assume Role Policy for EventBridge

You need an IAM role that allows EventBridge to assume the role and invoke your Lambda functions.
The following policy should be attached to the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "scheduler.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<your account id>"
        }
      }
    }
  ]
}
```

### Execute Lambda Policy

You also need a policy that allows EventBridge to execute your Lambda functions. Attach the following policy to the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": [
        "<your lambda arn>:*",
        "<your lambda arn>"
      ]
    }
  ]
}
```

## Compatibility with Whenever

### Timezone Configuration

In `lambda_whenever`, setting the timezone is slightly different from the traditional `whenever` gem.
Instead of using `env "CRON_TZ", <zone>`, you should use the `set :timezone, <zone>` syntax to specify the timezone for your scheduled tasks.

Example:

```ruby
set :timezone, "Asia/Tokyo"
```

### Methods

Whenever supports custom job types with `job_type`, `env`, and `job_template` methods, but Lambda Whenever does not support these.

### mailto

Whenever supports the `mailto` method, but Lambda Whenever does not.
Amazon EventBridge Scheduler does not natively support email notifications.
As a result, the `mailto` option is not available in this gem.

### Frequency

Lambda Whenever processes the frequency passed to the `every` block similarly to Whenever.

#### `:reboot`

Whenever supports `:reboot` as a cron option, but Lambda Whenever does not support it.

### Bundle Commands

Whenever checks if the application uses Bundler and automatically adds a prefix to commands.
However, Lambda Whenever always adds a prefix, assuming the application is using Bundler.

```ruby
# Whenever
#   With bundler    -> bundle exec rake hoge:run
#   Without bundler -> rake hoge:run
#
# Lambda Whenever
#   bundle exec rake hoge:run
#
rake "hoge:run"
```

If you don't want to add the prefix, set `bundle_command` to an empty string as follows:

```ruby
set :bundle_command, ""
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/toshichanapp/lambda_whenever](https://github.com/toshichanapp/lambda_whenever).

## License

The gem is available as open-source under the terms of the MIT License.

## Acknowledgement

This gem is inspired by and built upon the work of the [whenever](https://github.com/javan/whenever) and [elastic_whenever](https://github.com/wata727/elastic_whenever) gems. We would like to express our gratitude to the developers and contributors of these projects for their foundational work and contributions to the Ruby community.
