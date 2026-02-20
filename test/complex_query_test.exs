defmodule AshDynamo.Test.ComplexQueryTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup
  import AshDynamo.Test.RequestHelper

  require Ash.Query

  alias AshDynamo.Test.PostGSI
  alias AshDynamo.Test.PostSortKey

  setup :migrate!

  describe "KeyCondition + FilterExpression + Limit" do
    test "combines PK, SK range, server-side filter and limit" do
      email = "complex-kc-fe-limit@example.com"
      cutoff = "2024-01-02T00:00:00Z"

      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-01T00:00:00Z"))

      generate(
        post_sort_key(email: email, status: "deleted", inserted_at: "2024-01-03T00:00:00Z")
      )

      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-04T00:00:00Z"))
      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-05T00:00:00Z"))
      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-06T00:00:00Z"))

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email and inserted_at >= ^cutoff)
        |> Ash.Query.filter(status == "active")
        |> Ash.Query.limit(2)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":fv0" => %{"S" => "active"},
                 ":v_pk" => %{"S" => ^email},
                 ":v_sk" => %{"S" => ^cutoff}
               },
               "FilterExpression" => "#fa0 = :fv0",
               "KeyConditionExpression" => "#pk = :v_pk AND #sk >= :v_sk",
               "TableName" => "posts_sort_key"
             } = request_body

      # Limit is not passed to DynamoDB when FilterExpression is present
      refute Map.has_key?(request_body, "Limit")

      assert {:ok, records} = result
      assert length(records) == 2
    end
  end

  describe "KeyCondition + FilterExpression + Sort + Limit" do
    test "combines PK, server-side filter, native sort and limit" do
      email = "complex-kc-fe-sort-limit@example.com"

      generate(
        post_sort_key(email: email, status: "deleted", inserted_at: "2024-01-01T00:00:00Z")
      )

      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-02T00:00:00Z"))
      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-03T00:00:00Z"))
      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-04T00:00:00Z"))

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(status != "deleted")
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(2)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":fv0" => %{"S" => "deleted"},
                 ":v_pk" => %{"S" => ^email}
               },
               "FilterExpression" => "#fa0 <> :fv0",
               "KeyConditionExpression" => "#pk = :v_pk",
               "ScanIndexForward" => false,
               "TableName" => "posts_sort_key"
             } = request_body

      # Limit is not passed to DynamoDB when FilterExpression is present
      refute Map.has_key?(request_body, "Limit")

      assert {:ok, [first, second]} = result
      assert first.inserted_at == "2024-01-04T00:00:00Z"
      assert second.inserted_at == "2024-01-03T00:00:00Z"
    end
  end

  describe "KeyCondition + Runtime filter + Limit" do
    test "combines PK, runtime 'in' filter and limit" do
      email = "complex-kc-runtime-limit@example.com"

      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-01T00:00:00Z"))

      generate(
        post_sort_key(email: email, status: "pending", inserted_at: "2024-01-02T00:00:00Z")
      )

      generate(
        post_sort_key(email: email, status: "deleted", inserted_at: "2024-01-03T00:00:00Z")
      )

      generate(post_sort_key(email: email, status: "active", inserted_at: "2024-01-04T00:00:00Z"))

      query =
        PostSortKey
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.filter(status in ["active", "pending"])
        |> Ash.Query.limit(2)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      # 'in' operator is not supported by DynamoDB — no FilterExpression
      assert %{
               "ExpressionAttributeValues" => %{":v_pk" => %{"S" => ^email}},
               "KeyConditionExpression" => "#pk = :v_pk",
               "Limit" => 2,
               "TableName" => "posts_sort_key"
             } = request_body

      refute Map.has_key?(request_body, "FilterExpression")

      assert {:ok, records} = result
      assert length(records) == 2
      assert Enum.all?(records, fn r -> r.status in ["active", "pending"] end)
    end
  end

  describe "GSI + SK range + Sort + Limit" do
    test "combines GSI index, SK range, native sort and limit" do
      status = "active"
      cutoff = "2024-01-02T00:00:00Z"

      generate(post_gsi(email: "a@test.com", status: status, inserted_at: "2024-01-01T00:00:00Z"))
      generate(post_gsi(email: "b@test.com", status: status, inserted_at: "2024-01-03T00:00:00Z"))
      generate(post_gsi(email: "c@test.com", status: status, inserted_at: "2024-01-04T00:00:00Z"))
      generate(post_gsi(email: "d@test.com", status: status, inserted_at: "2024-01-05T00:00:00Z"))

      generate(
        post_gsi(email: "e@test.com", status: "inactive", inserted_at: "2024-01-06T00:00:00Z")
      )

      query =
        PostGSI
        |> Ash.Query.filter(status == ^status and inserted_at > ^cutoff)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(2)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status},
                 ":v_sk" => %{"S" => ^cutoff}
               },
               "IndexName" => "by_status",
               "KeyConditionExpression" => "#pk = :v_pk AND #sk > :v_sk",
               "Limit" => 2,
               "ScanIndexForward" => false,
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [first, second]} = result
      assert first.inserted_at == "2024-01-05T00:00:00Z"
      assert second.inserted_at == "2024-01-04T00:00:00Z"
    end
  end
end
