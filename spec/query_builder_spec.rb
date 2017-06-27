require 'json'
require 'spec_helper.rb'

describe "Query Builder" do

  class QueryHelper
    include Mondrian::REST::QueryHelper
    attr_accessor :olap, :mdx_parser
    def error!(*args)
      raise
    end
  end

  before(:all) do
    @fm_params = setup_foodmart
    @qh = QueryHelper.new
    @olap = Mondrian::OLAP::Connection.new(@fm_params)
    @olap.connect
    @qh.olap = @olap
    @qh.mdx_parser = @olap.raw_connection.getParserFactory
                     .createMdxParser(@olap.raw_connection)
  end


  before(:each) do
    @cube = @olap.cube('Sales')
  end

  it "should get a member from an MDX member expression" do
    expect(@qh.get_member(@cube, 'Product.Product Family.Drink').property_value('MEMBER_KEY')).to eq('Drink')
    expect(@qh.get_member(@cube, 'Product.Product Family.&Drink').property_value('MEMBER_KEY')).to eq('Drink')
    expect(@qh.get_member(@cube, 'Product.Product Family.Does not exist')).to eq(nil)
  end

  it "should raise an error if member expression does not parse" do
    expect(@qh).to receive(:"error!").with(kind_of(String), 400)
    @qh.get_member(@cube, 'Product..Product Family.Drink')
  end

  it "should generate a set expression from a drilldown spec" do
    expect(@qh.parse_drilldown(@cube, 'Store').raw_level.unique_name).to eq('[Store].[Store Country]')
  end

  it "should error out if a key expression is given as a drilldown spec" do
    expect(@qh).to receive(:"error!").with(kind_of(String), 400)
    @qh.parse_drilldown(@cube, 'Product.Product Family.&Drink')
  end

  it "should generate an MDX query that aggregates the default measure across the entire cube" do
    expect(@qh.build_query(@cube).to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS\nFROM [Sales]")
  end

  it "should generate an MDX query that aggregates two measures across the entire cube" do
    q = @qh.build_query(@cube, { 'measures' => ['Unit Sales', 'Sales Count']})
    expect(q.to_mdx).to eq(("SELECT {[Measures].[Unit Sales], [Measures].[Sales Count]} ON COLUMNS\nFROM [Sales]"))
  end

  it "should drilldown on the first level of the time dimension" do
    q = @qh.build_query(@cube, { 'drilldown' => ['Time']})
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Time].[Year].Members ON ROWS\nFROM [Sales]")
  end

  it "should drilldown on a level of an explicit hierarchy" do
    q = @qh.build_query(@cube, { 'drilldown' => ['Time.Weekly.Week']})
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Time].[Weekly].[Week].Members ON ROWS\nFROM [Sales]")
  end

  it "should drilldown on the second level of a dimension" do
    q = @qh.build_query(@cube, { 'drilldown' => ['Product.Product Category']})
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Product Category].Members ON ROWS\nFROM [Sales]")
  end

  it "should cut on the provided cell" do
    q = @qh.build_query(@cube,
                        {
                          'drilldown' => ['Product.Product Category'],
                          'cut' => ['Time.Year.1997']
                        })
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Product Category].Members ON ROWS\nFROM [Sales]\nWHERE (Time.Year.1997)")
  end

  it "should aggregate on the next level of the dimension in the cut" do
    q = @qh.build_query(@cube,
                        {
                          'cut' => ['Product.Product Family.Drink'],
                          'drilldown' => ['Product']
                        })
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n{Product.Product Family.Drink} ON ROWS\nFROM [Sales]")
  end

  it "should slice on a tuple if more than one member provided in cut" do
    q = @qh.build_query(@cube,
                        {
                          'drilldown' => ['Product.Product Category'],
                          'cut' => ['Time.Year.1997', '[Store Type].[Supermarket]']
                        })
    # likely this is invalid MDX, but mondrian will rewrite it as
    # ... WHERE ({Time.Year.1997} * {[Store Type].[Supermarket]})
    # ie. cross join of sets of cardinality = 1
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Product Category].Members ON ROWS\nFROM [Sales]\nWHERE (Time.Year.1997 * [Store Type].[Supermarket])")
  end

  it "should slice on a crossjoin of the sets provided in the cut" do
    q = @qh.build_query(@cube,
                        {
                          'drilldown' => ['Product.Product Category'],
                          'cut' => ['Time.Year.1997', '{[Store Type].[Supermarket], [Store Type].[Deluxe Supermarket]}']
                        })
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Product Category].Members ON ROWS\nFROM [Sales]\nWHERE (Time.Year.1997 * {[Store Type].[Supermarket], [Store Type].[Deluxe Supermarket]})")
  end

  it "should drilldown on the descendants if drilling down on a higher level than the cut" do
    q = @qh.build_query(@cube,
                        {
                          'drilldown' => ['Product.Product Category'],
                          'cut' => ['Product.Product Family.Drink'],
                          'measures' => ['Unit Sales']
                        })

    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\nDESCENDANTS(Product.Product Family.Drink, [Product].[Product Category]) ON ROWS\nFROM [Sales]")
  end


  describe "parse_cut" do
    it "should correctly parse a cut specified as a set" do
      l = @cube.dimension('Product').hierarchies[0].level('Product Family')
      pc = @qh.parse_cut(@cube, '{ [Product].[Product Family].[Drink] }')

      expect(pc[:cut]).to eq('{[Product].[Product Family].[Drink]}')
      expect(pc[:level]).to eq(l.raw_level)
    end

    it "should raise if levels in the cut set are not unique" do
      expect(@qh).to receive(:"error!").with(kind_of(String), 400)
      @qh.parse_cut(@cube, '{ [Product].[Product Family].[Drink], [Product].[Product Category].[Dairy] }')
    end

    it "should correctly parse a cut specified as a range" do
      l = @cube.dimension('Time').hierarchies[0].level('Year')
      pc = @qh.parse_cut(@cube, '([Time].[Year].[1997]:[Time].[Year].[1998])')
      expect(pc[:cut]).to eq('([Time].[Year].[1997] : [Time].[Year].[1998])')
      expect(pc[:level]).to eq(l.raw_level)
    end

    it "should correctly parse a cut specified as a member" do
      l = @cube.dimension('Time').hierarchies[0].level('Year')
      pc = @qh.parse_cut(@cube, '[Time].[Year].[1997]')
      expect(pc[:cut]).to eq('[Time].[Year].[1997]')
      expect(pc[:level]).to eq(l.raw_level)
    end
  end

  describe "named sets" do
    it "should support drilling down on a named set" do
      cube = @olap.cube('Warehouse')

      q = @qh.build_query(cube, { 'drilldown' => ['Top Sellers']})
      expect(q.to_mdx).to eq("SELECT {[Measures].[Store Invoice]} ON COLUMNS,\n{[Top Sellers]} ON ROWS\nFROM [Warehouse]")
    end
  end
end
