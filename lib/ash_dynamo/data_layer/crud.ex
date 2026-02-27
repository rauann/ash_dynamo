defmodule AshDynamo.DataLayer.CRUD do
  @moduledoc """
  Encapsulates DynamoDB write operations — PutItem, UpdateItem, and DeleteItem.
  """

  alias AshDynamo.DataLayer.Info

  @doc """
  Inserts a new item via DynamoDB PutItem.

  Uses a `condition_expression` with `attribute_not_exists` to prevent
  overwriting existing items (duplicate key guard).

  Returns `{:ok, resource}` with the inserted attributes, or `{:error, error}`.
  """
  def insert_item(resource, changeset, schema) do
    attrs = prepare_attrs(schema, Map.keys(changeset.attributes))
    pk = Info.partition_key(resource)
    sk = Info.sort_key(resource)

    item =
      attrs
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    {condition_expression, names} =
      case sk do
        nil ->
          {"attribute_not_exists(#pk)", %{"#pk" => pk}}

        sk ->
          {"attribute_not_exists(#pk) AND attribute_not_exists(#sk)", %{"#pk" => pk, "#sk" => sk}}
      end

    opts = [
      condition_expression: condition_expression,
      expression_attribute_names: names
    ]

    resource
    |> Info.table()
    |> ExAws.Dynamo.put_item(item, opts)
    |> ExAws.request()
    |> case do
      {:ok, _resp} ->
        {:ok, struct(resource, attrs)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Updates an existing item via DynamoDB UpdateItem.

  Builds a `SET` expression for all non-key attributes and uses
  `attribute_exists` condition to ensure the item exists (in `:update` mode).
  In `:upsert` mode, the condition is skipped to allow creating new items.

  Returns `{:ok, resource}` with the final state from `ALL_NEW` return values.
  """
  def update_item(resource, changeset, schema, mode) do
    attrs = prepare_attrs(schema, Map.keys(changeset.attributes))
    pk = Info.partition_key(resource)
    sk = Info.sort_key(resource)
    key = build_item_key(schema, pk, sk)

    # Build SET expr for non-key fields
    non_keys =
      [pk, sk]
      |> Enum.reject(&is_nil/1)
      |> then(&Map.drop(attrs, &1))

    {set_expr, names, values} =
      Enum.with_index(non_keys, 1)
      |> Enum.reduce({"", %{}, %{}}, fn {{k, v}, i}, {expr, n, val} ->
        name = "#k#{i}"
        value = "v#{i}"
        piece = "#{name} = :#{value}"

        {
          if(expr == "", do: "SET " <> piece, else: expr <> ", " <> piece),
          Map.put(n, name, to_string(k)),
          Map.put(val, value, v)
        }
      end)

    # UpdateItem in Dynamo is an upsert by default. Calling it with a key that doesn't exist,
    # it will create the item. The attribute_exists(#pk) condition is only applied in :update mode.
    # To force "update only": it fails with a conditional check error if the item isn't there.
    # In :upsert mode we skip the condition so both create and update are allowed.
    {condition_expression, names} =
      case mode do
        :update -> {"attribute_exists(#pk)", Map.put(names, "#pk", pk)}
        :upsert -> {nil, names}
      end

    # Use return_values: "ALL_NEW" to get the final state back for building the resource struct
    opts =
      [
        update_expression: set_expr,
        expression_attribute_names: names,
        expression_attribute_values: values,
        return_values: "ALL_NEW"
      ]
      |> maybe_put(:condition_expression, condition_expression)

    resource
    |> Info.table()
    |> ExAws.Dynamo.update_item(key, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{"Attributes" => attrs}} ->
        {:ok, ExAws.Dynamo.decode_item(attrs, as: resource)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Deletes an item via DynamoDB DeleteItem.

  Uses a `condition_expression` with `attribute_exists` to ensure the item
  exists before deletion.

  Returns `:ok` on success, or `{:error, error}`.
  """
  def delete_item(resource, schema) do
    pk = Info.partition_key(resource)
    sk = Info.sort_key(resource)
    key = build_item_key(schema, pk, sk)

    {condition_expression, names} =
      case sk do
        nil -> {"attribute_exists(#pk)", %{"#pk" => pk}}
        sk -> {"attribute_exists(#pk) AND attribute_exists(#sk)", %{"#pk" => pk, "#sk" => sk}}
      end

    opts = [
      condition_expression: condition_expression,
      expression_attribute_names: names
    ]

    resource
    |> Info.table()
    |> ExAws.Dynamo.delete_item(key, opts)
    |> ExAws.request()
    |> case do
      {:ok, _resp} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp build_item_key(schema, pk, nil), do: %{"#{pk}" => Map.get(schema, pk)}

  defp build_item_key(schema, pk, sk),
    do: %{"#{pk}" => Map.get(schema, pk), "#{sk}" => Map.get(schema, sk)}

  defp prepare_attrs(schema, allowed_keys) do
    schema
    |> Map.from_struct()
    |> Map.take(allowed_keys)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
