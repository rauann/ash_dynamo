defmodule AshDynamo.Test.SelectTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup

  require Ash.Query

  alias AshDynamo.Test.Post

  setup :migrate!

  test "selects only values present in the query (Scan) " do
    %Post{email: email, inserted_at: inserted_at} = generate(post())

    query = Ash.Query.select(Post, [:email, :inserted_at])

    {:ok, [result]} = Ash.read(query)

    assert result.email == email
    assert result.inserted_at == inserted_at
    assert match?(%Ash.NotLoaded{}, result.status)
    assert match?(%Ash.NotLoaded{}, result.title)
  end
end
