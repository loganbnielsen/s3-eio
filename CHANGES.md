# Changes

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
- Public-API cleanup: internal helpers (`interpret_put`/`interpret_get`/
  `interpret_delete`/`interpret_head`, `reclassify_transport_result`,
  `host_and_path`, `validate_config`) moved into a `For_testing` submodule
  instead of sitting bare in the top-level signature, so the `.mli` itself
  states they aren't part of the stable contract. The repeated
  `int * (string * string) list * string` transport-response shape given a
  name: `For_testing.raw_response`.
