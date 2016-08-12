require 'json'
require 'spec_helper.rb'

describe "Cube API" do

  include Rack::Test::Methods

  before(:all) do
    @fm_params = setup_foodmart
    Mondrian::REST::APIHelpers.class_variable_set('@@olap', nil)
    @app = Mondrian::REST::Api.new
  end

  before(:each) do
    env('mondrian-olap.params', @fm_params)
  end

  def app
    @app
  end

  it "should return a list of cubes" do
    get '/cubes'
    expected = ["Sales 2", "Warehouse", "Sales Ragged", "Store", "HR", "Warehouse and Sales", "Sales"].sort
    expect(JSON.parse(last_response.body)['cubes'].map { |c| c['name'] }.sort).to eq(expected)
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

  it "should return a member by full name" do
    get '/cubes/Sales%202/members?full_name=%5BProduct%5D.%5BDrink%5D'
    expected = {"name"=>"Drink", "full_name"=>"[Product].[Drink]", "caption"=>"Drink", "all_member?"=>false, "drillable?"=>true, "depth"=>1, "key"=>"Drink", "num_children"=>3, "parent_name"=>"[Product].[All Products]", "ancestors"=>[{"name"=>"All Products", "full_name"=>"[Product].[All Products]", "caption"=>"All Products", "all_member?"=>true, "drillable?"=>true, "depth"=>0, "key"=>0, "num_children"=>3, "parent_name"=>nil}], "dimension"=>{"name"=>"Product", "caption"=>"Product", "type"=>"standard", "level"=>"Product Family"}}
    expect(JSON.parse(last_response.body)).to eq(expected)
  end

  it "should return 404 if member can't be found" do
    get '/cubes/Sales%202/members/%5BProduct%5D.%5BDoesNotExist%5D'
    expect(404).to eq(last_response.status)
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
    # XXX TODO assertions
  end

  it "should cut and drilldown skipping levels correctly" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&cut[]=Customers.Country.USA'
    exp = ["Altadena", "Arcadia", "Bellflower", "Berkeley", "Beverly Hills", "Burbank", "Burlingame", "Chula Vista", "Colma", "Concord", "Coronado", "Daly City", "Downey", "El Cajon", "Fremont", "Glendale", "Grossmont", "Imperial Beach", "La Jolla", "La Mesa", "Lakewood", "Lemon Grove", "Lincoln Acres", "Long Beach", "Los Angeles", "Mill Valley", "National City", "Newport Beach", "Novato", "Oakland", "Palo Alto", "Pomona", "Redwood City", "Richmond", "San Carlos", "San Diego", "San Francisco", "San Gabriel", "San Jose", "Santa Cruz", "Santa Monica", "Spring Valley", "Torrance", "West Covina", "Woodland Hills", "Albany", "Beaverton", "Corvallis", "Lake Oswego", "Lebanon", "Milwaukie", "Oregon City", "Portland", "Salem", "W. Linn", "Woodburn", "Anacortes", "Ballard", "Bellingham", "Bremerton", "Burien", "Edmonds", "Everett", "Issaquah", "Kirkland", "Lynnwood", "Marysville", "Olympia", "Port Orchard", "Puyallup", "Redmond", "Renton", "Seattle", "Sedro Woolley", "Spokane", "Tacoma", "Walla Walla", "Yakima"]
    expect(exp).to eq(JSON.parse(last_response.body)['axes'][2]['members'].map { |m| m['caption'] })
  end

  it "should not allow drilling down on an ascendant" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.Country&measures[]=Store%20Sales&cut[]=Customers.USA.OR.Lake%20Oswego'
    expect(400).to eq(last_response.status)
  end

  it "should return the members' parent if specified in the query string" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&parents=true'
    r = JSON.parse(last_response.body)

    expect(r.has_key?('axis_parents')).to be(true)

    r['axes'][2]['members'].each { |m|
      expect(m['parent_name']).to eq(r['axis_parents'][2][m['parent_name']]['full_name'])
    }
  end

  it "should not return the members' parent if not specified in the query string" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales'
    r = JSON.parse(last_response.body)
    expect(r.has_key?('axis_parents')).to be(false)
  end

  it "should include the generated MDX query in the response if debug=True" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&debug=true'
    r = JSON.parse(last_response.body)
    expect(r.has_key?('mdx')).to be(true)
    expect(r['mdx']).to eq("SELECT {[Measures].[Store Sales]} ON COLUMNS,\n[Time].[Month].Members ON ROWS,\n[Customers].[City].Members ON PAGES\nFROM [Sales]")
  end

  it "should not include the generated MDX in the response if debug not given or if debug=false" do
    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales'
    r = JSON.parse(last_response.body)
    expect(r.has_key?('mdx')).to be(false)

    get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&debug=false'
    r = JSON.parse(last_response.body)
    expect(r.has_key?('mdx')).to be(false)
  end

  it "should add the parents as columns to the CSV" do
    get '/cubes/Sales/aggregate.csv?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&parents=true'
  end

end
