require 'json'
require 'spec_helper.rb'

describe Mondrian::REST::GraphQL::Schema do

  include Rack::Test::Methods

  before(:all) do
    fm_params = setup_foodmart
    @olap = Mondrian::OLAP::Connection.new(fm_params)
    @olap.connect
  end

  def execute(query)
    Mondrian::REST::GraphQL::Schema.execute(query,
                                            context: { olap: @olap })
  end

  describe "Metadata resources" do
    it "should return a list of cubes" do
      # TODO assertions
      puts execute("query { cubes { name } }").inspect
    end

    it "should get dimensions" do
      # TODO assertions
      Q = <<-Q
      query {
        cubes {
          name
          dimensions {
            name
            # type
            hierarchies {
              name
              hasAll
              levels {
                name
                fullName
                caption
                depth
              }
            }
          }
        }
      }
      Q
      puts execute(Q).inspect
    end
  end

  it "should get a cube" do
    # TODO assertions
    Q = <<-Q
      query {
         cube(name: "Sales") {
           name
           dimensions {
             hierarchies {
               name
             }
           }
         }
      }
    Q
    puts execute(Q).inspect
  end

  it "should get a cube" do
    # TODO Assertions
    Q = <<-Q
      query {
         aggregate {
           CubeSales {
             name
           }
         }
      }
    Q
    puts execute(Q).inspect
  end
end
