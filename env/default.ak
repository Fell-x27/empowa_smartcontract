use cardano/address.{Address, Script, VerificationKey}
use cardano/transaction.{OutputReference}
use config

// A set of constants defined here to simplify writing tests

pub const payout_asset_pid = "EMP_policy_id"

pub const payout_asset_name = "EMP"

pub const burn_nft_pid = "NFT_policy_id"

pub const burn_nft_name = "NFT name pattern"

pub const n2a_change_rate = 1100

pub const start_change_time = config.contract_exchange_start_after

pub const unlock_unclaimed_assets_time = 10

pub const assets_owner_pcred = VerificationKey("EMP owner")

pub const user_pcred = VerificationKey("Some user")

pub const contract_policy_id = "BURNER"

pub const contract_pcred = Script(contract_policy_id)

pub const contract_treasury_marker_name = config.contract_treasury_marker_name

pub const utxo_def_ref = OutputReference("any", 0)

pub const utxo_contract_ref = OutputReference("contract", 0)

pub const user_address = Address(user_pcred, None)

pub const contract_address = Address(contract_pcred, None)

pub const owner_address = Address(assets_owner_pcred, None)
