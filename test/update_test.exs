defmodule AshDynamo.Test.UpdateTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.PostSortKey
  require Ash.Query

  setup :migrate!

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

  test "when schema has sort key, updates the resource" do
    post1 = generate(post_sort_key())

    %PostSortKey{email: email, inserted_at: inserted_at} =
      post2 = generate(post_sort_key(email: post1.email))

    assert post1.email == post2.email
    refute post1.inserted_at == post2.inserted_at

    result =
      post2
      |> Ash.Changeset.for_update(:update, %{status: "inactive"})
      |> Ash.update()

    assert {:ok, updated} = result
    assert updated.status == "inactive"

    query =
      PostSortKey
      |> Ash.Query.filter(email == ^email)
      |> Ash.Query.filter(inserted_at == ^inserted_at)

    assert {
             :ok,
             %PostSortKey{
               email: ^email,
               inserted_at: ^inserted_at,
               status: "inactive"
             }
           } = Ash.load(updated, query)
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
