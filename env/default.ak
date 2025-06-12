use cardano/address.{Script, VerificationKey}
use cardano/transaction.{OutputReference}
use config

// A set of constants defined here to simplify writing tests

pub const dist_asset_pid = "EMP_policy_id"

pub const dist_asset_name = "EMP"

pub const burn_nft_pid = "NFT_policy_id"

pub const burn_nft_name = "NFT name pattern"

pub const n2a_change_rate = 1100

pub const start_change_time = 1

pub const unlock_unclaimed_assets_time = 10

pub const assets_owner_pcred = VerificationKey("EMP owner")

pub const contract_policy_id = "BURNER"

pub const contract_pcred = Script(contract_policy_id)

pub const contract_treasury_asset_name = config.contract_treasury_asset_name

pub const utxo_def_ref = OutputReference("", 0)
