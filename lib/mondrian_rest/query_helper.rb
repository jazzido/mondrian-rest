module Mondrian::REST
  module QueryHelper

    def get_dimension(cube, dname)
      cube_dimensions = cube.dimensions
                        .find_all { |d| d.dimension_type != :measures }
      dim = cube_dimensions.find { |d| d.name == dname }
      error!("Dimension #{dname} does not exist", 400) if dim.nil?
      dim
    end

    def get_member(cube, member_exp)
      begin
        rm = cube.raw_cube
           .lookupMember(org.olap4j.mdx.IdentifierNode.parseIdentifier(member_exp).getSegmentList)
      rescue Java::JavaLang::IllegalArgumentException
        error!("Illegal member expression: #{member_exp}", 400)
      end
      member = nil
      unless rm.nil?
        member = Mondrian::OLAP::Member.new(rm)
      end
      member
    end

    def parse_drilldown(cube, drilldown)
      begin
        s = org.olap4j.mdx.IdentifierNode.parseIdentifier(drilldown).getSegmentList
        if s.size > 3 || s.map(&:quoting).any? { |q| q.name == 'KEY' }
          error!("Illegal drilldown specification: #{drilldown}", 400)
          return
        end

        dimension = get_dimension(cube, s.first.name)
        hierarchy = dimension.hierarchies.first
        level = hierarchy.levels[hierarchy.has_all? ? 1 : 0]

        if s.size > 1
          if s.size == 3 # 3 parts, means that a hierarchy was provided
            hierarchy = dimension.hierarchies.find { |h_| h_.name == "#{dimension.name}.#{s[1].name}" }
            if hierarchy.nil?
              error!("Hierarchy `#{s[1].name}` does not exist in dimension #{dimension.name}", 404)
            end
          end
          level = hierarchy.levels.find { |l_| l_.name == s[s.size - 1].name }
          if level.nil?
            error!("Level `#{s[1].name}` does not exist in #{dimension.name}", 404)
          end
        end
      rescue Java::JavaLang::IllegalArgumentException
        error!("Illegal drilldown specification: #{drilldown}", 400)
      end

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

      # measures go in axis(0) of the resultset
      axis_idx = 0
      query = olap.from(cube.name)
              .axis(axis_idx,
                    *options['measures'].map { |m|
                      cube_measures.find { |cm| cm.name == m }.full_name
                    })
      axis_idx += 1

      # query axes (drilldown)
      query_axes = options['drilldown'].each { |dd| parse_drilldown(cube, dd) }
      options['drilldown'].each do |ds|
        query = query.axis(axis_idx, parse_drilldown(cube, ds))
        axis_idx += 1
      end

      # slicer axes (cut)
      #slicer_axis = options['cut'].each { |cut| get_member(cube, cut) }
      if options['cut'].size >= 1
        query = query.where(options['cut'].map { |cut|
                              get_member(cube, cut).full_name
                            })
      end
      query
    end
  end
end
