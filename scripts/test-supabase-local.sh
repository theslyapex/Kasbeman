#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command in supabase psql curl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

cleanup() {
  supabase stop --no-backup >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting isolated local Supabase services..."
supabase start

echo "Applying the complete canonical migration chain to the local Supabase database..."
supabase db reset --local --yes

echo "Reading local-only API credentials..."
eval "$(supabase status -o env)"
API_URL="${API_URL:-http://127.0.0.1:54321}"
ANON_KEY="${ANON_KEY:-${PUBLISHABLE_KEY:-}}"
if [[ -z "$ANON_KEY" ]]; then
  echo "Supabase CLI did not expose a local anon/publishable key." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"; cleanup' EXIT
signup_body="$tmp_dir/signup.json"
user_body="$tmp_dir/user.json"
profile_body="$tmp_dir/profile.json"
business_body="$tmp_dir/business.json"
business_read_body="$tmp_dir/business-read.json"

run_id="${GITHUB_RUN_ID:-local-$(date +%s)}"
email="kasbeman-ci-${run_id}@example.com"
password="Local-CI-Only-${run_id}-Aa9!"

echo "Checking real local Supabase Auth signup..."
signup_status="$(curl --silent --show-error --output "$signup_body" --write-out '%{http_code}' \
  --request POST "$API_URL/auth/v1/signup" \
  --header "apikey: $ANON_KEY" \
  --header 'Content-Type: application/json' \
  --data "$(jq -n --arg email "$email" --arg password "$password" --arg name "Kasbeman Local CI" \
    '{email:$email,password:$password,data:{full_name:$name}}')")"
if [[ "$signup_status" != "200" && "$signup_status" != "201" ]]; then
  echo "Local Auth signup failed (HTTP $signup_status):" >&2
  cat "$signup_body" >&2
  exit 1
fi

access_token="$(jq -r '.access_token // empty' "$signup_body")"
user_id="$(jq -r '.user.id // empty' "$signup_body")"
if [[ -z "$access_token" || -z "$user_id" ]]; then
  echo "Local Auth signup did not return a user and access token." >&2
  cat "$signup_body" >&2
  exit 1
fi

echo "Checking authenticated user endpoint..."
user_status="$(curl --silent --show-error --output "$user_body" --write-out '%{http_code}' \
  "$API_URL/auth/v1/user" \
  --header "apikey: $ANON_KEY" \
  --header "Authorization: Bearer $access_token")"
if [[ "$user_status" != "200" ]] || [[ "$(jq -r '.id // empty' "$user_body")" != "$user_id" ]]; then
  echo "Local Auth user verification failed (HTTP $user_status)." >&2
  cat "$user_body" >&2
  exit 1
fi

echo "Checking Auth trigger, PostgREST and profile RLS..."
profile_status="$(curl --silent --show-error --output "$profile_body" --write-out '%{http_code}' \
  "$API_URL/rest/v1/profiles?select=id,display_name&id=eq.$user_id" \
  --header "apikey: $ANON_KEY" \
  --header "Authorization: Bearer $access_token")"
if [[ "$profile_status" != "200" ]] || ! jq -e --arg id "$user_id" 'length == 1 and .[0].id == $id' "$profile_body" >/dev/null; then
  echo "Authenticated profile read failed (HTTP $profile_status)." >&2
  cat "$profile_body" >&2
  exit 1
fi

echo "Checking authenticated Data API RPC and tenant visibility..."
business_slug="kasbeman-local-ci-${run_id//[^a-zA-Z0-9-]/-}"
business_status="$(curl --silent --show-error --output "$business_body" --write-out '%{http_code}' \
  --request POST "$API_URL/rest/v1/rpc/create_business" \
  --header "apikey: $ANON_KEY" \
  --header "Authorization: Bearer $access_token" \
  --header 'Content-Type: application/json' \
  --data "$(jq -n --arg name "کسب‌وکار آزمایش محلی" --arg slug "$business_slug" \
    '{p_name:$name,p_slug:$slug}')")"
if [[ "$business_status" != "200" ]]; then
  echo "Authenticated create_business RPC failed (HTTP $business_status)." >&2
  cat "$business_body" >&2
  exit 1
fi
business_id="$(jq -r 'if type == "array" then .[0] else . end' "$business_body")"
if [[ -z "$business_id" || "$business_id" == "null" ]]; then
  echo "create_business did not return a business id." >&2
  cat "$business_body" >&2
  exit 1
fi

business_read_status="$(curl --silent --show-error --output "$business_read_body" --write-out '%{http_code}' \
  "$API_URL/rest/v1/businesses?select=id,name,slug&id=eq.$business_id" \
  --header "apikey: $ANON_KEY" \
  --header "Authorization: Bearer $access_token")"
if [[ "$business_read_status" != "200" ]] || ! jq -e --arg id "$business_id" 'length == 1 and .[0].id == $id' "$business_read_body" >/dev/null; then
  echo "New tenant could not read its business through the Data API (HTTP $business_read_status)." >&2
  cat "$business_read_body" >&2
  exit 1
fi

echo "Local Supabase Auth + Data API smoke tests passed."

echo "Running existing RLS, RBAC, CRM, ticketing and sales/inventory SQL smoke tests against real local Supabase PostgreSQL..."
KASBEMAN_LOCAL_SUPABASE=1 \
PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres \
  bash scripts/test-postgres-schema.sh

echo "Running multi-connection concurrency tests against local Supabase PostgreSQL..."
PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres \
  bash scripts/test-postgres-concurrency.sh

echo "All local Supabase Auth, Data API, schema, RLS, module and concurrency tests passed."
