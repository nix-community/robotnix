{ system ? builtins.currentSystem }:
  let
    lock               = builtins.fromJSON (builtins.readFile ./../flake.lock);
    flake-compat-entry = lock.nodes.root.inputs.flake-compat;

    inherit (lock.nodes."${ flake-compat-entry }".locked) owner repo narHash;

    flake-compat = builtins.fetchTarball {
                     url = "https://github.com/${ owner }/${ repo }/archive/${ lock.nodes.flake-compat.locked.rev }.tar.gz";
                     sha256 = narHash;
                   };
  in
    import flake-compat {
      inherit system;

       src =  ./..;
    }
