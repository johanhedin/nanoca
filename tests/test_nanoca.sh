#!/bin/bash

# test_nanoca.sh - Test suite for nanoca
#
# Created: 2026-03-24
# Updated: 2026-04-01
#
# Exercises all commands and options that nanoca supports. Supposed to be run
# from the project root using make test
#
# Written with help of Claude Code.
#
# Usage: ./test_nanoca.sh

set -uo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NANOCA="${REPO_ROOT}/bin/nanoca"
OPENSSL="/usr/bin/openssl"

if [[ ! -x "${NANOCA}" ]]; then
    echo "ERROR: nanoca binary not found at ${NANOCA}" >&2
    exit 1
fi

if [[ ! -x "${OPENSSL}" ]]; then
    echo "ERROR: openssl not found at ${OPENSSL}" >&2
    exit 1
fi

TMPDIR_BASE="$(mktemp -d)"
CADIR="${TMPDIR_BASE}/testca"
WORKDIR="${TMPDIR_BASE}/work"
mkdir -p "${CADIR}" "${WORKDIR}"

cleanup() {
    rm -rf "${TMPDIR_BASE}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0

section() {
    echo ""
    echo "=== $* ==="
}

ok() {
    echo "  PASS: $1"
    ((PASS++)) || true
}

fail() {
    local desc="$1"
    local detail="${2:-}"
    echo "  FAIL: ${desc}${detail:+ (${detail})}"
    ((FAIL++)) || true
}

# Run command, capturing stdout+stderr into _out and exit code into _rc.
# Usage: run CMD [ARGS...]
# Note: do not prepend env var assignments — set them before calling run,
# or use inline capture for commands that need specific env vars.
run() {
    _out=$("$@" 2>&1)
    _rc=$?
    true
}

check_rc() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${actual}" -eq "${expected}" ]]; then
        ok "${desc}"
    else
        fail "${desc}" "expected rc=${expected}, got rc=${actual}"
    fi
}

check_file() {
    [[ -f "$1" ]] && ok "$2" || fail "$2" "file not found: $1"
}

check_dir() {
    [[ -d "$1" ]] && ok "$2" || fail "$2" "directory not found: $1"
}

check_output() {
    local output="$1" pattern="$2" desc="$3"
    if echo "${output}" | grep -q "${pattern}"; then
        ok "${desc}"
    else
        fail "${desc}" "pattern '${pattern}' not found in output"
    fi
}

# ---------------------------------------------------------------------------
# Section: Global options
# ---------------------------------------------------------------------------
section "Global options"

run "${NANOCA}" --help
check_rc "--help exits 0" 0 ${_rc}
check_output "${_out}" "Usage:" "--help output contains 'Usage:'"
check_output "${_out}" "Commands:" "--help output contains 'Commands:'"
check_output "${_out}" "client-auth" "--help output documents --client-auth option"

run "${NANOCA}" -h
check_rc "-h exits 0" 0 ${_rc}

run "${NANOCA}" --version
check_rc "--version exits 0" 0 ${_rc}
check_output "${_out}" "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" "--version prints a version string"

run "${NANOCA}" -v
check_rc "-v exits 0" 0 ${_rc}
check_output "${_out}" "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" "-v prints a version string"

run "${NANOCA}"
check_rc "no command exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "no command prints error"

run "${NANOCA}" nosuchcmd
check_rc "unknown command exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "unknown command prints error"

run "${NANOCA}" --unknown-option --version
check_rc "unsupported option exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "unsupported option prints error"

# ---------------------------------------------------------------------------
# Section: create — error cases
# ---------------------------------------------------------------------------
section "create — error cases"

run "${NANOCA}" --dir="${TMPDIR_BASE}/nonexistent" create
check_rc "create in non-existent dir exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "create non-existent dir: error message printed"

mkdir -p "${TMPDIR_BASE}/emptyca"
run "${NANOCA}" --yes --dir="${TMPDIR_BASE}/emptyca" create
check_rc "create --yes without CA_CN exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "create without CA_CN: error message printed"

# ---------------------------------------------------------------------------
# Section: create — success
# ---------------------------------------------------------------------------
section "create — success (--yes with env vars)"

# Use inline capture so env vars reach the subprocess
_out=$(CA_CN="Test CA" CA_O="Test Org" CA_C="SE" \
       "${NANOCA}" --yes --dir="${CADIR}" create 2>&1)
_rc=$?
check_rc "create --yes exits 0" 0 ${_rc}
check_output "${_out}" "successfully created" "create: success message printed"

check_dir  "${CADIR}/private"              "create: private/ dir exists"
check_dir  "${CADIR}/public"               "create: public/ dir exists"
check_dir  "${CADIR}/crts"                 "create: crts/ dir exists"
check_dir  "${CADIR}/csrs"                 "create: csrs/ dir exists"
check_file "${CADIR}/private/crtdb"        "create: crtdb exists"
check_file "${CADIR}/private/crtserial"    "create: crtserial exists"
check_file "${CADIR}/private/crlserial"    "create: crlserial exists"
check_file "${CADIR}/private/settings.cfg" "create: settings.cfg exists"

# Derive the CA filename stem dynamically so tests are not coupled to the CN
CA_STEM=$(ls "${CADIR}/private/"*.key 2>/dev/null | head -1 | xargs -r basename | sed 's/\.key$//')
check_file "${CADIR}/private/${CA_STEM}.key" "create: CA key file named from CN"
check_file "${CADIR}/public/${CA_STEM}.crt"  "create: CA cert file named from CN"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" \
    "${CADIR}/public/test-ca.crt" &>/dev/null
check_rc "create: CA cert is self-signed and valid" 0 $?

"${OPENSSL}" x509 -noout -text -in "${CADIR}/public/test-ca.crt" 2>/dev/null \
    | grep -q "CA:TRUE"
check_rc "create: CA cert has CA:TRUE basic constraint" 0 $?

