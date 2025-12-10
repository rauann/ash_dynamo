# AshDynamo

Ash data layer for DynamoDB backed by [ExAws.Dynamo](https://github.com/ex-aws/ex_aws_dynamo). It provides a `dynamodb` DSL section so an Ash resource can declare its table, partition/sort keys, and actions, and then persist records to Dynamo.

## Installation

If [available in Hex](https://hex.pm/docs/publish), add `ash_dynamo` to `mix.exs`:

```elixir
def deps do
  [
    {:ash_dynamo, "~> 0.1.0"}
  ]
end
```

## Supported Ash Features

### CRUD Operations

| Capability | Status | Notes                                              |
| ---------- | ------ | -------------------------------------------------- |
| `:read`    | ✅     | Query (with PK) or Scan fallback                   |
| `:create`  | ✅     | PutItem with uniqueness check                      |
| `:update`  | ✅     | UpdateItem with existence check                    |
| `:destroy` | ✅     | DeleteItem with existence check                    |
| `:select`  | ✅     | ProjectionExpression                               |
| `:filter`  | ✅     | KeyCondition + FilterExpression + Runtime fallback |

### Filter Operators

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

### Not Supported / Not Implemented

| Feature               | Notes                                           |
| --------------------- | ----------------------------------------------- |
| `:or`                 | Possible via filter expression. Not implemented |
| `:upsert`             | Explicit upsert mode. Not implemented           |
| `:sort`               | Sort by SK. Not implemented                     |
| `:limit` / `:offset`  | Pagination. Not implemented                     |
| `:aggregate`          | Possible via `Select: COUNT`. Not implemented   |
| Bulk operations       | Bulk insert/update/delete. Not implemented      |
| GSI/LSI query routing | DSL defined. Not implemented                    |
| Relationships         | DynamoDB has no native joins. Not supported     |
| Transactions          | DynamoDB TransactWriteItems. Not supported      |

## Usage

Define a resource with the `dynamodb` section and the usual Ash actions/attributes:

```elixir
defmodule MyApp.Post do
  use Ash.Resource, data_layer: AshDynamo.DataLayer, domain: MyApp.Domain

  dynamodb do
    table "posts"
    partition_key :id
    sort_key :inserted_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title]
    end

    update :update do
      accept [:title]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false

    attribute :inserted_at, :string do
      writable? false
      default fn -> DateTime.to_iso8601(DateTime.utc_now()) end
      allow_nil? false
    end
  end
end
```

Then use it as any Ash resource:

```elixir
# create
{:ok, post} =
  MyApp.Post
  |> Ash.Changeset.for_create(:create, %{title: "hello"})
  |> Ash.create()

# update
{:ok, post} =
  post
  |> Ash.Changeset.for_update(:update, %{title: "updated"})
  |> Ash.update()

# destroy
:ok =
  post
  |> Ash.Changeset.for_destroy(:destroy)
  |> Ash.destroy()

# read (Scan-based)
{:ok, posts} = Ash.read(MyApp.Post)
```

Make sure `ExAws` is configured for your Dynamo endpoint (local or AWS):

```elixir
# config/prod.exs

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]
```

```elixir
# config/dev.exs

config :ex_aws,
  access_key_id: "accesskeyid",
  secret_access_key: "secretaccesskey"

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 8088,
  region: "eu-west-1"
```

Partition/sort keys must match your table definition. Example of a `posts` table with `id` as the partition key,
`inserted_at` as the sort key, no GSI/LSI and on-demaind billing mode created using `ExAws.Dynamo`:

```elixir
ExAws.Dynamo.create_table(
  "posts",
  [id: :hash, inserted_at: :range],
  %{id: :string, inserted_at: :string},
  nil,
  nil,
  [],
  [],
  :pay_per_request
)
|> ExAws.request!()
```

Generate docs with [ExDoc](https://github.com/elixir-lang/ex_doc); once published they’ll be at <https://hexdocs.pm/ash_dynamo>.
