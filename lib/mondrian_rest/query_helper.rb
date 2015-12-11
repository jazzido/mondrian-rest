module Mondrian::REST
  module QueryHelper

    DIM_LEVEL_RE = /([^\.]+)\.([^\.]+)/
    DIM_LEVEL_MEMBER_RE = /([^\.]+)\.([^\.]+)\.(.+)/

    def get_dimension(cube, dname)
      cube_dimensions = cube.dimensions
                        .find_all { |d| d.dimension_type != :measures }
      dim = cube_dimensions.find { |d| d.name == dname }
      error!("Dimension #{dname} does not exist", 400) if dim.nil?
      dim
    end

    def parse_drilldown(cube, drilldown)
      begin
        s = org.olap4j.mdx.IdentifierNode.parseIdentifier(drilldown).getSegmentList

        if s.size > 3
          error!("Illegal drilldown specification: #{drilldown}", 400)
        end

        dimension = get_dimension(cube, s.first.name)
        hierarchy = dimension.hierarchies.first
        level = hierarchy.levels[hierarchy.has_all? ? 1 : 0]

        if s.size == 3
          hierarchy = dimension.hierarchies.find { |h_| h_.name == s[1].name }
          if hierarchy.nil?
            error!("Hierarchy `#{s[1].name}` does not exist in dimension #{dimension.name}")
          end
        elsif s.size == 2
          level = hierarchy.levels.find { |l_| l_.name == s[1].name }
          if level.nil?
            error!("Level `#{s[1].name}` does not exist in #{dimension.name}")
          end
        end
      rescue Java::JavaLang::IllegalArgumentException => e
        error!("Illegal drilldown specification: #{drilldown}", 400)
      end

      # XX TODO decide what to do with members

      level.raw_level.unique_name + '.Members'
    end

    def build_query(cube, options={})

      options = {
        'cut' => [],
        'drilldown' => [],
        'measures' => [cube.dimension('Measures').hierarchy.levels.first.members.first.name]
      }.merge(options)


      # validate measures exist
      cube_measures = cube.dimension('Measures')
                      .hierarchy
                      .levels.first
                      .members
      cm_names = cube_measures.map(&:name)

      options['measures'].each { |m|
        error!("Measure #{m} does not exist in cube #{cube.name}", 404) unless cm_names.include?(m)
      }

      axis_idx = 0
      query = olap.from(cube.name)
              .axis(axis_idx,
                    *options['measures'].map { |m|
                      cube_measures.find { |cm| cm.name == m }.full_name
                    })
      axis_idx += 1

      options['drilldown'].each do |ds|
        query = query.axis(axis_idx, parse_drilldown(cube, ds))
        axis_idx += 1
      end

      query

    end
  end
end
