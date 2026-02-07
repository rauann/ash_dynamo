defmodule AshDynamo.Test.CreateTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.RequestHelper
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  setup :migrate!

  test "creates a resource" do
    attrs = %{
      email: "john.doe@example.com",
      title: "foobar",
      status: "active"
    }

    {result, request_body} =
      capture_dynamo_request(fn ->
        Post
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      end)

    assert %{
             "ConditionExpression" => "attribute_not_exists(#pk)",
             "ExpressionAttributeNames" => %{"#pk" => "email"},
             "Item" => %{
               "email" => %{"S" => "john.doe@example.com"},
               "inserted_at" => %{"S" => _},
               "status" => %{"S" => "active"},
               "title" => %{"S" => "foobar"}
             },
             "TableName" => "posts"
           } = request_body

    assert {:ok, user} = result
    assert user.email == attrs.email
    assert user.title == attrs.title
    assert user.status == attrs.status
  end

  test "when resource exists with same partition key, returns an error" do
    post = generate(post())

    attrs = %{
      email: post.email,
      inserted_at: DateTime.to_iso8601(DateTime.utc_now()),
      status: "active"
    }

    {result, request_body} =
      capture_dynamo_request(fn ->
        Post
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      end)

    email = post.email

    assert %{
             "ConditionExpression" => "attribute_not_exists(#pk)",
             "ExpressionAttributeNames" => %{"#pk" => "email"},
             "Item" => %{
               "email" => %{"S" => ^email},
               "inserted_at" => %{"S" => _},
               "status" => %{"S" => "active"}
             },
             "TableName" => "posts"
           } = request_body

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end

  test "when resource exists with same partition key and sort key, returns an error" do
    post = generate(post_sort_key())

    attrs = %{
      email: post.email,
      inserted_at: post.inserted_at,
      status: "active"
    }

    email = post.email
    inserted_at = post.inserted_at

    {result, request_body} =
      capture_dynamo_request(fn ->
        PostSortKey
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      end)

    assert %{
             "ConditionExpression" => "attribute_not_exists(#pk) AND attribute_not_exists(#sk)",
             "ExpressionAttributeNames" => %{"#pk" => "email", "#sk" => "inserted_at"},
             "Item" => %{
               "email" => %{"S" => ^email},
               "inserted_at" => %{"S" => ^inserted_at},
               "status" => %{"S" => "active"}
             },
             "TableName" => "posts_sort_key"
           } = request_body

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
