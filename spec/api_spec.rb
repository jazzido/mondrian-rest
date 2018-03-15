require 'json'
require 'spec_helper.rb'

describe "Cube API" do

  include Rack::Test::Methods

  before(:all) do
    @fm_params = setup_foodmart
    Mondrian::REST::APIHelpers.class_variable_set('@@olap', nil)
    Mondrian::REST::APIHelpers.class_variable_set('@@mdx_parser', nil)
    @app = Mondrian::REST::Api.new
  end

  before(:each) do
    env('mondrian-olap.params', @fm_params)
  end

  def app
    @app
  end

  describe "Metadata resources" do
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
      expect(cube['measures'].map { |m| m['aggregator'] }).to eq(['COUNT', 'SUM', 'SUM', 'SUM', 'UNKNOWN', 'UNKNOWN'])
    end

    it "should return named sets in the definition of a cube" do
      get '/cubes/Warehouse'
      expect(JSON.parse(last_response.body)['named_sets']).to eq([{"name"=>"Top Sellers", "dimension"=>"Warehouse", "hierarchy"=>"Warehouse", "level"=>"Warehouse Name", "annotations"=>{"named_set_annotation"=>"Named Set Annotation"}}])

    end

    it "should return a list of properties of a Level" do
      get '/cubes/Store'
      cube = JSON.parse(last_response.body)

      expect(cube['dimensions'].map { |d| d['hierarchies'][0]['levels'] }.flatten.map { |l| l['properties'] }).to eq([[], [], [], [], [], [], ["Store Type", "Store Manager", "Store Sqft", "Grocery Sqft", "Frozen Sqft", "Meat Sqft", "Has coffee bar", "Street address"], [], []])
    end

    it "should return the members of a dimension" do
      get '/cubes/Sales%202/dimensions/Product'
      dim = JSON.parse(last_response.body)

      expect(dim['hierarchies'].size).to eq(1)
      expect(dim['hierarchies'].first['levels'].map { |l| l['name'] }).to eq(["(All)", "Product Family", "Product Department", "Product Category", "Product Subcategory", "Brand Name", "Product Name"])
      expect(dim['hierarchies'].first['levels'][1]['members'].map { |l| l['name'] }).to eq(['Drink', 'Food', 'Non-Consumable'])
    end

    it "should return the members of a dimension level along with the requested properties" do
      get '/cubes/Sales/dimensions/Store/levels/Store%20Name/members?member_properties[]=Street%20address&member_properties[]=Has%20coffee%20bar'
      res = JSON.parse(last_response.body)
      expect(res['members'].map { |m| m['properties' ]}).to all(have_key('Street address').and have_key('Has coffee bar'))
    end


    it "should return the members of a dimension level and replace their caption with the requested property" do
      get '/cubes/Sales/dimensions/Store/levels/Store%20Name/members?member_properties[]=Street%20address&member_properties[]=Has%20coffee%20bar&caption=Street%20address'
      res = JSON.parse(last_response.body)

      expect(res['members'].map { |m| m['properties']['Street address'] == m['caption'] }).to all(be true)
    end

    it "should return the members of a dimension level along with their children" do
      get '/cubes/Sales/dimensions/Store/levels/Store%20City/members?children=true'
      res = JSON.parse(last_response.body)
      # TODO add assertions
    end


    it "should return a member" do
      get '/cubes/Sales%202/dimensions/Product/levels/Product%20Family/members/Drink'
      m = JSON.parse(last_response.body)
      expect(m['name']).to eq('Drink')
      expect(m['full_name']).to eq('[Product].[Drink]')
    end

    it "should return a member and replace its caption with the requested property, and fetch requested properties" do
      get '/cubes/Sales/dimensions/Store/levels/Store%20Name/members/Store%208?member_properties[]=Street%20address&member_properties[]=Has%20coffee%20bar&caption=Street%20address'
      res = JSON.parse(last_response.body)

      expect(res['properties']).to have_key('Street address').and have_key('Has coffee bar')
      expect(res['caption']).to eq(res['properties']['Street address'])

    end

    it "should return a member by full name" do
      get '/cubes/Sales%202/members?full_name=%5BProduct%5D.%5BDrink%5D'
      expected = {"name"=>"Drink", "full_name"=>"[Product].[Drink]", "caption"=>"Drink", "children" => [], "all_member?"=>false, "drillable?"=>true, "depth"=>1, "key"=>"Drink", "level_name" => "Product Family", "num_children"=>3, "parent_name"=>"[Product].[All Products]", "ancestors"=>[{"name"=>"All Products", "full_name"=>"[Product].[All Products]", "caption"=>"All Products", "all_member?"=>true, "drillable?"=>true, "depth"=>0, "key"=>0, "num_children"=>3, "parent_name"=>nil, "level_name"=>"(All)", "children" => []}], "dimension"=>{"name"=>"Product", "caption"=>"Product", "type"=>"standard", "level"=>"Product Family", "level_depth"=>1}}
      expect(JSON.parse(last_response.body)).to eq(expected)
    end

    it "should return 404 if member can't be found" do
      get '/cubes/Sales%202/members/%5BProduct%5D.%5BDoesNotExist%5D'
      expect(404).to eq(last_response.status)
    end
  end

  describe "Aggregation resources" do
    it "should 404 if measure does not exist" do
      get '/cubes/Sales/aggregate?measures[]=doesnotexist'
      expect(last_response.body).to include("does not exist in cube")
      expect(400).to eq(last_response.status)
    end

    it "should generate a MDX query that aggregates the default measure across the entire cube" do
      get '/cubes/Sales/aggregate'
      expect(266773.0).to eq(JSON.parse(last_response.body)['values'][0])
    end

    it "should aggregate on two dimensions of the Sales cube" do
      get '/cubes/Sales/aggregate?drilldown[]=[Product].[Product Family]&drilldown[]=[Store%20Type].[Store%20Type]&drilldown[]=[Time].[Year]&measures[]=Store%20Sales'
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
      get '/cubes/Sales/aggregate?drilldown[]=Product&measures[]=Store%20Sales&cut[]=[Product].[Product%20Family].Drink'
      puts last_response.body
      # XXX TODO assertions
    end

    it "should cut and drilldown skipping levels correctly" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&cut[]=[Customers].[Country].[USA]'
      exp = ["Altadena", "Arcadia", "Bellflower", "Berkeley", "Beverly Hills", "Burbank", "Burlingame", "Chula Vista", "Colma", "Concord", "Coronado", "Daly City", "Downey", "El Cajon", "Fremont", "Glendale", "Grossmont", "Imperial Beach", "La Jolla", "La Mesa", "Lakewood", "Lemon Grove", "Lincoln Acres", "Long Beach", "Los Angeles", "Mill Valley", "National City", "Newport Beach", "Novato", "Oakland", "Palo Alto", "Pomona", "Redwood City", "Richmond", "San Carlos", "San Diego", "San Francisco", "San Gabriel", "San Jose", "Santa Cruz", "Santa Monica", "Spring Valley", "Torrance", "West Covina", "Woodland Hills", "Albany", "Beaverton", "Corvallis", "Lake Oswego", "Lebanon", "Milwaukie", "Oregon City", "Portland", "Salem", "W. Linn", "Woodburn", "Anacortes", "Ballard", "Bellingham", "Bremerton", "Burien", "Edmonds", "Everett", "Issaquah", "Kirkland", "Lynnwood", "Marysville", "Olympia", "Port Orchard", "Puyallup", "Redmond", "Renton", "Seattle", "Sedro Woolley", "Spokane", "Tacoma", "Walla Walla", "Yakima"]
      expect(exp).to eq(JSON.parse(last_response.body)['axes'][2]['members'].map { |m| m['caption'] })
    end

    it "should drilldown on the set union of descendents of the cut" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=[Product].[Product Name]&measures[]=Unit%20Sales&cut[]=%7B[Product].[Product Department].[Produce], [Product].[Product Department].[Seafood]%7D&cut[]=[Time].[Year].[1997]'
      fnames = JSON.parse(last_response.body)['axes'][2]['members'].map { |m| m['full_name'] }
      # assert that we only obtained descendants of 'Produce' and 'Seafood'
      re = /\[([^\]]+)\]/
      expect(["Produce", "Seafood"]).to eq(fnames.map { |fn| fn.scan(re)[2][0] }.uniq.sort)
    end

    it "should not allow drilling down on an ascendant" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.Country&measures[]=Store%20Sales&cut[]=[Customers].[USA].[OR].[Lake%20Oswego]'
      expect(400).to eq(last_response.status)
    end

    it "should return an error if cutting on a nonexistent member" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&cut[]=[Customers].[Country].[Uqbar]'
      expect(400).to eq(last_response.status)
      expect(last_response.body).to include("Member does not exist")
    end

    it "should return an error if cutting on a set that contains a nonexistent member" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&cut[]=%7B[Product].[Product Department].[Produce], [Product].[Product Department].[Does not Exist]%7D'
      expect(400).to eq(last_response.status)
      expect(last_response.body).to include("Unknown member in cut set")
    end

    it "should return the members' ancestors if 'parents=true' in query string" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&parents=true'
      r = JSON.parse(last_response.body)

      r['axes'][1..-1].each { |a|
        a['members'].each { |m|
          expect(m['ancestors']).to be_kind_of(Array)
        }
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
      expect(r['mdx']).to eq("SELECT {[Measures].[Store Sales]} ON COLUMNS,\n[Time].[Time].[Month].Members ON ROWS,\n[Customers].[Customers].[City].Members ON PAGES\nFROM [Sales]")
    end

    it "should not include the generated MDX in the response if debug not given or if debug=false" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales'
      r = JSON.parse(last_response.body)
      expect(r.has_key?('mdx')).to be(false)

      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&debug=false'
      r = JSON.parse(last_response.body)
      expect(r.has_key?('mdx')).to be(false)
    end

    it "should add the parents as columns to the CSV, if requested" do
      get '/cubes/Sales/aggregate.csv?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&parents=true&nonempty=true'
      csv = CSV.parse(last_response.body)
      expect(csv.first).to eq(["ID Year", "Year", "ID Quarter", "Quarter", "ID Month", "Month", "ID Country", "Country", "ID State Province", "State Province", "ID City", "City", "Store Sales"])
    end

    it "should not add the parents as columns to the CSV by default" do
      get '/cubes/Sales/aggregate.csv?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&nonempty=true'
      csv = CSV.parse(last_response.body)
      expect(csv.first).to eq(["ID Month", "Month", "ID City", "City", "Store Sales"])
    end

    it "should include member properties if requested" do
      get '/cubes/HR/aggregate?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&properties[]=Store.Store%20Name.Has%20coffee%20bar&properties[]=Store.Store%20Name.Grocery%20Sqft'
      r = JSON.parse(last_response.body)
      expect(r['axes'][-1]['members'].map { |m| m['properties'] }).to all(include('Has coffee bar'))
      expect(r['axes'][-1]['members'].map { |m| m['properties'] }).to all(include('Grocery Sqft'))
    end

    it "should include member properties if requested, with format Dimension.Hierarchy.Level.Property" do
      get '/cubes/HR/aggregate?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&properties[]=Store.Store.Store%20Name.Has%20coffee%20bar&properties[]=Store.Store.Store%20Name.Grocery%20Sqft'
      r = JSON.parse(last_response.body)
      expect(r['axes'][-1]['members'].map { |m| m['properties'] }).to all(include('Has coffee bar'))
      expect(r['axes'][-1]['members'].map { |m| m['properties'] }).to all(include('Grocery Sqft'))
    end


    it "should include member properties in CSV if requested" do
      get '/cubes/HR/aggregate.csv?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&properties[]=Store.Store%20Name.Has%20coffee%20bar&properties[]=Store.Store%20Name.Grocery%20Sqft'
      csv = CSV.parse(last_response.body)
      expect(csv.first).to eq(["ID Year", "Year", "ID Store Name", "Store Name", "Has coffee bar", "Grocery Sqft", "Org Salary"])
    end

    it "should include member properties in CSV when parents are requested" do
      get '/cubes/HR/aggregate.csv?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&properties[]=Store.Store%20Name.Has%20coffee%20bar&properties[]=Store.Store%20Name.Grocery%20Sqft&parents=true'
      csv = CSV.parse(last_response.body)
      expect(csv.first).to eq(["ID Year", "Year", "ID Store Country", "Store Country", "ID Store State", "Store State", "ID Store City", "Store City", "ID Store Name", "Store Name", "Has coffee bar", "Grocery Sqft", "Org Salary"])
    end

    it "should fail if requested member properties of a dimension not in drilldown[]" do
      get '/cubes/HR/aggregate?drilldown[]=Time.Year&&measures[]=Org%20Salary&properties[]=Store.Store%20Name.Has%20coffee%20bar&properties[]=Store.Store%20Name.Grocery%20Sqft'
      expect(400).to eq(last_response.status)
    end

    it "should replace default caption with the `caption` parameter" do
      get '/cubes/HR/aggregate.csv?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&caption[]=Store.Store%20Name.Has%20coffee%20bar'
      expect(CSV.parse(last_response.body)[1..-1].map { |r| r[3] }).to all(eq('1').or eq('0'))
    end

    it "should replace default caption with the `caption` parameter when caption is in format Dimension.Hierarchy.Level.Property" do
      get '/cubes/HR/aggregate.csv?drilldown[]=Time.Year&drilldown[]=Store.Store%20Name&measures[]=Org%20Salary&caption[]=Store.Store.Store%20Name.Has%20coffee%20bar'
      expect(CSV.parse(last_response.body)[1..-1].map { |r| r[3] }).to all(eq('1').or eq('0'))
    end

    it "should drilldown on a named set" do
      get '/cubes/Warehouse/aggregate.csv?drilldown[]=Top%20Sellers&measures[]=Warehouse%20Profit&nonempty=true'
      expect(CSV.parse(last_response.body).size).to eq(6) # length=5 + header
    end

    it "should cut on a named set" do
      get '/cubes/Warehouse/aggregate.csv?drilldown[]=[Store+Type].[Store+Type]&cut[]=Top%20Sellers&measures[]=Warehouse%20Profit&nonempty=true'
      expect(CSV.parse(last_response.body).size).to eq(3) # length=2 + header
    end

    it "should cut on a named set and a member" do
      get '/cubes/Warehouse/aggregate.csv?drilldown[]=[Store+Type].[Store+Type]&cut[]=Top%20Sellers&cut[]=[Store].[Store].[Store+Country].%26[USA]&measures[]=Warehouse%20Profit&nonempty=true'
      expect(CSV.parse(last_response.body).size).to eq(3) # length=2 + header
    end

    it "should accept a POST request" do
      post '/cubes/Sales/aggregate', { 'drilldown' => ['Time.Month', 'Customers.City'], 'measures' => ['Store Sales'], 'parents' => 'true', 'nonempty' => 'true' }
      rpost = JSON.parse(last_response.body)

      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&parents=true&nonempty=true'
      rget = JSON.parse(last_response.body)

      expect(rget['values']).to eql(rpost['values'])
    end

    it "should add parents to the result of a raw MDX query" do
      mdx = <<-MDX
        SELECT {[Measures].[Store Sales]} ON COLUMNS,
               TOPCOUNT(Time.Time.Month.Members, 10, [Measures].[Store Sales]) ON ROWS,
               [Customers].[Customers].[City].Members ON PAGES
        FROM [Sales]
      MDX

      post '/mdx.csv?parents=true', mdx

      csv = CSV.parse(last_response.body)
      expect(csv.first).to eq(["ID Year","Year","ID Quarter","Quarter","ID Month","Month","ID Country","Country","ID State Province","State Province","ID City","City","Store Sales"])

    end

    it "should not fail on an empty result" do
      get '/cubes/Warehouse/aggregate?drilldown[]=[Store+Type].[Store+Type]&cut[]=[Store].[Store].[Store+Country].%26[Mexico]&measures[]=Store+Invoice&nonempty=true&distinct=false&parents=false&debug=true'

      expect(JSON.parse(last_response.body)['values'].size).to eql(0)

      get '/cubes/Warehouse/aggregate.jsonrecords?drilldown[]=[Store+Type].[Store+Type]&cut[]=[Store].[Store].[Store+Country].%26[Mexico]&measures[]=Store+Invoice&nonempty=true&distinct=false&parents=false&debug=true'

      expect(JSON.parse(last_response.body)).to eql({"data" => []})

      get '/cubes/Warehouse/aggregate.csv?drilldown[]=[Store+Type].[Store+Type]&cut[]=[Store].[Store].[Store+Country].%26[Mexico]&measures[]=Store+Invoice&nonempty=true&distinct=false&parents=false&debug=true'

      expect(last_response.body).to eql("")
    end
  end
end

