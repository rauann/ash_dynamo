defmodule AshDynamo.Test.ReadTest do
  use ExUnit.Case
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.Post

  setup :migrate!

  test "reads a resource" do
    attrs = %{
      email: "john.doe@example.com",
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      title: "foobar",
      status: "active"
    }

    "posts"
    |> ExAws.Dynamo.put_item(attrs)
    |> ExAws.request!()

    {:ok, [resource]} = Ash.read(Post)

    assert resource.email == attrs.email
    assert resource.inserted_at == attrs.inserted_at
    assert resource.title == attrs.title
    assert resource.status == attrs.status
  end
end