grep -q "CA_SIGNED_CERT_DAYS" "${CADIR}/private/settings.cfg"
check_rc "create: settings.cfg has CA_SIGNED_CERT_DAYS" 0 $?
grep -q "CA_CRL_DAYS" "${CADIR}/private/settings.cfg"
check_rc "create: settings.cfg has CA_CRL_DAYS" 0 $?
grep -q "CA_CRL_URL" "${CADIR}/private/settings.cfg"
check_rc "create: settings.cfg has CA_CRL_URL" 0 $?

run "${NANOCA}" --yes --dir="${CADIR}" create
check_rc "create in non-empty dir exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "create in non-empty dir: error message printed"

# ---------------------------------------------------------------------------
# Section: create — 4096-bit key
# ---------------------------------------------------------------------------
section "create — 4096-bit RSA key"

CA4096="${TMPDIR_BASE}/ca4096"
mkdir -p "${CA4096}"
_out=$(CA_CN="Test CA 4096" CA_RSA_KEYSIZE=4096 \
       "${NANOCA}" --yes --dir="${CA4096}" create 2>&1)
_rc=$?
check_rc "create with 4096-bit key exits 0" 0 ${_rc}
CA4096_STEM=$(ls "${CA4096}/private/"*.key 2>/dev/null | head -1 | xargs -r basename | sed 's/\.key$//')
check_file "${CA4096}/private/${CA4096_STEM}.key" "create 4096: key file named from CN"
check_file "${CA4096}/public/${CA4096_STEM}.crt"  "create 4096: cert file named from CN"

"${OPENSSL}" rsa -in "${CA4096}/private/${CA4096_STEM}.key" \
    -text -noout 2>/dev/null | grep -q "4096 bit"
check_rc "create 4096: key is 4096 bits" 0 $?

# ---------------------------------------------------------------------------
# Section: create — PSS signature scheme
# ---------------------------------------------------------------------------
section "create — PSS signature scheme"

CAPSS="${TMPDIR_BASE}/capss"
mkdir -p "${CAPSS}"
_out=$(CA_CN="Test CA PSS" CA_RSA_SSA=PSS \
       "${NANOCA}" --yes --dir="${CAPSS}" create 2>&1)
_rc=$?
check_rc "create with PSS scheme exits 0" 0 ${_rc}
CAPSS_STEM=$(ls "${CAPSS}/private/"*.key 2>/dev/null | head -1 | xargs -r basename | sed 's/\.key$//')
check_file "${CAPSS}/private/${CAPSS_STEM}.key" "create PSS: key file exists"
check_file "${CAPSS}/public/${CAPSS_STEM}.crt"  "create PSS: cert file exists"

# ---------------------------------------------------------------------------
# Section: debug command
# ---------------------------------------------------------------------------
section "debug command"

run "${NANOCA}" --dir="${CADIR}" debug
check_rc "debug exits 0" 0 ${_rc}
check_output "${_out}" "CA_YEARS"            "debug: CA_YEARS shown"
check_output "${_out}" "CA_RSA_KEYSIZE"      "debug: CA_RSA_KEYSIZE shown"
check_output "${_out}" "CA_SIGNED_CERT_DAYS" "debug: CA_SIGNED_CERT_DAYS shown"
check_output "${_out}" "CA_CRL_DAYS"         "debug: CA_CRL_DAYS shown"
check_output "${_out}" "CA_CRL_URL"          "debug: CA_CRL_URL shown"
check_output "${_out}" "CERT_RSA_KEYSIZE"    "debug: CERT_RSA_KEYSIZE shown"
check_output "${_out}" "CSR_RSA_SSA"         "debug: CSR_RSA_SSA shown"

# ---------------------------------------------------------------------------
# Section: name command
# ---------------------------------------------------------------------------
section "name command"

run "${NANOCA}" --dir="${CADIR}" name
check_rc "name exits 0" 0 ${_rc}
# The name command prints the CA's Common Name (CN), not the filename stem
check_output "${_out}" "Test CA" "name: prints the CA Common Name"
[[ "${_out}" == "Test CA" ]] \
    && ok "name: output is exactly 'Test CA'" \
    || fail "name: output is exactly 'Test CA'" "got '${_out}'"

run "${NANOCA}" --dir="${TMPDIR_BASE}/nonexistent" name
check_rc "name on non-CA dir exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "name on non-CA dir: error message printed"

# ---------------------------------------------------------------------------
# Section: list — empty CA
# ---------------------------------------------------------------------------
section "list — empty CA"

run "${NANOCA}" --dir="${CADIR}" list
check_rc "list on empty CA exits 0" 0 ${_rc}
check_output "${_out}" "State" "list: header line printed"

# ---------------------------------------------------------------------------
# Section: req — machine certificate (new key)
# ---------------------------------------------------------------------------
section "req — machine certificate (new key)"

SRV_KEY="${WORKDIR}/server.key"
SRV_CSR="${WORKDIR}/server.csr"

# Interactive input sequence for machine cert with new key:
#  1. req type:    <Enter>           → default "1" (machine)
#  2. C:           SE
#  3. ST:          <Enter>           → empty
#  4. L:           <Enter>           → empty
#  5. O:           Test Org
#  6. OU:          <Enter>           → empty
#  7. CN:          server.example.com
#  8. server auth? <Enter>           → default Yes (adds CN to san_str)
#  9. client auth? <Enter>           → default No
# 10. SAN list:    <Enter>           → empty (CN already in san_str)
# 11. keysize:     2048              → must be explicit; read -e -i default
#                                      is not applied when stdin is a pipe
# 12. sig scheme:  PKCS1-V1.5       → must be explicit; same reason
# 13. pass phrase? <Enter>           → default No
# 14. Continue?    y
printf "\nSE\n\n\nTest Org\n\nserver.example.com\n\n\n\n2048\nPKCS1-V1.5\n\ny\n" \
    | "${NANOCA}" req "${SRV_KEY}" "${SRV_CSR}" 2>/dev/null 1>/dev/null
_rc=$?
check_rc "req machine (new key) exits 0" 0 ${_rc}
check_file "${SRV_KEY}" "req machine: key file created"
check_file "${SRV_CSR}" "req machine: CSR file created"

