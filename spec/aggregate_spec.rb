require 'json'
require 'spec_helper.rb'

describe "Mondrian REST API" do

  include Rack::Test::Methods

  before(:all) do
    @agg = Mondrian::REST::Server.instance
    @agg.params = PARAMS
    @agg.connect!

    @app = Mondrian::REST::Api.new
  end

  def app
    @app
  end

  def get_cube(name)
    @agg.cube(name)
  end

  it "should 404 if measure does not exist" do
    get '/cubes/Sales/aggregate?measures[]=doesnotexist'
    expect(404).to eq(last_response.status)
  end

  it "should generate a MDX query that aggregates the default measure across the entire cube" do
    get '/cubes/Sales/aggregate'
    expect(266773.0).to eq(JSON.parse(last_response.body)['values'][0])
  end

  it "should aggregate on two dimensions of the Sales cube" do
    get '/cubes/Sales/aggregate?drilldown[]=Product&drilldown[]=Store%20Type&drilldown[]=Time&measures[]=Store%20Sales'
    exp = [[[[13487.16], [117088.87], [31486.21]],
            [[3940.54], [33424.17], [8385.53]],
            [[nil], [nil], [nil]],
            [[2348.79], [17314.24], [4666.2]],
            [[1142.61], [10175.3], [2568.47]],
            [[27917.11], [231033.01], [60259.92]]],
           [[[nil], [nil], [nil]],
            [[nil], [nil], [nil]],
            [[nil], [nil], [nil]],
            [[nil], [nil], [nil]],
            [[nil], [nil], [nil]],
            [[nil], [nil], [nil]]]]
    expect(exp).to eq(JSON.parse(last_response.body)['values'])
  end
end
