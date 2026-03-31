defmodule AshDynamo.EmbeddedTypeTest do
  use ExUnit.Case
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.Article
  alias AshDynamo.Test.Tag

  setup :migrate!

  describe "embedded type with AshDynamo.EmbeddedType" do
    test "when creating with embedded structs, persists and reads back correctly" do
      tags = [
        %{name: "elixir", color: "purple"},
        %{name: "ash", color: "orange"}
      ]

      article =
        Article
        |> Ash.Changeset.for_create(:create, %{
          slug: "hello-world",
          title: "Hello World",
          tags: tags
        })
        |> Ash.create!()

      assert article.slug == "hello-world"
      assert length(article.tags) == 2

      # Read back from DynamoDB
      {:ok, loaded} = Ash.get(Article, "hello-world")

      assert loaded.title == "Hello World"
      assert length(loaded.tags) == 2

      [first, second] = Enum.sort_by(loaded.tags, & &1.name)
      assert %Tag{name: "ash", color: "orange"} = first
      assert %Tag{name: "elixir", color: "purple"} = second
    end

    test "when creating with empty embedded list, persists and reads back correctly" do
      article =
        Article
        |> Ash.Changeset.for_create(:create, %{
          slug: "no-tags",
          title: "No Tags",
          tags: []
        })
        |> Ash.create!()

      assert article.tags == []

      {:ok, loaded} = Ash.get(Article, "no-tags")
      assert loaded.tags == []
    end

    test "when reading embedded structs, returns proper Ash resource structs" do
      Article
      |> Ash.Changeset.for_create(:create, %{
        slug: "struct-check",
        title: "Struct Check",
        tags: [%{name: "test", color: "red"}]
      })
      |> Ash.create!()

      {:ok, loaded} = Ash.get(Article, "struct-check")
      [tag] = loaded.tags

      assert %Tag{} = tag
      assert tag.name == "test"
      assert tag.color == "red"
    end
  end
end
