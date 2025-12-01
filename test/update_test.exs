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
    post = generate(post())

    result =
      post
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.email == post.email
    assert updated.inserted_at == post.inserted_at
    assert updated.status == "inactive"
  end

  test "when schema has partition key and sort key, updates the resource" do
    post1 = generate(post_sort_key())
    post2 = generate(post_sort_key(email: post1.email))

    assert post1.email == post2.email
    refute post1.inserted_at == post2.inserted_at

    result =
      post2
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.status == "inactive"
    # TODO: read user1 again
  end

  test "when resource does not exist, returns an error" do
    post = Enum.fetch!(post(), 1)

    result =
      post
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