"${OPENSSL}" req -verify -noout -in "${SRV_CSR}" &>/dev/null
check_rc "req machine: CSR signature is valid" 0 $?

"${OPENSSL}" req -noout -subject -in "${SRV_CSR}" 2>/dev/null \
    | grep -q "server.example.com"
check_rc "req machine: subject contains CN" 0 $?

"${OPENSSL}" req -noout -text -in "${SRV_CSR}" 2>/dev/null \
    | grep -q "DNS:server.example.com"
check_rc "req machine: CSR has SAN DNS:server.example.com" 0 $?

"${OPENSSL}" req -noout -text -in "${SRV_CSR}" 2>/dev/null \
    | grep -q "TLS Web Server Authentication"
check_rc "req machine: CSR has serverAuth EKU" 0 $?

"${OPENSSL}" rsa -in "${SRV_KEY}" -text -noout 2>/dev/null \
    | grep -q "2048 bit"
check_rc "req machine: key is 2048 bits" 0 $?

# ---------------------------------------------------------------------------
# Section: req — machine certificate (existing key, extra SAN, client auth)
# ---------------------------------------------------------------------------
section "req — machine certificate (existing key)"

SRV2_CSR="${WORKDIR}/server2.csr"

# Existing key → keysize and pass-phrase prompts are skipped.
#  1. req type:   <Enter>              → machine
#  2-6. subject:  SE, empty×4
#  7. CN:         server2.example.com
#  8. server auth? <Enter>             → Yes
#  9. client auth? y                   → Yes
# 10. SAN list:   10.0.0.1            → extra IP SAN
# 11. sig scheme: PKCS1-V1.5         → explicit (no default in pipe mode)
# 12. Continue?   y
printf "\nSE\n\n\n\n\nserver2.example.com\n\ny\n10.0.0.1\nPKCS1-V1.5\ny\n" \
    | "${NANOCA}" req "${SRV_KEY}" "${SRV2_CSR}" &>/dev/null
_rc=$?
check_rc "req machine (existing key) exits 0" 0 ${_rc}
check_file "${SRV2_CSR}" "req machine existing key: CSR created"

"${OPENSSL}" req -verify -noout -in "${SRV2_CSR}" &>/dev/null
check_rc "req machine existing key: CSR signature is valid" 0 $?

"${OPENSSL}" req -noout -text -in "${SRV2_CSR}" 2>/dev/null \
    | grep -q "IP Address:10.0.0.1"
check_rc "req machine existing key: CSR has IP SAN" 0 $?

"${OPENSSL}" req -noout -text -in "${SRV2_CSR}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "req machine existing key: CSR has clientAuth EKU" 0 $?

# ---------------------------------------------------------------------------
# Section: req — machine certificate (empty CN, SAN only)
# ---------------------------------------------------------------------------
section "req — machine certificate (empty CN, SAN only)"

SAN_ONLY_KEY="${WORKDIR}/sanonly.key"
SAN_ONLY_CSR="${WORKDIR}/sanonly.csr"

# All subject fields empty (including CN); SAN provided explicitly.
#  1.  req type:    <Enter>  → machine
#  2-7. subject:    empty×6
#  8.  server auth? <Enter>  → Yes (san_str stays empty because CN is empty)
#  9.  client auth? <Enter>  → No
# 10.  SAN:         server3.example.com
# 11.  keysize:     2048
# 12.  sig scheme:  PKCS1-V1.5        → explicit
# 13.  pass phrase? <Enter>  → No
# 14.  Continue?    y
printf "\n\n\n\n\n\n\n\n\nserver3.example.com\n2048\nPKCS1-V1.5\n\ny\n" \
    | "${NANOCA}" req "${SAN_ONLY_KEY}" "${SAN_ONLY_CSR}" &>/dev/null
_rc=$?
check_rc "req machine (SAN-only, empty CN) exits 0" 0 ${_rc}
check_file "${SAN_ONLY_CSR}" "req SAN-only: CSR file created"

"${OPENSSL}" req -verify -noout -in "${SAN_ONLY_CSR}" &>/dev/null
check_rc "req SAN-only: CSR signature is valid" 0 $?

"${OPENSSL}" req -noout -text -in "${SAN_ONLY_CSR}" 2>/dev/null \
    | grep -q "DNS:server3.example.com"
check_rc "req SAN-only: CSR has correct SAN" 0 $?

# ---------------------------------------------------------------------------
# Section: req — personal certificate
# ---------------------------------------------------------------------------
section "req — personal certificate"

PERS_KEY="${WORKDIR}/personal.key"
PERS_CSR="${WORKDIR}/personal.csr"

# Personal cert; CN must be sent explicitly (readline -i default is not
# active when stdin is a pipe).
#  1.  req type:   2             → personal
#  2.  C:          SE
#  3-6. ST/L/O/OU: empty×4
#  7.  GN:         John
#  8.  SN:         Doe
#  9.  CN:         John Doe      (sent explicitly)
# 10.  email:      john@example.com
# 11.  SAN email?  <Enter>       → default Yes
# 12.  UPN:        <Enter>       → empty
# 13.  UID:        johndoe
# 14.  keysize:    2048
# 15.  sig scheme: PKCS1-V1.5    → explicit
# 16.  pass phrase? <Enter>      → No
# 17.  Continue?   y
printf "2\nSE\n\n\n\n\nJohn\nDoe\nJohn Doe\njohn@example.com\n\n\njohndoe\n2048\nPKCS1-V1.5\n\ny\n" \
    | "${NANOCA}" req "${PERS_KEY}" "${PERS_CSR}" &>/dev/null
_rc=$?
check_rc "req personal cert exits 0" 0 ${_rc}
check_file "${PERS_KEY}" "req personal: key file created"
check_file "${PERS_CSR}" "req personal: CSR file created"

"${OPENSSL}" req -verify -noout -in "${PERS_CSR}" &>/dev/null
check_rc "req personal: CSR signature is valid" 0 $?

"${OPENSSL}" req -noout -subject -in "${PERS_CSR}" 2>/dev/null \
    | grep -q "John Doe"
