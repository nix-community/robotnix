#!/usr/bin/env nix-shell
#!nix-shell -i python -p python2 nix git nix-prefetch-git cipd -I nixpkgs=../../pkgs.nix
# TODO: Include cipd above

from __future__ import print_function

import sys
import os
import shutil
import subprocess
import string
import json
import argparse

# TODO: Memoized hash stuff
BASEDIR = "/mnt/media/chromium" # /tmp/z

def hash_path(path):
    return subprocess.check_output(["nix", "hash-path", "--base32", "--type", "sha256", path]).strip() # TODO: Error check

def checkout_git(url, rev, path):
    subprocess.check_call([
        "nix-prefetch-git",
        "--builder",
        "--url", url,
        "--out", path,
        "--rev", rev,
        "--fetch-submodules"])
    return hash_path(path)

def checkout_cipd(package, version, path):
    os.mkdir(path)
    subprocess.check_call(["cipd", "init", path])
    subprocess.check_call(["cipd", "install", "-root", path, package, version])
    return hash_path(path)

def nix_str_git(path, dep):
    return '''  %(path)-90s = fetchgit { url = %(url)-128s; rev = "%(rev)s"; sha256 = "%(sha256)s"; };\n''' % {
        "path": '"' + path + '"',
        "url": '"' + dep["url"] + '"',
        "rev": dep["rev"],
        "sha256": dep["sha256"],
    }

def nix_str_cipd(path, dep):
    def _fetchcipd_str(p):
        return 'fetchcipd { package = "%(package)s"; version = "%(version)s"; sha256 = "%(sha256)s"; }' % p

    if len(dep['packages']) == 1:
        src_str = _fetchcipd_str(dep['packages'][0])
    else:
        nix_paths = '    \n'.join([ "(%s)" % (_fetchcipd_str(p),) for p in dep['packages'] ])
        src_str = '''
            symlinkJoin { name = "cipd-joined"; paths = [
            %s
            ]; }
        ''' % nix_paths

    return "  %-90s = %s;\n" %  ('"' + path + '"', src_str)

