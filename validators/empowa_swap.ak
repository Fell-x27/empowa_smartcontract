use cardano/address.{PaymentCredential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference, Transaction}

validator empowa_swap(
  asset_pid: PolicyId,
  asset_name: AssetName,
  nft_pid: PolicyId,
  nft_name: AssetName,
  n2a_change_rate: Int,
  start_change_time: Int,
  unlock_unclaimed_assets_time: Int,
  unlock_unclaimed_assets_pcred: PaymentCredential,
) {
  spend(_d, _r, _u, _tx: Transaction) {
    todo
  }

  mint(_r, _pid, _tx: Transaction) {
    todo
  }

  else(_) {
    fail
  }
}
