# this is a generated file, to avoid over-writing it just delete this comment
begin
  require 'jar_dependencies'
rescue LoadError
  require 'com/fasterxml/jackson/datatype/jackson-datatype-jdk8/2.8.5/jackson-datatype-jdk8-2.8.5.jar'
  require 'com/fasterxml/jackson/core/jackson-annotations/2.8.0/jackson-annotations-2.8.0.jar'
  require 'me/yanaga/guava-stream/1.0/guava-stream-1.0.jar'
  require 'com/fasterxml/jackson/core/jackson-databind/2.8.5/jackson-databind-2.8.5.jar'
  require 'no/ssb/jsonstat/json-stat-java/0.2.2/json-stat-java-0.2.2.jar'
  require 'com/fasterxml/jackson/core/jackson-core/2.8.5/jackson-core-2.8.5.jar'
  require 'com/fasterxml/jackson/datatype/jackson-datatype-guava/2.8.5/jackson-datatype-guava-2.8.5.jar'
  require 'com/google/guava/guava/19.0/guava-19.0.jar'
  require 'com/fasterxml/jackson/datatype/jackson-datatype-jsr310/2.8.5/jackson-datatype-jsr310-2.8.5.jar'
  require 'com/codepoetics/protonpack/1.9/protonpack-1.9.jar'
end

if defined? Jars
  require_jar( 'com.fasterxml.jackson.datatype', 'jackson-datatype-jdk8', '2.8.5' )
  require_jar( 'com.fasterxml.jackson.core', 'jackson-annotations', '2.8.0' )
  require_jar( 'me.yanaga', 'guava-stream', '1.0' )
  require_jar( 'com.fasterxml.jackson.core', 'jackson-databind', '2.8.5' )
  require_jar( 'no.ssb.jsonstat', 'json-stat-java', '0.2.2' )
  require_jar( 'com.fasterxml.jackson.core', 'jackson-core', '2.8.5' )
  require_jar( 'com.fasterxml.jackson.datatype', 'jackson-datatype-guava', '2.8.5' )
  require_jar( 'com.google.guava', 'guava', '19.0' )
  require_jar( 'com.fasterxml.jackson.datatype', 'jackson-datatype-jsr310', '2.8.5' )
  require_jar( 'com.codepoetics', 'protonpack', '1.9' )
end
