#!/usr/bin/env bash

set -euo pipefail

img=$1
out=$2

cd "$(mktemp -d)"

if [[ $img =~ -factory- ]]; then
  bsdtar xvf "$img" --strip-components 1
  bsdtar xvf image-*.zip
  rm image-*.zip
else
  bsdtar xvf "$img"
fi

for filename in *; do
  cp "$filename" "$out"
  if [[ $filename == *.img ]]; then
    filetype=$(file "$filename")
    part=''${filename%.img}

    case "$filetype" in
    *"Android sparse image"*)
      simg2img "$filename" "$part.raw"
      mkdir "$out/$part"
      debugfs "$part.raw" -R "rdump / $out/$part"
      ;;
    *"Android bootimg"*)
      mkdir "$out/$part"
      unpack_bootimg.py --boot_img "$filename" --out "$out/$part" | tee "$out/$part/info"
      mkdir "$out/$part/ramdisk-ext"
      bsdtar xf "$out/$part/ramdisk" -C "$out/$part/ramdisk-ext"
      ;;
    *)
      if [[ $part == vendor_boot ]]; then
        mkdir "$out/$part"
        unpack_bootimg.py --boot_img "$filename" --out "$out/$part" | tee "$out/$part/info"
        for filepath in "$out"/"$part"/vendor_ramdisk*; do
          mkdir "$filepath-ext"
          bsdtar xf "$filepath" -C "$filepath-ext"
        done
      elif [[ $part == vbmeta* ]]; then
        avbtool.py info_image --image "$filename" --out "$out/$part-info"
      fi
      ;;
    esac
  fi
done
