require 'writeexcel'

module Mondrian::REST::Formatters
  module XLS
    def self.call(result, env)
      params = env['api.endpoint'].params
      add_parents = params['parents']
      debug = params['debug']
      sparse = params['sparse']
      properties = params['properties'] || []

      out = StringIO.new
      book = WriteExcel.new(out)
      sheet = book.add_worksheet

      Mondrian::REST::Formatters
        .tidy(result,
              add_parents: add_parents,
              debug: debug,
              sparse: sparse,
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
