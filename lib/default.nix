# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

lib:

rec {
  # Guess resource type. Should normally work fine, but can't detect color/dimension types
  resourceTypeName = r:
    if lib.isBool r then "bool"
    else if lib.isInt r then "integer"
    else if lib.isString r then "string"
    else if lib.isList r then
      (assert (lib.length r != 0); # Cannot autodetect type of empty list
       if lib.isInt (lib.head r) then "integer-array"
       else if lib.isString (lib.head r) then "string-array"
       else assert false; "Unknown type"
      )
    else assert false; "Unknown type";
  resourceValueXML = value: type: {
    bool = lib.boolToString value;
    color = value; # define our own specialized type for these?
    dimension = value;
    integer = toString value;
    string = value;
    integer-array = lib.concatMapStringsSep "" (i: "<item>${toString i}</item>") value;
    string-array = lib.concatMapStringsSep "" (i: "<item>${i}</item>") value;
    # Ignoring other typed arrays for now
  }.${type};

  resourceXML = name: value: let
    resourceXMLEntity = name: value: type: ''<${type} name="${name}">${resourceValueXML value type}</${type}>'';
  in if lib.isAttrs value then
      # Submodule with manually specified resource type
      resourceXMLEntity name value.value value.type
    else
      # Bare value, so use Autodetected resource type
      resourceXMLEntity name value (resourceTypeName value);

  configXML = resources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList resourceXML resources)}
    </resources>
  '';

}
