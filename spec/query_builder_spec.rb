require 'json'
require 'spec_helper.rb'

require 'pry'

describe "Query Builder" do
  include Mondrian::REST::QueryHelper

  before(:all) do
    @agg = Mondrian::REST::Server.instance
    @agg.params = PARAMS
    @agg.connect!
  end

  def olap
    @agg.olap
  end

  def get_cube(name)
    olap.cube(name)
  end

  it "should generate a MDX query that aggregates the default measure across the entire cube" do
    c = get_cube('Sales')
    q = build_query(c)
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS\nFROM [Sales]")
  end

  it "should generate an MDX query that aggregates two measures across the entire cube" do
    c = get_cube('Sales')
    q = build_query(c, { 'measures' => ['Unit Sales', 'Sales Count']})
    expect(q.to_mdx).to eq(("SELECT {[Measures].[Unit Sales], [Measures].[Sales Count]} ON COLUMNS\nFROM [Sales]"))
  end

  it "should generate a Member expression from a drilldown spec" do
    c = get_cube('Sales')
    expect(parse_drilldown(c, 'Store')).to eq('[Store].[Store Country].Members')
  end

  it "should drilldown on the first level of the time dimension" do
    c = get_cube('Sales')
    q = build_query(c, { 'drilldown' => ['Time']})
    expect(q.to_mdx).to eq("SELECT {[Measures].[Unit Sales]} ON COLUMNS,\n[Time].[Year].Members ON ROWS\nFROM [Sales]")
  end
end