check_rc "req personal: subject contains CN=John Doe" 0 $?

"${OPENSSL}" req -noout -text -in "${PERS_CSR}" 2>/dev/null \
    | grep -q "email:john@example.com"
check_rc "req personal: email SAN present" 0 $?

"${OPENSSL}" req -noout -text -in "${PERS_CSR}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "req personal: clientAuth EKU present" 0 $?

# ---------------------------------------------------------------------------
# Section: req — error cases
# ---------------------------------------------------------------------------
section "req — error cases"

run "${NANOCA}" req "${WORKDIR}" "${WORKDIR}/bad.csr"
check_rc "req with directory as KEY exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "req directory as KEY: error printed"

run "${NANOCA}" req "${WORKDIR}/dummy.key" "${WORKDIR}"
check_rc "req with directory as CSR exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "req directory as CSR: error printed"

# ---------------------------------------------------------------------------
# Section: sign — non-interactive (--yes)
# ---------------------------------------------------------------------------
section "sign — non-interactive (--yes)"

SRV_CRT="${WORKDIR}/server.crt"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${SRV_CSR}" "${SRV_CRT}"
check_rc "sign --yes exits 0" 0 ${_rc}
check_output "${_out}" "successfully created" "sign: success message printed"
check_file "${SRV_CRT}" "sign: certificate file created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${SRV_CRT}" &>/dev/null
check_rc "sign: certificate is valid and signed by CA" 0 $?

check_file "${CADIR}/csrs/01.csr" "sign: CSR cached as 01.csr"
check_file "${CADIR}/crts/01.pem" "sign: cert stored as 01.pem"

"${OPENSSL}" x509 -noout -text -in "${SRV_CRT}" 2>/dev/null \
    | grep -q "CA:FALSE"
check_rc "sign: issued cert has CA:FALSE" 0 $?

"${OPENSSL}" x509 -noout -text -in "${SRV_CRT}" 2>/dev/null \
    | grep -q "server.example.com"
check_rc "sign: cert contains expected CN/SAN" 0 $?

# ---------------------------------------------------------------------------
# Section: sign — default CRT output path
# ---------------------------------------------------------------------------
section "sign — default CRT output path (no CRT argument)"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${SRV2_CSR}"
check_rc "sign with default CRT path exits 0" 0 ${_rc}
check_file "${WORKDIR}/server2.crt" "sign: default CRT file created (.csr→.crt)"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" \
    "${WORKDIR}/server2.crt" &>/dev/null
check_rc "sign default path: cert is valid" 0 $?

# ---------------------------------------------------------------------------
# Section: sign — SAN-only CSR (empty subject, CN synthesized from SAN)
# ---------------------------------------------------------------------------
section "sign — SAN-only CSR (subject synthesized from first SAN)"

SAN_ONLY_CRT="${WORKDIR}/sanonly.crt"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${SAN_ONLY_CSR}" "${SAN_ONLY_CRT}"
check_rc "sign SAN-only CSR exits 0" 0 ${_rc}
check_file "${SAN_ONLY_CRT}" "sign SAN-only: certificate created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${SAN_ONLY_CRT}" &>/dev/null
check_rc "sign SAN-only: certificate is valid" 0 $?

"${OPENSSL}" x509 -noout -subject -in "${SAN_ONLY_CRT}" 2>/dev/null \
    | grep -q "server3.example.com"
check_rc "sign SAN-only: CN synthesized from first SAN" 0 $?

# ---------------------------------------------------------------------------
# Section: sign — personal certificate
# ---------------------------------------------------------------------------
section "sign — personal certificate"

PERS_CRT="${WORKDIR}/personal.crt"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${PERS_CSR}" "${PERS_CRT}"
check_rc "sign personal cert exits 0" 0 ${_rc}
check_file "${PERS_CRT}" "sign personal: certificate created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${PERS_CRT}" &>/dev/null
check_rc "sign personal: certificate is valid" 0 $?

"${OPENSSL}" x509 -noout -subject -in "${PERS_CRT}" 2>/dev/null \
    | grep -q "John Doe"
check_rc "sign personal: cert subject contains CN=John Doe" 0 $?

# ---------------------------------------------------------------------------
# Section: sign — interactive mode (without --yes)
# ---------------------------------------------------------------------------
section "sign — interactive mode"

INTER_CRT="${WORKDIR}/server-interactive.crt"

# Input: RSA sig scheme (explicit); Continue? y
printf "PKCS1-V1.5\ny\n" \
    | "${NANOCA}" --dir="${CADIR}" sign "${SRV_CSR}" "${INTER_CRT}" &>/dev/null
_rc=$?
check_rc "sign interactive exits 0" 0 ${_rc}
check_file "${INTER_CRT}" "sign interactive: certificate created"

# Overwrite existing output file: sig scheme; Continue? y; Overwrite? y
printf "PKCS1-V1.5\ny\ny\n" \
    | "${NANOCA}" --dir="${CADIR}" sign "${SRV_CSR}" "${INTER_CRT}" &>/dev/null
_rc=$?
check_rc "sign interactive overwrite exits 0" 0 ${_rc}

# Decline overwrite: sig scheme; Continue? y; Overwrite? n → rc=1
INTER_CRT2="${WORKDIR}/server-interactive2.crt"
cp "${INTER_CRT}" "${INTER_CRT2}"
printf "PKCS1-V1.5\ny\nn\n" \
    | "${NANOCA}" --dir="${CADIR}" sign "${SRV_CSR}" "${INTER_CRT2}" &>/dev/null
_rc=$?
check_rc "sign interactive decline overwrite exits non-zero" 1 ${_rc}

# ---------------------------------------------------------------------------
# Section: sign — error cases
# ---------------------------------------------------------------------------
section "sign — error cases"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${SRV_CRT}"
check_rc "sign with .crt file (wrong extension) exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "sign wrong extension: error message printed"

run "${NANOCA}" --yes --dir="${CADIR}" sign "${WORKDIR}/nosuch.csr"
check_rc "sign with non-existent CSR exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "sign non-existent CSR: error message printed"

