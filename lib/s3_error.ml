type t =
  | Aws of Aws_error.t
  | Not_found
  | Service_error of { code : string; message : string; status : int }
  | Unparseable_error_response of { status : int; body : string }
  | Invalid_config of string

(* Deliberately non-general: a substring search for "<Tag>text</Tag>" rather
   than a structural XML parse. Works because S3 error documents' Code/Message
   leaves carry no attributes or namespace prefix. Private to this module —
   not aws-eio's Aws_credentials.extract_tag, which parses a different (STS)
   document and is not part of aws-eio's public contract. *)
let extract_tag tag xml =
  let open_tag = "<" ^ tag ^ ">" and close_tag = "</" ^ tag ^ ">" in
  let hlen = String.length xml and olen = String.length open_tag in
  let rec find needle nlen start =
    if start + nlen > hlen then None
    else if String.sub xml start nlen = needle then Some start
    else find needle nlen (start + 1)
  in
  match find open_tag olen 0 with
  | None -> None
  | Some i ->
    let content_start = i + olen in
    (match find close_tag (String.length close_tag) content_start with
     | None -> None
     | Some j -> Some (String.sub xml content_start (j - content_start)))

let of_response ~status ~body =
  if status = 404 then Not_found
  else
    match (extract_tag "Code" body, extract_tag "Message" body) with
    | Some code, Some message -> Service_error { code; message; status }
    | _ -> Unparseable_error_response { status; body }

let to_string = function
  | Aws e -> Aws_error.to_string e
  | Not_found -> "not found"
  | Service_error { code; message; status } -> Printf.sprintf "S3 error %d (%s): %s" status code message
  | Unparseable_error_response { status; body } ->
    Printf.sprintf "S3 error %d, unparseable response: %s" status body
  | Invalid_config msg -> "invalid s3-eio config: " ^ msg
