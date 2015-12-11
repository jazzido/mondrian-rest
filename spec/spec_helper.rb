require 'rack/test'

require 'jdbc/derby'
Jdbc::Derby.load_driver

require_relative '../lib/mondrian_rest.rb'

PARAMS = {
  driver: 'jdbc',
  jdbc_driver: 'org.apache.derby.jdbc.EmbeddedDriver',
  jdbc_url: "jdbc:derby:#{File.join(File.dirname(__FILE__), 'fixtures', 'derby-foodmart')}",
  username: 'sa',
  password: 'sa',
  catalog: File.join(File.dirname(__FILE__), 'fixtures', 'foodmart.xml')
}
