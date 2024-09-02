# frozen_string_literal: true

module LambdaWhenever
  # The IamRole class is responsible for interacting with AWS IAM roles.
  class IamRole
    def initialize(option)
      client = option.iam_client
      @resource = Aws::IAM::Resource.new(client: client)
      @role_name = option.iam_role
      @role = resource.role(@role_name)
    end

    def arn
      role&.arn
    end

    def exists?
      !!arn
    rescue Aws::IAM::Errors::NoSuchEntity
      false
    end

    private

    attr_reader :resource, :role
  end
end
