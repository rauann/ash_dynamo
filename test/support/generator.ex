defmodule AshDynamo.Test.Generator do
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
        status: "active",
        inserted_at: inserted_at_sequence()
      },
      overrides: opts
    )
  end

  def post_sort_key(opts \\ []) do
    seed_generator(
      %PostSortKey{
        email: sequence(:unique_email, fn i -> "post#{i}@example.com" end),
        status: "active",
        inserted_at: inserted_at_sequence()
      },
      overrides: opts
    )
  end

  defp inserted_at_sequence do
    sequence(:inserted_at, fn i ->
      DateTime.utc_now()
      |> DateTime.add(i, :minute)
      |> DateTime.to_iso8601()
    end)
  end
end
