defmodule AshDynamo.EmbeddedType do
  @moduledoc """
  Generates a custom `Ash.Type` for an embedded Ash resource stored in DynamoDB.

  DynamoDB stores embedded resources as plain maps with string keys. When Ash reads
  them back, it tries to "load through" embedded attributes expecting Ash structs with
  `__metadata__`. This causes a `KeyError` on `:__metadata__`.

  This macro generates a type that handles the DynamoDB map ↔ struct conversion and
  sets `cast_in_query?: false` to prevent Ash from loading through.

  ## Usage

  First, define your embedded resource:

      defmodule MyApp.Tag do
        use Ash.Resource, data_layer: :embedded

        attributes do
          attribute :name, :string, allow_nil?: false, public?: true
          attribute :color, :string, allow_nil?: false, public?: true
        end
      end

  Then create a type module for it:

      defmodule MyApp.Types.Tag do
        use AshDynamo.EmbeddedType, resource: MyApp.Tag
      end

  Finally, use the type in your DynamoDB-backed resource:

      defmodule MyApp.Post do
        use Ash.Resource,
          data_layer: AshDynamo.DataLayer,
          domain: MyApp.Domain

        attributes do
          attribute :tags, {:array, MyApp.Types.Tag}, allow_nil?: false
        end
      end

  ## Why is this needed?

  When using `{:array, MyApp.Tag}` directly (the embedded resource), Ash attempts to
  "load through" the embedded attributes after reading from the data layer. This works
  with data layers like AshPostgres that return properly cast embedded structs, but
  DynamoDB returns plain maps with string keys, causing:

      ** (KeyError) key :__metadata__ not found in: %{"name" => "elixir", "color" => "purple"}

  The custom type solves this by:

  1. Casting string-keyed maps from DynamoDB into the embedded resource struct (`cast_stored/2`)
  2. Casting input maps (atom or string keys) into the struct (`cast_input/2`)
  3. Dumping the struct back to a plain map for DynamoDB storage (`dump_to_native/2`)
  4. Returning `cast_in_query?: false` to prevent Ash from loading through the type

  ## ExAws.Dynamo.Encodable

  The macro automatically implements the `ExAws.Dynamo.Encodable` protocol for the
  embedded resource, so ExAws can encode it when writing to DynamoDB. The implementation
  converts the struct to a plain map containing only the resource's attribute fields.

  If you prefer to control the encoding yourself (e.g. to exclude specific fields), you
  can add `@derive {ExAws.Dynamo.Encodable, only: [:name, :color]}` to your embedded
  resource module before `use AshDynamo.EmbeddedType` is called. The macro will skip
  the automatic implementation if one already exists.
  """

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)

    quote do
      use Ash.Type

      alias unquote(resource), as: Resource

      @resource unquote(resource)
      @fields @resource |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      @impl Ash.Type
      def storage_type(_constraints), do: :map

      @impl Ash.Type
      def cast_input(nil, _constraints), do: {:ok, nil}
      def cast_input(%Resource{} = value, _constraints), do: {:ok, value}

      def cast_input(%{} = map, _constraints) do
        attrs =
          Map.new(@fields, fn field ->
            {field, map[field] || map[to_string(field)]}
          end)

        {:ok, struct!(Resource, attrs)}
      end

      def cast_input(_value, _constraints), do: :error

      @impl Ash.Type
      def cast_stored(nil, _constraints), do: {:ok, nil}
      def cast_stored(%Resource{} = value, _constraints), do: {:ok, value}

      def cast_stored(%{} = map, _constraints) do
        attrs =
          Map.new(@fields, fn field ->
            {field, map[field] || map[to_string(field)]}
          end)

        {:ok, struct!(Resource, attrs)}
      end

      def cast_stored(_value, _constraints), do: :error

      @impl Ash.Type
      def dump_to_native(nil, _constraints), do: {:ok, nil}

      def dump_to_native(%Resource{} = value, _constraints) do
        {:ok, Map.new(@fields, fn field -> {field, Map.get(value, field)} end)}
      end

      def dump_to_native(%{} = map, _constraints), do: {:ok, map}
      def dump_to_native(_value, _constraints), do: :error

      @impl Ash.Type
      def cast_in_query?(_constraints), do: false

      unless Enumerable.impl_for(struct!(Resource, %{})) do
        defimpl ExAws.Dynamo.Encodable, for: Resource do
          def encode(value, options) do
            fields = unquote(resource) |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

            value
            |> Map.from_struct()
            |> Map.take(fields)
            |> ExAws.Dynamo.Encodable.encode(options)
          end
        end
      end
    end
  end
end
