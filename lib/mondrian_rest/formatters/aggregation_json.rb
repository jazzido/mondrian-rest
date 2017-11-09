module Mondrian::REST::Formatters
  module AggregationJSON
    def self.call(result, env)
      params = env['api.endpoint'].params
      add_parents = params['parents']
      debug = params['debug']

      result.to_h(add_parents, debug).to_json
    end
  end
end
