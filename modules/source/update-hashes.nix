with (import ../../pkgs.nix);
# TODO: Nice to depend on  pkgs above so that nix-prefetch-git can use fetchGit override for local mirror
writeScript "update-hashes.sh" ''
  hashesFile=$1
  shift
  jsonFiles=$*

  function update() {
    local url="$1"
    local rev="$2"
    local tree="$3"

    echo "[-] Fetching $url $rev"
    local hash=$(${pkgs.nix-prefetch-git}/bin/nix-prefetch-git --quiet "$url" "$rev" | ${pkgs.jq}/bin/jq ".sha256")
    local temp=$(mktemp)

    local key
    if [[ "$tree" == "null" ]]; then
      key=$rev
    else
      key=$tree
    fi

    echo $hash
    ${pkgs.jq}/bin/jq --sort-keys ". * {\"$key\": $hash}" < "$hashesFile" > "$temp" || exit 1
    cp "$temp" "$hashesFile"
    rm "$temp"

    echo
  }

  ${pkgs.jq}/bin/jq --raw-output --slurp --slurpfile existing "$hashesFile" \
    '[.[][]]
      | unique_by(if .tree then .tree else .rev end)
      | sort_by(.url)
      | .[]
      | select(
        [([.rev] |inside($existing[] | keys)),
         ([.tree]|inside($existing[] | keys))
        ] |any|not)
      | "\(.url)\t\(.rev)\t\(.tree)"' \
    $jsonFiles \
    | while read -r url rev tree; do
    update $url $rev $tree
  done
''
