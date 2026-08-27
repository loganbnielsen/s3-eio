#!/usr/bin/env bash
# Runs the live S3 smoke test end to end: provision -> test -> teardown.
# Teardown always runs, even if the test fails.
#
# Two identities are involved:
#   PROFILE           - admin-ish profile that creates the bucket + attaches
#                        the scoped inline policy (default: sts-smoke-test-provisioner)
#   TEST_USER_PROFILE - profile holding sts-smoke-test-user's own static keys;
#                        used only to mint a short-lived session token
#                        (default: sts-smoke-test-user)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${PROFILE:-sts-smoke-test-provisioner}"
REGION="${REGION:-us-east-1}"
TEST_USER_PROFILE="${TEST_USER_PROFILE:-sts-smoke-test-user}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)}"
BUCKET_NAME="${BUCKET_NAME:-sun-live-test-${ACCOUNT_ID}}"

export PROFILE REGION ACCOUNT_ID BUCKET_NAME

cleanup() {
  echo "==> Tearing down..."
  rm -f "${probe_file:-}"
  ./scripts/teardown.sh
}
trap cleanup EXIT

echo "==> Provisioning..."
./scripts/setup.sh

echo "==> Minting short-lived session token for ${TEST_USER_PROFILE}..."
creds="$(aws sts get-session-token --profile "$TEST_USER_PROFILE" --duration-seconds 900 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<<"$creds"

export S3_EIO_LIVE=1
export S3_EIO_LIVE_BUCKET="$BUCKET_NAME"
export AWS_REGION="$REGION"

# ponytail: IAM policy attachment isn't immediately consistent — the same
# eventual-consistency gap setup.sh's create-function retry works around for
# Lambda's execution role. Probe with the real permission (put+delete a
# scratch key) using the test user's own credentials until it's actually
# enforced, instead of guessing a fixed sleep.
echo "==> Waiting for IAM policy to propagate..."
probe_key="sun-live-test/.iam-propagation-probe"
probe_file="$(mktemp)"
printf probe > "$probe_file"
attempt=0
delay=2
deadline=$((SECONDS + 300))
until aws s3api put-object --bucket "$BUCKET_NAME" --key "$probe_key" --body "$probe_file" \
  --region "$REGION" > /dev/null 2>&1
do
  attempt=$((attempt + 1))
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "error: PutObject still denied after ${attempt} attempts / 5m (IAM policy propagation?)" >&2
    exit 1
  fi
  echo "    not yet authorized, retrying in ${delay}s (attempt ${attempt})..."
  sleep "$delay"
  if [ "$delay" -lt 16 ]; then delay=$((delay * 2)); fi
done
rm -f "$probe_file"
aws s3api delete-object --bucket "$BUCKET_NAME" --key "$probe_key" --region "$REGION" > /dev/null

echo "==> Running live S3 smoke test against s3://${BUCKET_NAME}..."
dune runtest test/
