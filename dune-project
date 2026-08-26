(lang dune 3.0)
(name s3-eio)
(version 0.1.0)
(generate_opam_files true)

(package
 (name s3-eio)
 (synopsis "Eio-native S3 client built on aws-eio")
 (description "\
An S3 client built on aws-eio's credentials and SigV4/HTTP transport — not an
AWS SDK, just the four REST-with-headers S3 operations that need no XML:
put_object, get_object, delete_object, head_object. Not in v1: list_objects_v2
(XML response body), multipart upload, and true streaming (whole objects are
buffered in memory).")
 (maintainers "lbendtlynielsen@gmail.com")
 (authors "lbendtly")
 (license "MIT")
 (homepage "https://github.com/loganbnielsen/s3-eio")
 (bug_reports "https://github.com/loganbnielsen/s3-eio/issues")
 (source (github loganbnielsen/s3-eio))
 (depends
  (ocaml (>= 5.4.0))
  (eio (>= 1.3))
  (aws-eio (>= 0.1.0))
  (eio_main (and (>= 1.3) :with-test))
  (alcotest :with-test)
  (odoc :with-doc)))
