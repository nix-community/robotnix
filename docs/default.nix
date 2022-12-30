# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

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
    in ''
      # Robotnix Configuration Options
      *Some robotnix flavors or modules may change the option defaults shown below.*
      *Refer to the flavor or module source for details*

    ''
    + concatStrings (map
      (name:
        let
          option = options.${name};
          exampleText =
            if option.example ? _type && (option.example._type == "literalExample")
            then option.example.text
            else builtins.toJSON option.example;
          declarationToLink = declaration: let
            trimmedDeclaration = concatStringsSep "/" (drop 4 (splitString "/" declaration));
          in
            if hasPrefix "/nix/store/" declaration
            then "[${trimmedDeclaration}](https://github.com/danielfullmer/robotnix/blob/master/${trimmedDeclaration})"
            else declaration;
          body = ''
            ${option.description}

          '' + optionalString (option ? defaultText || option ? default) ''
            *Default*: `${option.defaultText or (generators.toPretty {} option.default)}`

          '' + optionalString (option ? example) ''
            *Example*: `${exampleText}`

          '' + ''
            *Type*: ${option.type}

            *Declared by*:
            ${concatMapStringsSep ", " (declaration: declarationToLink declaration) option.declarations}
          '';
        in optionalString (isString option.description) # work around _module "option"
        ''
          ### `${name}`
          ${body}
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
