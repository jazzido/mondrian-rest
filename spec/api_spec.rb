require 'json'
require 'spec_helper.rb'

describe "Cube metadata API" do

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

  it "should return a list of cubes" do
    get '/cubes'
    expected = {"cubes"=>["Sales 2", "Warehouse", "Sales Ragged", "Store", "HR", "Warehouse and Sales", "Sales"]}
    expect(JSON.parse(last_response.body)).to eq(expected)
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
end
