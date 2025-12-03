defmodule AshDynamo.Test.FilterTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator

  require Ash.Query

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  setup do
    AshDynamo.Test.Migrate.create!()

    on_exit(fn ->
      AshDynamo.Test.Migrate.drop!()
    end)
  end

  describe "scan" do
    test "filters with non-key fields" do
      generate(post(status: "active"))

      post = generate(post(status: "inactive"))

      query = Ash.Query.filter(Post, status == "inactive")

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end
  end

  describe "query" do
    test "filters with key partition key field" do
      generate(post(status: "active"))

      %Post{email: email} = post = generate(post(status: "inactive"))

      query = Ash.Query.filter(Post, email == ^email)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with key partition and sort key fields" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at == ^inserted_at)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end
  end
end
