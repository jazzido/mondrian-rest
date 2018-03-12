# coding: utf-8
module Mondrian::REST
  module QueryHelper

    VALID_FILTER_OPS = [
      '>', '<', '>=', '<=', '=', '<>'
    ]
    VALID_FILTER_RE = /(?<measure>[a-zA-Z0-9\s]+)\s*(?<operand>#{VALID_FILTER_OPS.join("|")})\s*(?<value>-?\d+\.?\d*)/
    FILTERED_MEASURE_PREFIX = "--MRFILTERED "

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
        error!("Illegal expression: #{member_exp}", 400)
      end
    end

    def get_named_set(cube, named_set_exp)
      nss = cube.named_sets
      nss.find { |ns| ns.name == named_set_exp }
    end

    ##
    # Parses a string containing a 'cut' expression
    # It can be a set (`{Dim.Mem, Dim2.Mem2}`), a range (`([Time].[Year].[1997]:[Time].[Year].[1998])`), a member identifier (`[Time].[Year].[1998]`) or a NamedSet.
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

        # does cut_expr look like a NamedSet?
        s = get_named_set(cube, cut_expr)
        if !s.nil?
          return { level: nil, cut: cut_expr, type: :named_set }
        end

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
          hierarchy = dimension.hierarchies.find { |h_| h_.name == s[1].name }
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

    def parse_measure_filter(cube, filter)
      m = VALID_FILTER_RE.match(filter)
      if m.nil?
        error!("Filter clause #{filter} is invalid", 400)
      end

      # unless cube.valid_measure?(m['measure'])
      #   error!("Invalid filter: measure #{m['measure']} does not exist", 400)
      # end

      {
        :measure => m['measure'].strip,
        :operand => m['operand'].strip,
        :value => m['value'].strip
      }
    end

    def build_query(cube, options={})

      measure_members = cube.dimension('Measures').hierarchy.levels.first.members
      options = {
        'cut' => [],
        'drilldown' => [],
        'measures' => [measure_members.first.name],
        'nonempty' => false,
        'distinct' => false,
        'filter' => []
      }.merge(options)

      # validate measures exist
      options['measures'].each { |m|
        error!("Measure #{m} does not exist in cube #{cube.name}", 400) unless cube.valid_measure?(m)
      }

      # create query object
      query = olap.from(cube.name)

      filters = options['filter'].map { |f| parse_measure_filter(cube, f) }

      query = if filters.size > 0
                # build IIF clause
                iif = filters.map { |f|  "Measures.[#{org.olap4j.mdx.MdxUtil.mdxEncodeString(f[:measure])}] #{f[:operand]} #{f[:value]}"}.join(" AND ")
                options['measures'].reduce(query) { |query, measure|
                  query
                    .with_member("Measures.[#{FILTERED_MEASURE_PREFIX}#{org.olap4j.mdx.MdxUtil.mdxEncodeString(measure)}]")
                    .as("IIF(#{iif}, [#{org.olap4j.mdx.MdxUtil.mdxEncodeString(measure)}], NULL)")
                }
                  .axis(0,
                        options['measures'].map { |m| "Measures.[#{FILTERED_MEASURE_PREFIX}#{org.olap4j.mdx.MdxUtil.mdxEncodeString(m)}]"})
              else
                query
                  .axis(0,
                        *options['measures'].map { |m|
                          measure_members.find { |cm| cm.name == m }.full_name
                        })
              end

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
                next if cut[:type] == :named_set
                qa.raw_level.hierarchy == lvl.hierarchy && lvl.depth < qa.depth
              }
          slicer_axis.delete(cut[0])
          cut = cut[1]

          case cut[:type]
          when :member
            "DESCENDANTS(#{cut[:cut]}, #{qa.unique_name})"
          when :set
            # TODO
            "{" + cut[:set_members].map { |m|
              "DESCENDANTS(#{m.full_name}, #{qa.unique_name})"
            }.join(",") + "}"
          when :range
            # TODO
            raise "Unsupported operation"
          end
        else
          qa.unique_name + '.Members'
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
        query = query.where(slicer_axis.values.map { |v|
                              if v[:type] == :named_set
                                "[#{v[:cut]}]"
                              else
                                v[:cut]
                              end
                            }.join(' * '))
      end
      query
    end
  end
end
