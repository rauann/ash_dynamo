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
        sort_key :created_at
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
end
