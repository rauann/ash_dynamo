defmodule AshDynamo.DataLayer do
  @moduledoc """
  DynamoDB data layer for `Ash`.

  This wires in a `dynamodb` DSL section on resources so you can declare how a
  resource maps to a table. Introspection helpers live in
  `AshDynamo.DataLayer.Info`.
  """

  @behaviour Ash.DataLayer

  require Logger

  alias AshDynamo.DataLayer.CRUD
  alias AshDynamo.DataLayer.Info
  alias AshDynamo.DataLayer.Query.Builder
  alias AshDynamo.DataLayer.Query.Paginator

  @global_secondary_index %Spark.Dsl.Entity{
    name: :global_secondary_index,
    describe: "Defines a Global Secondary Index (GSI) for automatic query routing.",
    target: AshDynamo.DataLayer.SecondaryIndex,
    args: [:name],
    auto_set_fields: [type: :global],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Index name (used as the DynamoDB `IndexName` parameter)."
      ],
      partition_key: [
        type: :atom,
        required: true,
        doc: "Partition (hash) key attribute for this GSI."
      ],
      sort_key: [
        type: :atom,
        doc: "Optional sort (range) key attribute for this GSI."
      ]
    ]
  }

  @dynamodb %Spark.Dsl.Section{
    name: :dynamodb,
    describe: "Configure the DynamoDB table backing this resource for querying.",
    examples: [
      """
      dynamodb do
        table "users"
        partition_key :email
        sort_key :inserted_at

        global_secondary_index :by_status do
          partition_key :status
          sort_key :inserted_at
        end
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
      ]
    ],
    entities: [@global_secondary_index]
  }

  use Spark.Dsl.Extension, sections: [@dynamodb]

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :domain,
      :select,
      :filter,
      :sort,
      :limit
    ]
  end

  # --- Capabilities --------------------------------------------------------
  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :select), do: true
  def can?(_, :filter), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, {:filter_expr, _expr}), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, :limit), do: true
  def can?(_, _), do: false

  # --- Query shaping ------------------------------------------------------
  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  @impl true
  def select(%Query{} = query, select, _resource) do
    {:ok, %{query | select: select}}
  end

  @impl true
  def filter(%Query{} = query, filter, _resource) do
    {:ok, %{query | filter: filter}}
  end

  @impl true
  def sort(query, [], _resource), do: {:ok, query}
  def sort(query, nil, _resource), do: {:ok, query}
  def sort(query, sort, _resource), do: {:ok, %{query | sort: sort}}

  @impl true
  def limit(query, nil, _resource), do: {:ok, query}
  def limit(query, limit, _resource), do: {:ok, %{query | limit: limit}}

  @impl true
  def run_query(%Query{} = query, resource) do
    table = Info.table(resource)
    select_fields = Builder.projection_fields(query, resource)

    {mode, opts, effective_sk} = Builder.request_opts(query, resource)

    maybe_warn_on_scan(mode, resource)

    opts =
      opts
      |> Builder.merge_projection_opts(select_fields)
      |> Builder.merge_sort_opts(query.sort, mode, effective_sk)

    with {:ok, resp} <- Paginator.fetch(table, mode, opts, query.limit),
         {:ok, items} <- decode_items(resp, resource),
         {:ok, filtered} <- apply_runtime_filter(items, query) do
      apply_runtime_sort(filtered, query, mode, effective_sk)
    end
  end

  defp decode_items(%{"Items" => items}, resource) when is_list(items) do
    decoded = Enum.map(items, &ExAws.Dynamo.decode_item(&1, as: resource))
    {:ok, decoded}
  end

  defp decode_items(other, _resource), do: {:error, {:unexpected_response, other}}

  defp apply_runtime_filter(results, %Query{filter: nil}), do: {:ok, results}

  defp apply_runtime_filter(results, %Query{filter: filter, domain: domain}) do
    Ash.Filter.Runtime.filter_matches(domain, results, filter)
  end

  # Runtime sort is applied when DynamoDB cannot natively sort the results:
  # - Scan mode: ScanIndexForward doesn't work
  # - Query mode with non-sort-key field: DynamoDB can only sort by the sort key
  # In Query mode when sorting by sort key, DynamoDB handles sorting via ScanIndexForward.
  defp apply_runtime_sort(results, %Query{sort: nil}, _mode, _effective_sk), do: {:ok, results}
  defp apply_runtime_sort(results, %Query{sort: []}, _mode, _effective_sk), do: {:ok, results}

  defp apply_runtime_sort(results, %Query{sort: sort}, mode, effective_sk) do
    sorting_by_sort_key? =
      case sort do
        [{field, _}] -> field == effective_sk
        _ -> false
      end

    if mode == :query and sorting_by_sort_key? do
      {:ok, results}
    else
      # rekey?: false prevents Ash from matching sorted records back to originals
      # by primary key. Without this, records sharing the same Ash primary key
      # (e.g., same partition key but different sort keys) would all resolve to
      # the first match, duplicating records in the output.
      sorted = Ash.Actions.Sort.runtime_sort(results, sort, rekey?: false)
      {:ok, sorted}
    end
  end

  @impl true
  def create(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      CRUD.insert_item(resource, changeset, schema)
    end
  end

  @impl true
  def update(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      CRUD.update_item(resource, changeset, schema, :update)
    end
  end

  @impl true
  def destroy(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      CRUD.delete_item(resource, schema)
    end
  end

  defp maybe_warn_on_scan(:scan, resource) do
    if Application.get_env(:ash_dynamo, :warn_on_scan?) == true do
      table = Info.table(resource)

      Logger.warning("""
      AshDynamo: Scan operation on table "#{table}" for resource #{inspect(resource)}. \
      Scans read every item in the table and consume significant read capacity. \
      Add a partition key filter or define a GSI to use a Query instead. \
      To disable this warning set: "config :ash_dynamo, warn_on_scan?: false"\
      """)
    end
  end

  defp maybe_warn_on_scan(_mode, _resource), do: :ok
end
