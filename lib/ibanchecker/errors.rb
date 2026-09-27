# frozen_string_literal: true

module IbanChecker
  # Base class for every error this client raises.
  #
  # A malformed IBAN is not an error: Client#validate returns a
  # ValidationResult with +valid?+ false. These are raised for transport,
  # authentication, quota and server-side problems only.
  class Error < StandardError
    # HTTP status that produced this error, when there was one.
    attr_reader :status

    # Machine-readable code from the API body, for example "BIC_NOT_FOUND".
    attr_reader :error_code

    # The decoded response body, when the API sent one.
    attr_reader :response

    def initialize(message, status: nil, error_code: nil, response: nil)
      super(message)
      @status = status
      @error_code = error_code
      @response = response
    end
  end

  # The request was malformed (HTTP 400).
  class BadRequestError < Error; end

  # The API key is missing, invalid or inactive (HTTP 401).
  class AuthenticationError < Error; end

  # The requested country code or BIC was not found (HTTP 404).
  class NotFoundError < Error; end

  # The key's monthly quota ("QUOTA_EXCEEDED") or the hourly limit for requests
  # without a key ("RATE_LIMIT_EXCEEDED") was exceeded (HTTP 429).
  class RateLimitError < Error; end

  # An unexpected server-side error, or a body that could not be read.
  class APIError < Error; end

  # The request never reached the API: DNS, TLS, connection or timeout.
  class TransportError < Error; end
end
