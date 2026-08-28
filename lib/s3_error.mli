(** Error type for {!S3_client}, extending {!Aws_error.t} the same way
    [kafka-eio-service]'s [Kafka_error.t] extends the raw librdkafka codes. *)

type t =
  | Aws of Aws_error.t
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
          could otherwise inject header lines. See
          {!S3_client.host_port_and_path}. *)

val of_response : status:int -> body:string -> t
(** Classify a non-2xx S3 response: 404 becomes [Not_found]; a body that
    parses as [<Error><Code>...</Code><Message>...</Message></Error>] becomes
    [Service_error]; anything else becomes [Unparseable_error_response]. *)

val to_string : t -> string
