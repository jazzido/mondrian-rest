module Mondrian::REST::Formatters
  module JSONRecords
    def self.call(result, env)
      params = env['api.endpoint'].params
      add_parents = params['parents']
      debug = params['debug']
      sparse = params['sparse']
      properties = params['properties'] || []

      qh = env['rack.request.query_hash']
      format = qh['format'] == 'array' ? 'array' : 'object'

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties,
                                             sparse: sparse).lazy
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
