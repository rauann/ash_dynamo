defmodule AshDynamo.Test.Tag do
  @moduledoc false

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :color, :string, allow_nil?: false, public?: true
  end
end

defmodule AshDynamo.Test.Types.Tag do
  @moduledoc false

  use AshDynamo.EmbeddedType, resource: AshDynamo.Test.Tag
end
