use async_trait::async_trait;
use ethers::prelude::*;

#[repr(u64)]
#[derive(Debug, Clone, Copy, Eq, PartialEq, Hash)]
pub enum ChainExt {
    Chain(Chain),
    UnknownChain(U256),
}

#[async_trait]
pub trait MiddlewareExt: Middleware {
    async fn get_chain(&self) -> Result<ChainExt, Self::Error> {
        let chain_id = self.get_chainid().await?;

        match Chain::try_from(chain_id) {
            Ok(chain) => Ok(ChainExt::Chain(chain)),
            Err(_) => Ok(ChainExt::UnknownChain(chain_id)),
        }
    }
}

impl<M: Middleware> MiddlewareExt for M {}

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::{providers::Provider, utils::Anvil};
    use url::Url;

    const ETHEREUM_URL: &'static str = "https://ethereum-mainnet-rpc.allthatnode.com";

    const FAKE_CHAIN_ID: u64 = 9999999999;

    #[tokio::test]
    async fn test_get_chain() {
        let provider = ethers::providers::Http::new(Url::parse(ETHEREUM_URL).unwrap());
        let provider = Provider::new(provider);
        let chain = provider.get_chain().await.unwrap();
        assert_eq!(chain, ChainExt::Chain(Chain::Mainnet));

        let anvil = Anvil::new().chain_id(FAKE_CHAIN_ID).spawn();
        let provider = ethers::providers::Http::new(Url::parse(&anvil.endpoint()).unwrap());
        let provider = Provider::new(provider);
        let chain = provider.get_chain().await.unwrap();
        assert_eq!(chain, ChainExt::UnknownChain(FAKE_CHAIN_ID.into()));
    }
}
