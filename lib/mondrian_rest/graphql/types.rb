module Mondrian::REST::GraphQL
  module Types
    CubeType = GraphQL::ObjectType.define do
      name "Cube"
      field :name, !types.String, hash_key: :name
      field :dimensions, types[DimensionType], hash_key: :dimensions
      #field :namedSets, types[NamedSetType]
      #field :measures, types[MeasureType]
      #field :annotations, types[AnnotationType]
    end

    DimensionType = GraphQL::ObjectType.define do
      field :name, types.String, hash_key: :name
      field :caption, types.String, hash_key: :caption
      # field :type, GraphQL::EnumType.define do
      #   name "Dimension types"
      #   description "Types of dimensions"
      #   value("STANDARD", "Standard Dimension")
      #   value("TIME", "Time Dimension")
      # end

      field :hierarchies do
        name "hierarchies"
        type types[HierarchyType]

        resolve -> (dimension, arguments, context) do
          dimension.hierarchies
        end
      end
    end

    HierarchyType = GraphQL::ObjectType.define do
      field :name, !types.String, hash_key: :name
    end

    NamedSetType = GraphQL::ObjectType.define do
    end

    MeasureType = GraphQL::ObjectType.define do
    end

    AnnotationType = GraphQL::ObjectType.define do
    end
  end
end
