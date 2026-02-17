# Scan Warning

## What is a DynamoDB Scan?

A DynamoDB **Scan** reads every item in a table (or index), examining each one against any filter expressions you provide. Unlike a **Query**, which uses partition key equality to jump directly to the relevant items, a Scan must visit all items regardless of your filters.

This makes Scans expensive:

- **Read Capacity**: A Scan consumes RCU proportional to the _total_ data in the table, not the number of results returned.
- **Latency**: Scanning large tables is slow, especially as data grows.
- **Cost**: Higher RCU consumption translates directly to higher AWS bills.

## When does AshDynamo fall back to Scan?

AshDynamo uses a **Query** when it can match a partition key equality filter against the table's primary key or a Global Secondary Index (GSI). It falls back to a **Scan** when:

- No filter is provided at all (e.g., `Ash.read(MyResource)`)
- Filters reference only non-key attributes (no partition key match)
- Filters use expressions that can't be translated to key conditions (e.g., `or` clauses)

## Enabling the Scan warning

By default, AshDynamo performs Scans silently. To opt in to warnings, add this to your config:

```elixir
# config/dev.exs or config/runtime.exs
config :ash_dynamo, warn_on_scan?: true
```

When enabled, AshDynamo logs a warning whenever a Scan is used:

```shell
[warning] AshDynamo: Scan operation on table "posts" for resource AshDynamo.Test.Post. Scans read every item in the table and consume significant read capacity. Add a partition key filter or define a GSI to use a Query instead. To disable this warning set: "config :ash_dynamo, warn_on_scan?: false"
```

This is particularly useful in development to catch unintended Scans early.

## How to avoid Scans

1. **Filter by partition key**: Always include an equality filter on the table's partition key.

   ```elixir
   MyResource |> Ash.Query.filter(email == "user@example.com") |> Ash.read()
   ```

2. **Define a GSI**: If you frequently query by a non-key attribute, consider defining a Global Secondary Index for your table. AshDynamo supports querying by the GSI's partition key:

   ```elixir
   dynamodb do
     table "posts"
     partition_key :author_id
     sort_key :inserted_at

     global_secondary_index :by_status do
       partition_key :status
       sort_key :inserted_at
     end
   end
   ```

   Then filter by the GSI's partition key:

   ```elixir
   Post |> Ash.Query.filter(status == "published") |> Ash.read()
   ```
