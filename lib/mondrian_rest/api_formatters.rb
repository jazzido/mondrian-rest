require 'csv'
require 'ruby-debug'
require 'pry'

module Mondrian::REST

  module XLSFormatter
    def self.call(object, env)
      # XXX TODO implement
      raise "NotImplemented"
    end
  end

  module CSVFormatter

    def self.call(obj, env)
      rs = obj.to_h
      measures = rs[:axes].first[:members]
      dimensions = rs[:axis_dimensions][1..-1]
      CSV.generate do |csv|
        # header
        csv << pluck(dimensions, :name) + pluck(measures, :name)
        # unnest values
        prod = rs[:axes][1..-1].map { |e|
          e[:members].map.with_index { |e_, i| [e_,i] }
        }
        values = rs[:values]
        prod.shift.product(*prod).each { |cell|
          cidxs = cell.map { |c,i| i }.reverse
          csv << pluck(cell.map(&:first), :caption) \
          + measures.map.with_index { |m, mi|
            (cidxs + [mi]).reduce(values) { |_, idx| _[idx] }
          }
        }
      end
    end

    private

    def self.pluck(a, m)
      a.map { |e| e[m] }
    end
  end
end
