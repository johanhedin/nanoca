# CLAUDE.md
This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.


## What this project is
`nanoca` is a single bash script (`bin/nanoca`) that implements a file-based
X.509 Certificate Authority. The entire CA is represented by files in a
directory. There is no build step — the script runs directly from
`bin/nanoca`.


## Running tests
```bash
make test
```

The test suite creates a temporary directory, exercises all commands, and
cleans up on exit. Tests live in `tests/`.


## Installing
```bash
make install           # installs to /usr/local by default
make install PREFIX=~  # installs to ~/bin, ~/share/man, etc.
make uninstall
```


## Architecture
Everything lives in `bin/nanoca`. Key internal functions:

| Function | Purpose |
|---|---|
| `create_ca()` | Creates a new CA directory structure |
| `create_request()` | Creates a key + CSR (the `req` command) |
| `sign_request()` | Signs a CSR against the CA |
| `revoke_cert()` | Marks a cert as revoked in `crtdb` |
| `recreate_crl()` | Regenerates the CRL file |
| `list_certs()` | Reads `crtdb` and prints a summary |
| `purge_expired_certs()` | Removes expired certs from `crts/`, their cached CSRs from `csrs/`, and their rows from `crtdb`; backs up `crtdb` to `crtdb.old` first |

The script uses a global `openssl_cfg` variable to hold the path to a
temporary OpenSSL config file; `exit_cleanup()` (trapped on EXIT) removes
it.


### CA directory layout
A CA directory contains:
- `private/` — CA key (`<cn-slug>.key`), `crtdb`, `crtserial`, `crlserial`, `settings.cfg`
- `public/` — CA cert (`<cn-slug>.crt`), current CRL
- `crts/` — signed end-entity certificates
- `csrs/` — cached CSRs (used by `re-sign`)

The CN slug is the CN with spaces replaced by hyphens and lowercased.

### openssl x509 -checkend stdout
`openssl x509 -checkend 0` prints "Certificate will expire" / "Certificate will not expire"
to **stdout** even when `-noout` is given. Suppress it with `&>/dev/null`, not just
`2>/dev/null`, or it will leak into captured output.

### Non-interactive / scripted use
`create`, `sign`, and `purge` respect `--yes` / `-y` to skip confirmation prompts.
For `create`, supply subject fields via env vars:

```bash
CA_CN="My CA" CA_O="My Org" CA_C="SE" nanoca --yes --dir=myca create
# Other env vars: CA_RSA_KEYSIZE, CA_RSA_SSA (PKCS1-V1.5 or PSS),
#                 CA_YEARS, CA_SIGNED_CERT_DAYS, CA_CRL_DAYS, CA_CRL_URL
```

For `req`, all prompts must be answered explicitly when stdin is a pipe — `read -e -i`
defaults are **not** applied in non-interactive mode. Always send explicit
values for keysize and signature scheme (see test_nanoca.sh for the exact
input sequence).

### Settings file
`private/settings.cfg` stores per-CA overrides for `CA_SIGNED_CERT_DAYS`,
`CA_CRL_DAYS`, `CA_CRL_URL`, and `CERT_RSA_KEYSIZE`. It is sourced at startup
when a CA directory is loaded. These variables can also be overridden by env
vars at invocation time.
