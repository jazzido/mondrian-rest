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

      out = StringIO.new
      book = WriteExcel.new(out)
      sheet = book.add_worksheet

      Mondrian::REST::Formatters
        .tidy(result,
              add_parents: add_parents,
              debug: debug)
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

      rows = Mondrian::REST::Formatters.tidy(result,
                                             add_parents: add_parents,
                                             debug: debug)

      puts result.inspect

      ::CSV.generate do |csv|
        rows.each { |row| csv << row }
      end
    end
  end

  ##
  # Generate 'tidy data' (http://vita.had.co.nz/papers/tidy-data.pdf)
  # from a result set
  def self.tidy(result, options)
    rs = result.to_h(options[:add_parents], options[:debug])

    measures = rs[:axes].first[:members]
    dimensions = rs[:axis_dimensions][1..-1]

    Enumerator.new do |y|
      dc = pluck(dimensions, :caption)

      column_names(result, options[:add_parents])

      y.yield dc.map { |d| "ID " + d }.zip(dc).flatten + pluck(measures, :name)

      prod = rs[:axes][1..-1].map { |e|
        e[:members].map.with_index { |e_, i| [e_,i] }
      }
      values = rs[:values]

      prod.shift.product(*prod).each { |cell|
        cidxs = cell.map { |c,i| i }.reverse

        cm = cell.map(&:first)
        y.yield pluck(cm, :key)
                  .zip(pluck(cm, :caption))
                  .flatten \
                + measures.map.with_index { |m, mi|
          (cidxs + [mi]).reduce(values) { |_, idx| _[idx] }
        }
      }
    end
  end

  def self.pluck(a, m)
    a.map { |e| e[m] }
  end

  private

  def self.column_names(result, parents=false)
    rs = result.to_h(parents, false)
    cube = result.cube
    columns = []

    if parents
      slices = []
      axes = rs[:axis_dimensions][1..-1]
      axes.each do |dd|
        slices << dd[:level_depth]

        hier = cube.dimension(dd[:name])
          .hierarchies
          .first

        hier
          .levels[(hier.has_all? ? 1 : 0)...dd[:level_depth]]
          .each do |ancestor_level|

          columns += ["ID #{ancestor_level.caption}", ancestor_level.caption]
        end

        columns += ["ID #{dd[:level]}", dd[:level]]
      end
    else

    end
  end

end
