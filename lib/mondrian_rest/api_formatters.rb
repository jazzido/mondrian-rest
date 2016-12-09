require 'csv'
require 'writeexcel'

module Mondrian::REST::Formatters

  module AggregationJSON
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'

      result.to_h(add_parents, debug).to_json
    end
  end

  module XLS
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'
      properties = env['rack.request.query_hash']['properties'] || []

      out = StringIO.new
      book = WriteExcel.new(out)
      sheet = book.add_worksheet

      Mondrian::REST::Formatters
        .tidy(result,
              add_parents: add_parents,
              debug: debug,
              properties: properties)
        .each_with_index do |row, i|
          row.each_with_index { |cell, j|
            sheet.write(i, j, cell)
          }
      end

      book.close
      out.string
    end
  end

  module CSV
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'
      properties = env['rack.request.query_hash']['properties'] || []

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties)

      ::CSV.generate do |csv|
        rows.each { |row| csv << row }
      end
    end
  end

  module JSONRecords
    def self.call(result, env)
      add_parents = env['rack.request.query_hash']['parents'] == 'true'
      debug = env['rack.request.query_hash']['debug'] == 'true'
      properties = env['rack.request.query_hash']['properties'] || []

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug,
                                             properties: properties).lazy
      keys = rows.next

      {
        data: rows.with_index.with_object([]) { |(row, i), data|
          next if i == 0
          data << Hash[keys.zip(row)]
        }
      }.to_json

    end
  end

  ##
  # Generate 'tidy data' (http://vita.had.co.nz/papers/tidy-data.pdf)
  # from a result set.
  def self.tidy(result, options)
    cube = result.cube

    add_parents = options[:add_parents]
    properties = options[:properties]
    rs = result.to_h(add_parents, options[:debug])
    measures = rs[:axes].first[:members]
    dimensions = rs[:axis_dimensions][1..-1]
    columns = []
    slices = []
    level_has_all = []

    Enumerator.new do |y|
      dimensions.each do |dd|
        if add_parents
          hier = cube.dimension(dd[:name])
                   .hierarchies
                   .first # TODO: Support other hierarchies

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

      pnames = properties.map { |p|
        org.olap4j.mdx.IdentifierNode.parseIdentifier(p).getSegmentList.last.name
      }

      # append properties and measure columns and yield table header
      y.yield columns + pnames + pluck(measures, :name)

      prod = rs[:axes][1..-1].map { |e|
        e[:members].map.with_index { |e_, i| [e_,i] }
      }
      values = rs[:values]

      prod.shift.product(*prod).each do |cell|
        cidxs = cell.map { |c,i| i }.reverse

        cm = cell.map(&:first)

        msrs = measures.map.with_index { |m, mi|
          (cidxs + [mi]).reduce(values) { |_, idx| _[idx] }
        }

        if add_parents
          vdim = cm.each.with_index.reduce([]) { |cnames, (member, j)|
            member[:ancestors][0...slices[j] - (level_has_all[j] ? 1 : 0)].reverse.each { |ancestor|
              cnames += [ancestor[:key], ancestor[:caption]]
            }
            cnames += [member[:key], member[:caption]]
          }
          y.yield vdim + get_props(cm, pnames, true) + msrs
        else

          row = pluck(cm, :key)
                  .zip(pluck(cm, :caption))
                  .flatten

          y.yield row + get_props(cm, pnames) + msrs
        end
      end
    end
  end

  def self.get_props(cm, pnames, dbg=false)
    pvalues = pluck(cm, :properties).reduce({}) { |h, p|
      h.merge(p || {})
    }

    pnames.map { |pn| pvalues[pn] }
  end

  def self.pluck(a, m)
    a.map { |e| e[m] }
  end
end
