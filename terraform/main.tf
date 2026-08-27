# Provisions the one dedicated S3 bucket + scoped IAM role s3-eio's live
# test (test/test_s3_live.ml, S3_EIO_LIVE=1) needs. Not part of any Sun
# customer workspace — this is this package's own test infra, owned here
# because s3-eio is a standalone package, not something living inside sun.
#
# No long-lived IAM access keys: the role is assumable by whatever
# principal(s) you name in trusted_principal_arns (your own IAM user/role, or
# a CI OIDC provider's role), via `aws sts assume-role`.
#
# Usage:
#   terraform init
#   terraform apply \
#     -var bucket_name=your-unique-bucket-name \
#     -var 'trusted_principal_arns=["arn:aws:iam::ACCOUNT_ID:user/you"]'
#
#   aws sts assume-role \
#     --role-arn "$(terraform output -raw role_arn)" \
#     --role-session-name s3-eio-live-test
#   # export the returned AccessKeyId/SecretAccessKey/SessionToken, then:
#   S3_EIO_LIVE=1 S3_EIO_LIVE_BUCKET="$(terraform output -raw bucket_name)" dune test
#
#   terraform destroy   # when done

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Globally-unique name for the dedicated live-test bucket"
}

variable "trusted_principal_arns" {
  type        = list(string)
  description = "ARNs allowed to assume the live-test role (your IAM user/role, or a CI OIDC role)"
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "live_test" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "live_test" {
  bucket                  = aws_s3_bucket.live_test.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "live_test" {
  statement {
    sid       = "S3LiveTestObjectsOnly"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.live_test.arn}/sun-live-test/*"]
  }
  statement {
    sid       = "S3LiveTestListOnlyPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.live_test.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["sun-live-test/*"]
    }
  }
}

resource "aws_iam_policy" "live_test" {
  name   = "s3-eio-live-test"
  policy = data.aws_iam_policy_document.live_test.json
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "live_test" {
  name               = "s3-eio-live-test"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "live_test" {
  role       = aws_iam_role.live_test.name
  policy_arn = aws_iam_policy.live_test.arn
}

output "bucket_name" {
  value = aws_s3_bucket.live_test.bucket
}

output "role_arn" {
  value = aws_iam_role.live_test.arn
}
