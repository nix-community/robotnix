# Source Directories

The AOSP source code is spread across a large number of git repositories.
The directories included in the robotnix build may be specified using the `source.dirs.*` options.

For example, the following configuration will include a new repository checked out under `foo/bar` by setting the `source.dir.<name>.src` option.
```nix
{
  source.dirs."foo/bar".src = pkgs.fetchGit {
    url = "https://example.com/repo/foobar.git";
    rev = "f506faf86b8f01f9c09aae877e00ad0a2b4bc511";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
}
```
While the above uses `pkgs.fetchGit`, the `src` option could refer to any Nix derivation producing a directory.
The `source.dirs` option does not currently support "nested" directories.
For example, if `source.dirs."foo"` is set, then setting `source.dirs."foo/bar".src` will not work properly.

Additionaly, robotnix provides a convenient mechanism for patching existing source directories:
```nix
{
  # source.dirs.<name>.patches can refer to a list of patches to apply
  source.dirs."frameworks/base".patches = [ ./example.patch ];

  # source.dirs.<name>.postPatch can refer to a snippet of shell script to modify the source tree
  source.dirs."frameworks/base".postPatch = ''
    sed -i 's/hello/there/' example.txt
  '';
}
```

Each flavor in robotnix conditionally sets the default `source.dirs` to include the Android source directories required for the build.


Robotnix supports two alternative approaches for fetching source files:

- Build-time source fetching with `pkgs.fetchgit`. This is the default.
  An end user wanting to fetch sources not already included in `robotnix` would
  need to create a repo json file using `scripts/mk_repo_file.py` and set
  `source.dirs = lib.importJSON ./example.json;`
- Evaluation-time source fetching with `builtins.fetchGit`.
  This is more convenient for development when changing branches, as it allows
  use of a shared user git cache.  The end user will need to set
  `source.manifest.{url,rev,sha256}` and enable `source.evalTimeFetching`.
  However, with `builtins.fetchGit`, the `drv`s themselves depend on the
  source, and `nix-copy-closure` of even just the `.drv` files would require
  downloading the source as well. This option is not as well tested as the
  build-time source fetching option.
