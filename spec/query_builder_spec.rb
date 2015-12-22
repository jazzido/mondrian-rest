require 'json'
require 'spec_helper.rb'

require 'pry'

describe "Query Builder" do
  class QueryHelper
    include Mondrian::REST::QueryHelper
    attr_accessor :olap
    def error!(*args)
      raise
    end
  end

  before(:all) do
    fm_params = setup_foodmart
    @agg = Mondrian::REST::Server.instance
    @agg.params = fm_params
    @agg.connect!

    @qh = QueryHelper.new
    @qh.olap = @agg.olap
  end

  before(:each) do
    @cube = @agg.olap.cube('Sales')
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
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Time.Weekly].[Week].Members ON ROWS\nFROM [Sales]")
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
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Product Category].Members ON ROWS\nFROM [Sales]\nWHERE ([Time].[1997])")
  end

  it "should aggregate on the next level of the dimension in the cut" do
    q = @qh.build_query(@cube,
                        {
                          'cut' => ['Product.Product Family.Drink'],
                          'drilldown' => ['Product']
                        })
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Product].[Drink].Children ON ROWS\nFROM [Sales]")
  end

end
