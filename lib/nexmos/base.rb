module Nexmos
  class Base
    def initialize(key = ::Nexmos.api_key, secret = ::Nexmos.api_secret)
      fail 'api_key should be set' unless key.present?
      fail 'api_secret should be set' unless secret.present?
      @default_params = {
        'api_key'    => key,
        'api_secret' => secret
      }
    end

    def faraday_options
      {
        url:     ::Nexmos.endpoint,
        headers: {
          accept:     'application/json',
          user_agent: ::Nexmos.user_agent
        }
      }
    end

    def connection
      @connection ||= ::Faraday::Connection.new(faraday_options) do |conn|
        conn.request :url_encoded
        conn.response :mashrashify
        conn.response :json, content_type: /\bjson$/
        conn.response :logger if ::Nexmos.debug
        conn.adapter ::Faraday.default_adapter
      end
    end

    def make_api_call(args, params = {})
      normalize_params(params)
      check_required_params(args, params)
      dasherize_params(params) if args[:dasherize]
      params.merge!(@default_params)
      get_response(args, params)
    end

    def get_response(args, params)
      method = args[:method]
      url    = args[:url]
      fail 'url or method params missing' if !method.present? || !url.present?
      res = connection.__send__(method, url, params)
      if res.success?
        data = if res.body.is_a?(::Hash)
                 res.body.merge(:success? => true)
               else
                 ::Hashie::Mash.new(:success? => true)
               end
        return data
      end
      failed_res = ::Hashie::Mash.new(:success? => false, :not_authorized? => false, :failed? => false)
      case res.status
      when 401
        failed_res.merge! :not_authorized? => true
      when 420
        failed_res.merge! :failed? => true
      end
      failed_res
    end

    def normalize_params(params)
      params.stringify_keys!
    end

    def dasherize_params(params)
      if params.respond_to?(:transform_keys!)
        params.transform_keys! { |key| key.dasherize }
      else
        params.keys.each do |key|
          params[key.dasherize] = params.delete(key)
        end
      end
    end

    def check_required_params(args, params)
      return unless args[:required]
      required = params.slice(*args[:required])
      return if required.keys.sort == args[:required].sort
      missed = (args[:required] - required.keys).join(',')
      fail ArgumentError, "#{missed} params required"
    end

    class << self
      def define_api_calls(key)
        ::Nexmos.apis[key].each do |k, v|
          define_method(k) do |*args|
            params = args[0] || {}
            make_api_call(v, params)
          end
        end
      end
    end # self
  end # Base
end # Nexmos
