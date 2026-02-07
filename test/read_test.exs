defmodule AshDynamo.Test.ReadTest do
  use ExUnit.Case
  import AshDynamo.Test.RequestHelper
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.Post

  setup :migrate!

  test "reads a resource" do
    attrs = %{
      email: "john.doe@example.com",
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      title: "foobar",
      status: "active"
    }

    "posts"
    |> ExAws.Dynamo.put_item(attrs)
    |> ExAws.request!()

    {result, request_body} = capture_dynamo_request(fn -> Ash.read(Post) end)

    assert %{
             "ExpressionAttributeNames" => _,
             "ProjectionExpression" => _,
             "TableName" => "posts"
           } = request_body

    assert {:ok, [resource]} = result
    assert resource.email == attrs.email
    assert resource.inserted_at == attrs.inserted_at
    assert resource.title == attrs.title
    assert resource.status == attrs.status
  end
end
