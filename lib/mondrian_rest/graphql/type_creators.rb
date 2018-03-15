require "active_support"

module Mondrian::REST::GraphQL

  def camelize_cube(cube)
    ActiveSupport::Inflector.camelize(cube.name.tr(' ', '_'))
  end

  def create_cube_aggregation_type(mondrian_cube)
    ::GraphQL::ObjectType.define do
      name("Cube#{camelize_cube(mondrian_cube)}")

      field :name, types.String do
        resolve -> (cube, arguments, context) do
          cube.name
        end
      end
    end
  end
end
