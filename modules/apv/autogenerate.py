#!/usr/bin/env python3

# Hackish script to automatically generate some parts of JSON file required for android-prepare-vendor
# Requires 4 arguments:
# (1) device name
# (2) module-info.json from build (3) below, can be found under out/target/product/<device>/module-info.json
# (3) listing of extracted files from a build of AOSP for device with a minimal vendor directory (see autogenerate.nix)
# (4) listing of extracted files from the upstream factory image for device

import sys
import json

from typing import List


def main() -> None:
    def _replace_system_system(s: str) -> str:
        if s.startswith("system/system/"):
            return s[len("system/") :]
        else:
            return s

    device_name = sys.argv[1]
    module_json = json.load(open(sys.argv[2]))

    built_files = set(
        _replace_system_system(s) for s in open(sys.argv[3]).read().split("\n")
    )
    upstream_files = set(
        _replace_system_system(s) for s in open(sys.argv[4]).read().split("\n")
    )

    filename_prefix = f"out/target/product/{device_name}/"

    file_module_lookup = {
        filename: modulename
        for modulename, data in module_json.items()
        for filename in data["installed"]
        if filename.startswith(filename_prefix)
    }

    needed_files = set()
    needed_modules = set()
    needed_modules_with_arch = set()
    for filename in upstream_files:
        if filename not in built_files:
            key = filename_prefix + filename
            if key in file_module_lookup:
                # if filename.startswith('vendor/') or filename.startswith('system_ext/'):
                if filename.startswith("vendor/"):
                    needed_modules.add(file_module_lookup[key])
                    if filename.startswith("vendor/lib64/"):
                        needed_modules_with_arch.add(file_module_lookup[key] + ":64")
                    else:
                        needed_modules_with_arch.add(file_module_lookup[key])
            else:
                if not filename.startswith("vendor/lib/modules/"):
                    needed_files.add(filename)

    modules_files = set()
    for modulename in needed_modules:
        for filename in module_json[modulename]["installed"]:
            if filename.startswith(filename_prefix):
                modules_files.add(filename[len(filename_prefix) :])

    def _is_bytecode(s: str) -> bool:
        return s.endswith(".apk") or s.endswith(".jar")

    DEP_DSOS: List[str] = [
        "vendor/lib/libadsprpc.so",
        "vendor/lib/libsdsprpc.so",
        "vendor/lib64/libadsprpc.so",
        "vendor/lib64/libsdsprpc.so",
    ]

    SKIP_MODULES: List[str] = []

    vendor_skip_files = set(
        filename[len("vendor/") :]
        for filename in modules_files
        if filename.startswith("vendor/")
    )
    vendor_skip_files.update(
        filename[len("vendor/") :]
        for filename in built_files
        if filename in upstream_files and filename.startswith("vendor/")
    )

    # Manual addition. Might not be needed if we include the corresponding stuff in system_ext
    vendor_skip_files.add("etc/vintf/manifest/manifest_wifi_ext.xml")

    apv_config = {
        # 'new-modules': [],
        "dep-dso": [dso for dso in DEP_DSOS if dso in needed_files],
        # 'rro-overlays': [],
        "forced-modules": sorted(
            set(
                modulename
                for modulename in needed_modules_with_arch
                if modulename not in SKIP_MODULES
            )
        ),
        "vendor-skip-files": sorted(vendor_skip_files),
        "system-bytecode": sorted(
            filename
            for filename in needed_files
            if (
                filename.startswith("system/")
                and _is_bytecode(filename)
                and not ("Google/" in filename or "/Google" in filename)
            )
        ),
        # 'system-other': sorted(
        #     filename for filename in needed_files
        #     if (filename.startswith('system/') and not _is_bytecode(filename)
        #         and not (filename.endswith('.odex') or filename.endswith('.vdex') or filename.endswith('.apex')))
        # ),
        # 'system_ext-bytecode': sorted(
        #     filename for filename in needed_files
        #     if (filename.startswith('system_ext/') and _is_bytecode(filename)
        #         and not ('Google/' in filename or '/Google' in filename))
        # ),
        # 'system_ext-other': sorted(
        #     filename for filename in needed_files
        #     if (filename.startswith('system_ext/') and not _is_bytecode(filename)
        #         and not (filename.endswith('.odex') or filename.endswith('.vdex')))
        # ),
        # 'product-bytecode': sorted(
        #     filename for filename in needed_files
        #     if filename.startswith('product/') and _is_bytecode(filename)
        # ),
        # 'product-other': sorted(
        #     filename for filename in needed_files
        #     if (filename.startswith('product/') and not _is_bytecode(filename)
        #         and not (filename.endswith('.odex') or filename.endswith('.vdex')))
        # ),
    }

    print(json.dumps(apv_config, sort_keys=True, indent=2, separators=(",", ": ")))


if __name__ == "__main__":
    main()
