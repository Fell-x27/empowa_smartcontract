# empowa\_swap

## 🛠 Building

To build the contract, simply run:

```sh
./build.sh
```

The script generates artifacts for both **mainnet** and **testnet** under the `./artifacts/` directory.

---

## 📁 Project Structure

* `validators/` — contains the validator and a set of tests for different phases.
* `lib/` — shared logic:

  * `helpers.ak` — utility functions.
  * `types.ak` — type definitions (currently includes only the contract phase type).
* `tx_files/` — holds keys, redeemers, and its own `README.md`.
* `aiken.toml` — contract configuration defining behavior and parameters.

---

## 📖 Glossary

* **PO\_asset** — the `payout_asset_pid.payout_asset_name` asset.
* **Receipt\_NFT** — NFT with the `burn_nft_pid` policy and a name starting with `burn_nft_name`.
* **Treasury\_marker** — a service token marking a `Treasury_UTxO` at the smart contract address.
* **Treasury\_UTxO** — a UTxO at the contract address containing 1 `Treasury_marker` and some `PO_asset`.
* **Base\_ada** — a minimum amount of ADA required to create a UTxO with an asset.
* **Exchange\_rate** — the rate of conversion from `Receipt_NFT` to `PO_asset`, defined in config.
* **owner\_key\_hash** — the hash of the owner's payment key, specified in the contract config.

## 🧾 Redeemers and Contract Phases

To set the contract phase, use the appropriate redeemer from the `./tx_files/redeemers` folder.

### 🔹 Bootstrap Phase

> Initializes the treasury by locking `PO_asset` at the contract address and minting a `Treasury_marker` for each output.

#### TX Structure

* **Inputs**:

  * *(required, ≥1)* Any UTxO(s) containing some amount of `PO_asset` and ADA

* **Outputs**:

  * *(required, ≥1)* Contract address output(s) with `Treasury_UTxO`, each containing:

    * *(required)* exactly `contract_treasury_lovelace_quantity` of `Base_ada`
    * *(required)* `contract_treasury_asset_quantity` of `PO_asset`
  * *(optional, ≥0)* User's change

* **Minting**:

  * *(optional, ≥1)* `Treasury_marker` with a positive quantity (minted), equal to the number of contract address outputs

#### Validation Logic

* Ensure that `Treasury_marker` is not present in any input (it may only be minted)
* Ensure that exactly one `Treasury_marker` is minted per contract output
* Treasury creation with less than `contract_treasury_asset_quantity` of `PO_asset` is not allowed
* Treasury creation with less than `contract_treasury_lovelace_quantity` lovelaces is not allowed
* Treasury creation with `contract_treasury_marker` > 1 is not allowed

---

### 🔹 Exchange Phase

> Allows users to burn `Receipt_NFT` and receive a proportional amount of `PO_asset` from the treasury.

#### TX Structure

* **Inputs**:

  * *(required, ≥1)* `Treasury_UTxO`
  * *(required, ≥1)* User’s UTxO(s) containing some amount of `Receipt_NFT` (could contain some user's `PO_asset`)
  * *(optional, ≥0)* User’s UTxO(s) containing any other assets (e.g., to cover transaction fees) (could contain some user's `PO_asset`)

* **Outputs**:

  * *(required, ≥1)* User outputs containing `PO_asset` in an amount equal to the number of burned `Receipt_NFT` × `Exchange_rate`, with one output per each address that held a burned `Receipt_NFT`
  * *(optional, 0–1)* Smart contract output containing the remaining `Treasury_UTxO` only if `PO_asset` remains; otherwise, the `Treasury_UTxO` must be destroyed
  * *(optional, exactly 1)* Smart contract owner’s output containing any `Base_ada` left after the destruction of a `Treasury_UTxO`, if applicable

* **Minting**:

  * *(required, ≥1)* `Receipt_NFT` with a negative quantity (burned)
  * *(optional, ≥0)* `Treasury_marker` with a negative quantity (burned), but only if a `Treasury_UTxO` must be destroyed

* **Time range**:

  * *(required)* A timestamp indicating when exchange operations are allowed to begin

#### Validation Logic

* Collect the list of burned `Receipt_NFT` (not necessarily equal to the full list of input `Receipt_NFT`)
* Ensure that at least one `Receipt_NFT` was burned
* Use the burn list and inputs to build a payouts map of the form "address\:amount"
* If the user included their own `PO_asset` in the inputs, the full amount must be sent to one of their outputs and accounted for in the payout calculations
* Ensure that the amount of `PO_asset` in the `Treasury_UTxO` inputs covers the total amount to be paid to users
* Ensure that there are no redundant `Treasury_UTxOs`
* Ensure that the difference in `PO_asset` between the contract’s `tx_outputs` and `tx_inputs` equals the total user payouts
* Ensure that no excess base ADA was withdrawn from the contract address, if any is present
* Ensure that the real user payouts match their corresponding expected payouts, both by address and by the expected payout amount calculated from the burned NFTs
* If multiple `Treasury_UTxO` were used as `tx_inputs` (because one was insufficient), no more than one may remain in `tx_outputs`
* If one or more `Treasury_UTxO` were emptied, the `Treasury_marker` must be burned
* If one or more `Treasury_UTxO` were emptied, ensure that their `Base_ada` is returned to the contract owner's address
* Ensure that there is at most one contract output with `Treasury_marker` (exactly one item if any)
* Ensure that only the exact number of `PO_asset` required for payouts was moved from the treasury

---

### 🔹 Recall Phase

> Allows the contract owner to withdraw remaining `PO_asset` and ADA by destroying unused treasury outputs after expiration.

#### TX Structure

* **Inputs**:

  * *(required, ≥1)* Any UTxO from the contract’s address
  * *(optional, ≥0)* Any UTxO(s) containing any assets (e.g., to cover transaction fees)

* **Outputs**:

  * *(required, exactly 1)* Output to the contract owner's address, derived from `owner_key_hash` in the config file

* **Minting**:

  * *(optional, ≥0)* `Treasury_marker` with a negative quantity (burned), as any such token in the outputs is prohibited

* **Time range**:

  * *(required)* A timestamp indicating when recall operations are permitted to begin

#### Validation Logic

* Burning is allowed only after `unlock_unclaimed_assets_time`
* Ensure that the only output is sent to the address associated with `owner_key_hash`
* Ensure that no `tx_outputs` contain `contract_policy_id.contract_treasury_marker_name`
