//! Generated Protocol Buffers types for the Pliwee wire protocol.
//!
//! This crate contains *only* generated code plus small, hand-written helpers
//! that are pure functions of the generated types. Nothing here knows about
//! sockets, TLS, or capabilities.

/// Types from `package pliwee.v1`.
pub mod v1 {
    include!(concat!(env!("OUT_DIR"), "/pliwee.v1.rs"));

    /// Types from `package pliwee.v1.capabilities`.
    pub mod capabilities {
        include!(concat!(env!("OUT_DIR"), "/pliwee.v1.capabilities.rs"));
    }
}

pub use prost::Message;
