defmodule AshDynamo.Test.User do
  use Ash.Resource,
    data_layer: AshDynamo.DataLayer,
    domain: AshDynamo.Test.Domain

  dynamodb do
    table "users"
    partition_key(:email)
    sort_key(:inserted_at)
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:email, :status, :phone, :inserted_at]
    end
  end

  attributes do
    attribute :email, :string, allow_nil?: false, primary_key?: true
    attribute :status, :string, allow_nil?: false
    attribute :phone, :string
    attribute :inserted_at, :string, allow_nil?: false
  end
end
