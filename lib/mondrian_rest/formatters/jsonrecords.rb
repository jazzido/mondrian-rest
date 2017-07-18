module Mondrian::REST::Formatters
  module JSONRecords
    def self.call(result, env)
      qh = env['rack.request.query_hash']
      add_parents = qh['parents'] == 'true'
      debug = qh['debug'] == 'true'
      properties = qh['properties'] || []
      format = qh['format'] == 'array' ? 'array' : 'object'

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties).lazy
      keys = rows.first

      if format == 'array'
        {
          variables: keys,
          data: rows.drop(1).to_a
        }.to_json
      else
        {
          data: rows.with_index.with_object([]) { |(row, i), data|
            next if i == 0
            data << Hash[keys.zip(row)]
          }
        }.to_json
      end
    end
  end
end
