# NixDroid

You know how people build their Android ROMs with Jenkins and stuff?

Well, at some point I set up a Hydra for all my NixOS systems, which got me thinking: couldn't I be using this to build an Android ROM for my phone?

So I went ahead and did just that.

This is a fork focusing on vanilla AOSP.

#### Building the vanilla AOSP ROM:

Generate keys to sign your build:

```console
$ nix-build ./vanilla.nix -A generateKeysScript -o generate-keys
$ mkdir keys
$ cd keys
$ ../generate-keys "/CN=NixDroidOS" # Use appropriate x509 cert fields
$ cd ..
```

Build and sign your release:

```console
$ nix-build ./vanilla.nix -A releaseScript -o release
$ ./release ./keys
```

#### TODO:

* Document (e.g. which patches to nix are needed why)

* While the hash thing is kind of fixed, there is definitely room for improvement.
