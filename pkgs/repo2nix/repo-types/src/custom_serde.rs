use serde::{Serializer, Deserialize, Deserializer};

pub mod oid {
    use git2::Oid;
    use super::*;

    pub fn serialize<S: Serializer>(oid: &Oid, ser: S) -> Result<S::Ok, S::Error> {
        ser.serialize_str(&oid.to_string())
    }

    pub fn deserialize<'a, D: Deserializer<'a>>(de: D) -> Result<Oid, D::Error> {
        Oid::from_str(
            <&str>::deserialize(de)?
        )
            .map_err(|e| <D::Error as serde::de::Error>::custom(e))
    }
}

pub mod nix_hash {
    use nix_compat::nixhash::NixHash;
    use super::*;

    pub fn serialize<S: Serializer>(nix_hash: &NixHash, ser: S) -> Result<S::Ok, S::Error> {
        ser.serialize_str(&nix_hash.to_sri_string())
    }

    pub fn deserialize<'a, D: Deserializer<'a>>(de: D) -> Result<NixHash, D::Error> {
        NixHash::from_sri(
            <&str>::deserialize(de)?
        )
            .map_err(|e| <D::Error as serde::de::Error>::custom(e))
    }
}
