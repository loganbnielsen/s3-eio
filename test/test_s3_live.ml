(* Live S3 smoke test — skipped unless S3_EIO_LIVE=1 (`dune runtest` must
   never touch a real AWS account).

   Required: S3_EIO_LIVE=1, S3_EIO_LIVE_BUCKET=<bucket>,
   AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (optionally AWS_SESSION_TOKEN),
   AWS_REGION (defaults to us-east-1).

   Writes one object under sun-live-test/ per run and deletes it via
   Fun.protect, so a failed assertion still cleans up. Minimal IAM policy:

   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "S3LiveTestObjectsOnly",
         "Effect": "Allow",
         "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::YOUR_BUCKET/sun-live-test/*"
       },
       {
         "Sid": "S3LiveTestListOnlyPrefix",
         "Effect": "Allow",
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::YOUR_BUCKET",
         "Condition": { "StringLike": { "s3:prefix": "sun-live-test/*" } }
       }
     ]
   } *)

let live_enabled () = Sys.getenv_opt "S3_EIO_LIVE" = Some "1"

let region () = Option.value (Sys.getenv_opt "AWS_REGION") ~default:"us-east-1"

let config () =
  let region = region () in
  { S3_client.bucket = Option.value (Sys.getenv_opt "S3_EIO_LIVE_BUCKET") ~default:"";
    region;
    credentials = Aws_credentials.of_env ~region ();
    endpoint = None }

let live_key = "sun-live-test/s3-eio-smoke.txt"
let live_body = "s3-eio live smoke test"

let with_live_object client f =
  match S3_client.put_object client ~key:live_key ~body:live_body with
  | Error e -> Alcotest.failf "PutObject failed: %s" (S3_error.to_string e)
  | Ok () ->
    Fun.protect
      ~finally:(fun () ->
        match S3_client.delete_object client ~key:live_key with
        | Ok () | Error _ -> ())
      (fun () -> f ())

let test_put_head_get_delete_roundtrip () =
  if not (live_enabled ()) then
    Printf.printf "[skip] S3_EIO_LIVE not set to 1 — skipping live S3 smoke test\n%!"
  else
    Eio_main.run @@ fun env ->
    let client = S3_client.create ~net:env#net ~clock:env#clock ~fs:env#fs (config ()) in
    with_live_object client (fun () ->
        (match S3_client.head_object client ~key:live_key with
         | Error e -> Alcotest.failf "HeadObject failed: %s" (S3_error.to_string e)
         | Ok { content_length; _ } ->
           Alcotest.(check (option int)) "Content-Length matches the body we wrote"
             (Some (String.length live_body)) content_length);
        match S3_client.get_object client ~key:live_key with
        | Error e -> Alcotest.failf "GetObject failed: %s" (S3_error.to_string e)
        | Ok body -> Alcotest.(check string) "round-tripped body" live_body body)

let test_missing_key_error_path () =
  if not (live_enabled ()) then
    Printf.printf "[skip] S3_EIO_LIVE not set to 1 — skipping live S3 smoke test\n%!"
  else
    Eio_main.run @@ fun env ->
    let client = S3_client.create ~net:env#net ~clock:env#clock ~fs:env#fs (config ()) in
    match S3_client.head_object client ~key:"sun-live-test/does-not-exist.txt" with
    | Error S3_error.Not_found -> ()
    | Error e -> Alcotest.failf "expected Not_found, got %s" (S3_error.to_string e)
    | Ok _ -> Alcotest.fail "expected the known-missing key to 404"

let () =
  Alcotest.run "s3_live"
    [ ( "smoke",
        [ Alcotest.test_case "put/head/get/delete round trip" `Quick test_put_head_get_delete_roundtrip;
          Alcotest.test_case "known-missing key returns Not_found" `Quick test_missing_key_error_path;
        ] );
    ]
