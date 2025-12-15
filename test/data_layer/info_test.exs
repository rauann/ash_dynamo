defmodule AshDynamo.Test.DataLayerInfoTest do
  use ExUnit.Case

  alias AshDynamo.DataLayer.Info
  alias AshDynamo.Test.Post
  alias AshDynamo.Test.PostSortKey

  describe "table/1" do
    test "returns configured table name" do
      assert Info.table(Post) == "posts"
      assert Info.table(PostSortKey) == "posts_sort_key"
    end
  end

  describe "partition_key/1" do
    test "returns configured partition key" do
      assert Info.partition_key(Post) == :email
      assert Info.partition_key(PostSortKey) == :email
    end
  end

  describe "sort_key/1" do
    test "returns nil when not configured" do
      assert Info.sort_key(Post) == nil
    end

    test "returns configured sort key" do
      assert Info.sort_key(PostSortKey) == :inserted_at
    end
  end

  describe "global_secondary_indexes/1" do
    test "returns empty list when not configured" do
      assert Info.global_secondary_indexes(Post) == []
      assert Info.global_secondary_indexes(PostSortKey) == []
    end
  end

  describe "local_secondary_indexes/1" do
    test "returns empty list when not configured" do
      assert Info.local_secondary_indexes(Post) == []
      assert Info.local_secondary_indexes(PostSortKey) == []
    end
  end
end
