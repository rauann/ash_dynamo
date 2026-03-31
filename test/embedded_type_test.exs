defmodule AshDynamo.EmbeddedTypeTest do
  use ExUnit.Case
  import AshDynamo.Test.Setup

  alias AshDynamo.Test.Article
  alias AshDynamo.Test.Tag

  setup :migrate!

  alias AshDynamo.Test.Types.Tag, as: TagType

  describe "type casting" do
    test "when map has valid values, casts successfully" do
      assert {:ok, %Tag{name: "elixir", color: "purple"}} =
               TagType.cast_input(%{name: "elixir", color: "purple"}, [])
    end

    test "when map has string keys, casts successfully" do
      assert {:ok, %Tag{name: "elixir", color: "purple"}} =
               TagType.cast_stored(%{"name" => "elixir", "color" => "purple"}, [])
    end

    test "when map has invalid type for a field, returns error" do
      assert :error = TagType.cast_input(%{name: 123, color: "purple"}, [])
    end

    test "when map has invalid type from storage, returns error" do
      assert :error = TagType.cast_stored(%{"name" => 123, "color" => "purple"}, [])
    end

    test "when value is nil, returns ok nil" do
      assert {:ok, nil} = TagType.cast_input(nil, [])
      assert {:ok, nil} = TagType.cast_stored(nil, [])
    end

    test "when value is already a struct, returns it as-is" do
      tag = %Tag{name: "elixir", color: "purple"}
      assert {:ok, ^tag} = TagType.cast_input(tag, [])
      assert {:ok, ^tag} = TagType.cast_stored(tag, [])
    end

    test "when value is not a map, returns error" do
      assert :error = TagType.cast_input("not a map", [])
      assert :error = TagType.cast_stored("not a map", [])
    end
  end

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

    test "when creating with invalid embedded field type, returns error" do
      result =
        Article
        |> Ash.Changeset.for_create(:create, %{
          slug: "invalid-tag",
          title: "Invalid Tag",
          tags: [%{name: 123, color: "red"}]
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "when DynamoDB contains corrupted embedded data, reading raises error" do
      ExAws.Dynamo.put_item("articles", %{
        "slug" => "corrupted",
        "title" => "Corrupted",
        "tags" => [%{"name" => 123, "color" => "red"}]
      })
      |> ExAws.request!()

      assert_raise Ash.Error.Unknown, fn ->
        Ash.get!(Article, "corrupted")
      end
    end
  end
end
