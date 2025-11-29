defmodule AshDynamo.Test.User do
  use Ash.Resource,
    data_layer: AshDynamo.DataLayer,
    domain: AshDynamo.Test.Domain

  dynamodb do
    table "users"
    partition_key(:email)
  end

  actions do
    defaults [:read]

    read :list_users do
      description "List all users from DynamoDB"
    end
  end

  attributes do
    attribute :email, :string, allow_nil?: false, primary_key?: true
    attribute :created_at, :utc_datetime
    attribute :status, :string, allow_nil?: false
  end
end
