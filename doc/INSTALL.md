# Install instructions
Check ut the repository and then install `naonca` and it's support files with
`sudo make install`:

```console
git clone https://github.com/johanhedin/nanoca.git
cd nanoca
sudo make install
```

Default install prefix is `/usr/local` but this can be changed with the
`PREFIX` environment variable like:

```console
sudo PREFIX=/usr make install
```

The files installed are the program itself, a man page and bash completion
support.
