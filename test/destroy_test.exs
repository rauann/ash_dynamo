defmodule AshDynamo.Test.DestroyTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.RequestHelper
  import AshDynamo.Test.Setup

  setup :migrate!

  test "destroys a resource" do
    post = generate(post())

    {result, request_body} =
      capture_dynamo_request(fn ->
        post
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy()
      end)

    email = post.email

    assert %{
             "ConditionExpression" => "attribute_exists(#pk)",
             "ExpressionAttributeNames" => %{"#pk" => "email"},
             "Key" => %{"email" => %{"S" => ^email}},
             "TableName" => "posts"
           } = request_body

    assert :ok = result
  end

  test "when schema has sort key, destroys the resource" do
    post = generate(post_sort_key())

    {result, request_body} =
      capture_dynamo_request(fn ->
        post
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy()
      end)

    email = post.email
    inserted_at = post.inserted_at

    assert %{
             "ConditionExpression" => "attribute_exists(#pk) AND attribute_exists(#sk)",
             "ExpressionAttributeNames" => %{"#pk" => "email", "#sk" => "inserted_at"},
             "Key" => %{
               "email" => %{"S" => ^email},
               "inserted_at" => %{"S" => ^inserted_at}
             },
             "TableName" => "posts_sort_key"
           } = request_body

    assert :ok = result
  end

  test "when resource does not exist, returns an error" do
    post = Enum.fetch!(post(), 1)

    {result, request_body} =
      capture_dynamo_request(fn ->
        post
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy()
      end)

    email = post.email

    assert %{
             "ConditionExpression" => "attribute_exists(#pk)",
             "ExpressionAttributeNames" => %{"#pk" => "email"},
             "Key" => %{"email" => %{"S" => ^email}},
             "TableName" => "posts"
           } = request_body

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
