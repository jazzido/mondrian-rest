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
                    :caption => l.caption
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

      def to_h
        {
          name: self.name,
          caption: self.caption,
          members: self.members
            .uniq { |m| m.property_value('MEMBER_KEY') }
            .map(&:to_h)
        }
      end
    end

    class Member

      def raw_level
        @raw_member.getLevel
      end

      def to_h
        kv = [:name, :full_name, :caption, :all_member?,
              :drillable?, :depth].map { |m|
          [m, self.send(m)]
        }
        kv << [:key, self.property_value('MEMBER_KEY')]
        kv << [:num_children, self.property_value('CHILDREN_CARDINALITY')]
        kv << [:parent_name, self.property_value('PARENT_UNIQUE_NAME')]
        Hash[kv]
      end

      def dimension_info
        d = @raw_member.getDimension
        {
          name: d.getName,
          caption: d.getCaption,
          type: self.dimension_type,
          level: @raw_member.getLevel.getCaption
        }
      end

      def ancestors
        @raw_member.getAncestorMembers.map { |am|
          self.class.new(am)
        }
      end
    end

    class Result

      def to_json
        to_h.to_json
      end

      def to_h(parents=false)
        # XXX TODO
        # return the contents of the filter axis
        # puts self.raw_cell_set.getFilterAxis.inspect

        dimensions = [ nil ] * self.axis_members.size
        parents_l = self.axis_members.size.times.map { |_| Hash.new }
        {
          axes: self.axis_members.each_with_index.map { |a, i|
            {
              members: a.map { |m|
                dimensions[i] ||= m.dimension_info
                mh = m.to_h
                if parents
                  parents_l[i][mh[:parent_name]] ||= m.ancestors.first.to_h
                end
                mh
              }
            }
          },
          axis_dimensions: dimensions,
          values: self.values
        }.merge(parents ? { axis_parents: parents_l } : {})
      end
    end
  end
end
