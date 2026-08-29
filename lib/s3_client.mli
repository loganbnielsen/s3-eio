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

type t

val create : net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> config -> t

val put_object : t -> key:string -> body:string -> (unit, S3_error.t) result

val get_object : t -> key:string -> (string, S3_error.t) result

val delete_object : t -> key:string -> (unit, S3_error.t) result

val head_object : t -> key:string -> (head_info, S3_error.t) result
