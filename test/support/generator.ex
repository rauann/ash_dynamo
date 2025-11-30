defmodule AshDynamo.Test.Generator do
  use Ash.Generator

  alias AshDynamo.Test.User
  alias AshDynamo.Test.UserSortKey

  def user_changeset(opts \\ []) do
    changeset_generator(User, :create, overrides: opts)
  end

  def user(opts \\ []) do
    seed_generator(
      %User{
        email: sequence(:unique_email, fn i -> "user#{i}@example.com" end),
        status: "active",
        inserted_at: inserted_at_sequence()
      },
      overrides: opts
    )
  end

  def user_sort_key(opts \\ []) do
    seed_generator(
      %UserSortKey{
        email: sequence(:unique_email, fn i -> "user#{i}@example.com" end),
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
