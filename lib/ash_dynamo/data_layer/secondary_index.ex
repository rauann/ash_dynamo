defmodule AshDynamo.DataLayer.SecondaryIndex do
  @moduledoc """
  Struct representing a secondary index (GSI or LSI) definition.

  Built automatically by the Spark DSL from `global_secondary_index` and
  `local_secondary_index` blocks inside the `dynamodb` section.

  The `:type` field is auto-set by the entity definition:
  - `:global` for Global Secondary Indexes
  - `:local` for Local Secondary Indexes

  Projection is always `ALL` — every index includes all table attributes.
  """

  defstruct [
    :name,
    :type,
    :partition_key,
    :sort_key,
    __spark_metadata__: nil
  ]
end
