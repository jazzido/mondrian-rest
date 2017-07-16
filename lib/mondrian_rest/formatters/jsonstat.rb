require 'java'

module Mondrian::REST::Formatters
  module JSONStat

    def self.call(result, env)

      mapper = Java::ComFasterxmlJacksonDatabind::ObjectMapper.new
      mapper.registerModule(Java::NoSsbJsonstat::JsonStatModule.new)
      mapper.registerModule(Java::ComFasterxmlJacksonDatatypeJdk8::Jdk8Module.new.configureAbsentsAsNulls(true))
      mapper.setSerializationInclusion(Java::ComFasterxmlJacksonAnnotation::JsonInclude::Include::NON_NULL)
      mapper.registerModule(Java::ComFasterxmlJacksonDatatypeGuava::GuavaModule.new.configureAbsentsAsNulls(false))

      rs = result.to_h
      nax = rs[:axis_dimensions].size

      builder = Java::NoSsbJsonstatV2::Dataset.create.withLabel('Aggregation')

      dimensions = rs[:axis_dimensions].reverse.map.with_index do |d, i|
        dim = Java::NoSsbJsonstatV2::Dimension
                .create(d[:name])

        if d[:type] == :measures
          dim = dim.withMetricRole
        elsif d[:type] == :time
          dim = dim.withTimeRole
        end

        dim.withLabel(d[:caption])
          .withIndexedLabels(
            Java::ComGoogleCommonCollect::ImmutableMap.copyOf(
              Hash[*(rs[:axes][-1 - i][:members].map { |m| [ m[:key].to_s, m[:caption] ] }.flatten)].to_java
            )
          )
      end

      dataset = builder
                  .withDimensions(dimensions)
                  .withValues(rs[:values].flatten)
                  .build

      mapper.writeValueAsString(dataset)

    end

  end
end
