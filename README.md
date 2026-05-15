# myrx-contracts

Smart contracts for MYRX-MAINNET (Chain ID 8472).

## Deployed Addresses (post-reset 2026-05-15)

| Contract | Address |
|---|---|
| WMRT | 0x00e69754c21090d69d29a2abe3b6cf153d3f1df7 |
| WBTC | 0xc8604c8fcf96cec581e8275a2cdf04e7f7348849 |
| MyrxBTCBridge | 0xc9be40494ef767a8760682d93de014e825bdb3e8 |
| MRTBridgeLock | 0x2819b247260e49a0c31cb60e8165b6ba38851920 |
| MRTDexFactory | 0x7e4a7cc7d9e4e416e7277f8309cc54cf5fd8af2b |
| MRTDexRouter | 0xe0eab9309910f7e0e60fc637af50b38a4b34ad2b |
| MRXSoulbound | 0xf307e448587babbbed2292679f8ce0b16da5c7b1 |
| MRTStaking | 0x50c984d1881ab005e5d5bbc00df643e75f40f9e1 |
| MRTGovernor | 0x431dc6e4b04207de550ee9ec1b07a9e72a486d13 |
| HealthDataMarket | 0xa7fbd8d2e6e51c12781dc75cc04b24998d5b84cf |
| MRTTokenFactory | 0x3b7b8326f4a83d1d3812ae9980cb7c8b5ad35bcf |

## Build

Requires [Foundry](https://getfoundry.sh).

```bash
forge build
forge test
```

## Contract Overview

| Contract | Description |
|---|---|
| WMRT | Wrapped MRT — ERC-20 wrapper for native MRT gas token (WETH-style) |
| WBTC | Wrapped BTC — 8-decimal ERC-20 minted 1:1 by the bridge |
| MyrxBTCBridge | Bitcoin bridge — mint WBTC on BTC deposit, burn on redemption |
| MRTBridgeLock | Lock MRT for cross-chain bridge operations |
| MRTDex | UniV2-style AMM factory + router |
| MRTStaking | MRT staking with rewards |
| MRTGovernor | On-chain governance |
| MRXSoulbound | Non-transferable identity/credential NFT |
| HealthDataMarket | Healthcare data marketplace |
| MRTTokenFactory | Permissionless ERC-20 factory |
| MerkleDropper | Merkle-proof token distribution |

## Security

See [SECURITY.md](SECURITY.md) for responsible disclosure.

## License
MIT — MyRxWallet North America Corporation 2026
