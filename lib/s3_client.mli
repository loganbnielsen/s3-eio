(** S3 client on top of [aws-eio]. See [s3-eio.md] for scope, host-addressing
    rules, and what v1 deliberately leaves out (streaming, list/multipart,
    credential caching). *)

type config = {
  bucket : string;
  region : string;
  credentials : Aws_credentials.t;
  endpoint : string option;
      (** [None]: real AWS, virtual-hosted-style addressing
          ([bucket.s3.region.amazonaws.com]). [Some host_port]: path-style
          against that host ([host_port/bucket/key]) — for a local
          S3-compatible test server, which can't provide a real
          [bucket.<host>] subdomain to resolve. *)
}

type head_info = {
  content_length : int option;
  etag : string option;
  last_modified : string option;
  content_type : string option;
}

val put_object :
  net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> config -> key:string -> body:string -> (unit, S3_error.t) result

val get_object :
  net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> config -> key:string -> (string, S3_error.t) result

val delete_object :
  net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> config -> key:string -> (unit, S3_error.t) result

val head_object :
  net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> config -> key:string -> (head_info, S3_error.t) result

(** {2 Exposed for testing} *)

val host_and_path : config -> key:string -> string * string
(** The [(host, path)] pair every operation signs and sends, port stripped
    off ([signed_request] takes host and port as separate arguments). See
    the host-addressing rules in [s3-eio.md]. *)

(** Pure (status, headers, body) -> result mappers, unit-testable without a
    network call — see [s3_client.ml]'s top comment on why these are tested
    directly instead of via a mock server. *)

val validate_config : config -> (unit, S3_error.t) result
(** The CR/LF fail-closed check every operation runs before building a
    request — see the [Invalid_config] doc above. *)

val reclassify_transport_result :
  (int * (string * string) list * string, Aws_error.t) result -> (int * (string * string) list * string, S3_error.t) result
(** Re-threads [signed_request]'s [Error (Http_error (status, body))] back
    into the [Ok] shape [interpret_*] expects, so their non-2xx branches are
    reachable. *)

val interpret_put : int * (string * string) list * string -> (unit, S3_error.t) result
val interpret_get : int * (string * string) list * string -> (string, S3_error.t) result
val interpret_delete : int * (string * string) list * string -> (unit, S3_error.t) result
val interpret_head : int * (string * string) list * string -> (head_info, S3_error.t) result
