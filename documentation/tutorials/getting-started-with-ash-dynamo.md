# Getting Started with AshDynamo

This guide will walk you through setting up AshDynamo to use DynamoDB as a data layer for your Ash resources.

## Define a Resource

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

## Using the Resource

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

# read (Query-based)
{:ok, posts} =
  MyApp.Post
  |> Ash.Query.filter(id == ^id)
  |> Ash.read()
```

## Configuring ExAws

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
  secret_access_key: "secretaccesskey",
  debug_requests: true

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 8088,
  region: "eu-west-1"
```

## DynamoDB Tables

The partition/sort keys in your DynamoDB table must match the keys defined in your resource's `dynamodb` DSL section.

See [`ExAws.Dynamo`](https://hexdocs.pm/ex_aws_dynamo/ExAws.Dynamo.html#functions) for creating tables programmatically.
