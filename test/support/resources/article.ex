defmodule AshDynamo.Test.Article do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshDynamo.DataLayer,
    domain: AshDynamo.Test.Domain

  dynamodb do
    table "articles"
    partition_key :slug
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:slug, :title, :tags]
    end
  end

  attributes do
    attribute :slug, :string, primary_key?: true, allow_nil?: false
    attribute :title, :string, allow_nil?: false
    attribute :tags, {:array, AshDynamo.Test.Types.Tag}, allow_nil?: false, default: []
  end
end
