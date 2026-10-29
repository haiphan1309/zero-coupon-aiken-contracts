# Zero Coupon — Ask/Bid Limit Order Book

Aiken (Plutus V3) validators for the limit order book that trades **PT**
(principal tokens) of the Zero Coupon fixed-rate lending protocol on Cardano.

| Validator | The maker posts | The taker does |
|---|---|---|
| `ask_limit` | PT, asking for a yield | buys PT, paying the order's token |
| `bid_limit` | the order's token, offering a yield | sells PT into the order |

A PT is a claim on a fixed amount at a fixed maturity, so an order is quoted as
a **yield**, not a price, and the price follows from when the transaction
settles.

This repository holds the order-book contracts only. Pools, loans, the oracle
and governance live elsewhere; `lib/types.ak` keeps `PoolDatum` because the
validators read a pool's datum as a reference input to learn a PT's maturity
and face value.

## Build and test

Needs [Aiken](https://aiken-lang.org) **v1.1.17**. The only dependency fetched
from the network is `aiken-lang/stdlib` v2.2.0. `lib/daken/` holds eleven
general-purpose modules vendored unmodified from an Apache-2.0 library that is
not publicly hosted, which is what lets a clean clone build.

```sh
aiken check     # 295 tests
aiken build     # writes plutus.json
```

## What the validators govern

Creating an order runs no validator: it is a plain payment to the script
address with an inline datum. The validators govern only what happens when an
order is spent.

- **spend** — one order being consumed. It carries no fill list; it reads one
  from the `withdraw` redeemer. Carrying it per input would repeat the list
  N+1 times in a transaction, growing bytes and CPU as N².
- **withdraw** — runs once, checks every fill together, grouped by pool so each
  `PoolDatum` is read once.

Price is taken from the validity bound **unfavourable to the taker**: `tx_end`
for ask, `tx_start` for bid. The other bound would hand the taker a free
discount on every fill.

## Deployed on Preview

Both validators share one config NFT: policy
`bc2d3b7cf1009c788b1daf2208a38026ab20d7f8209d896ad1a09c14`, name
`e0b8368b6afdf93de52aa934b888455f307831a6711681272b5142e769ff6d9a`.

| | script hash |
|---|---|
| `ask_limit.exec` | `2a09a081b7b020396954641cd798e586bdf942aca436146b23d79773` |
| `bid_limit.exec` | `84e9582b77f7c2bd2244aebf56e0ee212bd5c5372ac7235fef808409` |

Addresses and reference-script UTxOs are in `deployments/`. Those are the
enterprise form of the address; orders are placed at the base form of the same
credential, so on an explorer they read `addr_test1z…` rather than
`addr_test1w…`.

**`ask_limit` is live; `bid_limit` is deployed but not yet in service.** As of
29 October 2026 the ask credential has taken part in 111 transactions; the bid
credential has 6, all within twenty-three minutes on 24 September 2026, proving
the validator on chain.

### Reproducing the hashes

`aiken build` yields the **unapplied** scripts:

```
ask_limit.exec   20938d0a64652b6893028082da4e38091a22f53d23b341a1e682f93e
bid_limit.exec   9ea3647d907045707144a5068f0da87fecc9b8f963bc848fc475026d
```

Applying the config NFT gives the deployed hashes above. The parameter is
`AskLimitConfig { config_nft }` / `BidLimitConfig { config_nft }`, with both the
constructor and the `(policy_id, asset_name)` pair encoded as
**indefinite-length** CBOR arrays — definite-length ones compile to a different
script:

```
d8799f9f581cbc2d3b7cf1009c788b1daf2208a38026ab20d7f8209d896ad1a09c145820
e0b8368b6afdf93de52aa934b888455f307831a6711681272b5142e769ff6d9affff
```

```sh
aiken blueprint apply -m ask_limit -v exec <the hex above, joined to one line>
aiken blueprint apply -m bid_limit -v exec <the hex above, joined to one line>
```

## Note on the Preview clock

`env/default.ak` builds against Preview with a compressed calendar: a day is
360 000 ms, so a year is 131 400 000 ms — about 36.5 real hours. Read any
duration here with that in mind.

## Licence

Apache-2.0. See `LICENSE`.
