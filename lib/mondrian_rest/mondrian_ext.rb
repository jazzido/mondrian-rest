require 'set'

module Mondrian
  module OLAP

    class Cube

      def named_sets
        raw_cube.getSets
      end

      def measure(name)
        self.dimension('Measures')
          .hierarchy
          .levels
          .first
          .members
          .detect { |m| m.name == name }
      end

      def valid_measure?(name)
        !self.measure(name).nil?
      end

      def level(*parts)
        dim = self.dimension(parts[0])
        hier = if parts.size > 2
                 dim.hierarchy(parts[1])
               else
                 dim.hierarchies[0]
               end
        hier.level(parts.last)
      end

      def to_h
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
          :dimensions => self.dimensions
                           .find_all { |d| d.dimension_type != :measures }
                           .map { |d| d.to_h(get_members: false) },
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
              :full_name => m.full_name,
              :aggregator => m.raw_member.getAggregator
            }
          end
        }
      end

    end

    class Dimension
      def to_h(options={})
        get_members = options[:get_members]
        {
          name: self.name,
          caption: self.caption,
          type: self.dimension_type,
          annotations: self.annotations,
          hierarchies: self.hierarchies.map { |h|
            {
              name: h.name,
              has_all: h.has_all?,
              all_member_name: h.all_member_name,
              levels: h.levels.map { |l|
                l.to_h(get_members: get_members)
              } #/levels
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

      def to_h(member_properties: [], get_children: false, member_caption: nil, get_members: false)
        rv = {
          name: self.name,
          full_name: self.full_name,
          depth: self.depth,
          caption: self.caption,
          annotations: self.annotations,
          :properties => self.own_props.map { |p|
            p.getName
          }
        }

        if get_members
          rv[:members] = self.members
                           .uniq { |m| m.property_value('MEMBER_KEY') }
                           .map { |m|
            m.to_h(member_properties, member_caption, get_children)
              .merge({ancestors: m.ancestors.map(&:to_h)})
          }
        end
        rv
      end

      def own_props
        @raw_level.properties.select { |p|
          !INTERNAL_PROPS.include?(p.name)
        }
      end

      def property(name)
        self.raw_level.getProperties.asMap[name]
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
        d = @raw_member.getDimension()
        l = @raw_member.getLevel()
        h = l.getHierarchy()

        x = {
          name: d.getName,
          caption: d.getCaption,
          type: self.dimension_type,
          level: l.getCaption,
          level_depth: l.depth,
          hierarchy: h.getName
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

        drilldowns_num = if self.raw_cell_set.getMetaData.getAxesMetaData.size == 1
                           0
                         else
                           self.raw_cell_set.getMetaData.getAxesMetaData[1].getHierarchies.size
                         end
        dimensions = self.axis_members
                       .flatten
                       .map(&:dimension_info)
                       .uniq

        pprops = {}
        pprops = Mondrian::REST::APIHelpers.parse_properties(self.properties, dimensions[1..-1]) unless self.properties.nil?
        cprops = Mondrian::REST::APIHelpers.parse_caption_properties(self.caption_properties)

        measure_axis = { members: self.axis_members.first.flatten.map(&:to_h) }
        measure_axis.merge!(dimensions[0]) if dimensions.size > 0

        member_axes = if drilldowns_num > 1
                        self.axis_members[1].transpose
                      elsif drilldowns_num == 1
                        [self.axis_members[1]]
                      else
                        []
                      end

        {
          axes: [measure_axis] + member_axes.each_with_index.map { |a, axis_index|
            {
              members: a.uniq(&:full_name).map { |m|
                mh = m.to_h(
                  pprops.dig(m.raw_member.getDimension.name, m.raw_level.name) || [],
                  (cprops.dig(m.raw_member.getDimension.name, m.raw_level.name) || [[]])[0][-1]
                )
                if parents
                  mh[:ancestors] = m.ancestors.map { |ma|
                    ma.to_h(
                      pprops.dig(ma.raw_member.getDimension.name, ma.raw_level.name) || [],
                      (cprops.dig(ma.raw_member.getDimension.name, ma.raw_level.name) || [[]])[0][-1])
                  }
                end
                mh
              }
            }.merge(dimensions.size > 1 ? dimensions[axis_index+1] : {})
          },
          cell_keys: if drilldowns_num > 1
                       self.axis_members[1].map { |t| t.map { |m| m.property_value('MEMBER_UNIQUE_NAME') } }
                     elsif drilldowns_num == 1
                       self.axis_members[1].map { |t| [ t.property_value('MEMBER_UNIQUE_NAME') ] }
                     else
                       []
                     end,
          values: self.values,
          mdx: debug ? self.mdx : nil
        }
      end
    end
  end
end
