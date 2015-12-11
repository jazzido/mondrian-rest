module Mondrian::REST
  module APIHelpers
      def olap
        @olap ||= Server.instance.olap
      end

      def get_cube_or_404(name)
        cube = olap.cube(name)
        error!('Not found', 404) if cube.nil?
        cube
      end

      def mdx(query)
        Mondrian::REST.log.info("Executing MDX query #{query}")
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
                    :caption => l.caption
                  }
                }
              }
            }
          }
        }

        {
          'name' => cube.name,
          'dimensions' => dimensions,
          'measures' => cube.dimensions
                       .find(&:measures?)
                       .hierarchy
                       .levels.first
                       .members
                       .find_all(&:visible?)
                       .map { |m|
                         {
                           :name => m.name,
                           :caption => m.caption,
                           :annotations => m.annotations
                         }
                        }
        }
      end
  end
end
