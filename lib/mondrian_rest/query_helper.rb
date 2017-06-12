# coding: utf-8
module Mondrian::REST
  module QueryHelper

    def unparse_node(node)
      sw = java.io.StringWriter.new
      ptw = org.olap4j.mdx.ParseTreeWriter.new(sw)
      node.unparse(ptw)
      sw.toString
    end

    def get_dimension(cube, dname)
      cube_dimensions = cube.dimensions
                        .find_all { |d| d.dimension_type != :measures }
      dim = cube_dimensions.find { |d| d.name == dname }
      error!("Dimension #{dname} does not exist", 400) if dim.nil?
      dim
    end

    def get_member(cube, member_exp)
      begin
        return cube.member(member_exp)
      rescue Java::JavaLang::IllegalArgumentException
        error!("Illegal member expression: #{member_exp}", 400)
      end
    end

    ##
    # Parses a string containing a 'cut' expression
    # It can be a set (`{Dim.Mem, Dim2.Mem2}`), a range (`([Time].[Year].[1997]:[Time].[Year].[1998])`) or a member identifier (`[Time].[Year].[1998]`).
    def parse_cut(cube, cut_expr)
      p = mdx_parser.parseExpression(cut_expr)

      case p
      when org.olap4j.mdx.CallNode
        case p.getOperatorName
        when "{}"
          # check that the set contains only Members of a single dimension level
          set_members = p.getArgList.map { |id_node|
            get_member(cube, unparse_node(id_node))
          }

          if set_members.any? { |m| m.nil? }
            error!("Illegal cut. Unknown member in cut set", 400)
          end

          ls = set_members.map(&:raw_level).uniq
          unless ls.size == 1
            error!("Illegal cut: " + cut_expr, 400)
          end
          { level: ls.first, cut: unparse_node(p), type: :set, set_members: set_members }
        when "()"
          # check that the range contains a valid range

          unless p.getArgList.first.is_a?(org.olap4j.mdx.CallNode) \
            and p.getArgList.first.getOperatorName == ':'
            error!("Illegal cut: " + cut_expr, 400)
          end

          ls = p.getArgList.first.getArgList.map { |id_node|
            get_member(cube, unparse_node(id_node)).raw_level
          }.uniq

          unless ls.size == 1
            error!("Illegal cut: " + cut_expr, 400)
          end

          { level: ls.first, cut: unparse_node(p), type: :range }
        else
          error!("Illegal cut: " + cut_expr, 400)
        end
      when org.olap4j.mdx.IdentifierNode
        # if `cut_expr` looks like a member, check that it's level is
        # equal to `level`
        m = get_member(cube, cut_expr)

        if m.nil?
          error!("Illegal cut: #{cut_expr} — Member does not exist", 400)
        end

        { level: m.raw_level, cut: cut_expr, type: :member }
      else
        error!("Illegal cut: " + cut_expr, 400)
      end
    end

    ##
    # Parses a drilldown specification
    # XXX TODO write doc
    def parse_drilldown(cube, drilldown)

      # check if the drilldown is a named set
      named_sets = cube.named_sets
      if ns = named_sets.find { |ns| ns.name == drilldown }
        return ns
      end

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
        error!("Measure #{m} does not exist in cube #{cube.name}", 400) unless cm_names.include?(m)
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

      slicer_axis = options['cut'].reduce({}) { |h, cut_expr|
        pc = parse_cut(cube, cut_expr)
        h[pc[:level]] = pc
        h
      }

      dd = query_axes.map do |qa|
        # if drilling down on a named set
        if qa.kind_of?(Java::MondrianOlap4j::MondrianOlap4jNamedSet)
          "[#{qa.name}]"
        # there's a slice (cut) on this axis
        elsif slicer_axis[qa.raw_level]
          cut = slicer_axis.delete(qa.raw_level)
          case cut[:type]
          when :member
            "{#{cut[:cut]}}"
          else
            cut[:cut]
          end
        elsif cut = slicer_axis.find { |lvl, cut|
                qa.raw_level.hierarchy == lvl.hierarchy && lvl.depth < qa.depth
              }
          slicer_axis.delete(cut[0])
          cut = cut[1]

          case cut[:type]
          when :member
            "DESCENDANTS(#{cut[:cut]}, #{qa.full_name})"
          when :set
            # TODO
            "{" + cut[:set_members].map { |m|
              "DESCENDANTS(#{m.full_name}, #{qa.full_name})"
            }.join(",") + "}"
          when :range
            # TODO
            raise "Unsupported operation"
          end
        else
          qa.raw_level.unique_name + '.Members'
        end
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
        query = query.where(slicer_axis.values.map { |v| v[:cut] }.join(' * '))
      end
      query
    end
  end
end
