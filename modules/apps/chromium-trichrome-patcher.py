#!/usr/bin/env python3

import zipfile
import sys

infilename, outfilename, orig_certdigest, new_certdigest = sys.argv[1:]

zin = zipfile.ZipFile(infilename, "r")
zout = zipfile.ZipFile(outfilename, "w")

for info in zin.infolist():
    data = zin.read(info.filename)
    if info.filename == "AndroidManifest.xml":
        # Make sure we can find the certdigest
        data.rindex(orig_certdigest.encode("utf-16-le"))
        # Replace it
        data = data.replace(
            orig_certdigest.encode("utf-16-le"), new_certdigest.encode("utf-16-le")
        )
    zout.writestr(info, data)
