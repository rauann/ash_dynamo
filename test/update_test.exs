defmodule AshDynamo.Test.UpdateTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator

  setup do
    AshDynamo.Test.Migrate.create!()

    on_exit(fn ->
      AshDynamo.Test.Migrate.drop!()
    end)
  end

  test "updates a resource" do
    user = generate(user())

    result =
      user
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.email == user.email
    assert updated.inserted_at == user.inserted_at
    assert updated.status == "inactive"
  end

  test "when schema has partition key and sort key, updates the resource" do
    user1 = generate(user_sort_key())
    user2 = generate(user_sort_key(email: user1.email))

    assert user1.email == user2.email
    refute user1.inserted_at == user2.inserted_at

    result =
      user2
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.status == "inactive"
    # TODO: read user1 again
  end

  test "when resource does not exist, returns an error" do
    user = Enum.fetch!(user(), 1)

    result =
      user
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
