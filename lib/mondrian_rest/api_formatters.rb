require 'csv'
require 'writeexcel'

module Mondrian::REST::Formatters

  module XLS
    def self.call(obj, env)
      out = StringIO.new
      book = WriteExcel.new(out)
      sheet = book.add_worksheet

      Mondrian::REST::Formatters.tidy(obj).each_with_index { |row, i|
        row.each_with_index { |cell, j|
          puts "(#{i},#{j}) #{cell}"
          sheet.write(i, j, cell)
        }
      }
      book.close
      out.string
    end
  end

  module CSV
    def self.call(obj, env)
      rows = Mondrian::REST::Formatters.tidy(obj)
      ::CSV.generate do |csv|
        # header
        rows.each { |row| csv << row }
      end
    end
  end

  ##
  # Generate 'tidy data' (http://vita.had.co.nz/papers/tidy-data.pdf)
  # from a result set
  def self.tidy(obj)
    rs = obj.to_h
    measures = rs[:axes].first[:members]
    dimensions = rs[:axis_dimensions][1..-1]
    Enumerator.new do |y|
      y.yield pluck(dimensions, :name) + pluck(measures, :name)

      prod = rs[:axes][1..-1].map { |e|
        e[:members].map.with_index { |e_, i| [e_,i] }
      }
      values = rs[:values]
      prod.shift.product(*prod).each { |cell|
        cidxs = cell.map { |c,i| i }.reverse
        y.yield pluck(cell.map(&:first), :caption) \
                + measures.map.with_index { |m, mi|
          (cidxs + [mi]).reduce(values) { |_, idx| _[idx] }
        }
      }
    end
  end

  def self.pluck(a, m)
    a.map { |e| e[m] }
  end
end
