defmodule AshDynamo.Test.Generator do
  @moduledoc false

  use Ash.Generator

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  def post_changeset(opts \\ []) do
    changeset_generator(Post, :create, overrides: opts)
  end

  def post(opts \\ []) do
    seed_generator(
      %Post{
        email: sequence(:unique_email, fn i -> "post#{i}@example.com" end),
        status: "active"
      },
      overrides: opts
    )
  end

  def post_sort_key(opts \\ []) do
    seed_generator(
      %PostSortKey{
        email: sequence(:unique_email, fn i -> "post#{i}@example.com" end),
        likes: sequence(:unique_likes, fn i -> i end),
        status: "active"
      },
      overrides: opts
    )
  end
end
