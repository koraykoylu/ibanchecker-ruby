# Changelog

## 0.1.2

Documentation only.

- The API now requires a key for every call except `country_format`:
  `lookup_bic` without one gets a 401 and the client raises
  `AuthenticationError`. The hourly limit for requests without a key (100 an
  hour per IP) now covers `country_format` only
- What a key can call follows its plan. The free key covers `validate`, 100
  requests a month; `validate_bulk` and `lookup_bic` need Basic or above;
  `extract` needs Growth or above. A key with a verified account can try the
  calls its plan lacks, with up to 10 IBANs per bulk call and 5,000
  characters per extraction; a trial call over that size gets a 400
  (`TOO_MANY_IBANS` or `TEXT_TOO_LONG`)
- A call outside the key's plan gets a 403 with `error_code`
  `PLAN_REQUIRED`, which the client raises as `APIError`; `#response` carries
  `required_plan` and `upgrade_url`
- `validate_bulk` counts one request per IBAN and `extract` one per IBAN
  found, at least one per call. A call that costs more than the requests left
  this month gets a 429 `QUOTA_EXCEEDED`, raised as `RateLimitError`
- README and doc comments say which plan each call needs

The client's behaviour does not change.

## 0.1.1

Documentation only; the client's behaviour is unchanged.

- The API now requires a key for `validate`, `validate_bulk` and `extract`:
  without one it answers 401 and the client raises `AuthenticationError`. The
  free key covers 100 requests a month
- `country_format` and `lookup_bic` still work without a key, limited to 100
  requests an hour per IP
- README, examples and doc comments construct the client with a key and say
  which calls need it

## 0.1.0

First release.

- `validate`, `validate_bulk`, `extract`, `country_format` and `lookup_bic`
- Typed models for every response, with the raw body kept on `#raw`
- Typed errors for 400, 401, 404, 429, other statuses and transport failures;
  a malformed IBAN is a result with `valid?` false, never an error
- No runtime dependencies; ships a `net/http` transport and accepts anything
  responding to `call(method, url, headers, body)` instead
