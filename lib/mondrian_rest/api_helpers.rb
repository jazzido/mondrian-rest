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

    def cube_def(cube)
      # gather dimensions
      dimensions = cube.dimensions
                   .find_all { |d| d.dimension_type != :measures }
                   .map { |d|
        {
          :name => d.name,
          :caption => d.caption,
          :type => d.dimension_type,
          :annotations => d.annotations,
          :hierarchies => d.hierarchies.map { |h|
            {
              :name => h.name,
              :has_all => h.has_all?,
              :all_member_name => h.all_member_name,
              :levels => h.levels.map { |l|
                {
                  :name => l.name,
                  :full_name => l.full_name,
                  :caption => l.caption
                }
              }
            }
          }
        }
      }

      {
        :name => cube.name,
        :annotations => cube.annotations,
        :dimensions => dimensions,
        :measures => cube.dimensions
                    .find(&:measures?)
                    .hierarchy
                    .levels.first
                    .members
                    .find_all(&:visible?)
                    .map do |m|
          {
            :name => m.name,
            :caption => m.caption,
            :annotations => m.annotations,
            :full_name => m.full_name
          }
        end
      }
    end
  end
end
