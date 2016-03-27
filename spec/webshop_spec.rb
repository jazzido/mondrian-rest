require 'json'
require 'pp'

require 'spec_helper.rb'

describe "Webshop" do
  include Rack::Test::Methods

  before(:all) do
    @ws_params = setup_webshop
    Mondrian::REST::APIHelpers.class_variable_set('@@olap', nil)
    @app = Mondrian::REST::Api.new
  end

  before(:each) do
    env('mondrian-olap.params', @ws_params)
  end

  def app
    @app
  end

  it "should return a list of cubes" do
    get '/cubes'
    expected = ["Sales"]
    expect(JSON.parse(last_response.body)['cubes'].map { |c| c['name'] }).to eq(expected)
  end

  it "should return the members of a dimension" do
    get '/cubes/Sales/dimensions/Country'
    expect(JSON.parse(last_response.body)['hierarchies'].first['levels'][1]['members'].size).to eq(4)
  end

  it "should drilldown by continent and product category" do
    get '/cubes/Sales/aggregate?drilldown[]=Country.Continent&drilldown[]=Product.Category&measures[]=Price%20Total'
    puts last_response.body
    # XXX TODO assertions
  end

  it "should drilldown by month and product category" do
    get '/cubes/Sales/aggregate?drilldown[]=Date.Month&drilldown[]=Product.Category&measures[]=Price%20Total&measures[]=Quantity'
    pp JSON.parse(last_response.body)
    # XXX TODO assertions
  end

  it "should drilldown by country, month, and product category and return CSV" do
    get '/cubes/Sales/aggregate.csv?drilldown[]=Country&drilldown[]=Date.Month&drilldown[]=Product.Category&measures[]=Price%20Total&measures[]=Quantity'
    expect(CSV.parse(last_response.body)).to eq(CSV.read(File.join(File.dirname(__FILE__), 'fixtures', 'webshop_1.csv')))
  end

  it "should drilldown by country, month, and product category and return XLS" do
    get '/cubes/Sales/aggregate.xls?drilldown[]=Country&drilldown[]=Date.Month&drilldown[]=Product.Category&measures[]=Price%20Total&measures[]=Quantity'
    # XXX TODO assert contents of XLS
    expect(last_response.headers['Content-Type']).to eq('application/vnd.ms-excel')
  end
end
