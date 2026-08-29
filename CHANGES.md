# Changes

## Unreleased

- `S3_client` now captures Eio capabilities in a client handle:
  `create ~net ~clock config`, then `put_object`/`get_object`/`delete_object`/
  `head_object` take that handle instead of repeating `~net ~clock config`.
- Hid internal request/interpreter helpers from the installed interface; the
  public API is the client handle plus object operations.
- Custom endpoints now validate host/port syntax and return
  `Invalid_config` for malformed values before credential resolution or
  network I/O.

## 0.1.0

- Initial standalone OPAM package, extracted from Sun: `S3_client`
  (`put_object`/`get_object`/`delete_object`/`head_object`, the four
  REST-with-headers S3 operations that need no XML), built on `aws-eio`'s
  credentials and SigV4/HTTP transport. Every public operation returns
  `(_, S3_error.t) result`; nothing raises.
- Live-tested against a real bucket: put/head/get/delete round trip + the
  404 path (`S3_EIO_LIVE=1`). Required a fix in `aws-eio` itself
  (`x-amz-content-sha256` was folded into the SigV4 signature but never
  actually sent as a header, which S3 rejects outright).
- Rename pass (internal only, no public-API change): `call`→`send_request`,
  `header_ci`→`find_header_case_insensitive`, `resp_body`→`body`.
