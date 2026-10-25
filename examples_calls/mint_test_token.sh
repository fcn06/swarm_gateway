#!/usr/bin/env bash
# ==============================================================================
# Mint a test HS256 JWT for Swarm Gateway Authentication Testing
# ==============================================================================
set -euo pipefail

SECRET="${SWARM_AUTH_SECRET:-your-256-bit-secret-key-here-must-be-long}"
AUDIENCE="${SWARM_AUTH_AUDIENCE:-swarm-api}"
ISSUER="${SWARM_AUTH_ISSUER:-swarm-auth-service}"
SUBJECT="${SWARM_AUTH_SUBJECT:-user_1}"
TENANT="${SWARM_AUTH_TENANT:-tenant_demo}"

now=$(date +%s)
exp=$((now + 3600))

# Base64URL encode helper
b64url() {
  openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\r\n'
}

header_json='{"alg":"HS256","typ":"JWT"}'
payload_json="{\"sub\":\"${SUBJECT}\",\"tenant_id\":\"${TENANT}\",\"aud\":\"${AUDIENCE}\",\"iss\":\"${ISSUER}\",\"exp\":${exp},\"iat\":${now},\"nbf\":${now}}"

header=$(printf '%s' "$header_json" | b64url)
payload=$(printf '%s' "$payload_json" | b64url)
signature=$(printf '%s' "${header}.${payload}" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)

printf '%s.%s.%s\n' "$header" "$payload" "$signature"
