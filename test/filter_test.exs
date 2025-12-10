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

  describe "Runtime filter (scan)" do
    test "filters with non-key fields" do
      generate(post(status: "active"))

      post = generate(post(status: "inactive"))

      query = Ash.Query.filter(Post, status == "inactive")

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with 'is_nil' operator" do
      generate(post(title: "foobar"))

      post = generate(post(title: nil))

      query = Ash.Query.filter(Post, is_nil(title))

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
    end

    test "filters with 'in' operator" do
      generate(post(title: "foobar"))

      post = generate(post(title: "foo"))

      query = Ash.Query.filter(Post, title in ["foo", "bar"])

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with 'contains' operator" do
      generate(post(title: "bar"))

      post = generate(post(title: "foobar foo"))

      query = Ash.Query.filter(Post, contains(title, "foo"))

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with 'or' operator" do
      generate(post(title: "bar", status: "inactive"))

      post = generate(post(title: "foobar", status: "active"))

      query = Ash.Query.filter(Post, title == "foobar" or status == "active")

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end
  end

  describe "KeyConditionExpression (query)" do
    test "filters with key partition key field" do
      generate(post(status: "active"))

      %Post{email: email} = post = generate(post(status: "inactive"))

      query = Ash.Query.filter(Post, email == ^email)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with key partition and sort key field with :== operator" do
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

    test "filters with key partition and sort key field with :> operator" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      {:ok, inserted_at, _} = DateTime.from_iso8601(inserted_at)

      one_day_ago =
        inserted_at
        |> DateTime.add(-1, :day)
        |> DateTime.to_iso8601()

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at > ^one_day_ago)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with key partition and sort key field with :>= operator" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      {:ok, inserted_at, _} = DateTime.from_iso8601(inserted_at)

      one_day_ago =
        inserted_at
        |> DateTime.add(-1, :day)
        |> DateTime.to_iso8601()

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at >= ^one_day_ago)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with key partition and sort key field with :< operator" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      {:ok, inserted_at, _} = DateTime.from_iso8601(inserted_at)

      one_day_after =
        inserted_at
        |> DateTime.add(1, :day)
        |> DateTime.to_iso8601()

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at < ^one_day_after)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with key partition and sort key field with :<= operator" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      {:ok, inserted_at, _} = DateTime.from_iso8601(inserted_at)

      one_day_after =
        inserted_at
        |> DateTime.add(1, :day)
        |> DateTime.to_iso8601()

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at <= ^one_day_after)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end
  end

  describe "FilterExpression (query)" do
    test "filters with :== expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email, inserted_at: inserted_at} =
        post = generate(post_sort_key(status: "inactive"))

      {:ok, inserted_at, _} = DateTime.from_iso8601(inserted_at)

      one_day_after =
        inserted_at
        |> DateTime.add(1, :day)
        |> DateTime.to_iso8601()

      generate(
        post_sort_key(
          email: email,
          status: "active",
          inserted_at: one_day_after
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(inserted_at <= ^one_day_after)
        |> Ash.Query.filter(status == "inactive")

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :!= expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} = generate(post_sort_key(status: "inactive"))

      post =
        generate(
          post_sort_key(
            email: email,
            status: "active"
          )
        )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(status != "inactive")

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :< expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} = post = generate(post_sort_key(status: "active", likes: 3))

      generate(
        post_sort_key(
          email: email,
          likes: 5,
          status: "active"
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(likes < 4)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :<= expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} = post = generate(post_sort_key(status: "active", likes: 4))

      generate(
        post_sort_key(
          email: email,
          likes: 5,
          status: "active"
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(likes <= 4)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :> expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} = post = generate(post_sort_key(status: "active", likes: 4))

      generate(
        post_sort_key(
          email: email,
          likes: 3,
          status: "active"
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(likes > 3)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :>= expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} = post = generate(post_sort_key(status: "active", likes: 4))

      generate(
        post_sort_key(
          email: email,
          likes: 2,
          status: "active"
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(likes >= 3)

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end

    test "filters with :contains expression" do
      generate(post_sort_key(status: "active"))

      %PostSortKey{email: email} =
        post = generate(post_sort_key(status: "active", likes: 4, title: "foobar"))

      generate(
        post_sort_key(
          email: email,
          likes: 2,
          status: "active"
        )
      )

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email and likes >= 3)
        |> Ash.Query.filter(contains(title, "foo"))

      {:ok, [result]} = Ash.read(query)

      assert result.email == post.email
      assert result.status == post.status
    end
  end
end
