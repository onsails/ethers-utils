use ethers::prelude::*;

#[derive(Debug, Clone, Copy, Eq, PartialEq, Hash)]
pub enum ChainVariant {
    Chain(Chain),
    UnknownChain(U256),
}

impl ChainVariant {
    /// # Panics
    /// Panics if the `Chain::UnknownChain` id is larger than u64::max_value().
    pub fn as_u64(&self) -> u64 {
        match self {
            ChainVariant::Chain(chain) => *chain as u64,
            ChainVariant::UnknownChain(id) => id.as_u64(),
        }
    }
}

impl From<u64> for ChainVariant {
    fn from(chain_id: u64) -> Self {
        match Chain::try_from(chain_id) {
            Ok(chain) => Self::Chain(chain),
            Err(_) => Self::UnknownChain(U256::from(chain_id)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const UNKNOWN_CHAIN_ID: u64 = 99999999;

    #[test]
    fn chain_variant() {
        let mainnet = ChainVariant::from(1);
        assert_eq!(mainnet, ChainVariant::Chain(Chain::Mainnet));
        assert_eq!(mainnet.as_u64(), 1);

        let unknown = ChainVariant::from(UNKNOWN_CHAIN_ID);
        assert_eq!(
            unknown,
            ChainVariant::UnknownChain(U256::from(UNKNOWN_CHAIN_ID))
        );
        assert_eq!(unknown.as_u64(), UNKNOWN_CHAIN_ID);
    }
}
