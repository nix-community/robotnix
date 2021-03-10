{ pkgs ? import ../pkgs { } }:

with pkgs.lib;
let
  eval = import ../default.nix { inherit pkgs; configuration = { }; };

  robotnixOptionsDoc = pkgs.nixosOptionsDoc {
    inherit (eval) options;
  };

  optionsMd =
    let
      options = robotnixOptionsDoc.optionsNix;
    in
    concatStrings (map
      (name:
        let
          option = options.${name};
          exampleText =
            if option.example ? _type && (option.example._type == "literalExample")
            then option.example.text
            else builtins.toJSON option.example;
          body = ''
            ${option.description}

          '' + optionalString (option ? defaultText || option ? default) ''
            Default: `${option.defaultText or (generators.toPretty {} option.default)}`

          '' + optionalString (option ? example) ''
            Example: `${exampleText}`

          '' + ''
            Type: ${option.type}
          '';
        in
        ''
            - `${name}`

          ${concatMapStrings (line: "    ${line}\n") (splitString "\n" body)}
        ''
      )
      (attrNames options));
in
{
  manual = pkgs.stdenv.mkDerivation {
    name = "manual";
    phases = [ "unpackPhase" "buildPhase" "installPhase" ];
    src = ./.;
    nativeBuildInputs = [ pkgs.mdbook ];
    buildPhase = ''
      cp ${builtins.toFile "options.md" optionsMd} src/options.md
      mdbook build
    '';
    installPhase = ''
      mkdir $out
      cp -R book $out/book
      cp -R src $out/src
      cp book.toml $out/book.toml
    '';
  };
}