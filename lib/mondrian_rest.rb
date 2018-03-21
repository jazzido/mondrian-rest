require 'json'

Java::JavaLang::System.setProperty("jdbc.driver.autoload", "true")

require 'mondrian-olap'
require 'grape'
require 'active_support'
require 'active_support/core_ext/enumerable'

require_relative './mondrian_rest/nest.rb'
require_relative './mondrian_rest/api.rb'
require_relative './mondrian_rest/mondrian_ext.rb'
