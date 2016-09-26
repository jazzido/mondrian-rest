require 'net/http'
require 'uri'
require 'fileutils'

require 'rack/test'
require 'zip'

require_relative '../lib/mondrian_rest.rb'

require 'coveralls'
Coveralls.wear!

def _download(url)
  uri = URI.parse(url)
  Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
    resp = http.get(uri.path)
    file = Tempfile.new('foo')
    file.binmode
    file.write(resp.body)
    file.flush
    file
  end
end

def setup_webshop
  require 'jdbc/sqlite3'
  Jdbc::SQLite3.load_driver

  fixtures = File.join(File.dirname(__FILE__), 'fixtures')

  # download webshop (from cubes-examples) if needed
  p = File.join(fixtures, 'webshop.sqlite')
  unless File.exists?(p)
    webshop = _download('https://raw.githubusercontent.com/DataBrewery/cubes-examples/master/webshop/webshop.sqlite')
    FileUtils.cp(webshop.path, p)
  end

  {
    driver: 'jdbc',
    jdbc_driver: 'org.sqlite.JDBC',
    jdbc_url: "jdbc:sqlite:#{p}",
    catalog: File.join(fixtures, 'webshop.xml')
  }
end

def setup_foodmart
  require 'jdbc/derby'
  Jdbc::Derby.load_driver

  fixtures = File.join(File.dirname(__FILE__), 'fixtures')

  # download foodmart-derby if needed
  derby = 'https://raw.githubusercontent.com/pentaho/mondrian/0513fbe724619a7c669009b7539bf51d1faaa858/demo/derby/derby-foodmart.zip'

  dest_dir = File.join(fixtures, 'foodmart')

  unless File.directory?(dest_dir)
    # download
    zip = _download(derby)

    # unzip
    Zip::File.open(zip.path) do |zipfile|
      zipfile.each do |entry|
        unless File.exist?(File.join(fixtures, entry.name))
          FileUtils::mkdir_p(File.join(fixtures, File.dirname(entry.name)))
          zipfile.extract(entry,
                          File.join(fixtures, entry.name))
        end
      end
    end
  end

  {
    driver: 'jdbc',
    jdbc_driver: 'org.apache.derby.jdbc.EmbeddedDriver',
    jdbc_url: "jdbc:derby:#{File.join(fixtures, 'foodmart')}",
    username: 'sa',
    password: 'sa',
    catalog: File.join(fixtures, 'foodmart.xml')
  }
end
