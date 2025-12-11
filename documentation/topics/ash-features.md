# Supported Ash Features

This document describes which Ash features are supported by AshDynamo and how they map to DynamoDB operations.

## Base Operations

| Capability | Status | Notes                                              |
| ---------- | ------ | -------------------------------------------------- |
| `:read`    | ✅     | Query (with PK) or Scan fallback                   |
| `:create`  | ✅     | PutItem with uniqueness check                      |
| `:update`  | ✅     | UpdateItem with existence check                    |
| `:destroy` | ✅     | DeleteItem with existence check                    |
| `:select`  | ✅     | ProjectionExpression                               |
| `:filter`  | ✅     | KeyCondition + FilterExpression + Runtime fallback |

## Filter Operators

**KeyConditionExpression (partition key + sort key):**

| Ash Operator | DynamoDB | Where Used        |
| ------------ | -------- | ----------------- |
| `==`         | `=`      | PK (required), SK |
| `<`          | `<`      | SK only           |
| `<=`         | `<=`     | SK only           |
| `>`          | `>`      | SK only           |
| `>=`         | `>=`     | SK only           |

**FilterExpression (non-key attributes, server-side filtering):**

| Ash Operator | DynamoDB   |
| ------------ | ---------- |
| `==`         | `=`        |
| `!=`         | `<>`       |
| `<`          | `<`        |
| `<=`         | `<=`       |
| `>`          | `>`        |
| `>=`         | `>=`       |
| `contains`   | `contains` |

**Runtime filter fallback (in-memory filtering):**

| Ash Operator | Status            |
| ------------ | ----------------- |
| `in`         | ⏳ Runtime filter |
| `is_nil`     | ⏳ Runtime filter |
| `or`         | ⏳ Runtime filter |

## Not Implemented

| Feature               | Notes                                                 |
| --------------------- | ----------------------------------------------------- |
| `:or`                 | Via filter expression                                 |
| `:upsert`             | Explicit upsert mode                                  |
| `:sort`               | Sort by SK                                            |
| `:limit` / `:offset`  | Pagination via `LastEvaluatedKey`/`ExclusiveStartKey` |
| `:aggregate`          | Via `Select: COUNT`                                   |
| Bulk operations       | Bulk insert/update/delete                             |
| GSI/LSI query routing | DSL defined                                           |
| Transactions          | Via `TransactWriteItems`                              |

> #### Warning {: .warning}
>
> Since pagination is not implemented, queries on large datasets will return only the first 1MB of results (DynamoDB's per-request limit).

## Not Supported

| Feature       | Notes                        |
| ------------- | ---------------------------- |
| Relationships | DynamoDB has no native joins |
