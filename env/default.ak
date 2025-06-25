use cardano/address.{Address, Script, VerificationKey}
use cardano/transaction.{OutputReference}
use config.{owner_key_hash}

// A set of constants defined here to simplify writing tests

pub const assets_owner_pcred = VerificationKey(owner_key_hash)

pub const user_pcred = VerificationKey("Some user")

pub const contract_policy_id = "CONTRACT"

pub const contract_pcred = Script(contract_policy_id)

pub const utxo_def_ref = OutputReference("any", 0)

pub const utxo_contract_ref = OutputReference("contract", 0)

pub const user_address = Address(user_pcred, None)

pub const contract_address = Address(contract_pcred, None)

pub const owner_address = Address(assets_owner_pcred, None)
