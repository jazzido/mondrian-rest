require_relative './formatters/aggregation_json'
require_relative './formatters/csv'
require_relative './formatters/excel'
require_relative './formatters/jsonrecords'

module Mondrian::REST::Formatters

  ##
  # Generate 'tidy data' (http://vita.had.co.nz/papers/tidy-data.pdf)
  # from a result set.
  def self.tidy(result, options)

    cube = result.cube

    add_parents = options[:add_parents]
    properties = options[:properties]
    sparse = options[:sparse]
    rs = result.to_h(add_parents, options[:debug])

    if rs[:values].empty?
      return []
    end

    measures = rs[:axes].first[:members]
    dimensions = rs[:axes][1..-1]

    indexed_members = rs[:axes].map { |ax|
      ax[:members].index_by { |m| m[:key] }
    }

    columns = []
    slices = []
    level_has_all = []

    Enumerator.new do |y|
      dimensions.each do |dd|
        if add_parents
          hier = cube.dimension(dd[:name])
                   .hierarchy(dd[:hierarchy])

          level_has_all << hier.has_all?
          slices << dd[:level_depth]

          hier
            .levels[(hier.has_all? ? 1 : 0)...dd[:level_depth]]
            .each do |ancestor_level|

            columns += ["ID #{ancestor_level.caption}", ancestor_level.caption]
          end
        end

        columns += ["ID #{dd[:level]}", dd[:level]]
      end

      props = Mondrian::REST::APIHelpers.parse_properties(properties, dimensions)
      pnames = properties.map { |p|
        org.olap4j.mdx.IdentifierNode.parseIdentifier(p).getSegmentList.last.name
      }

      # append properties and measure columns and yield table header
      y.yield columns + pnames + pluck(measures, :name)

      rs[:cell_keys].each_with_index do |row, i|
        cm = row.each_with_index.map { |member_key, i| indexed_members[i+1][member_key] }
        msrs = rs[:values][i]

        if !add_parents
          y.yield pluck(cm, :key).zip(pluck(cm, :caption)).flatten \
                  + get_props(cm, pnames, props, dimensions) \
                  + msrs
        else
          vdim = cm.each.with_index.reduce([]) { |cnames, (member, j)|
                     member[:ancestors][0...slices[j] - (level_has_all[j] ? 1 : 0)].reverse.each { |ancestor|
                       cnames += [ancestor[:key], ancestor[:caption]]
                     }
                     cnames += [member[:key], member[:caption]]
                   }

          y.yield vdim + get_props(cm, pnames, props, dimensions) + msrs
        end
      end
    end
  end

  def self.get_props(cm, pnames, props, dimensions)
    pvalues = cm.each.with_index.reduce({}) do |h, (member, ax_i)|
      dname = dimensions[ax_i][:name]
      if props[dname] # are there properties requested for members of this dimension?
        mmbr_lvl = dimensions[ax_i][:level]
        (props[dname][mmbr_lvl] || []).each { |p|
          h[p] = member[:properties][p]
        }
        if member[:ancestors]
          props[dname]
            .select { |k, _| k != mmbr_lvl } # levels other than member's own
            .each { |l, p|
            p.each # get all requested props for this level's ancestor
              .with_object(member[:ancestors].find { |anc|
                             anc[:level_name] == l
                           }) { |prop, anc|
              h[prop] = anc[:properties][prop]
            }
          }
        end
      end
      h
    end # reduce
    pnames.map { |pn| pvalues[pn] }
  end

  def self.pluck(a, m)
    a.map { |e| e[m] }
  end
end
