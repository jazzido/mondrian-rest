require 'java'
require 'uri'

require_relative './api_helpers.rb'
require_relative './query_helper.rb'
require_relative './api_formatters.rb'

module Mondrian::REST

  class Api < Grape::API
    version '1', using: :header, vendor: 'mondrian_rest'
    default_format :json

    helpers Mondrian::REST::APIHelpers
    helpers Mondrian::REST::QueryHelper
    helpers do
      def logger
        Api.logger
      end
    end

    resource :mdx do
      content_type :xls, "application/vnd.ms-excel"
      formatter :xls, Mondrian::REST::Formatters::XLS

      content_type :csv, "text/csv"
      formatter :csv, Mondrian::REST::Formatters::CSV

      content_type :json, "application/json"
      formatter :json, Mondrian::REST::Formatters::AggregationJSON

      content_type :jsonrecords, "application/x-jsonrecords"
      formatter :jsonrecords, Mondrian::REST::Formatters::JSONRecords

      desc "Execute an MDX query against a cube"
      content_type :txt, "text/plain"

      params do
        optional :parents, type: Boolean, desc: "Include members' ancestors"
        optional :debug, type: Boolean, desc: "Include generated MDX", default: false
        optional :properties, type: Array, desc: "Include member properties"
        optional :caption, type: Array, desc: "Replace caption with property", default: []
      end

      post do
        status 200

        rbody = request.body.read.force_encoding('utf-8')
        mdx(rbody)
      end
    end

    resource :flush do
      params do
        requires :secret, type: String, desc: "Secret key"
      end
      content_type :json, "application/json"
      desc "Flush the schema cache"

      get do
        if ENV['MONDRIAN_REST_SECRET'].nil?
          error!("Please set MONDRIAN_REST_SECRET to use this endpoint", 403)
        end
        if params[:secret] != ENV['MONDRIAN_REST_SECRET']
          error!("Invalid secret key.", 403)
        end
        {
          'status' => olap_flush
        }
      end
    end

    resource :cubes do
      content_type :json, "application/json"
      default_format :json
      desc "Returns the cubes defined in this server's schema"
      get do
        {
          'cubes' => olap.cube_names.map { |cn| olap.cube(cn).to_h }
        }
      end

      route_param :cube_name do
        desc "Return a cube"
        params do
          requires :cube_name, type: String, desc: "Cube name"
        end

        get do
          cube = get_cube_or_404(params[:cube_name])
          cube.to_h
        end

        resource :members do
          desc "return a member by its full name"
          params do
            requires :full_name,
                     type: String,
                     regexp: /[a-z0-9\.,\-\s%\[\]\(\)]+/i
          end
          get do
            member_full_name = URI.decode(params[:full_name])

            m = get_member(get_cube_or_404(params[:cube_name]),
                           member_full_name)
            if m.nil?
              error!("Member `#{member_full_name}` not found in cube `#{params[:cube_name]}`", 404)
            end
            m.to_h.merge({
                           ancestors: m.ancestors.map(&:to_h),
                           dimension: m.dimension_info
                         })
          end
        end


        resource :aggregate do
          content_type :xls, "application/vnd.ms-excel"
          formatter :xls, Mondrian::REST::Formatters::XLS

          content_type :csv, "text/csv"
          formatter :csv, Mondrian::REST::Formatters::CSV

          content_type :json, "application/json"
          formatter :json, Mondrian::REST::Formatters::AggregationJSON

          content_type :jsonrecords, "application/x-jsonrecords"
          formatter :jsonrecords, Mondrian::REST::Formatters::JSONRecords

          content_type :jsonstat, "application/x-jsonstat"
          formatter :jsonstat, Mondrian::REST::Formatters::JSONStat

          rescue_from PropertyError do |e|
            error!({error: e}, 400)
          end

          desc "aggregate from query parameters"
          params do
            optional :measures, type: Array
            optional :cut, type: Array, desc: "Specification of slicer axis"
            optional :drilldown, type: Array, desc: "Dimension(s) to be drilled down"
            optional :nonempty, type: Boolean, desc: "Only return non empty cells"
            optional :sparse, type: Boolean, desc: "Skip rows where all measures are null (only applies to CSV, XLS and JSONRECORDS)", default: !java.lang.System.getProperty('mondrian-rest.sparseDefault').nil?
            optional :distinct, type: Boolean, desc: "Apply DISTINCT() to every axis"
            optional :parents, type: Boolean, desc: "Include members' ancestors"
            optional :debug, type: Boolean, desc: "Include generated MDX", default: false
            optional :properties, type: Array, desc: "Include member properties"
            optional :caption, type: Array, desc: "Replace caption with property", default: []
            optional :filter, type: Array, desc: "Filter by measure value. Accepts: #{Mondrian::REST::QueryHelper::VALID_FILTER_OPS.join(', ')}"
          end

          get do
            run_from_params(params)
          end

          post do
            run_from_params(params)
          end
        end

        resource :dimensions do
          route_param :dimension_name do
            desc "Return a dimension's members"
            params do
              requires :cube_name, type: String, desc: "Cube name"
              requires :dimension_name, type: String, desc: "Dimension name"
            end

            get do
              cube = get_cube_or_404(params[:cube_name])
              dimension = cube.dimension(params[:dimension_name])
              dimension.to_h(get_members: true)
            end

            resource :levels do
              route_param :level_name do
                resource :members do

                  params do
                    optional :member_properties, type: Array, default: []
                    optional :caption, type: String, desc: "Replace caption with property", default: nil
                    optional :children, type: Boolean, default: false
                  end

                  get do
                    cube = get_cube_or_404(params[:cube_name])

                    dimension = cube.dimension(params[:dimension_name])
                    if dimension.nil?
                      error!("dimension #{params[:dimension_name]} not found in cube #{params[:cube_name]}", 404)
                    end

                    level = dimension.hierarchies[0].level(params[:level_name])
                    if level.nil?
                      error!("level #{params[:level_name]} not found in dimension #{params[:dimension_name]}")
                    end

                    level.to_h(member_properties: params[:member_properties],
                               get_children: params[:children],
                               member_caption: params[:caption],
                               get_members: true)
                  end

                  route_param :member_key,
                              type: String,
                              requirements: { member_key: /[A-Za-z0-9\.\-\s%]+/i } do

                    params do
                      optional :caption, type: String, desc: "Replace caption with property", default: nil
                      optional :member_properties, type: Array, default: []
                      optional :children, type: Boolean, default: false
                    end

                    get do
                      cube = get_cube_or_404(params[:cube_name])
                      dimension = cube.dimension(params[:dimension_name])
                      level = dimension.hierarchies[0].level(params[:level_name])

                      member = level.members.detect { |m|
                        m.property_value('MEMBER_KEY').to_s == params[:member_key]
                      }
                      error!('member not found', 404) if member.nil?
                      member
                        .to_h(params[:member_properties], params[:caption], params[:children])
                        .merge({ancestors: member.ancestors.map(&:to_h)})
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
