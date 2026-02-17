defmodule AshDynamo.Test.LimitTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup
  import AshDynamo.Test.RequestHelper

  require Ash.Query

  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  setup :migrate!

  describe "Scan" do
    test "limits the number of returned records" do
      generate_many(post(), 5)

      query = Ash.Query.limit(Post, 3)

      {result, request_body} =
        capture_dynamo_request(fn ->
          Ash.read(query)
        end)

      assert %{
               "ExpressionAttributeNames" => _,
               "Limit" => 3,
               "ProjectionExpression" => _,
               "TableName" => "posts"
             } = request_body

      assert {:ok, records} = result
      assert length(records) == 3
    end

    test "paginates with LastEvaluatedKey when results exceed 1MB" do
      # Each item ~1KB with a large body, ~1100 items exceeds the 1MB page limit.
      # Limit is set lower than the total count to test that the paginator
      # passes the remaining count to DynamoDB on subsequent requests.
      large_body = String.duplicate("x", 1_000)
      generate_many(post(body: large_body), 1_100)

      limit = 1_050
      query = Ash.Query.limit(Post, limit)

      {result, requests} =
        capture_all_dynamo_requests(fn ->
          Ash.read(query)
        end)

      assert [first_request, second_request | _] = requests

      assert %{
               "ExpressionAttributeNames" => _,
               "Limit" => ^limit,
               "ProjectionExpression" => _,
               "TableName" => "posts"
             } = first_request

      assert %{
               "ExclusiveStartKey" => %{"email" => %{"S" => _}},
               "Limit" => remaning_limit,
               "TableName" => "posts"
             } = second_request

      assert {:ok, records} = result
      assert length(records) == limit
      assert remaning_limit < limit
    end
  end

  describe "Query" do
    test "limits the number of returned records" do
      email = "limit-query@example.com"
      generate_many(post_sort_key(email: email), 5)

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.limit(3)

      {result, request_body} =
        capture_dynamo_request(fn ->
          Ash.read(query)
        end)

      assert %{
               "ExpressionAttributeNames" => _,
               "ExpressionAttributeValues" => %{":v_pk" => %{"S" => ^email}},
               "KeyConditionExpression" => "#pk = :v_pk",
               "Limit" => 3,
               "ProjectionExpression" => _,
               "TableName" => "posts_sort_key"
             } = request_body

      assert {:ok, records} = result
      assert length(records) == 3
    end

    test "paginates with LastEvaluatedKey when results exceed 1MB" do
      email = "limit-query-paginated@example.com"
      large_body = String.duplicate("x", 1_000)
      generate_many(post_sort_key(email: email, body: large_body), 1_100)

      limit = 1_050

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.limit(limit)

      {result, requests} =
        capture_all_dynamo_requests(fn ->
          Ash.read(query)
        end)

      assert [first_request, second_request | _] = requests

      assert %{
               "ExpressionAttributeNames" => _,
               "ExpressionAttributeValues" => %{":v_pk" => %{"S" => ^email}},
               "KeyConditionExpression" => "#pk = :v_pk",
               "Limit" => ^limit,
               "ProjectionExpression" => _,
               "TableName" => "posts_sort_key"
             } = first_request

      assert %{
               "ExclusiveStartKey" => %{
                 "email" => %{"S" => ^email},
                 "inserted_at" => %{"S" => _}
               },
               "KeyConditionExpression" => "#pk = :v_pk",
               "Limit" => remaning_limit,
               "TableName" => "posts_sort_key"
             } = second_request

      assert {:ok, records} = result
      assert length(records) == limit
      assert remaning_limit < limit
    end
  end
end
