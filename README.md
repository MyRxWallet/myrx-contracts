# myrx-contracts

Smart contracts deployed on **MYRX-MAINNET** (Chain 8472).

All contracts are MIT licensed, Slither-audited, and owned by the protocol multisig.

## Deployed Addresses

| Contract | Address | Description |
|---|---|---|
| WMRT | `0x5A08434f87c8189F31b9FFDeA7CF64e5704691fc` | Wrapped native MRT token |
| WBTC | `0x0602D45DF10436bA26Aa4FD0e8f5baA60b1BE0D1` | Wrapped Bitcoin — bridge-controlled mint/burn |
| MyrxBTCBridge | `0x8f650C43A1e94c29Ed038C0F19458FbE42A68d05` | BTC peg-in/peg-out bridge |
| MyrxSwap Factory | `0x83995Ac39CED53a93E77Ab5d194E43D47e076b34` | DEX pair factory |
| MyrxSwap Router | `0x5Bde6072B6C4443BC993bb1cDD4f311383739c41` | DEX swap router |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` | Canonical multicall |

## Security

- Slither 0.11.5 audit passed (no high/critical findings)
- CEI (Checks-Effects-Interactions) pattern enforced
- Bridge: replay protection via `btcTxHash` mapping, 10 BTC daily cap, pause switch
- Forge test suite: 23/23 passing

## Build

```bash
forge build
forge test
```

Requires [Foundry](https://getfoundry.sh).

## License

MIT — MyRxWallet North America Corporation
