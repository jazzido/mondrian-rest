module Mondrian::REST::Formatters
  module AggregationJSON
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'

      result.to_h(add_parents, debug).to_json
    end
  end
end
