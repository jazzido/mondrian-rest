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

    ##
    # Parses a drilldown specification
    # XXX TODO write doc
    def parse_drilldown(cube, drilldown)
      begin
        s = org.olap4j.mdx.IdentifierNode.parseIdentifier(drilldown).getSegmentList
      rescue Java::JavaLang::IllegalArgumentException
        error!("Illegal drilldown specification: #{drilldown}", 400)
      end

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

      level
    end

    def build_query(cube, options={})

      measure_members = cube.dimension('Measures').hierarchy.levels.first.members
      options = {
        'cut' => [],
        'drilldown' => [],
        'measures' => [measure_members.first.name],
        'nonempty' => false,
        'distinct' => false
      }.merge(options)

      # validate measures exist
      cm_names = measure_members.map(&:name)

      options['measures'].each { |m|
        error!("Measure #{m} does not exist in cube #{cube.name}", 404) unless cm_names.include?(m)
      }

      # measures go in axis(0) of the resultset
      query = olap.from(cube.name)
              .axis(0,
                    *options['measures'].map { |m|
                      measure_members.find { |cm| cm.name == m }.full_name
                    })
      if options['nonempty']
        query = query.nonempty
      end
      axis_idx = 1

      query_axes = options['drilldown'].map { |dd| parse_drilldown(cube, dd) }
      slicer_axis = options['cut'].map { |cut| get_member(cube, cut) }

      dd = query_axes.map do |qa|
        sa_idx = slicer_axis.index { |sa| sa.raw_level.hierarchy == qa.raw_level.hierarchy }
        m = nil
        if sa_idx.nil? # no slice (cut) on this axis
          m = qa.raw_level.unique_name + '.Members'
        else
          sa = slicer_axis[sa_idx]
          slicer_axis.delete_at(sa_idx)

          if sa.raw_level.depth > qa.depth
            error!("#{sa.raw_level.unique_name} is above #{qa.raw_level.unique_name}, can't drilldown", 400)
          end

          if sa.drillable?
            dist = qa.depth - sa.raw_level.depth
            m = "Descendants(#{sa.full_name}, #{dist == 0 ? 1 : dist})"
          else
            m = "{#{sa.full_name}}"
          end
        end
        m
      end

      # query axes (drilldown)
      dd.each do |ds|
        query = query.axis(axis_idx,
                           ds)

        if options['distinct']
          query = query.distinct
        end

        if options['nonempty']
          query = query.nonempty
        end

        axis_idx += 1
      end

      # slicer axes (cut)
      if slicer_axis.size >= 1
        query = query.where(slicer_axis.map(&:full_name))
      end
      query
    end
  end
end
