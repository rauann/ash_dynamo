defmodule AshDynamo.Test.ReadTest do
  use ExUnit.Case

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
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      phone: "1234567890",
      status: "active"
    }

    "users"
    |> ExAws.Dynamo.put_item(attrs)
    |> ExAws.request!()

    {:ok, [resource]} = Ash.read(User)

    assert resource.email == attrs.email
    assert resource.inserted_at == attrs.inserted_at
    assert resource.phone == attrs.phone
    assert resource.status == attrs.status
  end
end
