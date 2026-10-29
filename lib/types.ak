use cardano/assets.{AssetName, PolicyId}
use daken/types.{Basis, TupleAsset} as daken_types

pub type OriginToken =
  TupleAsset

pub type YieldToken =
  TupleAsset

pub type PoolDatum {
  supply_token: (YieldToken, OriginToken),
  pt_supply: Int,
  yt_supply: Int,
  // timestamp
  supply_maturity: Int,
  collaterals: PoolCollaterals,
  base_interest_rate: Basis,
  gradient: Basis,
  // millisecond
  max_duration: Int,
  loan_activated: Int,
  fee_collected: Bool,
  min_borrow_amount: Int,
}

pub type PoolCollaterals =
  Pairs<CollateralToken, LiquidationThreshold>

pub type CollateralToken =
  TupleAsset

pub type LiquidationThreshold =
  Basis
