defmodule AshDynamo.DataLayer do
  @moduledoc """
  DynamoDB data layer scaffold for Ash.

  This wires in a `dynamodb` DSL section on resources so you can declare how a
  resource maps to a table. Introspection helpers live in
  `AshDynamo.DataLayer.Info`.
  """

  @behaviour Ash.DataLayer

  alias AshDynamo.DataLayer.Info

  @dynamodb %Spark.Dsl.Section{
    name: :dynamodb,
    describe: "Configure the DynamoDB table backing this resource for querying.",
    examples: [
      """
      dynamodb do
        table "users"
        partition_key :email
        sort_key :inserted_at
      end
      """
    ],
    schema: [
      table: [
        type: :string,
        doc: "Table name to read from/write to. Defaults to the underscored resource name."
      ],
      partition_key: [
        type: :atom,
        required: true,
        doc: "Required partition (hash) key attribute name."
      ],
      sort_key: [
        type: :atom,
        default: nil,
        doc: "Optional sort (range) key attribute name."
      ],
      global_secondary_indexes: [
        type: {:list, :any},
        default: [],
        doc: "GSI definitions (shape matches ExAws.Dynamo expectations; used for query planning)."
      ],
      local_secondary_indexes: [
        type: {:list, :any},
        default: [],
        doc: "LSI definitions (shape matches ExAws.Dynamo expectations; used for query planning)."
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@dynamodb]

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :domain
    ]
  end

  # --- Capabilities --------------------------------------------------------
  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :update), do: true
  def can?(_, _), do: false

  # --- Query shaping ------------------------------------------------------
  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  # --- Execution ----------------------------------------------------------
  @impl true
  def run_query(%Query{} = _query, resource) do
    table = Info.table(resource)

    ExAws.Dynamo.scan(table)
    |> ExAws.request()
    |> case do
      {:ok, resp} -> {:ok, ExAws.Dynamo.decode_item(resp, as: resource)}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def create(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      insert_item(resource, changeset, schema)
    end
  end

  @impl true
  def update(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      update_item(resource, changeset, schema, :update)
    end
  end

  defp update_item(resource, changeset, schema, mode) do
    attrs = prepare_attrs(schema, Map.keys(changeset.attributes))
    pk = get_pk(resource)
    sk = get_sk(resource)
    pk_atom = String.to_atom(pk)
    sk_atom = sk && String.to_atom(sk)

    key =
      %{"#{pk}" => Map.get(schema, pk_atom)}
      |> then(fn k -> if sk, do: Map.put(k, sk, Map.get(schema, sk_atom)), else: k end)

    # Build SET expr for non-key fields
    non_keys =
      [pk, sk]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.to_atom/1)
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

    # UpdateItem in Dynamo is an upsert by default. Calling it with a key that doesn’t exist,
    # it will create the item. The attribute_exists(#pk) condition is only applied in :update mode.
    # to force “update only”: it fails with a conditional check error if the item isn’t there.
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
      {:ok, %{"Attributes" => attrs}} -> {:ok, ExAws.Dynamo.decode_item(attrs, as: resource)}
      {:error, error} -> {:error, error}
    end
  end

  defp insert_item(resource, changeset, schema) do
    attrs = prepare_attrs(schema, Map.keys(changeset.attributes))
    pk = get_pk(resource)
    sk = get_sk(resource)

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
      {:ok, _resp} -> {:ok, struct(resource, attrs)}
      {:error, error} -> {:error, error}
    end
  end

  defp prepare_attrs(schema, allowed_keys) do
    schema
    |> Map.from_struct()
    |> Map.take(allowed_keys)
  end

  defp get_pk(resource), do: resource |> Info.partition_key() |> to_string()
  defp get_sk(resource), do: resource |> Info.sort_key() |> then(&if &1, do: to_string(&1))

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
