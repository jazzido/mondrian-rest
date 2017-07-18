require "rspec/core/rake_task"
require 'jars/installer'


desc "Run specs"
RSpec::Core::RakeTask.new(:spec)
RSpec::Core::RakeTask.new(:rcov) do |t|
  t.rcov = true
  t.rcov_opts =  ['--exclude', '/Library,spec/']
end

desc "API Routes"
task :routes do
  require_relative './lib/mondrian_rest.rb'
  Mondrian::REST::Api.routes.each do |api|
    method = api.route_method.ljust(10)
    path = api.route_path
    puts "     #{method} #{path}"
  end
end

task :install_jars do
  Jars::Installer.vendor_jars!("lib/jars")
end

task :default => [:spec]
