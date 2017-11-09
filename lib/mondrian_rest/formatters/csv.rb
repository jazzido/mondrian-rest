require 'csv'

module Mondrian::REST::Formatters
  module CSV
    def self.call(result, env)
      params = env['api.endpoint'].params
      add_parents = params['parents']
      debug = params['debug']
      sparse = params['sparse']
      properties = params['properties'] || []

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties,
                                             sparse: sparse)

      ::CSV.generate do |csv|
        rows.each { |row| csv << row }
      end
    end
  end
end
