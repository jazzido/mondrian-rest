require 'set'

module Mondrian
  module OLAP

    class Cube

      def named_sets
        raw_cube.getSets
      end

      def to_h
        # gather dimensions
        dimensions = self.dimensions
                       .find_all { |d| d.dimension_type != :measures }
                       .map do |d|
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
                    :annotations => l.annotations,
                    :properties => l.own_props.map { |p|
                      p.getName
                    }
                  }
                }
              }
            }
          }
        end

        # gather named sets
        named_sets = self.named_sets
                       .map do |ns|

          t = ns.getExpression.getType
          {
            :name => ns.name,
            :dimension => t.getDimension.getName,
            :hierarchy => t.getHierarchy.getName,
            :level => t.getLevel.getName,
            :annotations => begin
                              annotated = ns.unwrap(Java::MondrianOlap::Annotated.java_class)
                              annotations_hash = annotated.getAnnotationMap.to_hash
                              annotations_hash.each do |key, annotation|
                                annotations_hash[key] = annotation.getValue
                              end
                              annotations_hash
                            rescue
                              {}
                            end
          }
        end

        return {
          :name => self.name,
          :annotations => self.annotations,
          :dimensions => dimensions,
          :named_sets => named_sets,
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

    class Hierarchy
      attr_reader :dimension
    end

    INTERNAL_PROPS = Set.new(['CATALOG_NAME', 'SCHEMA_NAME', 'CUBE_NAME', 'DIMENSION_UNIQUE_NAME', 'HIERARCHY_UNIQUE_NAME', 'LEVEL_UNIQUE_NAME', 'LEVEL_NUMBER', 'MEMBER_ORDINAL', 'MEMBER_NAME', 'MEMBER_UNIQUE_NAME', 'MEMBER_TYPE', 'MEMBER_GUID', 'MEMBER_CAPTION', 'CHILDREN_CARDINALITY', 'PARENT_LEVEL', 'PARENT_UNIQUE_NAME', 'PARENT_COUNT', 'DESCRIPTION', '$visible', 'MEMBER_KEY', 'IS_PLACEHOLDERMEMBER', 'IS_DATAMEMBER', 'DEPTH', 'DISPLAY_INFO', 'VALUE', '$scenario', 'CELL_FORMATTER', 'CELL_FORMATTER_SCRIPT', 'CELL_FORMATTER_SCRIPT_LANGUAGE', 'DISPLAY_FOLDER', 'FORMAT_EXP', 'KEY', '$name']).freeze

    class Level
      attr_reader :hierarchy

      def full_name
        @full_name ||= @raw_level.getUniqueName
      end

      def unique_name
        "#{Java::MondrianOlap::Util.quoteMdxIdentifier(hierarchy.dimension.name)}.#{Java::MondrianOlap::Util.quoteMdxIdentifier(hierarchy.name)}.#{Java::MondrianOlap::Util.quoteMdxIdentifier(self.name)}"
      end

      def to_h(member_properties=[], get_children=false, member_caption=nil)
        {
          name: self.name,
          caption: self.caption,
          members: self.members
            .uniq { |m| m.property_value('MEMBER_KEY') }
            .map { |m| m.to_h(member_properties, member_caption, get_children) },
          :properties => self.own_props.map { |p|
            p.getName
          }
        }
      end

      def own_props
        @raw_level.properties.select { |p|
          !INTERNAL_PROPS.include?(p.name)
        }
      end

    end

    class Member

      alias_method :_caption, :caption

      def raw_level
        @raw_member.getLevel
      end

      def to_h(properties=[], caption_property=nil, get_children=false)
        kv = [:name, :full_name, :all_member?,
              :drillable?, :depth].map { |m|
          [m, self.send(m)]
        }
        kv << [:caption, self.pcaption(caption_property)]
        kv << [:key, self.property_value('MEMBER_KEY')]
        kv << [:num_children, self.property_value('CHILDREN_CARDINALITY')]
        kv << [:parent_name, self.property_value('PARENT_UNIQUE_NAME')]
        kv << [:level_name, self.raw_level.name]
        kv << [:children, get_children ? self.children.map { |c| c.to_h([], nil, get_children)} : []]

        if properties.size > 0
          kv << [
            :properties,
            properties.reduce({}) { |h, p| h[p] = self.property_value(p); h }
          ]
        end

        Hash[kv]
      end

      def pcaption(caption_property=nil)
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
