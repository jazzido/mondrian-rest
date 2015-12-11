require 'singleton'
require 'json'

Java::JavaLang::System.setProperty("jdbc.driver.autoload", "true")

require 'mondrian-olap'

require 'null_logger'
require 'grape'

require_relative './mondrian_rest/api.rb'
require_relative './mondrian_rest/mondrian_ext.rb'

module Mondrian
  module REST
    class << self
      attr_accessor :logger
      def log
        logger.nil? ? NullLogger.instance : logger
      end
    end

    class Server
      include Singleton
      attr_reader :olap
      attr_writer :params

      def connect!
        raise "params must be set" if @params.nil?
        @olap = Mondrian::OLAP::Connection.new(@params)
        REST.log.info "Connected to Mondrian"
        @olap.connect
      end

      def flush
        if olap.connected?
          olap.flush_schema_cache
          olap.close
        end
        olap.connect
      end
    end
  end
end
