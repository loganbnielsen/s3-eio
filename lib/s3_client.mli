(** S3 client on top of [aws-eio]. See [s3-eio.md] for scope, host-addressing
    rules, and what v1 deliberately leaves out (streaming, list/multipart,
    credential caching). *)

type config = {
  bucket : string;
  region : string;
  credentials : Aws_credentials.t;
  endpoint : endpoint option;
      (** [None]: real AWS over HTTPS, virtual-hosted-style addressing
          ([bucket.s3.region.amazonaws.com]). [Some endpoint]: path-style
          against a custom S3-compatible endpoint. *)
}

and endpoint = {
  scheme : [ `Http | `Https ];
  host : string;
  port : int option;
}
(** Custom path-style S3-compatible endpoint. Use [`Http] only for local
    test servers such as MinIO/Localstack. [host] is a DNS name, IPv4
    literal, or IPv6 literal without brackets; malformed values return
    [Error (Invalid_config _)] from operations. *)

type head_info = {
  content_length : int option;
  etag : string option;
  last_modified : string option;
  content_type : string option;
}

type t

val create : net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> fs:Eio.Fs.dir_ty Eio.Path.t -> config -> t
(** [fs] is used only when [config.credentials] resolves via [Web_identity]
    (a Kubernetes-projected service-account token file) — pass
    [Eio.Stdenv.fs env]. *)

val put_object : t -> key:string -> body:string -> (unit, S3_error.t) result

val get_object : t -> key:string -> (string, S3_error.t) result

val delete_object : t -> key:string -> (unit, S3_error.t) result

val head_object : t -> key:string -> (head_info, S3_error.t) result
