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

    {:ok, updated} =
      user
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert updated.email == user.email
    assert updated.inserted_at == user.inserted_at
    assert updated.status == "inactive"
  end

  test "when schema has partition key and sort key, updates the resource" do
    [user1, user2] =
      generate_many(
        user_sort_key(%{
          email: "john.doe2@example.com"
        }),
        2
      )

    assert user1.email == user2.email
    refute user1.inserted_at == user2.inserted_at

    {:ok, updated} =
      user2
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert updated.status == "inactive"
    # TODO: read user1 again
  end
end
