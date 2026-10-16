use serde::de::{Deserializer, IgnoredAny, MapAccess, SeqAccess, Visitor};
use serde::Deserialize;
use std::fmt;
use std::marker::PhantomData;
use std::sync::{Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};

//len visitor macros
macro_rules! skip_scalars {
    ($value:ty) => {
        fn visit_bool<E>(self, _: bool) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_i64<E>(self, _: i64) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_u64<E>(self, _: u64) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_f64<E>(self, _: f64) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_str<E>(self, _: &str) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_unit<E>(self) -> Result<$value, E> {
            Ok(Default::default())
        }

        fn visit_none<E>(self) -> Result<$value, E> {
            Ok(Default::default())
        }
    };
}

macro_rules! skip_seq {
    ($value:ty) => {
        fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut a: A) -> Result<$value, A::Error> {
            while a.next_element::<serde::de::IgnoredAny>()?.is_some() {}
            Ok(Default::default())
        }
    };
}

macro_rules! skip_map {
    ($value:ty) => {
        fn visit_map<A: serde::de::MapAccess<'de>>(self, mut a: A) -> Result<$value, A::Error> {
            while a
                .next_entry::<serde::de::IgnoredAny, serde::de::IgnoredAny>()?
                .is_some()
            {}
            Ok(Default::default())
        }
    };
}

pub(crate) use skip_scalars;
pub(crate) use skip_seq;

//scalar values
pub enum Scalar {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Text(String),
}

struct ScalarVisitor;

impl<'de> Visitor<'de> for ScalarVisitor {
    type Value = Scalar;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("any value")
    }

    fn visit_bool<E>(self, v: bool) -> Result<Scalar, E> {
        Ok(Scalar::Bool(v))
    }

    fn visit_i64<E>(self, v: i64) -> Result<Scalar, E> {
        Ok(Scalar::Int(v))
    }

    fn visit_u64<E>(self, v: u64) -> Result<Scalar, E> {
        Ok(Scalar::Int(i64::try_from(v).unwrap_or(i64::MAX)))
    }

    fn visit_f64<E>(self, v: f64) -> Result<Scalar, E> {
        Ok(Scalar::Float(v))
    }

    fn visit_str<E>(self, v: &str) -> Result<Scalar, E> {
        Ok(Scalar::Text(v.to_owned()))
    }

    fn visit_string<E>(self, v: String) -> Result<Scalar, E> {
        Ok(Scalar::Text(v))
    }

    fn visit_unit<E>(self) -> Result<Scalar, E> {
        Ok(Scalar::Null)
    }

    fn visit_none<E>(self) -> Result<Scalar, E> {
        Ok(Scalar::Null)
    }

    fn visit_some<D: Deserializer<'de>>(self, d: D) -> Result<Scalar, D::Error> {
        d.deserialize_any(self)
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<Scalar, A::Error> {
        while a.next_element::<IgnoredAny>()?.is_some() {}
        Ok(Scalar::Null)
    }

    fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<Scalar, A::Error> {
        while a.next_entry::<IgnoredAny, IgnoredAny>()?.is_some() {}
        Ok(Scalar::Null)
    }
}

impl<'de> Deserialize<'de> for Scalar {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(ScalarVisitor)
    }
}

impl Scalar {
    pub fn into_string(self) -> String {
        match self {
            Scalar::Null => String::new(),
            Scalar::Bool(b) => b.to_string(),
            Scalar::Int(i) => i.to_string(),
            Scalar::Float(f) => f.to_string(),
            Scalar::Text(s) => s,
        }
    }

    pub fn into_int(self) -> i64 {
        match self {
            Scalar::Int(i) => i,
            Scalar::Float(f) => f as i64,
            Scalar::Text(s) => s.trim().parse().unwrap_or(0),
            _ => 0,
        }
    }

    pub fn into_float(self) -> f64 {
        match self {
            Scalar::Int(i) => i as f64,
            Scalar::Float(f) => f,
            Scalar::Text(s) => s.trim().parse().unwrap_or(0.0),
            _ => 0.0,
        }
    }

    pub fn into_nullable(self) -> Option<String> {
        if matches!(self, Scalar::Null) {
            return None;
        }
        let text = self.into_string();
        let trimmed = text.trim();
        if trimmed.is_empty() { None } else { Some(trimmed.to_owned()) }
    }
}

//field deserializers
pub fn string<'de, D: Deserializer<'de>>(d: D) -> Result<String, D::Error> {
    Scalar::deserialize(d).map(Scalar::into_string)
}

pub fn int<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Scalar::deserialize(d).map(Scalar::into_int)
}

pub fn float<'de, D: Deserializer<'de>>(d: D) -> Result<f64, D::Error> {
    Scalar::deserialize(d).map(Scalar::into_float)
}

pub fn strict_true<'de, D: Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Scalar::deserialize(d).map(|s| matches!(s, Scalar::Bool(true)))
}

pub fn nullable_string<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    Scalar::deserialize(d).map(Scalar::into_nullable)
}

pub fn trust_level<'de, D: Deserializer<'de>>(d: D) -> Result<String, D::Error> {
    let clean = Scalar::deserialize(d)?.into_string().trim().to_lowercase();
    Ok(match clean.as_str() {
        "verified_source" | "security_reviewed" => clean,
        _ => String::new(),
    })
}

//list parsing
struct Maybe<T>(Option<T>);

impl<T> Default for Maybe<T> {
    fn default() -> Self {
        Self(None)
    }
}

struct MaybeVisitor<T>(PhantomData<T>);

impl<'de, T: Deserialize<'de>> Visitor<'de> for MaybeVisitor<T> {
    type Value = Maybe<T>;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("an object")
    }

    fn visit_map<A: MapAccess<'de>>(self, map: A) -> Result<Maybe<T>, A::Error> {
        T::deserialize(serde::de::value::MapAccessDeserializer::new(map)).map(|v| Maybe(Some(v)))
    }

    skip_scalars!(Maybe<T>);
    skip_seq!(Maybe<T>);
}

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Maybe<T> {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(MaybeVisitor(PhantomData))
    }
}

struct ListVisitor<T>(PhantomData<T>);

impl<'de, T: Deserialize<'de>> Visitor<'de> for ListVisitor<T> {
    type Value = Vec<T>;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a list")
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Vec<T>, A::Error> {
        let mut out = Vec::with_capacity(seq.size_hint().unwrap_or(0).min(1 << 16));
        while let Some(item) = seq.next_element::<Maybe<T>>()? {
            if let Some(value) = item.0 {
                out.push(value);
            }
        }
        Ok(out)
    }

    skip_scalars!(Vec<T>);
    skip_map!(Vec<T>);
}

pub fn list<'de, D: Deserializer<'de>, T: Deserialize<'de>>(d: D) -> Result<Vec<T>, D::Error> {
    d.deserialize_any(ListVisitor(PhantomData))
}

struct TextListVisitor;

impl<'de> Visitor<'de> for TextListVisitor {
    type Value = Vec<String>;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a list of strings")
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Vec<String>, A::Error> {
        let mut out = Vec::new();
        while let Some(item) = seq.next_element::<Scalar>()? {
            if let Scalar::Text(s) = item {
                out.push(s);
            }
        }
        Ok(out)
    }

    skip_scalars!(Vec<String>);
    skip_map!(Vec<String>);
}

pub fn text_list<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<String>, D::Error> {
    d.deserialize_any(TextListVisitor)
}

//lock helpers
pub fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn read<T>(l: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    l.read().unwrap_or_else(|e| e.into_inner())
}

pub fn write<T>(l: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    l.write().unwrap_or_else(|e| e.into_inner())
}
