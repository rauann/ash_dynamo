defmodule AshDynamo.Test.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshDynamo.Test.Post
    resource AshDynamo.Test.PostSortKey
    resource AshDynamo.Test.PostGSI
  end
end