echo "not a csr" > "${WORKDIR}/fake.csr"
run "${NANOCA}" --yes --dir="${CADIR}" sign "${WORKDIR}/fake.csr"
check_rc "sign with invalid CSR content exits non-zero" 1 ${_rc}

# ---------------------------------------------------------------------------
# Section: sign — CRL Distribution Point URL embedded in signed certificate
# ---------------------------------------------------------------------------
section "sign — CRL Distribution Point URL"

CACRL="${TMPDIR_BASE}/cacrl"
mkdir -p "${CACRL}"
CRL_URL="http://crl.example.com/test-ca-crl.crl"

_out=$(CA_CN="CRL CA" CA_O="Test Org" CA_C="SE" CA_CRL_URL="${CRL_URL}" \
       "${NANOCA}" --yes --dir="${CACRL}" create 2>&1)
_rc=$?
check_rc "create CA with CRL URL exits 0" 0 ${_rc}

grep -q "${CRL_URL}" "${CACRL}/private/settings.cfg"
check_rc "CRL URL persisted in settings.cfg" 0 $?

CACRL_STEM=$(ls "${CACRL}/private/"*.key 2>/dev/null | head -1 | xargs -r basename | sed 's/\.key$//')
check_file "${CACRL}/public/${CACRL_STEM}.crt" "create CRL CA: cert file exists"

CACRL_CRT="${WORKDIR}/crl-signed.crt"
run "${NANOCA}" --yes --dir="${CACRL}" sign "${SRV_CSR}" "${CACRL_CRT}"
check_rc "sign with CRL CA exits 0" 0 ${_rc}
check_file "${CACRL_CRT}" "sign CRL CA: certificate created"

"${OPENSSL}" x509 -noout -text -in "${CACRL_CRT}" 2>/dev/null \
    | grep -q "crl.example.com"
check_rc "sign: CRL Distribution Point URL embedded in signed cert" 0 $?

# A CA without CRL URL must NOT embed the extension
if "${OPENSSL}" x509 -noout -text -in "${SRV_CRT}" 2>/dev/null \
        | grep -q "CRL Distribution"; then
    fail "sign (no CRL URL): cert must not have CRL Distribution Point"
else
    ok "sign (no CRL URL): cert has no CRL Distribution Point"
fi

# ---------------------------------------------------------------------------
# Section: sign — --client-auth option
# ---------------------------------------------------------------------------
section "sign — --client-auth option"

# Create a CSR with no EKU directly via openssl (no KU/EKU extensions at all)
NO_EKU_KEY="${WORKDIR}/noeku.key"
NO_EKU_CSR="${WORKDIR}/noeku.csr"
${OPENSSL} req -new -nodes -newkey rsa:2048 -keyout "${NO_EKU_KEY}" \
    -subj "/CN=noeku.example.com" -out "${NO_EKU_CSR}" 2>/dev/null

# 1. serverAuth-only CSR: --client-auth adds clientAuth and preserves serverAuth
CA_AUTH_CRT="${WORKDIR}/server-client-auth.crt"
run "${NANOCA}" --yes --client-auth --dir="${CADIR}" sign "${SRV_CSR}" "${CA_AUTH_CRT}"
check_rc "--client-auth sign exits 0" 0 ${_rc}
check_file "${CA_AUTH_CRT}" "--client-auth: certificate created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${CA_AUTH_CRT}" &>/dev/null
check_rc "--client-auth: certificate valid and signed by CA" 0 $?

"${OPENSSL}" x509 -noout -text -in "${CA_AUTH_CRT}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "--client-auth: clientAuth added to cert with serverAuth-only CSR" 0 $?

"${OPENSSL}" x509 -noout -text -in "${CA_AUTH_CRT}" 2>/dev/null \
    | grep -q "TLS Web Server Authentication"
check_rc "--client-auth: serverAuth preserved in cert with serverAuth-only CSR" 0 $?

# 2. -c short form works identically
CA_SHORT_CRT="${WORKDIR}/server-short-c.crt"
run "${NANOCA}" --yes -c --dir="${CADIR}" sign "${SRV_CSR}" "${CA_SHORT_CRT}"
check_rc "-c short form exits 0" 0 ${_rc}

"${OPENSSL}" x509 -noout -text -in "${CA_SHORT_CRT}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "-c short form: clientAuth present in signed cert" 0 $?

# 3. CSR that already has clientAuth: --client-auth is idempotent (not duplicated)
CA_IDEMPOTENT_CRT="${WORKDIR}/pers-client-auth.crt"
run "${NANOCA}" --yes --client-auth --dir="${CADIR}" sign "${PERS_CSR}" "${CA_IDEMPOTENT_CRT}"
check_rc "--client-auth on CSR already with clientAuth exits 0" 0 ${_rc}

"${OPENSSL}" x509 -noout -text -in "${CA_IDEMPOTENT_CRT}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "--client-auth idempotent: clientAuth still present" 0 $?

eku_count=$("${OPENSSL}" x509 -noout -text -in "${CA_IDEMPOTENT_CRT}" 2>/dev/null \
    | grep -c "TLS Web Client Authentication" || true)
[[ "${eku_count}" -eq 1 ]] \
    && ok "--client-auth idempotent: clientAuth not duplicated" \
    || fail "--client-auth idempotent: clientAuth not duplicated" "count=${eku_count}"

# 4. No-EKU CSR: --client-auth adds clientAuth from nothing
NO_EKU_CRT="${WORKDIR}/noeku.crt"
run "${NANOCA}" --yes --client-auth --dir="${CADIR}" sign "${NO_EKU_CSR}" "${NO_EKU_CRT}"
check_rc "--client-auth on no-EKU CSR exits 0" 0 ${_rc}
check_file "${NO_EKU_CRT}" "--client-auth no-EKU: certificate created"

"${OPENSSL}" x509 -noout -text -in "${NO_EKU_CRT}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "--client-auth no-EKU: clientAuth added to cert from CSR with no EKU" 0 $?

