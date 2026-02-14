defmodule AshDynamo.Test.SecondaryIndexQueryTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup
  import AshDynamo.Test.RequestHelper

  require Ash.Query

  alias AshDynamo.Test.PostGSI

  setup :migrate!

  describe "GSI query routing" do
    test "queries by GSI partition key use Query with IndexName" do
      status = "active"

      generate(post_gsi(status: "inactive"))
      post = generate(post_gsi(status: status, title: "hello"))

      query = Ash.Query.filter(PostGSI, status == ^status)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status}
               },
               "IndexName" => "by_status",
               "KeyConditionExpression" => "#pk = :v_pk",
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [result]} = result
      assert result.email == post.email
    end

    test "queries by GSI partition key with sort key condition" do
      status = "active"
      inserted_at = "2024-01-01T12:00:00Z"

      generate(post_gsi(status: "inactive"))
      generate(post_gsi(email: "a@test.com", status: status, inserted_at: inserted_at))

      post =
        generate(
          post_gsi(email: "b@test.com", status: status, inserted_at: "2024-01-02T00:00:00Z")
        )

      query =
        PostGSI
        |> Ash.Query.filter(status == ^status and inserted_at > ^inserted_at)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status},
                 ":v_sk" => %{"S" => ^inserted_at}
               },
               "IndexName" => "by_status",
               "KeyConditionExpression" => "#pk = :v_pk AND #sk > :v_sk",
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [result]} = result
      assert result.email == post.email
    end

    test "queries by second GSI (by_title) use correct IndexName" do
      title = "unique-title"

      generate(post_gsi(status: "inactive"))
      post = generate(post_gsi(title: title, status: "active"))

      query = Ash.Query.filter(PostGSI, title == ^title)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^title}
               },
               "IndexName" => "by_title",
               "KeyConditionExpression" => "#pk = :v_pk",
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [result]} = result
      assert result.email == post.email
    end

    test "table partition key takes priority over GSI" do
      generate(post_gsi(status: "inactive"))

      post = generate(post_gsi(status: "active"))
      email = post.email

      query = Ash.Query.filter(PostGSI, email == ^email)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      # Should NOT have IndexName — querying the main table
      refute Map.has_key?(request_body, "IndexName")

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^email}
               },
               "KeyConditionExpression" => "#pk = :v_pk",
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [result]} = result
      assert result.email == post.email
    end

    test "non-key filter falls back to Scan" do
      likes = 42

      generate(post_gsi(status: "inactive"))
      post = generate(post_gsi(likes: likes, status: "active"))

      query = Ash.Query.filter(PostGSI, likes == ^likes)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      # Scan has no KeyConditionExpression or IndexName
      refute Map.has_key?(request_body, "KeyConditionExpression")
      refute Map.has_key?(request_body, "IndexName")

      assert %{"TableName" => "posts_gsi"} = request_body

      assert {:ok, [result]} = result
      assert result.email == post.email
    end
  end

  describe "GSI sort optimization" do
    test "sort by GSI sort key uses ScanIndexForward" do
      status = "active"

      generate(post_gsi(status: "inactive"))
      generate(post_gsi(email: "a@test.com", status: status, inserted_at: "2024-01-01T00:00:00Z"))

      generate(post_gsi(email: "b@test.com", status: status, inserted_at: "2024-01-02T00:00:00Z"))

      query =
        PostGSI
        |> Ash.Query.filter(status == ^status)
        |> Ash.Query.sort(inserted_at: :desc)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status}
               },
               "IndexName" => "by_status",
               "ScanIndexForward" => false,
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [first | _]} = result
      assert first.inserted_at == "2024-01-02T00:00:00Z"
    end

    test "sort by GSI sort key ascending uses ScanIndexForward true" do
      status = "active"

      generate(post_gsi(status: "inactive"))
      generate(post_gsi(email: "a@test.com", status: status, inserted_at: "2024-01-01T00:00:00Z"))

      generate(post_gsi(email: "b@test.com", status: status, inserted_at: "2024-01-02T00:00:00Z"))

      query =
        PostGSI
        |> Ash.Query.filter(status == ^status)
        |> Ash.Query.sort(inserted_at: :asc)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status}
               },
               "IndexName" => "by_status",
               "ScanIndexForward" => true,
               "TableName" => "posts_gsi"
             } = request_body

      assert {:ok, [first | _]} = result
      assert first.inserted_at == "2024-01-01T00:00:00Z"
    end

    test "sort by non-GSI-sort-key field uses runtime sort" do
      status = "active"

      generate(post_gsi(status: "inactive"))
      generate(post_gsi(email: "a@test.com", status: status, title: "bbb"))

      generate(post_gsi(email: "b@test.com", status: status, title: "aaa"))

      query =
        PostGSI
        |> Ash.Query.filter(status == ^status)
        |> Ash.Query.sort(title: :asc)

      {result, request_body} = capture_dynamo_request(fn -> Ash.read(query) end)

      assert %{
               "ExpressionAttributeValues" => %{
                 ":v_pk" => %{"S" => ^status}
               },
               "IndexName" => "by_status"
             } = request_body

      # No ScanIndexForward — title is not the GSI's sort key
      refute Map.has_key?(request_body, "ScanIndexForward")

      assert {:ok, [first | _]} = result
      assert first.title == "aaa"
    end
  end
end
