require 'json'
require 'spec_helper.rb'

describe "Cube API" do

  include Rack::Test::Methods

  before(:all) do
    fm_params = setup_foodmart
    @agg = Mondrian::REST::Server.instance
    @agg.params = fm_params
    @agg.connect!

    @app = Mondrian::REST::Api.new
  end

  def app
    @app
  end

  it "should return a list of cubes" do
    get '/cubes'
    expected = ["Sales 2", "Warehouse", "Sales Ragged", "Store", "HR", "Warehouse and Sales", "Sales"].sort
    expect(JSON.parse(last_response.body)['cubes'].sort).to eq(expected)
  end

  it "should return the definition of a cube" do
    get '/cubes/Sales%202'
    cube = JSON.parse(last_response.body)
    expect(cube['name']).to eq('Sales 2')
    expect(cube['dimensions'].map { |d| d['name'] }).to eq(['Time', 'Product', 'Gender'])
  end

  it "should return the members of a dimension" do
    get '/cubes/Sales%202/dimensions/Product'
    dim = JSON.parse(last_response.body)

    expect(dim['hierarchies'].size).to eq(1)
    expect(dim['hierarchies'].first['levels'].map { |l| l['name'] }).to eq(["(All)", "Product Family", "Product Department", "Product Category", "Product Subcategory", "Brand Name", "Product Name"])
    expect(dim['hierarchies'].first['levels'][1]['members'].map { |l| l['name'] }).to eq(['Drink', 'Food', 'Non-Consumable'])
  end

  it "should return a member" do
    get '/cubes/Sales%202/dimensions/Product/levels/Product%20Family/members/Drink'
    m = JSON.parse(last_response.body)
    expect(m['name']).to eq('Drink')
    expect(m['full_name']).to eq('[Product].[Drink]')
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

  it "should aggregate on the next level of the dimension in the cut" do
    get '/cubes/Sales/aggregate?drilldown[]=Product&measures[]=Store%20Sales&cut[]=Product.Product%20Family.Drink'
    puts last_response.body
  end

end
