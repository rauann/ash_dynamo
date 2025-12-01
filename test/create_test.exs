defmodule AshDynamo.Test.CreateTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

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
      title: "foobar",
      status: "active"
    }

    result =
      Post
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:ok, user} = result
    assert user.email == attrs.email
    assert user.inserted_at == attrs.inserted_at
    assert user.title == attrs.title
    assert user.status == attrs.status
  end

  test "when resource exists with same partition key, returns an error" do
    post = generate(post())

    attrs = %{
      email: post.email,
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      status: "active"
    }

    result =
      Post
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end

  test "when resource exists with same partition key and sort key, returns an error" do
    post = generate(post_sort_key())

    attrs = %{
      email: post.email,
      inserted_at: post.inserted_at,
      status: "active"
    }

    result =
      PostSortKey
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
