defmodule AshDynamo.Test.SortTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup

  require Ash.Query

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  setup :migrate!

  setup do
    {:ok, email: "foo@example.com"}
  end

  describe "sort by sort key (Query mode)" do
    test "sorts posts by sort key in descending order", %{email: email} do
      post1 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.sort(inserted_at: :desc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).inserted_at == post3.inserted_at
      assert Enum.at(results, 1).inserted_at == post2.inserted_at
      assert Enum.at(results, 2).inserted_at == post1.inserted_at
    end

    test "sorts posts by sort key in ascending order", %{email: email} do
      post1 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.sort(inserted_at: :asc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).inserted_at == post1.inserted_at
      assert Enum.at(results, 1).inserted_at == post2.inserted_at
      assert Enum.at(results, 2).inserted_at == post3.inserted_at
    end

    test "default sort order is ascending (DynamoDB default)", %{email: email} do
      post1 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: email,
            status: "active",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      query = Ash.Query.filter(PostSortKey, email == ^email)

      {:ok, results} = Ash.read(query)

      assert length(results) == 2
      assert Enum.at(results, 0).inserted_at == post1.inserted_at
      assert Enum.at(results, 1).inserted_at == post2.inserted_at
    end
  end

  describe "sort validation errors" do
    test "returns error when sorting on resource without sort key" do
      query = Ash.Query.sort(Post, inserted_at: :desc)

      assert {:error, error} = Ash.read(query)
      assert Exception.message(error) =~ "Cannot sort without a sort key"
    end

    test "returns error when sorting on non-sort-key field" do
      query = Ash.Query.sort(PostSortKey, status: :desc)

      assert {:error, error} = Ash.read(query)
      assert Exception.message(error) =~ "DynamoDB only supports sorting by the sort key"
    end

    test "returns error when sorting on multiple fields" do
      query = Ash.Query.sort(PostSortKey, inserted_at: :desc, status: :asc)

      assert {:error, error} = Ash.read(query)
      assert Exception.message(error) =~ "DynamoDB only supports sorting by a single field"
    end
  end
end
