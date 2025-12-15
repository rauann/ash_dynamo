defmodule AshDynamo.Test.Migrate do
  @moduledoc false

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshDynamo.DataLayer.Info, as: DynamoInfo

  def create! do
    Enum.each(resources(), fn resource ->
      table = DynamoInfo.table(resource)

      partition_key =
        DynamoInfo.partition_key(resource) ||
          raise "Partition key is required for #{inspect(resource)}"

      sort_key = DynamoInfo.sort_key(resource)

      key_spec =
        [{partition_key, :hash}] ++
          if sort_key do
            [{sort_key, :range}]
          else
            []
          end

      attr_defs =
        key_spec
        |> Enum.map(fn {name, _kind} ->
          attr = ResourceInfo.attribute(resource, name)
          {name, dynamo_type(attr.type)}
        end)
        |> Map.new()

      ExAws.Dynamo.create_table(
        table,
        key_spec,
        attr_defs,
        nil,
        nil,
        [],
        [],
        :pay_per_request
      )
      |> ExAws.request!()
    end)
  end

  def drop! do
    Enum.each(resources(), fn resource ->
      table = DynamoInfo.table(resource)

      table
      |> ExAws.Dynamo.delete_table()
      |> ExAws.request!()
    end)
  end

  defp resources, do: Ash.Domain.Info.resources(AshDynamo.Test.Domain)

  @dynamo_types %{
    string: :string,
    uuid: :string,
    integer: :number,
    float: :number,
    decimal: :number,
    utc_datetime: :string,
    naive_datetime: :string,
    date: :string,
    binary: :binary
  }

  defp dynamo_type(type) do
    storage_type = Ash.Type.storage_type(type)

    Map.get_lazy(@dynamo_types, storage_type, fn ->
      raise "Unsupported partition/sort key type #{inspect(type)} (storage: #{inspect(storage_type)})"
    end)
  end
end
