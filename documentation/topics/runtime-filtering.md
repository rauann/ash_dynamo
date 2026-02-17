# Runtime Filtering and Pagination

DynamoDB is not a relational database. It supports a limited set of filter operations natively, so AshDynamo uses a layered filtering strategy where DynamoDB handles what it can and Ash handles the rest at runtime.

## How Filtering Works

AshDynamo partitions Ash filter predicates into three tiers:

1. **KeyConditionExpression** -- Partition key (equality) and sort key (comparison operators). These define _which_ items DynamoDB reads from the index.

2. **FilterExpression** -- Non-key attribute comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`) and `contains`. Applied server-side _after_ items are read but _before_ they are returned. Reduces data transfer but still consumes read capacity for all scanned items.

3. **Runtime filter** -- Predicates that DynamoDB cannot express (OR conditions, `is_nil`, `in`, etc.). Applied in-memory via `Ash.Filter.Runtime.filter_matches` after DynamoDB returns results.

The runtime filter evaluates the **full original Ash filter**, not just the unsupported predicates. This means DynamoDB-handled predicates are re-evaluated redundantly, which is harmless since those items already satisfy them.

## Interaction with Limit and Pagination

When `Ash.Query.limit(N)` is used, AshDynamo passes `Limit=N` to DynamoDB and follows `LastEvaluatedKey`/`ExclusiveStartKey` pagination to accumulate results across pages.

DynamoDB's `Limit` parameter counts items **evaluated**, not items **returned** after `FilterExpression`. This means a request with `Limit=10` and a `FilterExpression` may return fewer than 10 items. The `AshDynamo.DataLayer.Query.Paginator` handles this by continuing to fetch pages until enough post-`FilterExpression` items are accumulated.

### Edge Case: Limit + Runtime Filters

When unsupported predicates (OR, `is_nil`) are present alongside a limit, the following can occur:

1. The `AshDynamo.DataLayer.Query.Paginator` accumulates N items that passed DynamoDB's partial filter
2. The runtime filter then re-evaluates these items against the full Ash filter
3. An item that passed DynamoDB's `FilterExpression` may fail an unsupported predicate evaluated at runtime
4. The final result may contain fewer than N items

This is not a limitation in AshDynamo's implementation. It is a consequence of DynamoDB's restricted query language -- certain predicates simply cannot be translated into DynamoDB expressions. The runtime filter exists to bridge this gap, and it may reduce the result set beyond what DynamoDB returned.

This mirrors how sort works: DynamoDB natively sorts via `ScanIndexForward` only when sorting by the sort key in Query mode. All other sort scenarios fall back to `Ash.Actions.Sort.runtime_sort` after results are fetched.

### When This Edge Case Does Not Apply

In the common case -- no unsupported predicates in the filter -- every item that passes DynamoDB's filter also passes the runtime filter. The `AshDynamo.DataLayer.Query.Paginator` returns exactly N items and no runtime reduction occurs.
