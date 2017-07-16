require 'json'

Java::JavaLang::System.setProperty("jdbc.driver.autoload", "true")

require_relative './jars/mondrian-rest_jars.rb'

require 'mondrian-olap'
require 'grape'

require_relative './mondrian_rest/nest.rb'
require_relative './mondrian_rest/api.rb'
require_relative './mondrian_rest/mondrian_ext.rb'
