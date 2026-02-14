# AshDynamo.DataLayer

A DynamoDB data layer for Ash, backed by [ExAws.Dynamo](https://github.com/ex-aws/ex_aws_dynamo).

## DSL Documentation

### dynamodb

Configure the DynamoDB table backing this resource for querying.

Examples:

```elixir
dynamodb do
  table "users"
  partition_key :email
  sort_key :inserted_at

  global_secondary_index :by_status do
    partition_key :status
    sort_key :inserted_at
  end
end
```

### Options

| Name                                                                   | Type       | Default | Docs                                                                         |
| ---------------------------------------------------------------------- | ---------- | ------- | ---------------------------------------------------------------------------- |
| [`table`](#dynamodb-table){: #dynamodb-table }                         | `String.t` |         | Table name to read from/write to. Defaults to the underscored resource name. |
| [`partition_key`](#dynamodb-partition_key){: #dynamodb-partition_key } | `atom`     |         | Required partition (hash) key attribute name.                                |
| [`sort_key`](#dynamodb-sort_key){: #dynamodb-sort_key }                | `atom`     | `nil`   | Optional sort (range) key attribute name.                                    |

### dynamodb.global_secondary_index

Defines a Global Secondary Index (GSI) for automatic query routing.

When a query filters on a GSI's partition key, AshDynamo automatically routes the query to that index instead of scanning the table.

```elixir
global_secondary_index :by_status do
  partition_key :status
  sort_key :inserted_at
end
```

#### Options

| Name                                                                                                                 | Type   | Default | Docs                                                     |
| -------------------------------------------------------------------------------------------------------------------- | ------ | ------- | -------------------------------------------------------- |
| [`name`](#dynamodb-global_secondary_index-name){: #dynamodb-global_secondary_index-name }                            | `atom` |         | Index name (used as the DynamoDB `IndexName` parameter). |
| [`partition_key`](#dynamodb-global_secondary_index-partition_key){: #dynamodb-global_secondary_index-partition_key } | `atom` |         | Partition (hash) key attribute for this GSI.             |
| [`sort_key`](#dynamodb-global_secondary_index-sort_key){: #dynamodb-global_secondary_index-sort_key }                | `atom` | `nil`   | Optional sort (range) key attribute for this GSI.        |