def make_vendor_file(chromium_version, target_os):
    topdir = os.path.join(BASEDIR, chromium_version)
    if not os.path.isdir(topdir):
        os.mkdir(topdir)

    # first checkout depot_tools for gclient.py which will help to produce list of deps
    if not os.path.isdir(os.path.join(topdir, "depot_tools")):
        checkout_git("https://chromium.googlesource.com/chromium/tools/depot_tools",
                     "fcde3ba0a657dd3d5cac15ab8a1b6361e293c2fe",
                     os.path.join(topdir, "depot_tools"))

    # Import gclient_eval from the just fetched sources
    sys.path.append(os.path.join(topdir, "depot_tools"))
    import gclient_eval

    # Not setting target_cpu, as it'st just used to run script fetching sysroot, which we don't use anyway
    target_cpu = []
    # Normally set in gclient.py
    builtin_vars={
        'checkout_android': 'android' in target_os,
        'checkout_chromeos': 'chromeos' in target_os,
        'checkout_fuchsia': 'fuchsia' in target_os,
        'checkout_ios': 'ios' in target_os,
        'checkout_linux': 'unix' in target_os,
        'checkout_mac': 'mac' in target_os,
        'checkout_win': 'win' in target_os,

        'checkout_arm': 'arm' in target_cpu,
        'checkout_arm64': 'arm64' in target_cpu,
        'checkout_x86': 'x86' in target_cpu,
        'checkout_mips': 'mips' in target_cpu,
        'checkout_mips64': 'mips64' in target_cpu,
        'checkout_ppc': 'ppc' in target_cpu,
        'checkout_s390': 's390' in target_cpu,
        'checkout_x64': 'x64' in target_cpu,

        'host_os': 'linux', # See _PLATFORM_MARPPING in tools/gclient.py
        'host_cpu': 'x64', # See tools/detect_host_arch.py. Luckily this variable is not really currently used much
    }

    # like checkout() but do not delete .git (gclient expects it) and do not compute hash
    # this subdirectory must have "src" name for 'gclient.py' recognises it
    src_dir = os.path.join(topdir, "src")
    if not os.path.isdir(src_dir):
        os.mkdir(src_dir)
        subprocess.check_call(["git", "init"], cwd=src_dir)
        subprocess.check_call(["git", "remote", "add", "origin", "https://chromium.googlesource.com/chromium/src.git"], cwd=src_dir)
        subprocess.check_call(["git", "fetch", "--progress", "--depth", "1", "origin", "+" + chromium_version], cwd=src_dir)
        subprocess.check_call(["git", "checkout", "FETCH_HEAD"], cwd=src_dir)
    else:
        # restore topdir into virgin state
        if ("tag '%s' of" % chromium_version) not in open(os.path.join(topdir, "src/.git/FETCH_HEAD")).read():
            print("already at", chromium_version)
        else:
            print('git fetch --progress --depth 1 origin "+%s"' % chromium_version)
            subprocess.check_call(["git", "fetch", "--progress", "--depth", "1", "origin", "+%s" % chromium_version], cwd=src_dir)
            subprocess.check_call(["git", "checkout", "FETCH_HEAD"], cwd=src_dir)

        # and remove all symlinks to subprojects, so their DEPS files won;t be included
        subprocess.check_call(["find", ".", "-name", ".gitignore", "-delete"], cwd=src_dir)
        os.system("cd %s; git status -u -s | grep -v '^ D ' | cut -c4- | xargs --delimiter='\\n' rm" % src_dir);
        subprocess.check_call(["git", "checkout", "-f", "HEAD"], cwd=src_dir)

    deps = {}
    need_another_iteration = True
    while need_another_iteration:
        need_another_iteration = False

        # # flatten fail because of duplicate valiable names, so rename them
        # if (-f 'src/third_party/angle/buildtools/DEPS') {
        # edit_file {
        #     s/\b(libcxx_revision)\b/${1}2/g;
        #     s/\b(libcxxabi_revision)\b/${1}2/g;
        #     s/\b(libunwind_revision)\b/${1}2/g;
        # } 'src/third_party/angle/buildtools/DEPS';
        # }

        subprocess.check_call(["python2", "depot_tools/gclient.py", "config", "https://chromium.googlesource.com/chromium/src.git"], cwd=topdir)
        flat = subprocess.check_output(["python2", "depot_tools/gclient.py", "flatten", "--pin-all-deps"], cwd=topdir)

        content = gclient_eval.Parse(flat, validate_syntax=True, filename='DEPS',
                             vars_override={}, builtin_vars=builtin_vars)

        merged_vars = dict(content['vars'])
        merged_vars.update(builtin_vars)

        for path, fields in content['deps'].iteritems():
            # Skip this one
            if path == "src/tools/luci-go":
                continue

            # Skip dependency if its condition evaluates to False
            if 'condition' in fields and not gclient_eval.EvaluateCondition(fields['condition'], merged_vars):
                continue

            if not path in deps:
                if fields['dep_type'] == "git":
                    url, rev = fields['url'].split('@')
                    wholepath = os.path.join(BASEDIR, rev)

                    if os.path.exists(wholepath + ".sha256"): # memoize hash
                        sha256 = open(wholepath + ".sha256").read()
                    else:
                        shutil.rmtree(path, ignore_errors=True)
                        sha256 = checkout_git(url, rev, wholepath)
                        open(wholepath + ".sha256", "w").write(sha256)

                    if os.path.exists(os.path.join(wholepath, "DEPS")):
                        need_another_iteration = True

                    deps[path] = {
                        "url": url,
                        "rev": rev,
                        "sha256": sha256,
                        "dep_type": "git",
                    }

                elif fields['dep_type'] == "cipd":
                    packages = []
                    for p in fields['packages']:
                        package, version = p['package'], p['version']
                        dirname = (package + '_' + version).replace('/', '_').replace(':', '') # TODO: Better path normalization
                        wholepath = os.path.join(BASEDIR, dirname)

                        if os.path.exists(wholepath + ".sha256"): # memoize hash
                            sha256 = open(wholepath + ".sha256").read()
                        else:
                            shutil.rmtree(wholepath, ignore_errors=True)
                            sha256 = checkout_cipd(package, version, wholepath)
                            open(wholepath + ".sha256", "w").write(sha256)

                        packages.append({
                            "package": package,
                            "version": version,
                            "sha256": sha256,
                        })

                    deps[path] = {
                        "packages": packages,
                        "dep_type": "cipd",
                    }

                else:
                    raise ValueError("Unrecognized dep_type", fields['dep_type'])

    with open('vendor-%s.nix' % chromium_version, 'w') as vendor_nix:
        vendor_nix.write("# GENERATED BY mk-vendor-file.py, %s for %s\n" % (chromium_version, ", ".join(target_os)))
        vendor_nix.write("{fetchgit, fetchcipd, fetchurl, runCommand, symlinkJoin}:\n");
        vendor_nix.write("{\n");

        for path, dep in sorted(deps.iteritems()):
            if dep['dep_type'] == "git":
                vendor_nix.write(nix_str_git(path, dep))
            if dep['dep_type'] == "cipd":
                vendor_nix.write(nix_str_cipd(path, dep))

        # Some additional non-git/cipd sources
        for path, name in [("src/third_party/node/node_modules", "chromium-nodejs"),
                        ("src/third_party/test_fonts/test_fonts", "chromium-fonts")]:
            sha1 = open(os.path.join(topdir, path + ".tar.gz.sha1")).read().strip()
            vendor_nix.write(
'''
"%(path)s" = runCommand "download_from_google_storage" {} ''
    mkdir $out
    tar xf ${fetchurl {
                url  = "https://commondatastorage.googleapis.com/%(name)s/%(sha1)s";
                sha1 = "%(sha1)s";
            }} --strip-components=1 -C $out
'';
''' % { "path": path, "name": name, "sha1": sha1 })

        # condition: checkout_android or checkout_linux
        # TODO: Memoize
        gs_url = open(os.path.join(topdir, 'src/chrome/android/profiles/newest.txt')).read().strip()
        GS_HTTP_URL = "https://storage.googleapis.com/"
        gz_prefix = "gs://"
        if gs_url.startswith(gz_prefix):
            url = GS_HTTP_URL + gs_url[len(gz_prefix):]
        else:
            url = GS_HTTP_URL + "chromeos-prebuilt/afdo-job/llvm/" + gs_url
        sha256 = subprocess.check_output(["nix-prefetch-url", "--type", "sha256", url]).strip()
        path = "src/chrome/android/profiles/afdo.prof"
        vendor_nix.write(
'''
"%(path)s" = runCommand "download_afdo_profile" {} ''
    bzip2 -d -c ${fetchurl {
                url  = "%(url)s";
                sha256 = "%(sha256)s";
            }} > $out
'';
''' % { "path": path, "url": url, "sha256": sha256 })

        local_scope = {}
        global_scope = {"__file__": "update.py"}
        exec(open(os.path.join(topdir, "src/tools/clang/scripts/update.py")).read(), local_scope, global_scope) # TODO: Safety?
        url = '%s/Linux_x64/clang-%s.tgz' % (global_scope['CDS_URL'], global_scope['PACKAGE_VERSION'])
        sha256 = subprocess.check_output(["nix-prefetch-url", "--type", "sha256", url]).strip()
        path = "src/third_party/llvm-build/Release+Asserts"
        vendor_nix.write(
'''
"%(path)s" = runCommand "download_upstream_clang" {} ''
    mkdir $out
    tar xf ${fetchurl {
                url  = "%(url)s";
                sha256 = "%(sha256)s";
            }} -C $out
'';
''' % { "path": path, "url": url, "sha256": sha256 })


        vendor_nix.write("}\n")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-os', type=str, default=["unix"], action='append')
    parser.add_argument('version', nargs='+')
    args = parser.parse_args()

    for chromium_version in args.version:
        make_vendor_file(chromium_version, args.target_os)

if __name__ == "__main__":
    main()
