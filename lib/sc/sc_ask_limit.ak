use aiken/builtin
use aiken/collection/list
use ask_limit/ask_types.{
  AskLimitAction, AskLimitConfig, Buy, BuyMulti, ExchangeConfig, Fill, PoolFills,
  Update,
}
use ask_limit/buy
use ask_limit/order
use ask_limit/update_order
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{Input, Output, OutputReference, Transaction, Withdraw}
use daken/pairs as daken_pairs
use daken/time
use daken/types.{OK} as daken_types
use env
use utils

pub fn spend(
  AskLimitAction { indexers, order_in_idx, .. }: AskLimitAction,
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
  expect Script(ask_skh) = payment_credential
  //
  when indexers is {
    Update(cont_ou_idx) ->
      update_order.verify(
        ask_skh,
        own_ref,
        order_in_idx,
        cont_ou_idx,
        inputs,
        outputs,
        extra_signatories,
      )
    // The Buy branch checks nothing about money on its own. It proves only
    // that this order appears in the fill list, then defers to withdraw, so
    // all the arithmetic lives in one place.
    //
    // The list is read straight out of the withdraw redeemer rather than
    // carried here and compared against it. A transaction holds exactly one
    // withdrawal per credential, so this is the redeemer that will run: there
    // is nothing to compare and nothing that can drift apart. Without a
    // withdrawal, `get_first` aborts.
    Buy -> {
      expect AskLimitAction { indexers: BuyMulti(pool_fills), .. }: AskLimitAction =
        daken_pairs.get_first(redeemers, Withdraw(payment_credential))
      fill_exists(pool_fills, order_in_idx)?
    }
    BuyMulti(_) -> fail @"BuyMulti is only for the withdraw branch"
  }
}

pub fn withdraw(
  AskLimitConfig{config_nft: (cfg_pid, cfg_tn)}: AskLimitConfig,
  AskLimitAction { indexers, config_ref_idx, fee_ou_idx, .. }: AskLimitAction,
  cre: Credential,
  Transaction { inputs, reference_inputs, outputs, validity_range, .. }: Transaction,
) -> Bool {
  expect BuyMulti(pool_fills) = indexers
  expect Script(ask_skh) = cre
  //
  expect cfg: ExchangeConfig =
    utils.get_datum_by_idx(reference_inputs, cfg_pid, cfg_tn, config_ref_idx)
  let ExchangeConfig { fee_addr, .. } = cfg
  let fee_val = order.get_fee_value(outputs, fee_ou_idx, fee_addr, ask_skh)
  //
  // Reuses the pool contract's validity-range check unchanged: same env.ttl,
  // same units, no second notion of time invented here.
  expect OK((_tx_start, tx_end)) =
    time.tx_validity_valid_with_boundaries(
      validity_range,
      env.slot_length,
      Some(env.ttl),
      True,
    )
  //
  buy.verify(
    ask_skh,
    cfg,
    pool_fills,
    inputs,
    reference_inputs,
    outputs,
    fee_val,
    tx_end,
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
