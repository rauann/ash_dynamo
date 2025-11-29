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
        default: nil,
        doc: "Optional partition (hash) key attribute name."
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
      update_item(resource, changeset, schema)
    end
  end

  defp update_item(resource, changeset, schema) do
    attrs =
      schema
      |> Map.from_struct()
      |> Map.take(Map.keys(changeset.attributes))

    pk = resource |> Info.partition_key() |> to_string()
    sk = resource |> Info.sort_key() |> then(&if &1, do: to_string(&1))

    key =
      %{"#{pk}" => attrs[:"#{pk}"]}
      |> then(fn k -> if sk, do: Map.put(k, sk, attrs[:"#{sk}"]), else: k end)

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

    # Use return_values: "ALL_NEW" to get the final state back for building the resource struct
    opts = [
      update_expression: set_expr,
      expression_attribute_names: names,
      expression_attribute_values: values,
      return_values: "ALL_NEW"
    ]

    resource
    |> Info.table()
    |> ExAws.Dynamo.update_item(key, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{"Attributes" => attrs}} -> {:ok, ExAws.Dynamo.decode_item(attrs, as: resource)}
      {:error, error} -> {:error, error}
    end
  end
end
