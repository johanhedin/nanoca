nanoca with smart card
====
`nanoca` can create CSRs using RSA keys on smart cards. This document is a short
instruction how to provision a `nanoca` signed certificate on a
[Aventra](https://aventra.fi) MyEID smart card using Fedora 38.

The instruction is mainly based on the two following OpenSC Wiki pages:

* https://github.com/OpenSC/OpenSC/wiki/Aventra-MyEID-PKI-card
* https://github.com/OpenSC/OpenSC/wiki/Card-personalization

Note that the instruction below only cover the simple case with one object
(key/certificate pair) on the token and with only one PIN. More advanced
use cases like multiple PINs, multiple keys and/or multiple certificates are
outside the scope of this instruction.


Prerequisites
====
* Aventra MyEID smart card. Can be ordered from their [web shop](https://webservices.aventra.fi/webshop).
* Supported smart card reader.
* Running Fedora 38 installation.


Software
====
OpenSC and pcsc-lite need to be installed (they are most likely already
installed on your system):

    $ sudo dnf install opensc pcsc-lite

The commands `pkcs15-init`and `pkcs15-tool`used below are included in the
`opensc`package.


CA setup
====
Setup a `nanoca` CA (or use an existing one):

    $ mkdir smartcard_ca
    $ cd smartcard_ca
    $ nanoca create


Initialize the smart card
====
The first step is to initialize the smart card and prepare it for key generation
and certificate provisioning. When it comes to smart cards, it is common to talk
about two roles, "User" and "Security Officer" (or SO for short). The User is
the one using the smart card and the Security Officer is the one handling certain
parts of the provisioning process.

The User and the Security Officer have their own PIN and PUK codes.

So, to start with, come up with one PIN and corresponding unlock code, PUK, for
the User. Write them down somewhere safe or be confident that you remember them.

Then do the same for the Security Officer, one PIN and one PUK.

If you loose the Security Officer PIN, you will not be able to wipe the card and
start over or provision new PINs (basically bricking the the card).

Insert the card into the card reader and make sure that only one card is
active on your computer. Run the following:

    $ pkcs15-init --create-pkcs15 --pin 1234 --puk 1234

Even though no PIN and PUK are created at this stage, they need to be given
as arguments. If not, `pkcs15-init` will ask for PIN indefinitely. The values
given are not used and can be whatever.

You will be asked to enter the Security Officer PIN and SO PUK that should be
used for the card. Enter the values that you came up with previously (note that
the wording for the Security Officer PUK prompt is a bit misleading and talk
about "User", but it is the Security Officer PUK that is requested).

The next step is to create the User PIN and PUK. For smart cards, the PIN is
considered it's own "object". You create a PIN and then references that
PIN when creating key and/or certificate objects. A PIN object is referenced
by a so called "auth id" and we will create auth id 1 here:

    $ pkcs15-init --store-pin --auth-id 1

Enter the values for User PIN and PUK that you came up with previously. Note
that the Security Officer PIN is requested as the last step to complete the
operation.

The card is not yet fully locked and the PINs are not enforced. Finalize
the process with the following command:

    $ pkcs15-init --finalize

The card is now ready to be used. The available "PIN objects" can be listed
with the `pkcs15-tool`:

    $ pkcs15-tool --list-pins


Create a RSA key on the card
====
To create a new RSA key object on the card run the following command:

    $ pkcs15-init --generate-key "rsa:2048" --key-usage digitalSignature,keyEncipherment --auth-id 1 \
                  --public-key-label "My Name"

Replace "My Name" with the name you intend to use as Common Name in the
certificate later on. There is no real requirement for them to match, but it
makes everything much more clear if they do. The `--auth-id 1` argument will
tie this key to the one and only User PIN object that was created in the
initialization step.

To list the key (both the private part and the public part), use:

    $ pkcs15-tool --list-keys --list-public-keys

Note that the actual private key is never printed, just information about it.


Create CSR and signed certificate with nanoca
====
You can now create a CSR using the key on the smart card. Given that only
one key is on the card and that only one card inserted, it is enough to reference
the key with "pkcs11:" (note the : at the end). Use nanoca like this:

    $ nanoca req "pkcs11:" /tmp/my_name.csr

Choose "2 - Request for personal client certificate" and enter the desired
information when asked for. Use "My Name" as Common Name. You will be asked for
the User PIN when the CSR is created because the CSR is signed with your private
key.

When the CSR is ready, you can use `openssl` with the `req` command to look at
it:

    $ openssl req -noout -text -in /tmp/my_name.csr

Now, create the certificate by signing the CSR in the CA:

    $ cd smartcard_ca
    $ nanoca sign /tmp/my_name.csr /tmp/my_name.crt

You can inspect the newly created certificate with `openssl` with the `x509` command:

    $ openssl x509 -noout -text -in /tmp/my_name.crt

You now have a signed certificate. The next step is to put it into the card.
The file `/tmp/my_name.csr` is not needed any more and can be removed.


Write certificate to the smart card
====
The final step is to write your certificate into the card:

    $ pkcs15-init --store-certificate /tmp/my_name.crt --auth-id 1 --label "My Name"

Remember to use the same label here as in the `--generate-key` step above. You
will be asked for the User PIN to complete the operation. When completed
without errors, the file `/tmp/my_name.crt` is not needed any more and can be
removed.

The certificate and key on the card can be listed with:

    $ pkcs15-tool --list-keys --list-public-keys --list-certificates

Note that the IDs are all the same for the objects. This is expected because
they all belong together. An object is uniquely identified by the combination
of id and object type (cert, pubkey, privkey).


Remove certificate and key from the card
====
It is possible to remove a certificate and a key from a card. Fist you need
to find the ID for the certificate/key to remove:

    $ pkcs15-tool --list-keys --list-public-keys --list-certificates

Note the ID for the object you want to remove and then run:

    $ pkcs15-init --delete-objects cert --id <ID from above>
    $ pkcs15-init --delete-objects pubkey --id <ID from above>
    $ pkcs15-init --delete-objects privkey --id <ID from above>

The card is now empty of certificates and keys and you can start over and
create a new key.


Erase the card
====
It is possible to totally erase the card to start over from scratch. This is
handy when experimenting with smart cards. Run the following command:

    $ pkcs15-init --erase-card

You will be asked for the Security Officer PIN to preform the erase. If you
have lost it, the card is "lost" to.
