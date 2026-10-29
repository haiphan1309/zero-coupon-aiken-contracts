use aiken/builtin
use aiken/collection/list
use ask_limit/ask_types.{ExchangeConfig}
use ask_limit/order as shared
use bid_limit/bid_types.{
  BidDatum, BidIndexer, BidLimitAction, BidLimitConfig, Fill, PoolFills, Sell,
  SellMulti, Update,
}
use bid_limit/sell
use bid_limit/update_order
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{Input, Output, OutputReference, Transaction, Withdraw}
use daken/pairs as daken_pairs
use daken/time
use daken/types.{OK} as daken_types
use env
use utils

pub fn spend(
  BidLimitAction { indexers, order_in_idx, .. }: BidLimitAction,
  own_ref: OutputReference,
  Transaction { inputs, outputs, redeemers, extra_signatories, .. }: Transaction,
) -> Bool {
  // Our own script hash follows from the input being spent, so it needs no
  // parameter.
  let Input {
    output_reference,
    output: Output { address: Address { payment_credential, .. }, .. },
  } = inputs |> utils.tail_list_by_idx(order_in_idx) |> builtin.head_list
  expect output_reference == own_ref
  expect Script(bid_skh) = payment_credential
  //
  when indexers is {
    Update(cont_ou_idx) ->
      update_order.verify(
        bid_skh,
        own_ref,
        order_in_idx,
        cont_ou_idx,
        inputs,
        outputs,
        extra_signatories,
      )
    // The Sell branch checks nothing about money on its own. It proves only
    // that this order appears in the fill list, then defers to withdraw, so
    // all the arithmetic lives in one place.
    //
    // The list is read straight out of the withdraw redeemer rather than
    // carried here and compared against it. A transaction holds exactly one
    // withdrawal per credential, so this is the redeemer that will run: there
    // is nothing to compare and nothing that can drift apart.
    Sell -> {
      expect BidLimitAction { indexers: SellMulti(pool_fills), .. }: BidLimitAction =
        daken_pairs.get_first(redeemers, Withdraw(payment_credential))
      fill_exists(pool_fills, order_in_idx)?
    }
    SellMulti(_) -> fail @"SellMulti is only for the withdraw branch"
  }
}

pub fn withdraw(
  BidLimitConfig{config_nft: (cfg_pid, cfg_tn)}: BidLimitConfig,
  BidLimitAction { indexers, config_ref_idx, fee_ou_idx, .. }: BidLimitAction,
  cre: Credential,
  Transaction { inputs, reference_inputs, outputs, validity_range, .. }: Transaction,
) -> Bool {
  expect SellMulti(pool_fills) = indexers
  expect Script(bid_skh) = cre
  //
  expect cfg: ExchangeConfig =
    utils.get_datum_by_idx(reference_inputs, cfg_pid, cfg_tn, config_ref_idx)
  let ExchangeConfig { fee_addr, .. } = cfg
  let fee_val = shared.get_fee_value(outputs, fee_ou_idx, fee_addr, bid_skh)
  //
  // The same validity-range check ask_limit uses, on the same env.ttl. One
  // thing differs: take the LOWER bound. Price on this side is anchored to
  // tx_start — see bid_limit/price.
  expect OK((tx_start, _tx_end)) =
    time.tx_validity_valid_with_boundaries(
      validity_range,
      env.slot_length,
      Some(env.ttl),
      True,
    )
  //
  sell.verify(
    bid_skh,
    cfg,
    pool_fills,
    inputs,
    reference_inputs,
    outputs,
    fee_val,
    tx_start,
  )
}

fn fill_exists(pool_fills: List<PoolFills>, order_in_idx: Int) -> Bool {
  list.any(
    pool_fills,
    fn((_pool_ref_idx, fills)) {
      list.any(
        fills,
        fn(Fill { order_in_idx: idx, .. }) { idx == order_in_idx },
      )
    },
  )
}
