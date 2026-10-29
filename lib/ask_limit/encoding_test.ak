//// Pins the CBOR shapes that on-chain and off-chain must agree on. Every
//// string below came from the off-chain builder. Change a shape on one side
//// and forget the other, and this test goes red rather than the validator
//// refusing every transaction once the UTxO is already on chain.

use aiken/cbor
use ask_limit/ask_types.{AskDatum, ExchangeConfig}
use ask_limit/fixture
use cardano/address.{Address, Inline, VerificationKey}

/// fee_addr is an enterprise address (no stake), buyer_fee 20, seller_fee 10,
/// and a single-element allowlist.
const config_datum_enterprise =
  #"d8799fd8799fd8799f581cf1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1ffd87a80ff140a9f581cfbfe1688e61ff0e52da1ccbaf1b3a601c66b670272ddb5e197ca39bdffff"

/// The same config, but with a fee_addr that has a stake credential.
const config_datum_with_stake =
  #"d8799fd8799fd8799f581cf1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1ffd8799fd8799fd8799f581ce2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2ffffffff140a9f581cfbfe1688e61ff0e52da1ccbaf1b3a601c66b670272ddb5e197ca39bdffff"

const fee_pkh = #"f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

const fee_stake = #"e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"

const pt_policy = #"fbfe1688e61ff0e52da1ccbaf1b3a601c66b670272ddb5e197ca39bd"

test config_datum_from_offchain_parses() {
  expect Some(raw) = cbor.deserialise(config_datum_enterprise)
  expect cfg: ExchangeConfig = raw
  and {
    cfg.buyer_fee == 20,
    cfg.seller_fee == 10,
    cfg.pt_policies == [pt_policy],
    cfg.fee_addr == Address {
      payment_credential: VerificationKey(fee_pkh),
      stake_credential: None,
    },
  }
}

test config_datum_with_stake_parses() {
  expect Some(raw) = cbor.deserialise(config_datum_with_stake)
  expect cfg: ExchangeConfig = raw
  cfg.fee_addr == Address {
    payment_credential: VerificationKey(fee_pkh),
    stake_credential: Some(Inline(VerificationKey(fee_stake))),
  }
}

/// AskDatum, as the off-chain builder emits it. It is built for every sell
/// order, so a wrong shape makes the order unbuyable.
const ask_datum_offchain =
  #"d8799f581ca1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a11905dcff"

test ask_datum_from_offchain_parses() {
  expect Some(raw) = cbor.deserialise(ask_datum_offchain)
  expect dt: AskDatum = raw
  dt == AskDatum { owner_vk: fixture.alice_vk, requested_yield: 1_500 }
}

/// The tag on the seller payout output and on the fee output: a bare bytearray,
/// with no constructor wrapper. `buy.verify` and `order.get_fee_value` read it
/// with `expect tag: ByteArray`, so one layer of wrapping fails the whole
/// transaction.
const payout_tag_offchain =
  #"581ca0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0"

test payout_tag_from_offchain_parses() {
  expect Some(raw) = cbor.deserialise(payout_tag_offchain)
  expect tag: ByteArray = raw
  tag == fixture.ask_skh
}
