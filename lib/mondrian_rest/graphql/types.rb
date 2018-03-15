module Mondrian::REST::GraphQL
  module Types
    CubeType = ::GraphQL::ObjectType.define do
      name "Cube"
      field :name, !types.String
      field :dimensions, types[DimensionType] do
        resolve -> (cube, arguments, context) do
          cube.dimensions.find_all { |d| d.dimension_type != :measures }
        end
      end
      #field :namedSets, types[NamedSetType]
      #field :measures, types[MeasureType]
      #field :annotations, types[AnnotationType]

      # field :aggregations, types[AggregationType] do

    end

    DimensionType = ::GraphQL::ObjectType.define do
      name "Dimension"
      field :name, types.String
      field :caption, types.String
      # field :type, GraphQL::EnumType.define do
      #   name "Dimension types"
      #   description "Types of dimensions"
      #   value("STANDARD", "Standard Dimension")
      #   value("TIME", "Time Dimension")
      # end

      field :hierarchies, types[HierarchyType] do
        resolve -> (dimension, arguments, context) do
          puts context.inspect
          dimension.hierarchies
        end
      end
    end

    HierarchyType = ::GraphQL::ObjectType.define do
      name "Hierarchy"
      field :name, !types.String
      field :hasAll, types.Boolean, property: :has_all?
      field :levels, types[LevelType]
    end

    LevelType = ::GraphQL::ObjectType.define do
      name "Level"
      field :name, !types.String
      field :fullName, types.String, property: :full_name
      field :caption, types.String
      field :depth, types.Int
      field :members, types[MemberType]
    end

    MemberType = ::GraphQL::ObjectType.define do
      name "Member"

      field :name, !types.String
    end

    AggregationType = ::GraphQL::ObjectType.define do
      name "Aggregation"

      olap = Mondrian::REST::APIHelpers.olap
      olap.cube_names.each do |cn|
        cube = olap.cube(cn)
        field camelize_cube(cube), create_cube_aggregation_type(cube)
      end
    end


    NamedSetType = ::GraphQL::ObjectType.define do
    end

    MeasureType = ::GraphQL::ObjectType.define do
    end

    AnnotationType = ::GraphQL::ObjectType.define do
    end
  end
end

