require 'csv'

module Mondrian::REST::Formatters
  module CSV
    def self.call(result, env)
      qh = env['rack.request.query_hash']
      add_parents = qh['parents'] == 'true'
      debug = qh['debug'] == 'true'
      properties = qh['properties'] || []

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
