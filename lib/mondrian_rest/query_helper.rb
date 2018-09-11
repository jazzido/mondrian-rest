# coding: utf-8
module Mondrian::REST
  module QueryHelper
    VALID_FILTER_OPS = [
      '>', '<', '>=', '<=', '=', '<>'
    ].freeze
    VALID_FILTER_RE = /(?<measure>[a-zA-Z0-9-!$%^&*()_+|@#~`{}\[\]:";'?,.\/\s]+)\s*(?<operand>#{VALID_FILTER_OPS.join("|")})\s*(?<value>-?\d+\.?\d*)/
    MEMBER_METHODS = %w[Caption Key Name UniqueName].freeze

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
      cube.member(member_exp)
    rescue Java::JavaLang::IllegalArgumentException
      error!("Illegal expression: #{member_exp}", 400)
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
        when '{}'
          # check that the set contains only Members of a single dimension level
          set_members = p.getArgList.map do |id_node|
            get_member(cube, unparse_node(id_node))
          end

          if set_members.any?(&:nil?)
            error!('Illegal cut. Unknown member in cut set', 400)
          end

          ls = set_members.map(&:raw_level).uniq
          error!('Illegal cut: ' + cut_expr, 400) unless ls.size == 1
          { level: ls.first, cut: unparse_node(p), type: :set, set_members: set_members }
        when '()'
          # check that the range contains a valid range

          unless p.getArgList.first.is_a?(org.olap4j.mdx.CallNode) \
            && (p.getArgList.first.getOperatorName == ':')
            error!('Illegal cut: ' + cut_expr, 400)
          end

          ls = p.getArgList.first.getArgList.map do |id_node|
            get_member(cube, unparse_node(id_node)).raw_level
          end.uniq

          error!('Illegal cut: ' + cut_expr, 400) unless ls.size == 1

          { level: ls.first, cut: unparse_node(p), type: :range }
        else
          error!('Illegal cut: ' + cut_expr, 400)
        end
      when org.olap4j.mdx.IdentifierNode

        # does cut_expr look like a NamedSet?
        s = get_named_set(cube, cut_expr)
        return { level: nil, cut: cut_expr, type: :named_set } unless s.nil?

        # if `cut_expr` looks like a member, check that it's level is
        # equal to `level`
        m = get_member(cube, cut_expr)

        if m.nil?
          error!("Illegal cut: #{cut_expr} — Member does not exist", 400)
        end

        { level: m.raw_level, cut: cut_expr, type: :member }
      else
        error!('Illegal cut: ' + cut_expr, 400)
      end
    end

    ##
    # Parses a drilldown specification
    # XXX TODO write doc
    def parse_drilldown(cube, drilldown)
      # check if the drilldown is a named set
      named_sets = cube.named_sets
      if (ns = named_sets.find { |ns| ns.name == drilldown })
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
      error!("Filter clause #{filter} is invalid", 400) if m.nil?

      unless cube.valid_measure?(m['measure'].strip)
        error!("Invalid filter: measure #{m['measure'].strip} does not exist", 400)
      end

      {
        measure: m['measure'].strip,
        operand: m['operand'].strip,
        value: m['value'].strip
      }
    end

    def parse_order(cube, order, order_desc)
      begin
        s = org.olap4j.mdx.IdentifierNode.parseIdentifier(order).getSegmentList.map(&:getName)
      rescue Java::JavaLang::IllegalArgumentException
        error!("Invalid order specification: #{order}", 400)
      end

      if s[0] == 'Measures'
        error!("Invalid measure in order: #{s[1]}", 400) unless cube.valid_measure?(s[1])

        return {
          order: cube.measure(s[1]).full_name,
          desc: order_desc
        }
      else # ordering by a property
        # we need at least dim.level.property
        error!('Invalid order: specify at least [Dimension].[Level].[Property]', 400) if s.size < 3

        lvl = cube.level(*s[0..-2])
        error!("Invalid order: level #{s[0..-2].join('.')} not found", 400) if lvl.nil?

        last = if MEMBER_METHODS.include?(s.last)
                 s.last
               else
                 prop = lvl.property(s[-1])
                 error!("Invalid order: property #{order} not found", 400) if prop.nil?
                 "Properties('#{s.last}')"
               end

        return {
          order: s[0..-2].map do |n|
            Java::MondrianOlap::Util.quoteMdxIdentifier(n)
          end.join('.') + '.CurrentMember.' + last,
          desc: order_desc
        }
      end
    end

    def build_query(cube, options = {})
      measure_members = cube.dimension('Measures').hierarchy.levels.first.members
      options = {
        'cut' => [],
        'drilldown' => [],
        'measures' => [measure_members.first.name],
        'nonempty' => false,
        'distinct' => false,
        'filter' => [],
        'order' => nil,
        'order_desc' => false,
        'offset' => nil,
        'limit' => nil
      }.merge(options)

      # validate measures exist
      cm_names = measure_members.map(&:name)

      options['measures'].each do |m|
        error!("Measure #{m} does not exist in cube #{cube.name}", 400) unless cm_names.include?(m)
      end

      filters = options['filter'].map { |f| parse_measure_filter(cube, f) }

      # measures go in axis(0) of the resultset
      query = olap.from(cube.name)
                  .axis(0,
                        *options['measures'].map do |m|
                          measure_members.find { |cm| cm.name == m }.full_name
                        end)
      query = query.nonempty if options['nonempty']

      query_axes = options['drilldown'].map { |dd| parse_drilldown(cube, dd) }

      slicer_axis = options['cut'].each_with_object({}) do |cut_expr, h|
        pc = parse_cut(cube, cut_expr)
        h[pc[:level]] = pc
      end

      dd = query_axes.map do |qa|
        # if drilling down on a named set
        if qa.is_a?(Java::MondrianOlap4j::MondrianOlap4jNamedSet)
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
        elsif cut = slicer_axis.find do |lvl, cut|
                next if cut[:type] == :named_set
                qa.raw_level.hierarchy == lvl.hierarchy && lvl.depth < qa.depth
              end
          slicer_axis.delete(cut[0])
          cut = cut[1]

          case cut[:type]
          when :member
            "DESCENDANTS(#{cut[:cut]}, #{qa.unique_name})"
          when :set
            # TODO
            '{' + cut[:set_members].map do |m|
              "DESCENDANTS(#{m.full_name}, #{qa.unique_name})"
            end.join(',') + '}'
          when :range
            # TODO
            raise 'Unsupported operation'
          end
        else
          qa.unique_name + '.Members'
        end
      end

      unless dd.empty?
        # Cross join all the drilldowns
        axis_exp = dd.join(' * ')

        # Apply filters
        unless filters.empty?
          filter_exp = filters.map { |f| "[Measures].[#{f[:measure]}] #{f[:operand]} #{f[:value]}" }.join(' AND ')
          axis_exp = "FILTER(#{axis_exp}, #{filter_exp})"
        end

        unless options['order'].nil?
          order = parse_order(cube, options['order'], options['order_desc'])
          axis_exp = "ORDER(#{axis_exp}, #{order[:order]}, #{order[:desc] ? 'BDESC' : 'BASC'})"
        end

        # TODO: Apply pagination
        unless options['offset'].nil?
          axis_exp = if options['limit'].nil?
                       "SUBSET(#{axis_exp}, #{options['offset']})"
                     else
                       "SUBSET(#{axis_exp}, #{options['offset']}, #{options['limit']})"
                     end
        end

        query = query.axis(1, axis_exp)
      end

      query = query.distinct if options['distinct']

      query = query.nonempty if options['nonempty']

      # slicer axes (cut)
      if slicer_axis.size >= 1
        query = query.where(slicer_axis.values.map do |v|
                              if v[:type] == :named_set
                                "[#{v[:cut]}]"
                              else
                                v[:cut]
                              end
                            end.join(' * '))
      end
      query
    end
  end
end
