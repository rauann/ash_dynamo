defmodule AshDynamo.Test.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshDynamo.Test.Article
    resource AshDynamo.Test.Post
    resource AshDynamo.Test.PostGSI
    resource AshDynamo.Test.PostSortKey
  end
end
