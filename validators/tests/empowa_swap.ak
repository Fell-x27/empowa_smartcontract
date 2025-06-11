use cardano/address.{Address}
use cardano/assets.{from_asset, from_asset_list, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use empowa_swap.{Bootstrap, Exchange}
use env.{
  assets_owner_pcred, contract_pcred, contract_policy_id,
  contract_treasury_asset_name, dist_asset_name, dist_asset_pid, n2a_change_rate,
  nft_name, nft_pid, start_change_time, unlock_unclaimed_assets_time,
  utxo_def_ref,
}

test contract_bootstrap() {
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: Address(assets_owner_pcred, None),
        value: from_asset(dist_asset_pid, dist_asset_name, 10_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: Address(assets_owner_pcred, None),
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: Address(assets_owner_pcred, None),
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let script_output =
    Output {
      address: Address(contract_pcred, None),
      value: from_asset_list(
        [
          Pair(dist_asset_pid, [Pair(dist_asset_name, 10_000)]),
          Pair(contract_policy_id, [Pair(contract_treasury_asset_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_asset_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, script_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    asset_pid: dist_asset_pid,
    asset_name: dist_asset_name,
    nft_pid: nft_pid,
    nft_name: nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    unlock_unclaimed_assets_pcred: assets_owner_pcred,
    redeemer: Bootstrap,
    contract_pid: contract_policy_id,
    tx: tx,
  )
}

test burning_success() {
  empowa_swap.empowa_swap.spend(
    dist_asset_pid,
    dist_asset_name,
    nft_pid,
    nft_name,
    n2a_change_rate,
    start_change_time,
    unlock_unclaimed_assets_time,
    assets_owner_pcred,
    None,
    Exchange,
    Void,
    placeholder,
  )
}
