defmodule AshDynamo.DataLayer.Query.Paginator do
  @moduledoc """
  Handles DynamoDB pagination via `LastEvaluatedKey` and `ExclusiveStartKey`.

  DynamoDB returns at most 1MB of data per request. When more items are available,
  the response includes a `LastEvaluatedKey` that must be passed as `ExclusiveStartKey`
  in the next request. This module encapsulates that loop, accumulating pages until
  the requested limit is reached or no more data is available.

  When a `FilterExpression` is present, `Limit` is not passed to DynamoDB. This is
  because DynamoDB applies `Limit` before `FilterExpression`, so a small limit would
  constrain the evaluation window and cause excessive pagination when few items match
  the filter. Instead, DynamoDB evaluates its natural 1MB page and the Paginator
  controls the stopping logic based on accumulated post-filter item count.

  When no `FilterExpression` is present, every evaluated item is returned, so `Limit`
  is passed directly to DynamoDB to avoid over-reading.
  """

  @doc """
  Fetches items from DynamoDB, handling pagination via `LastEvaluatedKey`/`ExclusiveStartKey`.

  Returns a merged response map with the same shape as a single ExAws response:
  `%{"Items" => [...], "Count" => N, "ScannedCount" => N}`.
  """
  def fetch(table, mode, base_opts, limit \\ nil) do
    do_fetch(table, mode, base_opts, limit, _acc = nil, _start_key = nil)
  end

  # Accumulator is `nil` for the first request and `{pages, count, scanned}`
  # for subsequent ones. Each page's items list is prepended as a whole (O(1)),
  # then reversed and concatenated in `to_response`.
  defp do_fetch(table, mode, base_opts, limit, acc, start_key) do
    dynamo_limit =
      if has_filter_expression?(base_opts), do: nil, else: remaining_limit(limit, acc)

    page_opts =
      base_opts
      |> maybe_put(:limit, dynamo_limit)
      |> maybe_put(:exclusive_start_key, start_key)

    result =
      mode
      |> case do
        :query -> ExAws.Dynamo.query(table, page_opts)
        :scan -> ExAws.Dynamo.scan(table, page_opts)
      end
      |> ExAws.request()

    with {:ok, resp} <- result do
      merged = accumulate(acc, resp)

      cond do
        limit != nil and item_count(merged) >= limit ->
          {:ok, to_response(merged, limit)}

        Map.has_key?(resp, "LastEvaluatedKey") ->
          do_fetch(table, mode, base_opts, limit, merged, resp["LastEvaluatedKey"])

        true ->
          {:ok, to_response(merged, limit)}
      end
    end
  end

  defp remaining_limit(nil, _acc), do: nil
  defp remaining_limit(limit, nil), do: limit
  defp remaining_limit(limit, {_pages, count, _scanned}), do: limit - count

  defp accumulate(nil, resp) do
    items = resp["Items"] || []
    {[items], resp["Count"] || 0, resp["ScannedCount"] || 0}
  end

  defp accumulate({pages, count, scanned}, resp) do
    items = resp["Items"] || []

    {
      [items | pages],
      count + (resp["Count"] || 0),
      scanned + (resp["ScannedCount"] || 0)
    }
  end

  # Pages are prepended during accumulation (O(1) per page), so we
  # reverse the page order and concatenate into a flat item list.
  #
  # When a limit is provided, trim the items to avoid returning more
  # than requested (the last page may overshoot the limit).
  defp to_response({pages, count, scanned}, limit) do
    items = pages |> Enum.reverse() |> Enum.concat()

    if limit != nil and length(items) > limit do
      %{"Items" => Enum.take(items, limit), "Count" => limit, "ScannedCount" => scanned}
    else
      %{"Items" => items, "Count" => count, "ScannedCount" => scanned}
    end
  end

  defp item_count({_pages, count, _scanned}), do: count

  defp has_filter_expression?(opts), do: Keyword.has_key?(opts, :filter_expression)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
