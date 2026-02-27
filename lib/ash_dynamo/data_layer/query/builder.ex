defmodule AshDynamo.DataLayer.Query.Builder do
  @moduledoc """
  Translates Ash filters into DynamoDB request options.

  This module handles the core query-building pipeline: index selection,
  key condition expressions, filter expressions, projection expressions,
  and sort direction.

  ## Routing priority

    1. Table partition key match  → Query on main table (strongly consistent)
    2. GSI partition key match    → Query with IndexName (eventually consistent)
    3. Neither                    → Scan (fallback)

  ## Filter predicate partitioning

    1. Partition key (PK) — must be equality (`=`), goes to `KeyConditionExpression`
    2. Sort key (SK) — supports `=, <, <=, >, >=`, goes to `KeyConditionExpression`
    3. Non-key attributes — go to `FilterExpression` (server-side filtering)
  """

  alias AshDynamo.DataLayer.Info
  alias AshDynamo.DataLayer.Query

  @key_condition_operators ~w(== < <= > >=)a
  @to_dynamo_operator %{
    :== => "=",
    :!= => "<>",
    :> => ">",
    :>= => ">=",
    :< => "<",
    :<= => "<="
  }

  @doc """
  Builds DynamoDB request options from an Ash query's filter.

  Returns `{mode, opts, effective_sk}` where:
  - `mode` is `:scan` or `:query`
  - `opts` is a keyword list of ExAws DynamoDB options
  - `effective_sk` is the sort key of the selected index (or `nil`)
  """
  def request_opts(%Query{filter: nil}, _resource), do: {:scan, [], nil}

  def request_opts(%Query{filter: filter}, resource) do
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

  @doc """
  Determines which attributes to include in the DynamoDB ProjectionExpression.

  Always includes:
  - The user's select (or defaults if none were provided)
  - Attributes referenced in the filter (so post-filtering works with Scan)
  - Partition/sort keys (needed to decode a valid record)
  """
  def projection_fields(%Query{select: select, filter: filter}, resource) do
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

  @doc """
  Merges a ProjectionExpression into the request options keyword list.
  """
  def merge_projection_opts(opts, fields) do
    {projection_expression, projection_names} = build_projection(fields)

    opts
    |> merge_opt_map(:expression_attribute_names, projection_names)
    |> maybe_put(:projection_expression, projection_expression)
  end

  @doc """
  Merges ScanIndexForward into the request options when DynamoDB can natively sort.

  ScanIndexForward optimization only applies when ALL conditions are met:
  - Query mode (partition key filter present)
  - Sorting by a SINGLE field
  - That field is the effective sort key of the selected index
  """
  def merge_sort_opts(opts, nil, _mode, _effective_sk), do: opts
  def merge_sort_opts(opts, [], _mode, _effective_sk), do: opts

  def merge_sort_opts(opts, [{field, direction}], :query, effective_sk) do
    if attr_name(field) == effective_sk do
      case direction do
        :asc -> Keyword.put(opts, :scan_index_forward, true)
        :desc -> Keyword.put(opts, :scan_index_forward, false)
      end
    else
      opts
    end
  end

  def merge_sort_opts(opts, _sort, _mode, _effective_sk), do: opts

  # --- Index selection -------------------------------------------------------

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

  # --- Key condition & filter expression building ----------------------------

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

  # --- Projection expression -------------------------------------------------

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

  # --- Utility helpers -------------------------------------------------------

  defp get_attr_name(%Ash.Query.Ref{attribute: attr}), do: attr_name(attr)

  defp extract_attr_and_value(%Ash.Query.Ref{attribute: attr}, value),
    do: {attr_name(attr), value}

  defp extract_attr_and_value(value, %Ash.Query.Ref{attribute: attr}),
    do: {attr_name(attr), value}

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

  defp merge_opt_map(opts, _key, nil), do: opts

  defp merge_opt_map(opts, key, map) do
    merged = map |> Map.merge(Keyword.get(opts, key, %{}))
    Keyword.put(opts, key, merged)
  end

  defp attr_name(%{name: name}), do: name
  defp attr_name(name), do: name

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
