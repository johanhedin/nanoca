nanoca with smart card
====
`nanoca` can create CSRs using RSA keys on smart cards. This document is a short
instruction how to create and provision a `nanoca` signed certificate on a
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
OpenSC, pcsc-lite and pkcs11_engine need to be installed (they are most likely
already installed on your system):

    $ sudo dnf install opensc pcsc-lite openssl-pkcs11

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
the Security Officer. Write them down somewhere safe or be confident that you
remember them. Do the same for the User, one PIN and one PUK.

> Note 1: If you loose the Security Officer PIN, you will not be able to wipe
the card and start over or provision new PINs, basically bricking the the card.

Insert the card into the card reader and make sure that this card is the only
PKCS11/PIV card/token connected to your computer. Then run the following:

    $ pkcs15-init --create-pkcs15

On older Fedora this command asked for PIN and/or PUK and did not work as stated
in the manual (just press ENTER). If this happes, run the following instead:

    $ pkcs15-init --create-pkcs15 --pin 1234 --puk 1234

(the PIN and PUK are just dummy values and are not used).

You will be asked to set the Security Officer PIN and PUK. Enter the values that
you came up with previously (note that the wording for the Security Officer PUK
prompt is a bit misleading and talk about "User unblocking PIN", but it is the
Security Officer PUK that is requested).

The next step is to set the User PIN and PUK. For smart cards, a PIN is
considered it's own "object". You create a PIN object and then references that
object when creating a new key. The Security Officer PIN object created
previously is automatically assigned the ID ff. Here we choose the ID 01 when
creating the User PIN object. The label below is optional, but it is nice to
have meaningful names on objects:

    $ pkcs15-init --store-pin --id 01 --label "User PIN"

Enter the values for User PIN and PUK that you came up with previously. The
Security Officer PIN might be requested as the last step depending on the
version of `pkcs15-init`.

The card is not yet fully locked and the PINs are not enforced. Finalize
the process with the following command:

    $ pkcs15-init --finalize

The card is now ready to be used. The available PIN objects can be listed
with the `pkcs15-tool`:

    $ pkcs15-tool --no-cache --list-pins

The `--no-cache` option is used so that pkcs15-tool does not use the opensc
file cache concept that Fedora activates out-of-the-box. The default settings
are that pkcs15-init is not cached but pkcs15-tool is. This totally mess up
things when you modify your card with pkcs15-init and then view the changes with
pkcs15-tool. The caching can also be controlled system wide via `/etc/opensc.conf`.

If the cache bites you anyway, it can be cleared with:

    $ pkcs15-tool --clear-cache

or by removing the `~/.cache/opensc` directory.

PIN objects can only be created once and can not be removed. The PIN codes
can be changed (see futher down on this page) but to add new PIN objects or
remove existing ones, the card need to be erased and then configured from scratch.


Create a RSA key on the card
====
To create a new RSA key object on the card run the following command:

    $ pkcs15-init --generate-key "rsa:2048" --key-usage digitalSignature,keyEncipherment --auth-id 01 \
                  --label "My Name" --public-key-label "My Name"

Replace "My Name" with the name you intend to use as Common Name in the
certificate later on. There is no real requirement for them to match, but it
makes everything much more clear if they do. The `--auth-id 01` argument will
tie this key to the one and only User PIN object that was created in the
initialization step. The `--key-usage` must match the key usage set in the
X.509 certificate (nanoca sets it like above).

> Note 2: The keypair will automatically be assigned a unique ID calculated from
the public key. If you like to set your own ID do that with the `--id <ID>`
option where `<ID>` is a hex value, e.g. `--id 45fa23`.

To list the key (both the private part and the public part), use:

    $ pkcs15-tool --no-cache --list-keys --list-public-keys

The actual private key is of course never shown, just information about it.


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

    $ pkcs15-init --store-certificate /tmp/my_name.crt --label "My Name"

Remember to use the same label here as in the `--generate-key` step above. You
will be asked for the User PIN to complete the operation. When completed
without errors, the file `/tmp/my_name.crt` is not needed any more and can be
removed.

> Note 3: The certificate object will be assigned an ID calculated from the
public key inside the certificate. Since this is the same public key as on the
card, the calculated ID will match that of the existing public key. If you
chose to set your own ID for your key, you can do the same here with the
`--id <ID>` option.


The certificate and key on the card can be listed with:

    $ pkcs15-tool --no-cache --list-keys --list-public-keys --list-certificates

Note that the IDs are all the same for the objects. This is expected because
they all belong together. An object is uniquely identified by the combination
of id and object type (privkey, pubkey, cert).

To write a text representation of a certificate on the card, identify the ID
of the certificate from above and run:

    $ pkcs15-tool --no-cache --read-certificate <ID> | openssl x509 -noout -text


Remove certificate and key from the card
====
It is possible to remove a certificate and a key from a card. Fist you need
to find the ID for the certificate/key to remove:

    $ pkcs15-tool --no-cache --list-keys --list-public-keys --list-certificates

Note the ID and object type for the object you want to remove and then run one
or all of the following:

    $ pkcs15-init --delete-objects cert --id <ID from above>
    $ pkcs15-init --delete-objects pubkey --id <ID from above>
    $ pkcs15-init --delete-objects privkey --id <ID from above>

And start over creating new objects.

> Note 4: If you remove the privkey, the pubkey becomes useless.


Change PIN
====
It is possible to change the User PIN and the Security Officer PIN with
`pkcs15-tool`. Use the following to change the User PIN (the one with auth ID 01):

    $ pkcs15-tool --no-cache --auth-id 01 --change-pin

To change the Security Officer PIN, use auth ID ff instead:

    $ pkcs15-tool --no-cache --auth-id ff --change-pin


Erase the card
====
It is possible to fully erase the card to start over from scratch. This is
handy when experimenting with smart cards. Run the following command:

    $ pkcs15-init --erase-card

You will be asked for the Security Officer PIN to preform the erase. If you
have lost it, the card is "lost" to.
