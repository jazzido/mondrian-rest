module Mondrian::REST

  class PropertyError < StandardError
  end

  module APIHelpers
    @@olap = nil
    @@mdx_parser = nil

    def olap
      if @@olap.nil?
        @@olap = Mondrian::OLAP::Connection.new(env['mondrian-olap.params'])
        @@olap.connect
      end
      @@olap
    end

    ##
    # Returns an instance of org.olap4j.mdx.parser.MdxParser
    def mdx_parser
      if @@mdx_parser.nil?
        @@mdx_parser = olap.raw_connection.getParserFactory
                       .createMdxParser(olap.raw_connection)
      end
      @@mdx_parser
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

      result = olap.execute query
      result.mdx = query if params[:debug]
      result.properties = params[:properties]
      result.caption_properties = params[:caption]
      result.cube = Mondrian::OLAP::Cube.new(olap,
                                             olap.raw_connection.prepareOlapStatement(query).getCube)
      result
    rescue Mondrian::OLAP::Error => st
      error!({ error: st.backtrace }, 400)
    end

    def run_from_params(params)
      cube = get_cube_or_404(params[:cube_name])
      query = build_query(cube, params)

      result = mdx(query.to_mdx)
      result.cube = cube
      result
    end

    def get_members(params)
      cube = get_cube_or_404(params[:cube_name])

      dimension = cube.dimension(params[:dimension_name])
      if dimension.nil?
        error!("dimension #{params[:dimension_name]} not found in cube #{params[:cube_name]}", 404)
      end

      hier = unless params[:hierarchy_name].nil?
               h = dimension.hierarchy(params[:hierarchy_name])
               error!("Hierarchy #{params[:hierarchy_name]} does not exist in dimension #{params[:dimension_name]}", 404) if h.nil?
               h
             else
               dimension.hierarchies.first
             end

      level = hier.level(params[:level_name])
      if level.nil?
        error!("level #{params[:level_name]} not found in dimension #{params[:dimension_name]}")
      end

      level.to_h(member_properties: params[:member_properties],
                 get_children: params[:children],
                 member_caption: params[:caption],
                 get_members: true)
    end

    NEST = Mondrian::REST::Nest.new
                               .key { |d| d[0] }
                               .key { |d| d[1] }.freeze

    def self.parse_caption_properties(cprops)
      return {} if cprops.nil? || cprops.empty?

      NEST.map(cprops.map do |cp|
                 names = org.olap4j.mdx.IdentifierNode.parseIdentifier(cp).getSegmentList.to_a.map(&:name)
                 # IF prop in Dim.Hier.Lvl.Prop format, skip names[1]
                 names.size == 4 ? [names[0], names[2], names[3]] : names
               end)
    end

    ##
    # parse an array of property specifications like so:
    # input: ['ISICrev4.Level 2.Level 2 ES', 'ISICrev4.Level 1.Level 1 ES']
    # output: {"ISICrev4"=>{"Level 2"=>["Level 2 ES"], "Level 1"=>["Level 1 ES"]}}
    def self.parse_properties(properties, dimensions)
      properties.map { |p|
        sl = org.olap4j.mdx.IdentifierNode.parseIdentifier(p).getSegmentList.to_a
        slsize = sl.size

        if slsize != 3 and slsize != 4
          raise PropertyError, "Properties must be in the form `Dimension.Level.Property Name`"
        end

        # check that the dimension is in the drilldown list
        if dimensions.find { |ad| sl[0].name == ad[:name] }.nil?
          raise PropertyError, "Dimension `#{sl[0].name}` not in drilldown list"
        end

        sl.map(&:name)
      }
            .group_by(&:first)
            .reduce({}) { |h, (k,v)|
        h[k] = Hash[v.group_by { |x| x.size == 4 ? x[2] : x[1] }
                      .map { |k1, v1| [k1, v1.map(&:last)] }]
        h
      }
    end
  end
end
