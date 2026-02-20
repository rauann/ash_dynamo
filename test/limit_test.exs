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

  describe "Limit + FilterExpression" do
    test "does not pass Limit to DynamoDB when FilterExpression is present" do
      email = "limit-filter-expr@example.com"

      # Create 10 items with same PK: only 3 match the FilterExpression (status "target"),
      # the other 7 do not (status "noise"). This ratio ensures the test is meaningful —
      # if Limit were passed to DynamoDB, most evaluated items would not match the filter.
      generate_many(post_sort_key(email: email, status: "noise"), 7)
      generate_many(post_sort_key(email: email, status: "target"), 3)

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email and status == "target")
        |> Ash.Query.limit(2)

      {result, requests} =
        capture_all_dynamo_requests(fn ->
          Ash.read(query)
        end)

      assert {:ok, records} = result
      assert length(records) == 2
      assert Enum.all?(records, fn r -> r.status == "target" end)

      # No Limit is passed to DynamoDB when FilterExpression is present.
      # DynamoDB evaluates all 10 items in a single request, applies the FilterExpression
      # server-side, and returns 3 matching items. The Paginator trims to 2.
      assert [single_request] = requests

      assert %{
               "KeyConditionExpression" => "#pk = :v_pk",
               "FilterExpression" => _,
               "TableName" => "posts_sort_key"
             } = single_request

      refute Map.has_key?(single_request, "Limit")
    end

    test "trims excess items when last page exceeds limit" do
      email = "limit-filter-trim@example.com"

      # Create 5 items that all match the FilterExpression.
      # Without Limit passed to DynamoDB, all 5 are returned in one page.
      # The Paginator must trim to the requested limit of 3.
      generate_many(post_sort_key(email: email, status: "target"), 5)

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email and status == "target")
        |> Ash.Query.limit(3)

      {result, _requests} =
        capture_all_dynamo_requests(fn ->
          Ash.read(query)
        end)

      assert {:ok, records} = result
      assert length(records) == 3
    end

    test "still passes Limit when no FilterExpression is present" do
      # When there is no FilterExpression, every evaluated item is returned.
      # Passing Limit is optimal — it avoids over-reading.
      email = "limit-no-filter-expr@example.com"
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
               "KeyConditionExpression" => "#pk = :v_pk",
               "Limit" => 3,
               "TableName" => "posts_sort_key"
             } = request_body

      refute Map.has_key?(request_body, "FilterExpression")

      assert {:ok, records} = result
      assert length(records) == 3
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
