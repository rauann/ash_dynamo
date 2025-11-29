defmodule AshDynamo.Test.ReadTest do
  use ExUnit.Case, async: true

  alias AshDynamo.Test.User

  setup do
    AshDynamo.Test.Migrate.create!()

    on_exit(fn ->
      AshDynamo.Test.Migrate.drop!()
    end)
  end

  test "reads a resource" do
    attrs = %{
      email: "john.doe@example.com",
      created_at: DateTime.to_iso8601(DateTime.utc_now()),
      status: "active"
    }

    "users"
    |> ExAws.Dynamo.put_item(attrs)
    |> ExAws.request!()

    [resource] = Ash.read!(User)

    assert resource.email == attrs.email
    assert resource.status == attrs.status
    assert resource.created_at == attrs.created_at
  end
end
