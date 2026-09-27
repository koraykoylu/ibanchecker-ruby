# ibanchecker

Official Ruby client for the [ibanchecker.cash](https://ibanchecker.cash) IBAN validation API.

Validate IBANs across 92 countries, validate up to 100 IBANs per request, extract IBANs from free text, look up country format specifications, and resolve SWIFT/BIC codes. No IBAN data is stored or logged; all validation runs in memory at the edge.

## Install

```bash
gem install ibanchecker
```

Or in a Gemfile:

```ruby
gem "ibanchecker"
```

Requires Ruby 2.7 or newer. There are no runtime dependencies: the client is built on `net/http` and `json` from the standard library.

## Quick start

Every call except `country_format` needs an API key. A free key covers single IBAN validation, 100 requests a month, and arrives by email in seconds from [ibanchecker.cash/api-docs](https://ibanchecker.cash/api-docs).

```ruby
require "ibanchecker"

client = IbanChecker::Client.new(ENV["IBANCHECKER_API_KEY"])   # or .new("iban_your_api_key")

result = client.validate("DE89 3704 0044 0532 0130 00")

if result.valid?
  result.country_name   # => "Germany"
  result.bank_name      # => "Commerzbank AG Cologne"
  result.bic            # => "COBADEFFXXX"
else
  result.error          # human-readable reason
  result.error_code     # e.g. "INVALID_COUNTRY"
end
```

## Authentication

`validate`, `validate_bulk`, `extract` and `lookup_bic` need an API key. Without one the API answers HTTP 401 and the client raises `IbanChecker::AuthenticationError`. `lookup_bic` used to work without a key; it no longer does. The free key from [ibanchecker.cash/api-docs](https://ibanchecker.cash/api-docs) covers `validate` only, 100 requests a month; paid plans are at [ibanchecker.cash/pricing](https://ibanchecker.cash/pricing).

`country_format` is the only call that works without a key, limited to 100 requests an hour per IP. Beyond that the API answers HTTP 429 with `error_code` `"RATE_LIMIT_EXCEEDED"`. This hourly limit applies to `country_format` only.

```ruby
client = IbanChecker::Client.new("iban_your_api_key")
client = IbanChecker::Client.new(ENV["IBANCHECKER_API_KEY"])

formats = IbanChecker::Client.new   # country_format only
```

### What each plan can call

| Method | Plan | Largest call |
| --- | --- | --- |
| `validate` | any key, including the free key | one IBAN |
| `validate_bulk` | Basic or above (Basic, Starter, Growth, Enterprise) | 100 IBANs |
| `lookup_bic` | Basic or above (Basic, Starter, Growth, Enterprise) | one BIC |
| `extract` | Growth or above (Growth, Enterprise) | 50,000 characters |
| `country_format` | no key needed | one country |

A key whose email address has a verified account at [ibanchecker.cash/dashboard](https://ibanchecker.cash/dashboard) can try the calls its plan lacks: `validate_bulk` with up to 10 IBANs per call, `lookup_bic`, and `extract` with up to 5,000 characters per call. This applies to any plan that lacks the call, so a Basic key with a verified account can try `extract` as well. A trial call over that size gets HTTP 400 with `error_code` `"TOO_MANY_IBANS"` (bulk) or `"TEXT_TOO_LONG"` (extraction), which the client raises as `IbanChecker::BadRequestError`.

A call outside the key's plan gets HTTP 403 with `error_code` `"PLAN_REQUIRED"`. The client has no class of its own for 403, so it raises `IbanChecker::APIError`; the decoded body on `#response` also carries `required_plan` (`"basic"` or `"growth"`) and `upgrade_url`. See [Error handling](#error-handling).

### How requests are counted

`validate` and `lookup_bic` count one request each. `validate_bulk` counts one request per IBAN in the call, and `extract` counts one per IBAN found, with at least one per call. A call that costs more than the requests left this month gets HTTP 429 with `error_code` `"QUOTA_EXCEEDED"`, raised as `IbanChecker::RateLimitError`.

## Methods

| Method | API key | Description |
| --- | --- | --- |
| `validate(iban)` | required, any plan | Validate a single IBAN. Returns a `ValidationResult`. |
| `validate_bulk(ibans)` | required, Basic or above | Validate up to 100 IBANs (10 on a trial). Returns a `BatchResult`. |
| `extract(text)` | required, Growth or above | Find and validate IBANs in free text (up to 50,000 chars, 5,000 on a trial). Returns a `BatchResult`. |
| `country_format(country)` | optional | IBAN format spec for an ISO country code. Returns a `FormatSpec`. |
| `lookup_bic(bic)` | required, Basic or above | Resolve an 8 or 11 character BIC. Returns a `BankRecord`. |

`country_format` is the one name that differs from the other ibanchecker clients, where it is `getFormat`. `format` is `Kernel#format`, Ruby's `sprintf`, so a method by that name on this class would shadow it for every line inside the class.

### Bulk validation

Needs a key on the Basic plan or above, or a trial (see [What each plan can call](#what-each-plan-can-call)). Each IBAN in the call counts as one request.

```ruby
batch = client.validate_bulk([
  "DE89370400440532013000",
  "GB29NWBK60161331926819",
  "XX00"
])

batch.count         # => 3
batch.valid_count   # => 2
batch.invalid_count # => 1

batch.each do |result|             # results come back in input order
  puts "#{result.iban} #{result.valid? ? 'ok' : result.error_code}"
end
```

`BatchResult` is `Enumerable`, so `map`, `select` and `find` work on it directly. `count` is the API's own count rather than `Enumerable#count`, so reach for `batch.results.count { |r| ... }` when you want the block form.

### Extract from text

Needs a key on the Growth plan or above, or a trial. Each IBAN found counts as one request, with at least one per call.

```ruby
batch = client.extract("Please wire to DE89 3704 0044 0532 0130 00 by Friday.")

batch.map { |r| [r.iban, r.bank_name] }
# => [["DE89370400440532013000", "Commerzbank AG Cologne"]]
```

### Country format and BIC lookup

`country_format` works without a key. `lookup_bic` needs a key on the Basic plan or above, or a trial.

```ruby
format = client.country_format("DE")
format.length    # => 22
format.example   # => "DE89370400440532013000"

format.bban_fields.map { |f| "#{f.label} (#{f.length})" }
# => ["BLZ (8)", "Account No. (10)"]

bank = client.lookup_bic("DEUTDEFF")
bank.bank_name   # => "Deutsche Bank AG Frankfurt"
bank.city        # => "FRANKFURT AM MAIN"
bank.sepa        # => true
```

### The national check digit

For a number of countries the API also runs the national account check digit on top of the ISO 13616 check, and reports it on `national_check_valid`. It is advisory: an IBAN with `valid?` true is a valid IBAN whatever this says. A `false` usually means a transcription error in the account number. It is `nil` where the country has no such scheme.

```ruby
result = client.validate("DE84100100100532013000")

if result.valid? && result.national_check_valid == false
  puts "Valid IBAN, but the account number looks mistyped."
end
```

`valid?` is the only predicate method on the models, because it is the only field that is always a boolean. `national_check_valid` and `sepa` can each be `nil`, and `nil` there means "not known for this IBAN" rather than "no", so they are plain readers and you compare them explicitly.

## Error handling

A malformed IBAN is **not** an error: `validate` returns a `ValidationResult` with `valid?` false. Errors are raised only for transport, authentication, quota and server-side problems.

```ruby
begin
  bank = client.lookup_bic("ZZZZZZZZ")
rescue IbanChecker::NotFoundError
  puts "No bank for that BIC"
rescue IbanChecker::RateLimitError => e
  puts "Slow down: #{e.message}"
rescue IbanChecker::AuthenticationError
  puts "Check your API key"
rescue IbanChecker::APIError => e
  raise unless e.error_code == "PLAN_REQUIRED"

  puts "Needs the #{e.response["required_plan"]} plan: #{e.response["upgrade_url"]}"
end
```

| Class | Raised when |
| --- | --- |
| `IbanChecker::BadRequestError` | HTTP 400, the request was malformed, or a trial call was over the trial size (`error_code` `"TOO_MANY_IBANS"` or `"TEXT_TOO_LONG"`) |
| `IbanChecker::AuthenticationError` | HTTP 401, the API key is missing, invalid or inactive; every call except `country_format` gets this without a key |
| `IbanChecker::NotFoundError` | HTTP 404, no such country code or BIC |
| `IbanChecker::RateLimitError` | HTTP 429, the key's monthly quota was exceeded or the call costs more than the requests left (`error_code` `"QUOTA_EXCEEDED"`), or `country_format` without a key went over 100 requests an hour (`"RATE_LIMIT_EXCEEDED"`) |
| `IbanChecker::APIError` | any other error status, including HTTP 403 for a call outside the key's plan (`error_code` `"PLAN_REQUIRED"`), or a body that could not be read |
| `IbanChecker::TransportError` | the request never reached the API: DNS, TLS, connection, timeout |

All of them inherit from `IbanChecker::Error`, so one `rescue IbanChecker::Error` catches everything this gem raises. Each carries `#status`, `#error_code` and `#response`.

## Timeouts

```ruby
client = IbanChecker::Client.new(ENV["IBANCHECKER_API_KEY"], timeout: 3.0)   # seconds, applied to connect and read
```

## Using your own HTTP stack

The client ships a `net/http` transport and needs nothing installed. If your application already has an HTTP layer, pass anything that responds to `call(method, url, headers, body)` and returns an object with `#status` and `#body`. This is also how the test suite runs without a network.

```ruby
class MyTransport
  def call(method, url, headers, body)
    # ... your HTTP stack here
    IbanChecker::Transport::Response.new(status, response_body)
  end
end

client = IbanChecker::Client.new("iban_your_api_key", transport: MyTransport.new)
```

The bundled transport follows a redirect only when it stays on the same host, so an `http` base URL upgrading to `https` works, and a redirect elsewhere raises `TransportError` instead of forwarding your API key to another host.

## Raw responses

Every model keeps the untouched response body on `#raw`, so a field added to the API later is reachable without waiting for a client release.

```ruby
result = client.validate("DE89370400440532013000")
result.raw["transfer_type"]   # => "SEPA+SWIFT"
```

## Tests

```bash
bundle install
bundle exec rake test
```

## Links

- Website: https://ibanchecker.cash
- API documentation: https://ibanchecker.cash/api-docs
- OpenAPI spec: https://ibanchecker.cash/openapi.json
- Free online tools: https://ibanchecker.cash/tools

Clients for other languages: [Python](https://pypi.org/project/ibanchecker/), [PHP](https://packagist.org/packages/ibanchecker/client), [JavaScript](https://www.npmjs.com/package/@ibanchecker/client), and an [MCP server](https://www.npmjs.com/package/@ibanchecker/mcp).

## License

MIT
