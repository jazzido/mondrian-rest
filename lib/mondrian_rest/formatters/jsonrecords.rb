module Mondrian::REST::Formatters
  module JSONRecords
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'
      properties = env['rack.request.query_hash']['properties'] || []

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties).lazy
      keys = rows.next

      {
        data: rows.with_index.with_object([]) { |(row, i), data|
          next if i == 0
          data << Hash[keys.zip(row)]
        }
      }.to_json

    end
  end
end
