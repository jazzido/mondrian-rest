require 'json'
require 'spec_helper.rb'

describe Mondrian::REST::GraphQL::Schema do

  include Rack::Test::Methods

  before(:all) do
    fm_params = setup_foodmart
    @olap = Mondrian::OLAP::Connection.new(fm_params)
    @olap.connect
  end

  describe "Metadata resources" do
    it "should return a list of cubes" do
      # TODO assertions
      puts Mondrian::REST::GraphQL::Schema.execute("query { cubes { name } }",
                                                   context: { olap: @olap }).inspect
    end

    it "should get dimensions" do
      # TODO assertions
      Q = <<-Q
      query {
        cubes {
          name
        }
      }
      Q
      puts Mondrian::REST::GraphQL::Schema.execute(Q,
                                                   context: { olap: @olap }).inspect
    end
  end

end
