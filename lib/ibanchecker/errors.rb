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

  # The request was malformed, or a trial call was over the trial size
  # ("TOO_MANY_IBANS" for bulk, "TEXT_TOO_LONG" for extraction) (HTTP 400).
  class BadRequestError < Error; end

  # The API key is missing, invalid or inactive (HTTP 401).
  #
  # Every call except Client#country_format needs a key, so a call without
  # one, a Client#lookup_bic included, gets this from the API's 401.
  class AuthenticationError < Error; end

  # The requested country code or BIC was not found (HTTP 404).
  class NotFoundError < Error; end

  # The key's monthly quota was exceeded, or the call costs more than the
  # requests left this month ("QUOTA_EXCEEDED"), or Client#country_format
  # without a key went over 100 requests an hour ("RATE_LIMIT_EXCEEDED")
  # (HTTP 429). Bulk validation counts one request per IBAN and extraction one
  # per IBAN found.
  class RateLimitError < Error; end

  # Any error status without a class of its own, or a body that could not be
  # read.
  #
  # This includes HTTP 403 for a call outside the key's plan: error_code is
  # "PLAN_REQUIRED" and #response carries "required_plan" ("basic" or
  # "growth") and "upgrade_url".
  class APIError < Error; end

  # The request never reached the API: DNS, TLS, connection or timeout.
  class TransportError < Error; end
end
