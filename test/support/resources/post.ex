defmodule AshDynamo.Test.Post do
  use Ash.Resource,
    data_layer: AshDynamo.DataLayer,
    domain: AshDynamo.Test.Domain

  dynamodb do
    table "posts"
    partition_key :email
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:email, :status, :inserted_at, :title]
    end

    update :update do
      accept [:status]
    end
  end

  attributes do
    attribute :email, :string, allow_nil?: false, primary_key?: true
    attribute :status, :string, allow_nil?: false
    attribute :title, :string

    attribute :inserted_at, :string do
      writable? true
      default fn -> DateTime.to_iso8601(DateTime.utc_now()) end
      allow_nil? false
    end
  end
end

defmodule AshDynamo.Test.PostSortKey do
  use Ash.Resource,
    data_layer: AshDynamo.DataLayer,
    domain: AshDynamo.Test.Domain

  dynamodb do
    table "posts_sort_key"
    partition_key :email
    sort_key :inserted_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:email, :status, :inserted_at]
    end

    update :update do
      accept [:status]
    end
  end

  attributes do
    attribute :email, :string, allow_nil?: false, primary_key?: true
    attribute :status, :string, allow_nil?: false

    attribute :inserted_at, :string do
      writable? true
      default fn -> DateTime.to_iso8601(DateTime.utc_now()) end
      allow_nil? false
    end
  end
end