# 5. Control: without --client-auth, a serverAuth-only CSR stays serverAuth-only
NO_FLAG_CRT="${WORKDIR}/server-no-flag.crt"
run "${NANOCA}" --yes --dir="${CADIR}" sign "${SRV_CSR}" "${NO_FLAG_CRT}"
check_rc "sign without --client-auth exits 0" 0 ${_rc}

if "${OPENSSL}" x509 -noout -text -in "${NO_FLAG_CRT}" 2>/dev/null \
        | grep -q "TLS Web Client Authentication"; then
    fail "sign without --client-auth: clientAuth must NOT be present"
else
    ok "sign without --client-auth: clientAuth absent from cert (as expected)"
fi

# 6. re-sign with --client-auth: cached SAN-only CSR (serverAuth only) gets clientAuth added
CLIENT_AUTH_RESIGN_SERIAL=$(awk -F'\t' 'NR==3{print $4}' "${CADIR}/private/crtdb")
CA_RESIGN_AUTH_CRT="${WORKDIR}/sanonly-client-auth.crt"
run "${NANOCA}" --yes --client-auth --dir="${CADIR}" re-sign "${CLIENT_AUTH_RESIGN_SERIAL}" "${CA_RESIGN_AUTH_CRT}"
check_rc "--client-auth re-sign exits 0" 0 ${_rc}
check_file "${CA_RESIGN_AUTH_CRT}" "--client-auth re-sign: certificate created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${CA_RESIGN_AUTH_CRT}" &>/dev/null
check_rc "--client-auth re-sign: certificate valid and signed by CA" 0 $?

"${OPENSSL}" x509 -noout -text -in "${CA_RESIGN_AUTH_CRT}" 2>/dev/null \
    | grep -q "TLS Web Client Authentication"
check_rc "--client-auth re-sign: clientAuth added to re-signed cert" 0 $?

# ---------------------------------------------------------------------------
# Section: list — with certificates
# ---------------------------------------------------------------------------
section "list — with certificates"

run "${NANOCA}" --dir="${CADIR}" list
check_rc "list with certs exits 0" 0 ${_rc}
check_output "${_out}" "^V" "list: shows valid (V) certificates"

count=$(echo "${_out}" | grep -c "^V" || true)
[[ "${count}" -ge 4 ]] \
    && ok "list: at least 4 valid certificates shown (got ${count})" \
    || fail "list: at least 4 valid certificates shown" "got ${count}"

# ---------------------------------------------------------------------------
# Section: recreate-crl
# ---------------------------------------------------------------------------
section "recreate-crl"

run "${NANOCA}" --dir="${CADIR}" recreate-crl
check_rc "recreate-crl exits 0" 0 ${_rc}
check_output "${_out}" "refreshed" "recreate-crl: success message printed"
check_file "${CADIR}/public/${CA_STEM}.crl" "recreate-crl: CRL file created"

"${OPENSSL}" crl -in "${CADIR}/public/${CA_STEM}.crl" -noout 2>/dev/null
check_rc "recreate-crl: CRL is a valid PEM CRL" 0 $?

"${OPENSSL}" crl -in "${CADIR}/public/${CA_STEM}.crl" \
    -CAfile "${CADIR}/public/${CA_STEM}.crt" -noout 2>/dev/null
check_rc "recreate-crl: CRL signature verifies against CA cert" 0 $?

# CRL must not list any revoked certs yet (none revoked so far)
"${OPENSSL}" crl -in "${CADIR}/public/${CA_STEM}.crl" -text -noout 2>/dev/null \
    | grep -q "No Revoked Certificates"
check_rc "recreate-crl: CRL has no revoked certs yet" 0 $?

# ---------------------------------------------------------------------------
# Section: revoke
# ---------------------------------------------------------------------------
section "revoke"

SERIAL_01=$(awk -F'\t' 'NR==1{print $4}' "${CADIR}/private/crtdb")

run "${NANOCA}" --dir="${CADIR}" revoke "${SERIAL_01}"
check_rc "revoke exits 0" 0 ${_rc}
check_output "${_out}" "revoked" "revoke: success message printed"

state=$(awk -F'\t' -v s="${SERIAL_01}" '$4==s{print $1}' "${CADIR}/private/crtdb")
[[ "${state}" == "R" ]] \
    && ok "revoke: certificate marked R in crtdb" \
    || fail "revoke: certificate marked R in crtdb" "state='${state}'"

run "${NANOCA}" --dir="${CADIR}" revoke "99"
check_rc "revoke non-existent serial exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "revoke non-existent serial: error message printed"

# Revoke a second cert for CRL verification
SERIAL_02=$(awk -F'\t' 'NR==2{print $4}' "${CADIR}/private/crtdb")
run "${NANOCA}" --dir="${CADIR}" revoke "${SERIAL_02}"
check_rc "revoke second certificate exits 0" 0 ${_rc}

# ---------------------------------------------------------------------------
# Section: recreate-crl after revoke
# ---------------------------------------------------------------------------
section "recreate-crl after revoke"

run "${NANOCA}" --dir="${CADIR}" recreate-crl
check_rc "recreate-crl after revoke exits 0" 0 ${_rc}

"${OPENSSL}" crl -in "${CADIR}/public/${CA_STEM}.crl" -text -noout 2>/dev/null \
    | grep -q "Revoked Certificates"
check_rc "CRL contains 'Revoked Certificates' section" 0 $?

"${OPENSSL}" crl -in "${CADIR}/public/${CA_STEM}.crl" -text -noout 2>/dev/null \
    | grep -qi "serial"
check_rc "CRL contains serial numbers of revoked certs" 0 $?

# ---------------------------------------------------------------------------
# Section: list — after revoke
# ---------------------------------------------------------------------------
section "list — after revoke"

run "${NANOCA}" --dir="${CADIR}" list
check_rc "list after revoke exits 0" 0 ${_rc}
check_output "${_out}" "^R" "list: shows revoked (R) certificate"
check_output "${_out}" "^V" "list: still shows valid (V) certificates"

# ---------------------------------------------------------------------------
# Section: re-sign
# ---------------------------------------------------------------------------
section "re-sign"

