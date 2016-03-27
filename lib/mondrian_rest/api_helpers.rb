module Mondrian::REST
  module APIHelpers

    @@olap = nil

    def olap
      if @@olap.nil?
        @@olap = Mondrian::OLAP::Connection.new(env['mondrian-olap.params'])
        @@olap.connect
      end
      @@olap
    end

    def olap_flush
      if olap.connected?
        olap.flush_schema_cache
        olap.close
      end
      olap.connect
    end

    def get_cube_or_404(name)
      cube = olap.cube(name)
      error!('Not found', 404) if cube.nil?
      cube
    end

    def mdx(query)
      logger.info("Executing MDX query #{query}")
      begin
        result = olap.execute query
        return result
      rescue Mondrian::OLAP::Error => st
        error!({error: st.backtrace}, 400)
      end
    end

  end
end
