module Mondrian::REST::GraphQL

  QueryRoot = ::GraphQL::ObjectType.define do
    name "QueryRoot"
    description "Query Root"

    field :cubes do
      type types[Types::CubeType]

      resolve -> (object, arguments, context) do
        olap = context[:olap]
        olap.cube_names.map { |cn|
          olap.cube(cn)
        }
      end
    end

    field :cube, Types::CubeType do
      description "Find a cube by name"
      argument :name, !types.String

      resolve -> (object, arguments, context) do
        olap = context[:olap]
        cn = olap.cube_names.detect { |cn| cn == arguments['name'] }
        # TODO guard for name not found
        olap.cube(cn)
      end
    end

    field :aggregate do
      type Types::AggregationType
      description "Aggregate"

    end
  end

  Schema = ::GraphQL::Schema.define do
    query QueryRoot
  end
end