# Use serial of the third cert (SAN-only) which is still valid
SERIAL_03=$(awk -F'\t' 'NR==3{print $4}' "${CADIR}/private/crtdb")
RESIGN_CRT="${WORKDIR}/sanonly-renewed.crt"

run "${NANOCA}" --yes --dir="${CADIR}" re-sign "${SERIAL_03}" "${RESIGN_CRT}"
check_rc "re-sign exits 0" 0 ${_rc}
check_output "${_out}" "successfully created" "re-sign: success message printed"
check_file "${RESIGN_CRT}" "re-sign: new certificate created"

"${OPENSSL}" verify -CAfile "${CADIR}/public/test-ca.crt" "${RESIGN_CRT}" &>/dev/null
check_rc "re-sign: new certificate is valid" 0 $?

new_serial=$("${OPENSSL}" x509 -noout -serial -in "${RESIGN_CRT}" 2>/dev/null \
             | sed 's/serial=//')
orig_serial=$("${OPENSSL}" x509 -noout -serial -in "${SAN_ONLY_CRT}" 2>/dev/null \
              | sed 's/serial=//')
[[ "${new_serial}" != "${orig_serial}" ]] \
    && ok "re-sign: new cert has different serial than original" \
    || fail "re-sign: new cert has different serial than original"

# --yes is non-interactive; re-sign to same output should succeed
run "${NANOCA}" --yes --dir="${CADIR}" re-sign "${SERIAL_03}" "${RESIGN_CRT}"
check_rc "re-sign --yes overwrites existing CRT without prompt" 0 ${_rc}

# error: missing output CRT argument
run "${NANOCA}" --yes --dir="${CADIR}" re-sign "${SERIAL_03}"
check_rc "re-sign without output filename exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "re-sign without output: error message printed"

# error: non-existent serial (no cached CSR)
run "${NANOCA}" --yes --dir="${CADIR}" re-sign "99" "${WORKDIR}/nosuch.crt"
check_rc "re-sign with non-existent serial exits non-zero" 1 ${_rc}

# ---------------------------------------------------------------------------
# Section: --dir option forms
# ---------------------------------------------------------------------------
section "--dir option forms"

run "${NANOCA}" -d "${CADIR}" list
check_rc "-d CADIR form works" 0 ${_rc}

run "${NANOCA}" --dir "${CADIR}" list
check_rc "--dir CADIR form works" 0 ${_rc}

run "${NANOCA}" --dir="${CADIR}" list
check_rc "--dir=CADIR form works" 0 ${_rc}

# From within the CA directory, no --dir needed
(cd "${CADIR}" && "${NANOCA}" list &>/dev/null)
check_rc "list from CA cwd (no --dir) works" 0 $?

run "${NANOCA}" --dir="${TMPDIR_BASE}/invalid" list
check_rc "non-CA dir exits non-zero" 1 ${_rc}
check_output "${_out}" "[Ee]rror" "non-CA dir: error message printed"

EMPTYDIR="${TMPDIR_BASE}/empty2"
mkdir -p "${EMPTYDIR}"
run "${NANOCA}" --dir="${EMPTYDIR}" list
check_rc "empty dir (not a CA) exits non-zero" 1 ${_rc}

# ---------------------------------------------------------------------------
# Section: CA directory with spaces in path
# ---------------------------------------------------------------------------
section "CA directory with spaces in path"

SPACEDIR="${TMPDIR_BASE}/my ca dir"
mkdir -p "${SPACEDIR}"

_out=$(CA_CN="Space CA" CA_O="Test Org" CA_C="SE" \
       "${NANOCA}" --yes --dir="${SPACEDIR}" create 2>&1)
_rc=$?
check_rc "create in dir with spaces exits 0" 0 ${_rc}
check_output "${_out}" "successfully created" "create with spaces: success message printed"

SPACE_KEY=$(ls "${SPACEDIR}/private/"*.key 2>/dev/null | head -1)
SPACE_STEM=$(basename "${SPACE_KEY}" .key)
check_file "${SPACEDIR}/private/${SPACE_STEM}.key" "create with spaces: key file created"
check_file "${SPACEDIR}/public/${SPACE_STEM}.crt"  "create with spaces: cert file created"

"${OPENSSL}" verify -CAfile "${SPACEDIR}/public/${SPACE_STEM}.crt" \
    "${SPACEDIR}/public/${SPACE_STEM}.crt" &>/dev/null
check_rc "create with spaces: CA cert is self-signed and valid" 0 $?

SPACE_CRT="${WORKDIR}/space-signed.crt"
run "${NANOCA}" --yes --dir="${SPACEDIR}" sign "${SRV_CSR}" "${SPACE_CRT}"
check_rc "sign with spaces in CA dir exits 0" 0 ${_rc}
check_file "${SPACE_CRT}" "sign with spaces: certificate created"

"${OPENSSL}" verify -CAfile "${SPACEDIR}/public/${SPACE_STEM}.crt" "${SPACE_CRT}" &>/dev/null
check_rc "sign with spaces: certificate is valid and signed by CA" 0 $?

SPACE_SERIAL=$(awk -F'\t' 'NR==1{print $4}' "${SPACEDIR}/private/crtdb")
run "${NANOCA}" --dir="${SPACEDIR}" revoke "${SPACE_SERIAL}"
check_rc "revoke with spaces in CA dir exits 0" 0 ${_rc}

run "${NANOCA}" --dir="${SPACEDIR}" recreate-crl
check_rc "recreate-crl with spaces in CA dir exits 0" 0 ${_rc}
check_file "${SPACEDIR}/public/${SPACE_STEM}.crl" "recreate-crl with spaces: CRL file created"

"${OPENSSL}" crl -in "${SPACEDIR}/public/${SPACE_STEM}.crl" \
    -CAfile "${SPACEDIR}/public/${SPACE_STEM}.crt" -noout &>/dev/null
check_rc "recreate-crl with spaces: CRL signature verifies against CA cert" 0 $?

# ---------------------------------------------------------------------------
# Section: purge
# ---------------------------------------------------------------------------
section "purge"

