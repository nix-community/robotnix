lib:

with lib; # Android stuff that might come in handy across multiple modules, profiles, etc
rec {
  # Guess resource type. Should normally work fine, but can't detect color/dimension types
  resourceType = r:
    if isBool r then "bool"
    else if isInt r then "integer"
    else if isString r then "string"
    else if isList r then
      (assert (length r != 0); # Cannot autodetect type of empty list
       if isInt (head r) then "integer-array"
       else if isString (head r) then "string-array"
       else assert false; "Unknown type"
      )
    else assert false; "Unknown type";
  resourceValueXML = value: type: {
    bool = boolToString value;
    color = value; # define our own specialized type for these?
    dimension = value;
    integer = toString value;
    string = value;
    integer-array = concatMapStringsSep "" (i: "<item>${toString i}</item>") value;
    string-array = concatMapStringsSep "" (i: "<item>${i}</item>") value;
    # Ignoring other typed arrays for now
  }.${type};
  resourceXML = name: value: type: ''<${type} name="${name}">${resourceValueXML value type}</${type}>'';
  configXML = resources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${concatStringsSep "\n" (mapAttrsToList
        (name: value: resourceXML name value (resourceType value))
       resources)}
    </resources>
  '';
}
