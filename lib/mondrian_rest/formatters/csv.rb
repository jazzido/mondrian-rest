require 'csv'

module Mondrian::REST::Formatters
  module CSV
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'
      properties = env['rack.request.query_hash']['properties'] || []

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties)

      ::CSV.generate do |csv|
        rows.each { |row| csv << row }
      end
    end
  end
end
