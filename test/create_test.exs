defmodule AshDynamo.Test.CreateTest do
  use ExUnit.Case

  alias AshDynamo.Test.User

  setup do
    AshDynamo.Test.Migrate.create!()

    on_exit(fn ->
      AshDynamo.Test.Migrate.drop!()
    end)
  end

  test "creates a resource" do
    attrs = %{
      email: "john.doe@example.com",
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      phone: "1234567890",
      status: "active"
    }

    assert {:ok, user} = Ash.create(User, attrs)
    assert user.email == attrs.email
    assert user.inserted_at == attrs.inserted_at
    assert user.phone == attrs.phone
    assert user.status == attrs.status
  end
end
