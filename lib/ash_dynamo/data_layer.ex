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
      :domain,
      :select,
      :filter
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

  # --- Execution ----------------------------------------------------------
  @impl true
  def run_query(%Query{} = query, resource) do
    table = Info.table(resource)
    select_fields = projection_fields(query, resource)

    {mode, opts} = request_opts(query, resource)
    opts = merge_projection_opts(opts, select_fields)

    mode
    |> case do
      :query -> ExAws.Dynamo.query(table, opts)
      :scan -> ExAws.Dynamo.scan(table, opts)
    end
    |> ExAws.request()
    |> case do
      {:ok, resp} ->
        with {:ok, items} <- decode_items(resp, resource),
             {:ok, filtered} <- apply_runtime_filter(items, query) do
          {:ok, filtered}
        end

      {:error, error} ->
        {:error, error}
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

      key =
        %{"#{pk}" => Map.get(schema, pk)}
        |> then(fn k -> if sk, do: Map.put(k, sk, Map.get(schema, sk)), else: k end)

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

    key =
      %{"#{pk}" => Map.get(schema, pk)}
      |> then(fn k -> if sk, do: Map.put(k, sk, Map.get(schema, sk)), else: k end)

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

  @query_key_condition_expression_operarators ~w(= < <= > >=)a

  # Dynamo Query requires a KeyConditionExpression with a concrete partition-key value.
  # If the filter gives us that (and optionally a sort-key equality), we build Query opts;
  # otherwise we must fall back to Scan because Dynamo won’t accept a Query without a key.
  # Returns {:query | :scan, opts} for run_query/2.
  defp request_opts(%Query{filter: nil}, _resource), do: {:scan, []}

  defp request_opts(%Query{filter: filter}, resource) do
    pk = Info.partition_key(resource)
    sk = Info.sort_key(resource)

    with {:ok, {pk_value, _pk_operator}} <- fetch_key_value(filter, pk) do
      names = %{"#pk" => to_string(pk)}
      values = %{"v_pk" => pk_value}

      {expr, names, values} =
        case fetch_key_value(filter, sk) do
          {:ok, {sk_value, sk_operator}}
          when sk_operator in @query_key_condition_expression_operarators ->
            {
              "#pk = :v_pk AND #sk #{sk_operator} :v_sk",
              Map.put(names, "#sk", to_string(sk)),
              Map.put(values, "v_sk", sk_value)
            }

          _ ->
            {"#pk = :v_pk", names, values}
        end

      {:query,
       [
         key_condition_expression: expr,
         expression_attribute_names: names,
         expression_attribute_values: values
       ]}
    else
      _ -> {:scan, []}
    end
  end

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
  defp filter_refs(%Ash.Filter{} = filter), do: Ash.Filter.list_refs(filter.expression)

  defp filter_refs(%Ash.Filter.Simple{predicates: predicates}),
    do: Ash.Filter.list_refs(predicates)

  defp filter_refs(_), do: []

  defp fetch_key_value(%Ash.Filter.Simple{predicates: predicates}, attr) do
    target = attr_name(attr) |> to_string()

    Enum.find_value(predicates, :error, fn %{left: left, right: right, operator: operator} ->
      cond do
        match_ref?(left, target) -> {:ok, {right, normalize_operator(operator)}}
        match_ref?(right, target) -> {:ok, {left, normalize_operator(operator)}}
        true -> nil
      end
    end)
  end

  defp normalize_operator(:==), do: :=
  defp normalize_operator(operator), do: operator

  defp match_ref?(%Ash.Query.Ref{attribute: ref_attr}, target),
    do: attr_name(ref_attr) |> to_string() == target

  defp match_ref?(_, _), do: false

  defp attr_name(%{name: name}), do: name
  defp attr_name(name), do: name

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
