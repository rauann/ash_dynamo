defmodule AshDynamo.Test.CreateTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator

  alias AshDynamo.Test.User
  alias AshDynamo.Test.UserSortKey

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

    result =
      User
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:ok, user} = result
    assert user.email == attrs.email
    assert user.inserted_at == attrs.inserted_at
    assert user.phone == attrs.phone
    assert user.status == attrs.status
  end

  test "when resource exists with same partition key, returns an error" do
    user = generate(user())

    attrs = %{
      email: user.email,
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      status: "active"
    }

    result =
      User
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end

  test "when resource exists with same partition key and sort key, returns an error" do
    user = generate(user_sort_key())

    attrs = %{
      email: user.email,
      inserted_at: user.inserted_at,
      status: "active"
    }

    result =
      UserSortKey
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
