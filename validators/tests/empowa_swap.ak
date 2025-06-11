use cardano/address.{VerificationKey}
use cardano/transaction.{placeholder}
use empowa_swap
use env.{
  asset_name, asset_pid, n2a_change_rate, nft_name, nft_pid, start_change_time,
  unlock_unclaimed_assets_pcred, unlock_unclaimed_assets_time,
}

test contract_bootstrap() {
  empowa_swap.empowa_swap.mint(
    asset_pid,
    asset_name,
    nft_pid,
    nft_name,
    n2a_change_rate,
    start_change_time,
    unlock_unclaimed_assets_time,
    unlock_unclaimed_assets_pcred,
    Void,
    "",
    placeholder,
  )
}

test burning_success() {
  empowa_swap.empowa_swap.spend(
    asset_pid,
    asset_name,
    nft_pid,
    nft_name,
    n2a_change_rate,
    start_change_time,
    unlock_unclaimed_assets_time,
    unlock_unclaimed_assets_pcred,
    None,
    Void,
    Void,
    placeholder,
  )
}
