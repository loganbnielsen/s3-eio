type config = {
  bucket : string;
  region : string;
  credentials : Aws_credentials.t;
  endpoint : string option;
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
  config : config;
}

let create ~net ~clock config =
  { net = (net :> [`Generic] Eio.Net.ty Eio.Std.r);
    clock = (clock :> float Eio.Time.clock_ty Eio.Std.r);
    config;
  }

let parse_port endpoint port =
  match int_of_string_opt port with
  | Some port when port > 0 && port <= 65535 -> Ok (Some port)
  | _ -> Error (S3_error.Invalid_config ("endpoint has an invalid port: " ^ endpoint))

(* Bracket-aware: splitting "[::1]:9000" on the last colon would cut into the
   IPv6 address itself; RFC 3986's "[host]:port" convention disambiguates. *)
let parse_endpoint endpoint =
  let host_port host port =
    if host = "" then Error (S3_error.Invalid_config "endpoint host is empty")
    else Ok (host, port)
  in
  if String.length endpoint > 0 && endpoint.[0] = '[' then
    match String.index_opt endpoint ']' with
    | None -> Error (S3_error.Invalid_config "IPv6 endpoint is missing closing bracket")
    | Some close ->
      let host = String.sub endpoint 1 (close - 1) in
      let rest = String.sub endpoint (close + 1) (String.length endpoint - close - 1) in
      if rest = "" then host_port host None
      else if String.length rest > 1 && rest.[0] = ':' then
        match parse_port endpoint (String.sub rest 1 (String.length rest - 1)) with
        | Error _ as e -> e
        | Ok port -> host_port host port
      else Error (S3_error.Invalid_config "IPv6 endpoint must be [host] or [host]:port")
  else
    match String.rindex_opt endpoint ':' with
    | Some i ->
      let host = String.sub endpoint 0 i in
      if String.contains host ':' then Error (S3_error.Invalid_config "IPv6 endpoint must be bracketed")
      else if String.contains endpoint '[' || String.contains endpoint ']' then
        Error (S3_error.Invalid_config "endpoint has invalid brackets")
      else (
        match parse_port endpoint (String.sub endpoint (i + 1) (String.length endpoint - i - 1)) with
        | Error _ as e -> e
        | Ok port -> host_port host port)
    | None ->
      if String.contains endpoint '[' || String.contains endpoint ']' then
        Error (S3_error.Invalid_config "endpoint has invalid brackets")
      else host_port endpoint None

let has_crlf s = String.exists (fun c -> c = '\r' || c = '\n') s

(* config.bucket/region become an unencoded Host header, unlike key (which
   is percent-encoded) — reject CRLF to block header injection from
   less-trusted input. *)
let validate_config config =
  if has_crlf config.bucket then Error (S3_error.Invalid_config "bucket contains a CR or LF character")
  else if has_crlf config.region then Error (S3_error.Invalid_config "region contains a CR or LF character")
  else
    match config.endpoint with
    | Some endpoint when has_crlf endpoint -> Error (S3_error.Invalid_config "endpoint contains a CR or LF character")
    | _ -> Ok ()

let host_port_and_path config ~key =
  match config.endpoint with
  | None -> Ok (Printf.sprintf "%s.s3.%s.amazonaws.com" config.bucket config.region, None, "/" ^ key)
  | Some endpoint ->
    match parse_endpoint endpoint with
    | Error _ as e -> e
    | Ok (host, port) -> Ok (host, port, "/" ^ config.bucket ^ "/" ^ key)

let ( let* ) = Result.bind

let resolve_credentials ~net ~clock config =
  match Aws_credentials.resolve ~net ~clock config.credentials with
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

let send_request ~net ~clock config ~meth ~key ?query ?body () =
  let* () = validate_config config in
  let* host, port, path = host_port_and_path config ~key in
  let* creds = resolve_credentials ~net ~clock config in
  reclassify_transport_result
    (Aws_http.signed_request ~net ~clock
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
    Ok
      { content_length =
          find_header_case_insensitive "content-length" headers |> Option.map int_of_string_opt |> Option.join;
        etag = find_header_case_insensitive "etag" headers;
        last_modified = find_header_case_insensitive "last-modified" headers;
        content_type = find_header_case_insensitive "content-type" headers;
      }
  else Error (S3_error.of_response ~status ~body)

let put_object t ~key ~body =
  match send_request ~net:t.net ~clock:t.clock t.config ~meth:`PUT ~key ~body () with
  | Error _ as e -> e
  | Ok r -> interpret_put r

let get_object t ~key =
  match send_request ~net:t.net ~clock:t.clock t.config ~meth:`GET ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_get r

let delete_object t ~key =
  match send_request ~net:t.net ~clock:t.clock t.config ~meth:`DELETE ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_delete r

let head_object t ~key =
  match send_request ~net:t.net ~clock:t.clock t.config ~meth:`HEAD ~key () with
  | Error _ as e -> e
  | Ok r -> interpret_head r
