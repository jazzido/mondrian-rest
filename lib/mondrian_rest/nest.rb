# D3 nest operator
# from: https://gist.github.com/herrstucki/3974701
module Mondrian::REST
  class Nest
    def initialize
      @nest = {}
      @keys = []
      @sort_keys = []
    end

    def map(array)
      _map(array, 0)
    end

    def entries(array)
      _entries(_map(array, 0), 0)
    end

    def key(&f)
      @keys << f
      self
    end

    def sort_keys(&order)
      @sort_keys[@keys.size - 1] = order
      self
    end

    def sort_values(&order)
      @sort_values = order
      self
    end

    def rollup(&f)
      @rollup = f
      self
    end

    private

    def _map(array, depth)
      if depth >= @keys.size
        return @rollup.call(array) if @rollup
        return array.sort { |a, b| @sort_values.call(a, b) } if @sort_values
        return array
      end

      key = @keys[depth]
      depth += 1
      values_by_key = {}

      array.each_with_index do |object, i|
        key_value = key.call(object)
        values_by_key[key_value] ||= []
        values_by_key[key_value] << object
      end

      o = {}
      values_by_key.each do |key_value, values|
        o[key_value] = _map(values, depth)
      end
      o
    end

    def _entries(map, depth)
      return map if depth >= @keys.size

      a = []
      sort_key = @sort_keys[depth]
      depth += 1

      map.each do |key, values|
        a << {
          key: key,
          values: _entries(values, depth)
        }
      end

      if sort_key
        a.sort { |a, b| sort_key.call(a[:key], b[:key]) }
      else
        a
      end
    end
  end

end


# TEST

# require 'pp'

# data = [
#   {year: "2013", category: "Cars", value: 1000},
#   {year: "2011", category: "Cars", value: 1200},
#   {year: "2012", category: "Cars", value: 1300},
#   {year: "2011", category: "Planes", value: 1000},
#   {year: "2011", category: "Planes", value: 1100},
#   {year: "2012", category: "Planes", value: 1200},
#   {year: "2011", category: "Planes", value: 1300},
#   {year: "2012", category: "Bikes", value: 1000},
#   {year: "2011", category: "Bikes", value: 1100},
#   {year: "2011", category: "Bikes", value: 1200},
# ]

# nest = Nest.new
# nest.key { |d| d[:year] }
# nest.sort_keys { |a,b| a <=> b }
# nest.key { |d| d[:category] }
# # nest.sort_values { |a,b| b[:value] <=> a[:value] }
# nest.rollup do |values|
#   {
#     count: values.size,
#     total_value: values.map { |d| d[:value] }.reduce(:+),
#     raw: values
#   }
# end

# # pp nest.entries(data)
# pp nest.map(data)
