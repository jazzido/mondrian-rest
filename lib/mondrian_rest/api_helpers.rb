module Mondrian::REST
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
      begin
        result = olap.execute query
        return result
      rescue Mondrian::OLAP::Error => st
        error!({error: st.backtrace}, 400)
      end
    end

    NEST = Mondrian::REST::Nest.new
             .key { |d| d[0] }
             .key { |d| d[1] }

    def self.parse_caption_properties(cprops)
      if cprops.size < 1
        return {}
      end

      NEST.map(cprops.map { |cp|
                 org.olap4j.mdx.IdentifierNode.parseIdentifier(cp).getSegmentList.to_a.map(&:name)
             })
    end

    ##
    # parse an array of property specifications like so:
    # input: ['ISICrev4.Level 2.Level 2 ES', 'ISICrev4.Level 1.Level 1 ES']
    # output: {"ISICrev4"=>{"Level 2"=>["Level 2 ES"], "Level 1"=>["Level 1 ES"]}}
    def self.parse_properties(properties, dimensions)
      properties.map { |p|
        sl = org.olap4j.mdx.IdentifierNode.parseIdentifier(p).getSegmentList.to_a
        if sl.size != 3
          raise "Properties must be in the form `Dimension.Level.Property Name`"
        end

        # check that the dimension is in the drilldown list
        if dimensions.find { |ad| sl[0].name == ad[:name] }.nil?
          raise "Dimension `#{sl[0].name}` not in drilldown list"
        end

        sl.map(&:name)
      }.group_by(&:first)
        .reduce({}) { |h, (k,v)|
        h[k] = Hash[v.group_by { |x| x[1] }.map { |k1, v1| [k1, v1.map(&:last)] }]
        h
      }
    end
  end
end
