# frozen_string_literal: true

require "net/http"
require "uri"

module IbanChecker
  # The HTTP seam.
  #
  # The client ships NetHttp, built entirely on the standard library, so the
  # gem has no runtime dependencies. Anything that responds to
  # #call(method, url, headers, body) and returns something with #status and
  # #body can be passed in instead. That is how the test suite runs without a
  # network, and how a host application can route calls through its own HTTP
  # stack.
  module Transport
    # What a transport returns.
    Response = Struct.new(:status, :body)

    # Default transport, built on net/http.
    class NetHttp
      METHODS = {
        "GET" => Net::HTTP::Get,
        "POST" => Net::HTTP::Post
      }.freeze

      def initialize(timeout: 10.0, max_redirects: 3)
        @timeout = timeout
        @max_redirects = max_redirects
      end

      def call(method, url, headers, body)
        request_class = METHODS.fetch(method) do
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        uri = URI.parse(url)
        redirects = 0

        loop do
          response = perform(request_class, uri, headers, body)
          location = response.is_a?(Net::HTTPRedirection) ? response["location"] : nil

          return Response.new(response.code.to_i, response.body.to_s) if location.nil? || redirects >= @max_redirects

          target = URI.join(uri.to_s, location)
          # Following a redirect to another host would send the Authorization
          # header there, which is how an API key leaks. An upgrade from http
          # to https on the same host is the case worth following.
          unless target.host == uri.host
            raise TransportError,
                  "Refusing to follow a redirect from #{uri.host} to #{target.host}: " \
                  "that would send the API key to another host"
          end

          uri = target
          redirects += 1
        end
      end

      private

      def perform(request_class, uri, headers, body)
        request = request_class.new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body if body

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http.write_timeout = @timeout if http.respond_to?(:write_timeout=)

        begin
          http.start { |connection| connection.request(request) }
        rescue StandardError => e
          raise TransportError, "Request to #{uri} failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
