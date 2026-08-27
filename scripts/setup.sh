#!/usr/bin/env bash
# Provisions a live-test S3 bucket in YOUR OWN AWS account and attaches a
# scoped inline policy to an IAM user of your choice, so you can run
# test/test_s3_live.ml (S3_EIO_LIVE=1) against a real bucket. Meant for
# anyone trying this package out locally, not tied to any specific account.
#
# Run with an AWS CLI profile that can create/manage the bucket and put an
# inline policy on the target user (see terraform/main.tf's header for the
# shape of that permission set) — override via env vars:
#   PROFILE=my-admin-profile USER_NAME=my-test-user ./scripts/setup.sh
#
# Not idempotent — re-running against an already-existing bucket will fail;
# run teardown.sh first if you need to recreate it.
set -euo pipefail

PROFILE="${PROFILE:-sts-smoke-test-provisioner}"
REGION="${REGION:-us-east-1}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)}"
BUCKET_NAME="${BUCKET_NAME:-sun-live-test-${ACCOUNT_ID}}"
USER_NAME="${USER_NAME:-sts-smoke-test-user}"
POLICY_NAME="s3-eio-live-test"

echo "==> Creating S3 bucket ${BUCKET_NAME}..."
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --profile "$PROFILE"

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "$PROFILE"

echo "==> Attaching inline policy to ${USER_NAME}..."
policy_file="$(mktemp)"
cat > "$policy_file" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3LiveTestObjectsOnly",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/sun-live-test/*"
    },
    {
      "Sid": "S3LiveTestListOnlyPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}",
      "Condition": { "StringLike": { "s3:prefix": "sun-live-test/*" } }
    }
  ]
}
EOF
aws iam put-user-policy \
  --user-name "$USER_NAME" --policy-name "$POLICY_NAME" \
  --policy-document "file://${policy_file}" --profile "$PROFILE"
rm -f "$policy_file"

echo "==> Setup complete. S3_EIO_LIVE_BUCKET=${BUCKET_NAME}"
