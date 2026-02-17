defmodule AshDynamo.DataLayer do
  @moduledoc """
  DynamoDB data layer for `Ash`.

  This wires in a `dynamodb` DSL section on resources so you can declare how a
  resource maps to a table. Introspection helpers live in
  `AshDynamo.DataLayer.Info`.
  """

  @behaviour Ash.DataLayer

  require Logger

  alias AshDynamo.DataLayer.Info
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

  # --- Execution ----------------------------------------------------------
  @impl true
  def run_query(%Query{} = query, resource) do
    table = Info.table(resource)
    select_fields = projection_fields(query, resource)

    {mode, opts, effective_sk} = request_opts(query, resource)

    maybe_warn_on_scan(mode, resource)

    opts =
      opts
      |> merge_projection_opts(select_fields)
      |> merge_sort_opts(query.sort, mode, effective_sk)

    with {:ok, resp} <- Paginator.fetch(table, mode, opts, query.limit),
         {:ok, items} <- decode_items(resp, resource),
         {:ok, filtered} <- apply_runtime_filter(items, query) do
      apply_runtime_sort(filtered, query, mode, effective_sk)
    end
  end

  # DynamoDB's ScanIndexForward parameter controls sort order for Query operations.
  # true (default) = ascending by sort key, false = descending.
  #
  # ScanIndexForward optimization only applies when ALL conditions are met:
  # - Query mode (partition key filter present)
  # - Sorting by a SINGLE field
  # - That field is the sort key
  #
  # All other cases use runtime sort:
  # - Scan mode (no partition key filter)
  # - Sorting by non-sort-key field
  # - Multiple sort fields (even if sort key is included)
  defp merge_sort_opts(opts, nil, _mode, _effective_sk), do: opts
  defp merge_sort_opts(opts, [], _mode, _effective_sk), do: opts

  defp merge_sort_opts(opts, [{field, direction}], :query, effective_sk) do
    if attr_name(field) == effective_sk do
      case direction do
        :asc -> Keyword.put(opts, :scan_index_forward, true)
        :desc -> Keyword.put(opts, :scan_index_forward, false)
      end
    else
      opts
    end
  end

  defp merge_sort_opts(opts, _sort, _mode, _effective_sk), do: opts

  # Runtime sort is applied when DynamoDB cannot natively sort the results:
  # - Scan mode: ScanIndexForward doesn't work
  # - Query mode with non-sort-key field: DynamoDB can only sort by the sort key
  # In Query mode when sorting by sort key, DynamoDB handles sorting via ScanIndexForward.
  defp apply_runtime_sort(results, %Query{sort: nil}, _mode, _effective_sk), do: {:ok, results}
  defp apply_runtime_sort(results, %Query{sort: []}, _mode, _effective_sk), do: {:ok, results}

  defp apply_runtime_sort(results, %Query{sort: sort}, mode, effective_sk) do
    sorting_by_sort_key? =
      case sort do
        [{field, _}] -> attr_name(field) == effective_sk
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
      insert_item(resource, changeset, schema)
    end
  end

  @impl true
  def update(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
      update_item(resource, changeset, schema, :update)
    end
  end

  @impl true
  def destroy(resource, changeset) do
    with {:ok, schema} <- Ash.Changeset.apply_attributes(changeset) do
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
  end

  defp update_item(resource, changeset, schema, mode) do
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

    # UpdateItem in Dynamo is an upsert by default. Calling it with a key that doesn’t exist,
    # it will create the item. The attribute_exists(#pk) condition is only applied in :update mode.
    # To force “update only”: it fails with a conditional check error if the item isn’t there.
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

  defp insert_item(resource, changeset, schema) do
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

  defp prepare_attrs(schema, allowed_keys) do
    schema
    |> Map.from_struct()
    |> Map.take(allowed_keys)
  end

  defp build_item_key(schema, pk, nil), do: %{"#{pk}" => Map.get(schema, pk)}

  defp build_item_key(schema, pk, sk),
    do: %{"#{pk}" => Map.get(schema, pk), "#{sk}" => Map.get(schema, sk)}

  # Decide which attributes we ask Dynamo to return. We always include:
  # - the user’s select (or defaults if none were provided)
  # - attributes referenced in the filter (so post-filtering works when we fall back to Scan)
  # - partition/sort keys (needed to decode a valid record)
  # These fields feed the ProjectionExpression passed to Query/Scan in run_query/2.
  defp projection_fields(%Query{select: select, filter: filter}, resource) do
    default =
      resource
      |> Ash.Resource.Info.selected_by_default_attribute_names()
      |> MapSet.new()

    filter_fields =
      filter
      |> filter_refs()
      |> Enum.map(fn ref ->
        case ref.attribute do
          %{name: name} -> name
          name -> name
        end
      end)

    select
    |> Kernel.||(default)
    |> Enum.to_list()
    |> Kernel.++(filter_fields)
    |> Kernel.++([Info.partition_key(resource), Info.sort_key(resource)])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @key_condition_operators ~w(== < <= > >=)a
  @to_dynamo_operator %{
    :== => "=",
    :!= => "<>",
    :> => ">",
    :>= => ">=",
    :< => "<",
    :<= => "<="
  }

  # Builds DynamoDB request options from an Ash filter.
  #
  # Routing priority (see select_index/2):
  #   1. Table partition key match  -> Query on main table (strongly consistent)
  #   2. GSI partition key match    -> Query with IndexName (eventually consistent)
  #   3. Neither                    -> Scan (fallback)
  #
  # Filter predicates are partitioned into three categories:
  #   1. Partition key (PK) - must be equality (=), goes to KeyConditionExpression
  #   2. Sort key (SK) - supports =, <, <=, >, >=, goes to KeyConditionExpression
  #   3. Non-key attributes - go to FilterExpression (server-side filtering)
  #
  # Returns {mode, opts, effective_sk} where effective_sk is the sort key
  # of the selected index (or table), used for ScanIndexForward optimization.
  defp request_opts(%Query{filter: nil}, _resource), do: {:scan, [], nil}

  defp request_opts(%Query{filter: filter}, resource) do
    # Convert to simple filter, skipping unsupported expressions (OR, contains).
    # Skipped expressions that are not implemented on dynamo query (i.e OR, or
    # contains when scan is used) are handled by runtime filter.
    filter = Ash.Filter.to_simple_filter(filter, skip_invalid?: true)

    case select_index(filter, resource) do
      {pk, pk_value, sk, extra_opts} ->
        build_query_request(filter, pk, pk_value, sk, extra_opts)

      :scan ->
        {:scan, [], nil}
    end
  end

  # Selects which index (table or GSI) can serve the query.
  # Table PK takes priority over GSIs because main table queries are strongly consistent.
  defp select_index(filter, resource) do
    pk = Info.partition_key(resource)
    sk = Info.sort_key(resource)

    with :error <- match_table_key(filter, pk, sk),
         :error <- match_gsi(filter, Info.global_secondary_indexes(resource)) do
      :scan
    end
  end

  defp match_table_key(filter, pk, sk) do
    case fetch_key_value(filter, pk) do
      {:ok, {pk_value, :==}} -> {pk, pk_value, sk, []}
      _ -> :error
    end
  end

  # Prefer GSIs where the SK also appears in the filter (more selective query).
  defp match_gsi(_filter, []), do: :error

  defp match_gsi(filter, gsis) do
    gsis
    |> Enum.filter(fn gsi ->
      match?({:ok, {_, :==}}, fetch_key_value(filter, gsi.partition_key))
    end)
    |> Enum.sort_by(fn gsi ->
      if gsi.sort_key && fetch_key_value(filter, gsi.sort_key) != :error, do: 0, else: 1
    end)
    |> case do
      [first | _] ->
        {:ok, {pk_value, _}} = fetch_key_value(filter, first.partition_key)
        {first.partition_key, pk_value, first.sort_key, index_name: to_string(first.name)}

      [] ->
        :error
    end
  end

  defp build_query_request(filter, pk, pk_value, sk, extra_opts) do
    key_attrs = Enum.reject([pk, sk], &is_nil/1)
    # Key predicates are already handled by build_key_condition/4 below
    {_key_preds, filter_preds} = partition_predicates(filter, key_attrs)

    {key_expr, names, values} = build_key_condition(pk, pk_value, sk, filter)
    {filter_expr, names, values} = build_filter_expression(filter_preds, names, values)

    opts =
      [
        key_condition_expression: key_expr,
        expression_attribute_names: names,
        expression_attribute_values: values
      ]
      |> maybe_put(:filter_expression, filter_expr)
      |> Keyword.merge(extra_opts)

    {:query, opts, sk}
  end

  defp build_key_condition(pk, pk_value, sk, filter) do
    names = %{"#pk" => to_string(pk)}
    values = %{"v_pk" => pk_value}

    case fetch_key_value(filter, sk) do
      {:ok, {sk_value, sk_operator}} when sk_operator in @key_condition_operators ->
        {
          "#pk = :v_pk AND #sk #{Map.get(@to_dynamo_operator, sk_operator)} :v_sk",
          Map.put(names, "#sk", to_string(sk)),
          Map.put(values, "v_sk", sk_value)
        }

      _ ->
        {"#pk = :v_pk", names, values}
    end
  end

  # Splits predicates into {key_preds, filter_preds} so key attributes go into
  # KeyConditionExpression and the rest go into FilterExpression.
  defp partition_predicates(%Ash.Filter.Simple{predicates: predicates}, key_attrs) do
    key_attr_names = Enum.map(key_attrs, &(attr_name(&1) |> to_string()))

    Enum.split_with(predicates, fn
      %{left: left, right: right} ->
        Enum.any?(key_attr_names, fn key ->
          match_ref?(left, key) or match_ref?(right, key)
        end)

      _other ->
        false
    end)
  end

  defp partition_predicates(_, _), do: {[], []}

  # Builds a DynamoDB FilterExpression from non-key predicates.
  #
  # FilterExpression applies server-side filtering AFTER KeyConditionExpression
  # narrows results. This reduces data transfer but still consumes read capacity
  # for all scanned items.
  #
  # Supported predicate types:
  #   1. Comparison operators (==, !=, <, <=, >, >=)
  #      - Ash: %{left: ref, right: value, operator: :==}
  #      - DynamoDB: "#attr = :val"
  #
  #   2. contains() function (string substring or set membership)
  #      - Ash: %Ash.Query.Function.Contains{arguments: [ref, value]}
  #      - DynamoDB: "contains(#attr, :val)"
  #
  # Unsupported predicates (is_nil, in, or, etc.) are skipped here and handled
  # by Ash.Filter.Runtime.filter_matches in apply_runtime_filter/2.
  #
  # Example: Given predicates [status == "active", contains(title, "foo")]
  #   - FilterExpression: "#fa0 = :fv0 AND contains(#fa1, :fv1)"
  #   - names: %{"#fa0" => "status", "#fa1" => "title"}
  #   - values: %{"fv0" => "active", "fv1" => "foo"}
  #
  # Returns {filter_expression | nil, updated_names, updated_values}.
  defp build_filter_expression([], names, values), do: {nil, names, values}

  defp build_filter_expression(predicates, names, values) do
    {exprs, names, values} =
      predicates
      |> Enum.with_index()
      |> Enum.reduce({[], names, values}, fn
        # Handle comparison predicates (==, !=, <, >, etc.)
        {%{left: left, right: right, operator: operator}, idx}, {exprs, n, v} ->
          dynamo_operator = Map.get(@to_dynamo_operator, operator)

          if dynamo_operator do
            {attr, value} = extract_attr_and_value(left, right)
            attr_placeholder = "#fa#{idx}"
            value_placeholder = "fv#{idx}"
            expr = "#{attr_placeholder} #{dynamo_operator} :#{value_placeholder}"

            {
              [expr | exprs],
              Map.put(n, attr_placeholder, to_string(attr)),
              Map.put(v, value_placeholder, value)
            }
          else
            {exprs, n, v}
          end

        # Handle contains() function
        {%Ash.Query.Function.Contains{arguments: [ref, value]}, idx}, {exprs, n, v} ->
          attr = get_attr_name(ref)
          attr_placeholder = "#fa#{idx}"
          value_placeholder = "fv#{idx}"
          expr = "contains(#{attr_placeholder}, :#{value_placeholder})"

          {
            [expr | exprs],
            Map.put(n, attr_placeholder, to_string(attr)),
            Map.put(v, value_placeholder, value)
          }

        # Skip unsupported - handled by runtime filter
        {_other, _idx}, acc ->
          acc
      end)

    case exprs do
      [] -> {nil, names, values}
      _ -> {exprs |> Enum.reverse() |> Enum.join(" AND "), names, values}
    end
  end

  defp get_attr_name(%Ash.Query.Ref{attribute: attr}), do: attr_name(attr)

  defp extract_attr_and_value(%Ash.Query.Ref{attribute: attr}, value),
    do: {attr_name(attr), value}

  defp extract_attr_and_value(value, %Ash.Query.Ref{attribute: attr}),
    do: {attr_name(attr), value}

  defp merge_projection_opts(opts, fields) do
    {projection_expression, projection_names} = build_projection(fields)

    opts
    |> merge_opt_map(:expression_attribute_names, projection_names)
    |> maybe_put(:projection_expression, projection_expression)
  end

  defp build_projection(fields) do
    names =
      fields
      |> Enum.with_index()
      |> Map.new(fn {field, idx} ->
        {"#f#{idx}", to_string(field)}
      end)

    expression =
      names
      |> Map.keys()
      |> Enum.join(", ")

    {expression, names}
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

  defp merge_opt_map(opts, _key, nil), do: opts

  defp merge_opt_map(opts, key, map) do
    merged = map |> Map.merge(Keyword.get(opts, key, %{}))
    Keyword.put(opts, key, merged)
  end

  defp filter_refs(nil), do: []

  defp filter_refs(%Ash.Filter.Simple{predicates: predicates}),
    do: Ash.Filter.list_refs(predicates)

  defp filter_refs(_), do: []

  defp fetch_key_value(%Ash.Filter.Simple{predicates: predicates}, attr) do
    target = attr_name(attr) |> to_string()

    Enum.find_value(predicates, :error, fn
      %{left: left, right: right, operator: operator} ->
        cond do
          match_ref?(left, target) -> {:ok, {right, operator}}
          match_ref?(right, target) -> {:ok, {left, operator}}
          true -> nil
        end

      # Functions like contains(), etc.
      _other ->
        nil
    end)
  end

  defp match_ref?(%Ash.Query.Ref{attribute: ref_attr}, target),
    do: attr_name(ref_attr) |> to_string() == target

  defp match_ref?(_, _), do: false

  defp attr_name(%{name: name}), do: name
  defp attr_name(name), do: name

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

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
