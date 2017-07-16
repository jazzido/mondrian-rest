require 'writeexcel'

module Mondrian::REST::Formatters
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
end
