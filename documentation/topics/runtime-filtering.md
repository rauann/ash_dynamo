# Runtime Filtering and Pagination

DynamoDB is not a relational database. It supports a limited set of filter operations natively, so AshDynamo uses a layered filtering strategy where DynamoDB handles what it can and Ash handles the rest at runtime.

## How Filtering Works

AshDynamo partitions Ash filter predicates into three tiers:

1. **KeyConditionExpression** -- Partition key (equality) and sort key (comparison operators). These define _which_ items DynamoDB reads from the index.

2. **FilterExpression** -- Non-key attribute comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`) and `contains`. Applied server-side _after_ items are read but _before_ they are returned. Reduces data transfer but still consumes read capacity for all scanned items.

3. **Runtime filter** -- Predicates that DynamoDB cannot express (OR conditions, `is_nil`, `in`, etc.). Applied in-memory via `Ash.Filter.Runtime.filter_matches` after DynamoDB returns results.

The runtime filter evaluates the **full original Ash filter**, not just the unsupported predicates. This means DynamoDB-handled predicates are re-evaluated redundantly, which is harmless since those items already satisfy them.

## Interaction with Limit and Pagination

DynamoDB processes each request in a fixed pipeline: **KeyConditionExpression → Limit → FilterExpression**. Because `Limit` is applied _before_ `FilterExpression`, it caps items **evaluated**, not items **returned**. This means passing `Limit=10` with a `FilterExpression` may return fewer than 10 items.

To avoid excessive pagination, the `AshDynamo.DataLayer.Query.Paginator` does not pass `Limit` to DynamoDB when a `FilterExpression` is present. Instead, DynamoDB evaluates its natural 1MB page and the Paginator controls the stopping logic based on accumulated post-filter item count. When no `FilterExpression` is present, `Limit` is passed directly to DynamoDB to avoid over-reading.
