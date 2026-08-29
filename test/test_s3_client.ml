let static_credentials =
  { Aws_credentials.source =
      Static { access_key_id = "test"; secret_access_key = "test"; session_token = None };
    region = "us-east-1";
  }

let client ~net ~clock endpoint =
  S3_client.create ~net ~clock
    { bucket = "bucket";
      region = "us-east-1";
      credentials = static_credentials;
      endpoint = Some endpoint;
    }

let test_invalid_endpoints_return_invalid_config () =
  Eio_main.run @@ fun env ->
  List.iter
    (fun endpoint ->
      match S3_client.head_object (client ~net:env#net ~clock:env#clock endpoint) ~key:"key" with
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
    ]

let () =
  Alcotest.run "s3_client"
    [ ( "config",
        [ Alcotest.test_case "invalid endpoints return Invalid_config" `Quick
            test_invalid_endpoints_return_invalid_config;
        ] );
    ]
