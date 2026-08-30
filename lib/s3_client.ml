type config = {
  bucket : string;
  region : string;
  credentials : Aws_credentials.t;
  endpoint : endpoint option;
}

and endpoint = {
  scheme : [ `Http | `Https ];
  host : string;
  port : int option;
}

type head_info = {
  content_length : int option;
  etag : string option;
  last_modified : string option;
  content_type : string option;
}

type t = {
  net : [`Generic] Eio.Net.ty Eio.Std.r;
  clock : float Eio.Time.clock_ty Eio.Std.r;
  fs : Eio.Fs.dir_ty Eio.Path.t;
  config : config;
}

let create ~net ~clock ~fs config =
  { net = (net :> [`Generic] Eio.Net.ty Eio.Std.r);
    clock = (clock :> float Eio.Time.clock_ty Eio.Std.r);
    fs;
    config;
  }

let valid_endpoint_host_char = function
  | '\000' .. ' ' | '\127' | '/' | '?' | '#' | '[' | ']' -> false
  | _ -> true

let validate_endpoint endpoint =
  if endpoint.host = "" then Error (S3_error.Invalid_config "endpoint host is empty")
  else if not (String.for_all valid_endpoint_host_char endpoint.host) then
    Error (S3_error.Invalid_config ("endpoint has an invalid host: " ^ endpoint.host))
  else
    match endpoint.port with
    | Some port when port <= 0 || port > 65535 ->
      Error (S3_error.Invalid_config ("endpoint has an invalid port: " ^ string_of_int port))
    | _ -> Ok ()

let has_crlf s = String.exists (fun c -> c = '\r' || c = '\n') s

(* config.bucket/region become an unencoded Host header, unlike key (which
   is percent-encoded) — reject CRLF to block header injection from
   less-trusted input. *)
let validate_config config =
  if has_crlf config.bucket then Error (S3_error.Invalid_config "bucket contains a CR or LF character")
  else if has_crlf config.region then Error (S3_error.Invalid_config "region contains a CR or LF character")
  else
    match config.endpoint with
    | Some endpoint when has_crlf endpoint.host -> Error (S3_error.Invalid_config "endpoint host contains a CR or LF character")
    | Some endpoint -> validate_endpoint endpoint
    | None ->
      (* Virtual-hosted-style addressing puts bucket.s3.<region>.amazonaws.com
         under AWS's *.s3.<region>.amazonaws.com wildcard certificate, which
         (per RFC 6125) only covers one label — a dotted bucket name produces
         a hostname the cert doesn't match, and TLS verification fails deep
         inside aws-eio/https-eio with an opaque Network_error instead of
         this actionable, config-shaped one. Path-style (endpoint <> None)
         doesn't hit this, so only reject it here. *)
      if String.contains config.bucket '.' then
        Error (S3_error.Invalid_config
          "bucket name contains '.', which breaks TLS certificate validation under \
           virtual-hosted-style addressing (endpoint = None); pass ~endpoint for path-style \
           addressing instead")
      else Ok ()

let host_port_and_path config ~key =
  match config.endpoint with
  | None -> Ok (`Https, Printf.sprintf "%s.s3.%s.amazonaws.com" config.bucket config.region, None, "/" ^ key)
  | Some endpoint -> Ok (endpoint.scheme, endpoint.host, endpoint.port, "/" ^ config.bucket ^ "/" ^ key)

let ( let* ) = Result.bind

let resolve_credentials ~net ~clock ~fs config =
  match Aws_credentials.resolve ~net ~clock ~fs config.credentials with
  | Error e -> Error (S3_error.Aws e)
  | Ok creds -> Ok creds

(* Credentials are resolved fresh on every call, not cached — an extra
   round trip per S3 call for Web_identity/Container/Imdsv2. Deferred; see
   s3-eio.md's "Out of Scope". *)
(* signed_request turns every non-2xx status into Error (Http_error _);
   re-thread it back into the Ok shape interpret_* expects, or their
   non-2xx branches are unreachable. Headers are lost here, matching
   signed_request's own success-only header return. *)
let reclassify_transport_result :
    (int * (string * string) list * string, Aws_error.t) result -> (int * (string * string) list * string, S3_error.t) result
    = function
  | Error (Aws_error.Http_error (status, body)) -> Ok (status, [], body)
  | Error e -> Error (S3_error.Aws e)
  | Ok (status, headers, body) -> Ok (status, headers, body)

let send_request ~net ~clock ~fs config ~meth ~key ?query ?body () =
  let* () = validate_config config in
  let* scheme, host, port, path = host_port_and_path config ~key in
  let* creds = resolve_credentials ~net ~clock ~fs config in
  reclassify_transport_result
    (Aws_http.signed_request ~net ~clock ~scheme
       ~access_key_id:creds.access_key_id
       ~secret_access_key:creds.secret_access_key
       ?session_token:creds.session_token
       ~region:config.region ~service:"s3" ~normalize_path:false
       ~meth ~host ?port ~path ?query ?body ())

let find_header_case_insensitive name headers =
  List.find_map (fun (k, v) -> if String.lowercase_ascii k = name then Some v else None) headers

(* Kept pure and separate from send_request: signed_request always
   negotiates real TLS (no plain-HTTP mode, and bare IP literals aren't
   valid SNI hostnames), so these are unit-tested directly rather than via
   a mock server — see s3-eio.md's test strategy note. *)
let interpret_put (status, _headers, body) =
  if status >= 200 && status < 300 then Ok () else Error (S3_error.of_response ~status ~body)

let interpret_get (status, _headers, body) =
  if status >= 200 && status < 300 then Ok body else Error (S3_error.of_response ~status ~body)

(* S3's DeleteObject returns 204 on success, including when the key never
   existed — deleting a nonexistent key is not an error. *)
let interpret_delete (status, _headers, body) =
  if status >= 200 && status < 300 then Ok () else Error (S3_error.of_response ~status ~body)

(* HEAD responses never carry a body, so a non-404 HEAD error always lands
   in Unparseable_error_response with an empty body — expected, not a
   parsing bug. *)
let interpret_head (status, headers, body) =
  if status >= 200 && status < 300 then
    let content_length =
      match find_header_case_insensitive "content-length" headers with
      | None -> Ok None
      | Some v ->
        (match int_of_string_opt v with
         | Some n -> Ok (Some n)
         | None -> Error (S3_error.Malformed_response { header = "content-length"; value = v }))
    in
    match content_length with
    | Error _ as e -> e
    | Ok content_length ->
      Ok
        { content_length;
          etag = find_header_case_insensitive "etag" headers;
          last_modified = find_header_case_insensitive "last-modified" headers;
          content_type = find_header_case_insensitive "content-type" headers;
        }
  else Error (S3_error.of_response ~status ~body)

let put_object t ~key ~body =
  match send_request ~net:t.net ~clock:t.clock ~fs:t.fs t.config ~meth:`PUT ~key ~body () with
  | Error _ as e -> e
  | Ok r -> interpret_put r

let get_object t ~key =
  match send_request ~net:t.net ~clock:t.clock ~fs:t.fs t.config ~meth:`GET ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_get r

let delete_object t ~key =
  match send_request ~net:t.net ~clock:t.clock ~fs:t.fs t.config ~meth:`DELETE ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_delete r

let head_object t ~key =
  match send_request ~net:t.net ~clock:t.clock ~fs:t.fs t.config ~meth:`HEAD ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_head r
