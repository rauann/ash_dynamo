defmodule AshDynamo.Test.SelectTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.RequestHelper
  import AshDynamo.Test.Setup

  require Ash.Query

  alias AshDynamo.Test.Post

  setup :migrate!

  test "selects only values present in the query (Scan) " do
    %Post{email: email, inserted_at: inserted_at} = generate(post())

    query = Ash.Query.select(Post, [:email, :inserted_at])

    {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

    assert %{
             "ExpressionAttributeNames" => _,
             "ProjectionExpression" => "#f0, #f1",
             "TableName" => "posts"
           } = request_body

    assert {:ok, [record]} = result
    assert record.email == email
    assert record.inserted_at == inserted_at
    assert match?(%Ash.NotLoaded{}, record.status)
    assert match?(%Ash.NotLoaded{}, record.title)
  end
end
