with (import ../../pkgs.nix {});

# Remove any hashes from file whose revision or tree hash aren't in the specified json files
writeScript "clean-hashes.sh" ''
  hashesFile=$1
  shift
  jsonFiles=$*

  jq --slurp --slurpfile existing $hashesFile \
    '. as $input
    | $existing[] | to_entries
    | map(select(
        [([.key]|inside([$input[][].rev])),
         ([.key]|inside([$input[][].tree]))
        ]|any))
    | from_entries
    ' \
    $jsonFiles
''
