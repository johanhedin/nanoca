nanoca
====
`nanoca` is a script that implement functions for a small file based X.509
Certificate Authority, CA.

It can create new CAs, create CSRs, sign CSRs, revoke certificates and create
CRLs for the CAs.

A CA is represented by files in a directory and creating a new CA is as simple
as creating a empty directory and run the create command (parameters for
the CA will be asked for interactively):

    $ mkdir myca
    $ cd myca
    $ nanoca create

Since a CA is fully contained in a directory, it is possible to have as many
CAs as needed by just using different directories.

To use a specific CA, cd into the relevant directory and run the desired
command, for example list certificates that the CA has created:

    $ cd myca
    $ nanoca list

For instructions how to use `nanoca`, use `--help`:

    $ nanoca --help


Some terminology
====
* CA - Certificate Authority.
* CSR - Certificate Signing Request.
* CRL - Certificate Revokation List.
* Signing - The process where a CA creates a new certificate by signing a CSR.
* Revoking - The process where a CA marks a previously created certificate as revoked (CA internal operation).


X.509 References
====
* [RFC 5280](https://tools.ietf.org/html/rfc5280)


Requirements
====
`nanoca` is written in bash and uses openssl, awk, ls and wc. It is tested on
CentOS 6, 7, and 8, Fedora 32 and Rasbian Buster but should run on almost any
Linux distribution that has openssl available.
