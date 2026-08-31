(** Error type for {!S3_client}, extending [Aws.Error.t] the same way
    [kafka-eio-service]'s [Kafka_error.t] extends the raw librdkafka codes. *)

type t =
  | Aws of Aws.Error.t
      (** Transport, signature, or credential-resolution failure from
          [aws-eio] itself. *)
  | Not_found  (** 404 — [NoSuchKey]/[NoSuchBucket]. *)
  | Service_error of { code : string; message : string; status : int }
      (** Other non-2xx with a parseable [<Error><Code>/<Message>] body. *)
  | Unparseable_error_response of { status : int; body : string }
      (** Non-2xx whose body didn't parse as an S3 error document — includes
          every non-404 HEAD error, since HEAD responses never carry a body
          to parse. *)
  | Invalid_config of string
      (** [config.bucket]/[config.region]/[config.endpoint] failed a
          fail-closed CR/LF check before being used to build a request —
          these become an unencoded HTTP [Host] header, so untrusted input
          could otherwise inject header lines. *)
  | Malformed_response of { header : string; value : string }
      (** A 2xx response carried the named header but its value didn't parse
          in the shape S3 always sends — e.g. a non-numeric
          [Content-Length]. Distinct from the header being absent, which is
          not an error: absent fields decode to [None] in the operation's
          result record. *)

val of_response : status:int -> body:string -> t
(** Classify a non-2xx S3 response: 404 becomes [Not_found]; a body that
    parses as [<Error><Code>...</Code><Message>...</Message></Error>] becomes
    [Service_error]; anything else becomes [Unparseable_error_response]. *)

val to_string : t -> string
