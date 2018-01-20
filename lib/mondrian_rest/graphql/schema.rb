module Mondrian::REST::GraphQL

  QueryRoot = ::GraphQL::ObjectType.define do
    name "QueryRoot"
    description "Query Root"

    field :cubes do
      name "cubes"
      type types[Types::CubeType]

      resolve -> (object, arguments, context) do
        olap = context[:olap]
        olap.cube_names.map { |cn|
          olap.cube(cn).to_h
        }
      end
    end

    # field :cube, Types::CubeType do
    #   description "Find a cube by name"
    #   arguments :name, !type.String

    #   resolve -> (object, arguments, context) do
    #     # TODO guard for name not found
    #     olap = context[:olap]
    #     olap.cube_names.find { |cn| cn == arguments[:name] }
    #   end
    # end
  end

  Schema = ::GraphQL::Schema.define do
    query QueryRoot
  end

end
