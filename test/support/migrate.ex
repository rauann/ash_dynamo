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

      global_secondary_indexes = DynamoInfo.global_secondary_indexes(resource)

      global_indexes = Enum.map(global_secondary_indexes, &build_index/1)

      key_spec =
        [{partition_key, :hash}] ++
          if sort_key do
            [{sort_key, :range}]
          else
            []
          end

      # DynamoDB requires all key attributes (table + GSI) in AttributeDefinitions
      gsi_key_attrs =
        global_secondary_indexes
        |> Enum.flat_map(fn index -> [index.partition_key | List.wrap(index.sort_key)] end)
        |> Enum.uniq()

      all_key_attrs =
        key_spec
        |> Enum.map(fn {name, _kind} -> name end)
        |> Enum.concat(gsi_key_attrs)
        |> Enum.uniq()

      attr_defs =
        all_key_attrs
        |> Map.new(fn name ->
          attr = ResourceInfo.attribute(resource, name)
          {name, dynamo_type(attr.type)}
        end)

      ExAws.Dynamo.create_table(
        table,
        key_spec,
        attr_defs,
        nil,
        nil,
        global_indexes,
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

  defp build_index(index) do
    key_schema =
      [%{attribute_name: "#{index.partition_key}", key_type: "HASH"}] ++
        if index.sort_key do
          [%{attribute_name: "#{index.sort_key}", key_type: "RANGE"}]
        else
          []
        end

    %{
      index_name: "#{index.name}",
      key_schema: key_schema,
      projection: %{projection_type: "ALL"}
    }
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
