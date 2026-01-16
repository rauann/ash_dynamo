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

  describe "runtime sort (Scan mode)" do
    test "sorts posts in descending order without partition key filter" do
      # Create posts with different emails to ensure Scan mode (no PK filter)
      post1 =
        generate(
          post_sort_key(
            email: "aaa@example.com",
            status: "active",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: "bbb@example.com",
            status: "active",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: "ccc@example.com",
            status: "active",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      # Query without PK filter forces Scan mode, runtime sort applies
      query = Ash.Query.sort(PostSortKey, inserted_at: :desc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).inserted_at == post3.inserted_at
      assert Enum.at(results, 1).inserted_at == post2.inserted_at
      assert Enum.at(results, 2).inserted_at == post1.inserted_at
    end

    test "sorts posts in ascending order without partition key filter" do
      post1 =
        generate(
          post_sort_key(
            email: "aaa@example.com",
            status: "active",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: "bbb@example.com",
            status: "active",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: "ccc@example.com",
            status: "active",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      query = Ash.Query.sort(PostSortKey, inserted_at: :asc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).inserted_at == post1.inserted_at
      assert Enum.at(results, 1).inserted_at == post2.inserted_at
      assert Enum.at(results, 2).inserted_at == post3.inserted_at
    end
  end

  describe "runtime sort for non-sort-key fields (Query mode)" do
    test "sorts by non-sort-key field in descending order", %{email: email} do
      post1 =
        generate(
          post_sort_key(
            email: email,
            status: "aaa",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: email,
            status: "bbb",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: email,
            status: "ccc",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      # Query mode (PK filter) + sort by non-sort-key field (status)
      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.sort(status: :desc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).status == post3.status
      assert Enum.at(results, 1).status == post2.status
      assert Enum.at(results, 2).status == post1.status
    end

    test "sorts by non-sort-key field in ascending order", %{email: email} do
      post1 =
        generate(
          post_sort_key(
            email: email,
            status: "aaa",
            inserted_at: "2024-01-01T00:00:00Z"
          )
        )

      post2 =
        generate(
          post_sort_key(
            email: email,
            status: "bbb",
            inserted_at: "2024-01-02T00:00:00Z"
          )
        )

      post3 =
        generate(
          post_sort_key(
            email: email,
            status: "ccc",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.sort(status: :asc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).status == post1.status
      assert Enum.at(results, 1).status == post2.status
      assert Enum.at(results, 2).status == post3.status
    end
  end

  describe "runtime sort on resource without sort key" do
    test "sorts by any field on resource without sort key" do
      post1 = generate(post(status: "aaa"))
      post2 = generate(post(status: "bbb"))
      post3 = generate(post(status: "ccc"))

      query = Ash.Query.sort(Post, status: :desc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).status == post3.status
      assert Enum.at(results, 1).status == post2.status
      assert Enum.at(results, 2).status == post1.status
    end
  end

  describe "multiple sort fields (always runtime sort)" do
    test "sorts by multiple fields using runtime sort", %{email: email} do
      # Same status, different inserted_at - tests secondary sort
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
            status: "inactive",
            inserted_at: "2024-01-03T00:00:00Z"
          )
        )

      # Sort by status desc, then by inserted_at asc
      # Expected order: inactive (post3), then active posts by inserted_at asc (post1, post2)
      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.sort(status: :desc, inserted_at: :asc)

      {:ok, results} = Ash.read(query)

      assert length(results) == 3
      assert Enum.at(results, 0).inserted_at == post3.inserted_at
      assert Enum.at(results, 1).inserted_at == post1.inserted_at
      assert Enum.at(results, 2).inserted_at == post2.inserted_at
    end
  end
end
