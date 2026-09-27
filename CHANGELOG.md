# Changelog

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
