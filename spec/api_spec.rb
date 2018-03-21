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
      expected = {"name"=>"Drink", "full_name"=>"[Product].[Drink]", "caption"=>"Drink", "children" => [], "all_member?"=>false, "drillable?"=>true, "depth"=>1, "key"=>"Drink", "level_name" => "Product Family", "num_children"=>3, "parent_name"=>"[Product].[All Products]", "ancestors"=>[{"name"=>"All Products", "full_name"=>"[Product].[All Products]", "caption"=>"All Products", "all_member?"=>true, "drillable?"=>true, "depth"=>0, "key"=>0, "num_children"=>3, "parent_name"=>nil, "level_name"=>"(All)", "children" => []}], "dimension"=>{"name"=>"Product", "caption"=>"Product", "type"=>"standard", "level"=>"Product Family", "level_depth"=>1, "hierarchy" => "Product"}}
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

    it "should aggregate on three dimensions of the Sales cube" do
      get '/cubes/Sales/aggregate?drilldown[]=[Product].[Product Family]&drilldown[]=[Store%20Type].[Store%20Type]&drilldown[]=[Time].[Year]&measures[]=Store%20Sales'
      exp = [[13487.16], [nil], [3940.54], [nil], [nil], [nil], [2348.79], [nil], [1142.61], [nil], [27917.11], [nil], [117088.87], [nil], [33424.17], [nil], [nil], [nil], [17314.24], [nil], [10175.3], [nil], [231033.01], [nil], [31486.21], [nil], [8385.53], [nil], [nil], [nil], [4666.2], [nil], [2568.47], [nil], [60259.92], [nil]]
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
      expect(r['mdx']).to eq("SELECT {[Measures].[Store Sales]} ON COLUMNS,\n[Time].[Time].[Month].Members * [Customers].[Customers].[City].Members ON ROWS\nFROM [Sales]")
    end

    it "should not include the generated MDX in the response if debug not given or if debug=false" do
      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales'
      r = JSON.parse(last_response.body)
      expect(r['mdx']).to be(nil)

      get '/cubes/Sales/aggregate?drilldown[]=Time.Month&drilldown[]=Customers.City&measures[]=Store%20Sales&debug=false'
      r = JSON.parse(last_response.body)
      expect(r['mdx']).to be(nil)
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
               TOPCOUNT(Time.Time.Month.Members, 10, [Measures].[Store Sales]) * [Customers].[Customers].[City].Members ON ROWS
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

    describe "Ordering" do

      it "should order on a measure, ascending" do
        # get without order
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Name%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&sparse=true&nonempty=true'
        csv = CSV.parse(last_response.body)[1..-1].map { |r| r[-1] } # get the measure value
        expect(csv[0..-2].zip(csv[1..-1]).map { |a| a[0].to_f <= a[1].to_f }.all?).to be(false)

        # get with order
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Name%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&sparse=true&order=Measures.%5BStore+Sqft%5D&order_desc=false&nonempty=true'
        csv = CSV.parse(last_response.body)[1..-1].map { |r| r[-1] } # get the measure value

        expect(csv[0..-2].zip(csv[1..-1]).map { |a| a[0].to_f <= a[1].to_f }.all?).to be(true)
      end

      it "should order a filtered aggregation" do
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&filter%5B%5D=Store+Sqft+>+50000&sparse=true&order=Measures.%5BStore+Sqft%5D'

        csv = CSV.parse(last_response.body)[1..-1].map { |r| r[-1] } # get the measure value
        # assert filter
        expect(csv.map { |r| r.to_f > 50000 }.all?).to be(true)
        # assert order
        expect(csv[0..-2].zip(csv[1..-1]).map { |a| a[0].to_f <= a[1].to_f }.all?).to be(true)
      end

      it "should error on an invalid measure" do
        get '/cubes/Store/aggregate?drilldown%5B%5D=%5BStore%5D.%5BStore+Name%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&sparse=true&order=Measures.%5BBLEBLEH%5D&order_desc=false'
        expect(last_response.status).to eq(400)
        expect(JSON.parse(last_response.body)['error']).to eq("Invalid measure in order: BLEBLEH")
        filtered_csv = CSV.parse(last_response.body)[1..-1]
        expect(filtered_csv.map { |r| r[-1].to_f > 50000 }.all?).to be(true)
      end

    end

    describe "Filter measures" do
      it "should filter on single-clause valid filter expression" do

        # get unfiltered aggregation
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&sparse=true'
        unfiltered_csv = CSV.parse(last_response.body)[1..-1]
        expect(unfiltered_csv.map { |r| r[-1].to_f <= 50000 }.any?).to be(true)

        # get filtered assertion
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&filter%5B%5D=Store+Sqft+>+50000&sparse=true'

        filtered_csv = CSV.parse(last_response.body)[1..-1]
        expect(filtered_csv.map { |r| r[-1].to_f > 50000 }.all?).to be(true)

        expect(unfiltered_csv.size).to be > filtered_csv.size
      end

      it "should filter on multiple-clause valid filter expression" do
        # get filtered assertion
        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&filter%5B%5D=Store+Sqft+>+50000&filter%5B%5D=Grocery+Sqft+<+90000&sparse=true'

        filtered_csv = CSV.parse(last_response.body)[1..-1]
        expect(filtered_csv.map { |r| r[-2].to_f < 90000 && r[-1].to_f > 50000 }.all?).to be(true)
      end

      it "should error on a malformed filter expression" do

        get '/cubes/Store/aggregate.csv?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&filter%5B%5D=Store+Sqft+>&sparse=true'

        expect(last_response.status).to eq(400)
        expect(last_response.body).to eq("Filter clause Store Sqft > is invalid")
      end

      it "should error on a filter expression that refers to a measure that doesn't exist" do
        get '/cubes/Store/aggregate?drilldown%5B%5D=%5BStore%5D.%5BStore+Country%5D&drilldown%5B%5D=%5BStore+Type%5D.%5BStore+Type%5D&measures%5B%5D=Grocery+Sqft&measures%5B%5D=Store+Sqft&filter%5B%5D=Invalid+measure+>+50000&sparse=true'

        expect(last_response.status).to eq(400)
        expect(JSON.parse(last_response.body)).to eq({"error" => "Invalid filter: measure Invalid measure does not exist"})
      end
    end

  end
end