# No expired certs yet — should be silent
run "${NANOCA}" --yes --dir="${CADIR}" purge
check_rc "purge on CA with no expired certs exits 0" 0 ${_rc}
[[ -z "${_out}" ]] \
    && ok "purge: no output when no expired certs exist" \
    || fail "purge: no output when no expired certs exist" "got '${_out}'"

# Create an expired certificate using openssl directly, plus a matching cached CSR
EXPIRED_KEY="${TMPDIR_BASE}/expired.key"
EXPIRED_CSR="${TMPDIR_BASE}/expired.csr"
EXPIRED_PEM="${CADIR}/crts/FE.pem"
EXPIRED_CACHED_CSR="${CADIR}/csrs/FE.csr"

${OPENSSL} req -new -nodes -newkey rsa:2048 -keyout "${EXPIRED_KEY}" \
    -subj "/CN=expired-test" -out "${EXPIRED_CSR}" 2>/dev/null
${OPENSSL} x509 -req -in "${EXPIRED_CSR}" \
    -signkey "${EXPIRED_KEY}" \
    -not_before 20200101000000Z \
    -not_after 20200102000000Z \
    -out "${EXPIRED_PEM}" 2>/dev/null
cp "${EXPIRED_CSR}" "${EXPIRED_CACHED_CSR}"
printf "V\t200102000000Z\t\tFE\tunknown\t/CN=expired-test\n" >> "${CADIR}/private/crtdb"

check_file "${EXPIRED_PEM}"        "purge setup: expired cert placed in crts/"
check_file "${EXPIRED_CACHED_CSR}" "purge setup: cached CSR placed in csrs/"
grep -q $'\tFE\t' "${CADIR}/private/crtdb"
check_rc "purge setup: FE entry present in crtdb" 0 $?

"${OPENSSL}" x509 -checkend 0 -noout -in "${EXPIRED_PEM}" 2>/dev/null && _expired_rc=0 || _expired_rc=$?
check_rc "purge setup: cert is indeed expired (checkend 0 non-zero)" 1 ${_expired_rc}

# Purge with --yes should remove cert, cached CSR and crtdb entry silently
run "${NANOCA}" --yes --dir="${CADIR}" purge
check_rc "purge --yes exits 0" 0 ${_rc}
[[ -z "${_out}" ]] \
    && ok "purge --yes: no output (silent removal)" \
    || fail "purge --yes: no output (silent removal)" "got '${_out}'"
[[ ! -f "${EXPIRED_PEM}" ]] \
    && ok "purge --yes: expired cert removed from crts/" \
    || fail "purge --yes: expired cert removed from crts/" "file still exists"
[[ ! -f "${EXPIRED_CACHED_CSR}" ]] \
    && ok "purge --yes: cached CSR removed from csrs/" \
    || fail "purge --yes: cached CSR removed from csrs/" "file still exists"
check_file "${CADIR}/private/crtdb.old" "purge --yes: crtdb.old backup created"
if grep -q $'\tFE\t' "${CADIR}/private/crtdb" 2>/dev/null ; then
    fail "purge --yes: FE entry removed from crtdb"
else
    ok "purge --yes: FE entry removed from crtdb"
fi
grep -q $'\t01\t' "${CADIR}/private/crtdb"
check_rc "purge --yes: valid entries remain in crtdb" 0 $?

# Running purge again when clean should also be silent
run "${NANOCA}" --yes --dir="${CADIR}" purge
check_rc "purge after clean exits 0" 0 ${_rc}
[[ -z "${_out}" ]] \
    && ok "purge after clean: silent when nothing to remove" \
    || fail "purge after clean: silent when nothing to remove" "got '${_out}'"

# Interactive purge: confirm with y → should show found + subjects, then remove both files
${OPENSSL} x509 -req -in "${EXPIRED_CSR}" \
    -signkey "${EXPIRED_KEY}" \
    -not_before 20200101000000Z \
    -not_after 20200102000000Z \
    -out "${EXPIRED_PEM}" 2>/dev/null
cp "${EXPIRED_CSR}" "${EXPIRED_CACHED_CSR}"

_out=$(printf "y\n" | "${NANOCA}" --dir="${CADIR}" purge 2>&1)
_rc=$?
check_rc "purge interactive (confirm y) exits 0" 0 ${_rc}
check_output "${_out}" "Found.*expired" "purge interactive: prints Found header"
check_output "${_out}" "expired-test" "purge interactive: lists expired cert subject"
[[ ! -f "${EXPIRED_PEM}" ]] \
    && ok "purge interactive confirm: expired cert removed" \
    || fail "purge interactive confirm: expired cert removed" "file still exists"
[[ ! -f "${EXPIRED_CACHED_CSR}" ]] \
    && ok "purge interactive confirm: cached CSR removed" \
    || fail "purge interactive confirm: cached CSR removed" "file still exists"

# Interactive purge: decline with n → should NOT remove
${OPENSSL} x509 -req -in "${EXPIRED_CSR}" \
    -signkey "${EXPIRED_KEY}" \
    -not_before 20200101000000Z \
    -not_after 20200102000000Z \
    -out "${EXPIRED_PEM}" 2>/dev/null

_out=$(printf "n\n" | "${NANOCA}" --dir="${CADIR}" purge 2>&1)
_rc=$?
check_rc "purge interactive (decline n) exits 0" 0 ${_rc}
check_output "${_out}" "Found.*expired" "purge interactive decline: still prints Found header"
[[ -f "${EXPIRED_PEM}" ]] \
    && ok "purge interactive decline: expired cert NOT removed" \
    || fail "purge interactive decline: expired cert NOT removed" "file was deleted"

rm -f "${EXPIRED_PEM}"

# Valid certs must survive a purge
valid_count=$(ls "${CADIR}/crts/"*.pem 2>/dev/null | wc -l)
[[ "${valid_count}" -ge 4 ]] \
    && ok "purge: valid certs untouched (${valid_count} remaining)" \
    || fail "purge: valid certs untouched" "only ${valid_count} remain"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==================================="

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
