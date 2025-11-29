defmodule AshDynamo.DataLayer.Info do
  @moduledoc """
  Introspection helpers for the Ash DynamoDB data layer.

  These functions are thin wrappers around the resource DSL configuration.
  """

  alias Spark.Dsl.Extension

  @doc "Table name for the resource, defaulting to the underscored module name."
  @spec table(Ash.Resource.t() | Spark.Dsl.t()) :: String.t()
  def table(resource) do
    Extension.get_opt(resource, [:dynamodb], :table, default_table(resource), true)
  end

  @doc "Partition (hash) key attribute name."
  @spec partition_key(Ash.Resource.t() | Spark.Dsl.t()) :: atom | nil
  def partition_key(resource) do
    Extension.get_opt(resource, [:dynamodb], :partition_key, nil, true)
  end

  @doc "Sort (range) key attribute name, if any."
  @spec sort_key(Ash.Resource.t() | Spark.Dsl.t()) :: atom | nil
  def sort_key(resource) do
    Extension.get_opt(resource, [:dynamodb], :sort_key, nil, true)
  end

  @doc "Global secondary index definitions."
  @spec global_secondary_indexes(Ash.Resource.t() | Spark.Dsl.t()) :: list
  def global_secondary_indexes(resource) do
    Extension.get_opt(resource, [:dynamodb], :global_secondary_indexes, [], true)
  end

  @doc "Local secondary index definitions."
  @spec local_secondary_indexes(Ash.Resource.t() | Spark.Dsl.t()) :: list
  def local_secondary_indexes(resource) do
    Extension.get_opt(resource, [:dynamodb], :local_secondary_indexes, [], true)
  end

  defp default_table(resource) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end
end
