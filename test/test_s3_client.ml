let static_credentials =
  { Aws_credentials.source =
      Static { access_key_id = "test"; secret_access_key = "test"; session_token = None };
    region = "us-east-1";
  }

let client ~net ~clock ~fs endpoint =
  S3_client.create ~net ~clock ~fs
    { bucket = "bucket";
      region = "us-east-1";
      credentials = static_credentials;
      endpoint = Some endpoint;
    }

let test_invalid_endpoints_return_invalid_config () =
  Eio_main.run @@ fun env ->
  List.iter
    (fun endpoint ->
      match S3_client.head_object (client ~net:env#net ~clock:env#clock ~fs:env#fs endpoint) ~key:"key" with
      | Error (S3_error.Invalid_config _) -> ()
      | Error e -> Alcotest.failf "%s: expected Invalid_config, got %s" endpoint (S3_error.to_string e)
      | Ok _ -> Alcotest.failf "%s: expected Invalid_config" endpoint)
    [ "";
      "localhost:";
      "localhost:abc";
      "localhost:70000";
      "localhost:0x50";
      "localhost:8_000";
      "localhost:+80";
      "::1";
      "[::1";
      "[::1]x";
      "local]host";
      "local host";
      "localhost/path";
      "localhost?x=1";
      "localhost#frag";
    ]

(* Regression test: a dotted bucket name under virtual-hosted-style
   addressing (endpoint = None) produces a multi-label hostname that AWS's
   *.s3.<region>.amazonaws.com wildcard cert doesn't cover, which used to
   surface as an opaque Network_error deep inside aws-eio/https-eio instead
   of this actionable Invalid_config. *)
let test_dotted_bucket_rejected_under_virtual_hosted_addressing () =
  Eio_main.run @@ fun env ->
  let client =
    S3_client.create ~net:env#net ~clock:env#clock ~fs:env#fs
      { bucket = "my.dotted.bucket";
        region = "us-east-1";
        credentials = static_credentials;
        endpoint = None;
      }
  in
  match S3_client.head_object client ~key:"key" with
  | Error (S3_error.Invalid_config _) -> ()
  | Error e -> Alcotest.failf "expected Invalid_config, got %s" (S3_error.to_string e)
  | Ok _ -> Alcotest.fail "expected a dotted bucket name to be rejected"

let () =
  Alcotest.run "s3_client"
    [ ( "config",
        [ Alcotest.test_case "invalid endpoints return Invalid_config" `Quick
            test_invalid_endpoints_return_invalid_config;
          Alcotest.test_case "dotted bucket name rejected under virtual-hosted addressing" `Quick
            test_dotted_bucket_rejected_under_virtual_hosted_addressing;
        ] );
    ]
