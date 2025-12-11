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
end
```

### Options

| Name                                                                   | Type       | Default | Docs                                                                         |
| ---------------------------------------------------------------------- | ---------- | ------- | ---------------------------------------------------------------------------- |
| [`table`](#dynamodb-table){: #dynamodb-table }                         | `String.t` |         | Table name to read from/write to. Defaults to the underscored resource name. |
| [`partition_key`](#dynamodb-partition_key){: #dynamodb-partition_key } | `atom`     |         | Required partition (hash) key attribute name.                                |
| [`sort_key`](#dynamodb-sort_key){: #dynamodb-sort_key }                | `atom`     | `nil`   | Optional sort (range) key attribute name.                                    |
