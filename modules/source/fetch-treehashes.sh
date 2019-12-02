#!/usr/bin/env bash

# Takes a repo2nix json file as argument and adds "tree" attributes to each project with the git tree SHA1 hash

out=$1

cp "$out" orig.json

function getTreeHash() {
    local url="$1"
    local rev="$2"
    local treeHash
    local retry=0

    while [[ "$retry" -lt 5 ]]; do
    echo "Fetching tree hash: $url" >&2
    treeHash=$(curl --retry 10 -s "$url/+/$rev" | pup "div[class~=TreeDetail-sha1] text{}" | cut -d" " -f2)

    if [[ "$treeHash" =~ ^([0-9]|[a-f]){40} ]]; then
        echo "$treeHash"
        exit 0
    fi

    echo "Incorrect tree hash, retrying in 5 seconds: $treeHash" >&2
    sleep 5
    retry=$(( retry + 1 ))
    done

    exit 1
}

# Parallelizing the following just seems to result in google complaining about exceeding allowable rates
# TODO: Could probably be refactored to not have to read the input file twice

cat orig.json | jq -r 'to_entries[] | select(.value.url|startswith("https://android.googlesource.com")) | "\(.key) \(.value.url) \(.value.rev)"' \
    | while read -r key url rev; do
    treeHash=$(getTreeHash "$url" "$rev") || exit 1
    echo "{\"$key\": {\"tree\": \"$treeHash\"}}"
done | jq --sort-keys --slurp --slurpfile orig ./orig.json '(.|add) * $orig[]' > "$out"

rm orig.json
