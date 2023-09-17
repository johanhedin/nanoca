nanoca
====
`nanoca` is a script that implement functions for a small file based X.509
Certificate Authority, CA, that can be used on a home or private network.

It can create CAs, create CSRs, sign CSRs, revoke certificates and create
CRLs. It has support for creating CSRs using PKCS11 enabled hardware tokens
(like smartcards) if the underlying `openssl` installation has support for
pkcs11_engine.

A CA is represented by files in a directory and creating a new CA is as simple
as creating a empty directory and run the `create` command (parameters for
the CA will be asked for interactively):

    $ mkdir myca
    $ cd myca
    $ nanoca create

Since a CA is fully contained in a directory, it is possible to have as many
CAs as needed by using different directories.

To use a specific CA, cd into the relevant directory and run the desired
command, for example `list` to list certificates that the CA has created:

    $ cd myca
    $ nanoca list

For instructions how to use `nanoca`, use `--help`:

    $ nanoca --help


Some terminology
====
* CA - Certificate Authority.
* CSR - Certificate Signing Request. A PEM encoded file representing a request
for a certificate. Created by the requester and sent to the CA for signing.
* CRT - Certificate. A PEM encoded certificate file created by a CA by signing a CSR.
* CRL - Certificate Revocation List. A list of revoked certificates. Issued by
a CA to inform the CA users about revoked certificates.
* Signing - The process where a CA creates a new certificate by signing a CSR.
* Revoking - The process where a CA marks a previously created certificate as
revoked (CA internal operation).


X.509 related references
====
* [RFC 5280](https://tools.ietf.org/html/rfc5280)


Requirements
====
`nanoca` is written in bash and uses `openssl`, `awk`, `ls`, `cat` and `wc`.
It has been tested on CentOS 7, Fedora 33 and Raspberry Pi OS but should run on
almost any Linux distribution that has `openssl >= 1.0.1e`.
