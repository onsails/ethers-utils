use crate::chain::*;
use async_trait::async_trait;
use ethers::{providers::Middleware, types::Chain};

#[async_trait]
pub trait MiddlewareExt: Middleware {
    async fn get_chain_variant(&self) -> Result<ChainVariant, Self::Error> {
        let chain_id = self.get_chainid().await?;

        match Chain::try_from(chain_id) {
            Ok(chain) => Ok(ChainVariant::Chain(chain)),
            Err(_) => Ok(ChainVariant::UnknownChain(chain_id)),
        }
    }
}

impl<M: Middleware> MiddlewareExt for M {}

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::types::Chain;
    use ethers::{providers::Provider, utils::Anvil};
    use url::Url;

    const ETHEREUM_URL: &'static str = "https://ethereum-mainnet-rpc.allthatnode.com";

    const FAKE_CHAIN_ID: u64 = 9999999999;

    #[tokio::test]
    async fn test_get_chain_variant() {
        let provider = ethers::providers::Http::new(Url::parse(ETHEREUM_URL).unwrap());
        let provider = Provider::new(provider);
        let chain = provider.get_chain_variant().await.unwrap();
        assert_eq!(chain, ChainVariant::Chain(Chain::Mainnet));

        let anvil = Anvil::new().chain_id(FAKE_CHAIN_ID).spawn();
        let provider = ethers::providers::Http::new(Url::parse(&anvil.endpoint()).unwrap());
        let provider = Provider::new(provider);
        let chain = provider.get_chain_variant().await.unwrap();
        assert_eq!(chain, ChainVariant::UnknownChain(FAKE_CHAIN_ID.into()));
    }
}
