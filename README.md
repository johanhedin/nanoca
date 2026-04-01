# nanoca
`nanoca` is a bash script implementing a small file based X.509
Certificate Authority, CA, that can be used on a home or private network.

It can create CAs, create CSRs, sign CSRs, revoke certificates, and create
CRLs. It supports creating CSRs using PKCS11-enabled hardware tokens
(like smart cards) if the underlying `openssl` library supports
pkcs11_engine and uses p11-kit.

A CA is represented by files in a directory and creating a new CA is as simple
as creating an empty directory and running the `create` command (CA parameters
will be prompted interactively):

```console
mkdir myca
cd myca
nanoca create
```

Since a CA is fully contained in a directory you can maintain as many CAs
as needed, each in its own directory.

To use a specific CA, cd into the relevant directory and run the desired
command, for example `list` to list certificates that the CA has created:

```console
cd myca
nanoca list
```

For instructions how to use `nanoca`, use `--help`:

```console
nanoca --help
```


## Some terminology
* CA - Certificate Authority
* CSR - Certificate Signing Request. A PEM encoded file representing a request
for a certificate. Created by the requester and sent to the CA for signing
* CRT - Certificate. A PEM encoded certificate file created by a CA by signing
a CSR
* CRL - Certificate Revocation List. A list of revoked certificates. Issued by
a CA to inform the CA users about revoked certificates
* Signing - The process where a CA creates a new certificate by signing a CSR
* Revoking - The process where a CA marks a previously created certificate as
revoked (CA internal operation)


## X.509 related references
* [RFC 5280](https://tools.ietf.org/html/rfc5280)


## Requirements
`nanoca` is written in bash and uses `openssl`, `awk`, `ls`, `cat`, `sed` and `wc`.
It has been tested on CentOS 6, CentOS 7, Rocky 9, Fedora 43, and Raspberry Pi OS,
but should run on almost any Linux distribution that has `openssl >= 1.0.1e`.
