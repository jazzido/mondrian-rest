module Mondrian
  module OLAP

    class Cube
      def to_h
        # gather dimensions
        dimensions = self.dimensions
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
                    :caption => l.caption,
                    :depth => l.depth,
                    :annotations => l.annotations
                  }
                }
              }
            }
          }
        }

        return {
          :name => self.name,
          :annotations => self.annotations,
          :dimensions => dimensions,
          :measures => self.dimensions
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

    class Dimension
      def to_h
        {
          hierarchies: self.hierarchies.map { |h|
            {
              name: h.name,
              has_all: h.has_all?,
              levels: h.levels.map(&:to_h) #/levels
            } # /hierarchies
          } #/map
        } #/ dimension
      end
    end

    class Level
      attr_reader :hierarchy

      def full_name
        @full_name ||= @raw_level.getUniqueName
      end

      def to_h(member_properties=[])
        {
          name: self.name,
          caption: self.caption,
          members: self.members
            .uniq { |m| m.property_value('MEMBER_KEY') }
            .map { |m| m.to_h(member_properties) }
        }
      end
    end

    class Member

      alias_method :_caption, :caption

      def raw_level
        @raw_member.getLevel
      end

      def to_h(properties=[], caption_property=nil)
        kv = [:name, :full_name, :all_member?,
              :drillable?, :depth].map { |m|
          [m, self.send(m)]
        }
        kv << [:caption, self.pcaption(caption_property)]
        kv << [:key, self.property_value('MEMBER_KEY')]
        kv << [:num_children, self.property_value('CHILDREN_CARDINALITY')]
        kv << [:parent_name, self.property_value('PARENT_UNIQUE_NAME')]
        kv << [:level_name, self.raw_level.name]

        if properties.size > 0
          kv << [
            :properties,
            properties.reduce({}) { |h, p| h[p] = self.property_value(p); h }
          ]
        end

        Hash[kv]
      end

      def pcaption(caption_property)
        if caption_property
          self.property_value(caption_property)
        else
          self._caption
        end
      end

      def dimension_info
        d = @raw_member.getDimension
        l = @raw_member.getLevel
        {
          name: d.getName,
          caption: d.getCaption,
          type: self.dimension_type,
          level: l.getCaption,
          level_depth: l.depth
        }
      end

      def ancestors
        @raw_member.getAncestorMembers.map { |am|
          self.class.new(am)
        }
      end
    end

    class Result

      attr_accessor :cube, :mdx, :properties, :caption_properties

      def to_json
        to_h.to_json
      end

      def to_h(parents=false, debug=false)
        # XXX TODO
        # return the contents of the filter axis
        # puts self.raw_cell_set.getFilterAxis.inspect

        dimensions = self.axis_members.map { |am| am.first.dimension_info }

        pprops = unless self.properties.nil?
                   Mondrian::REST::APIHelpers.parse_properties(self.properties,
                                                               dimensions[1..-1]) # exclude Measures dimension
                 else
                   {}
                 end

        cprops = Mondrian::REST::APIHelpers.parse_caption_properties(
          self.caption_properties
        )

        rv = {
          axes: self.axis_members.each_with_index.map { |a, i|
            {
              members: a.map { |m|
                mh = m.to_h(
                  pprops.dig(m.raw_member.getDimension.name, m.raw_level.name) || [],
                  (cprops.dig(m.raw_member.getDimension.name, m.raw_level.name) || [[]])[0][-1]
                )
                if parents
                  mh.merge!({
                              ancestors: m.ancestors.map { |ma|
                                ma.to_h(
                                  pprops.dig(ma.raw_member.getDimension.name, ma.raw_level.name) || [],
                                  (cprops.dig(ma.raw_member.getDimension.name, ma.raw_level.name) || [[]])[0][-1]
                                )
                              }
                            })
                end
                mh
              }
            }
          },
          axis_dimensions: dimensions,
          values: self.values
        }

        rv[:mdx] = self.mdx if debug

        rv

      end
    end
  end
end
