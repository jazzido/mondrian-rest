require 'net/http'
require 'uri'

require 'rack/test'
require 'zip'

require 'jdbc/derby'
Jdbc::Derby.load_driver

require_relative '../lib/mondrian_rest.rb'

FIXTURES = File.join(File.dirname(__FILE__), 'fixtures')

# download foodmart-derby if needed
DERBY = 'https://raw.githubusercontent.com/pentaho/mondrian/0513fbe724619a7c669009b7539bf51d1faaa858/demo/derby/derby-foodmart.zip'

dest_dir = File.join(FIXTURES, 'foodmart')

unless File.directory?(dest_dir)
  # download
  uri = URI.parse(DERBY)
  zip = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
    resp = http.get(uri.path)
    file = Tempfile.new('foo', Dir.tmpdir, 'wb+')
    file.binmode
    file.write(resp.body)
    file.flush
    file
  end

  # unzip
  Zip::File.open(zip.path) do |zipfile|
    zipfile.each do |entry|
      unless File.exist?(File.join(FIXTURES, entry.name))
        FileUtils::mkdir_p(File.join(FIXTURES, File.dirname(entry.name)))
        zipfile.extract(entry,
                        File.join(FIXTURES, entry.name))
      end
    end
  end
end

PARAMS = {
  driver: 'jdbc',
  jdbc_driver: 'org.apache.derby.jdbc.EmbeddedDriver',
  jdbc_url: "jdbc:derby:#{File.join(FIXTURES, 'derby-foodmart')}",
  username: 'sa',
  password: 'sa',
  catalog: File.join(FIXTURES, 'foodmart.xml')
}
