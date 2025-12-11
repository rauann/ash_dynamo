defmodule AshDynamo.Test.DestroyTest do
  use ExUnit.Case
  import AshDynamo.Test.Generator
  import AshDynamo.Test.Setup

  setup :migrate!

  test "destroys a resource" do
    post = generate(post())

    result =
      post
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.destroy()

    assert :ok = result
  end

  test "when schema has sort key, destroys the resource" do
    post = generate(post_sort_key())

    result =
      post
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.destroy()

    assert :ok = result
  end

  test "when resource does not exist, returns an error" do
    post = Enum.fetch!(post(), 1)

    result =
      post
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.destroy()

    assert {:error, error} = result
    assert Ash.Error.error_descriptions(error) =~ "ConditionalCheckFailedException"
  end
end
