# Empowa Swap – Test Key & Redeemer Set

This directory contains a set of **redeemer** and **key** files for testing on the real Cardano mainnet.
The `aiken.toml` configuration is designed to use these files directly.

---

## 🛠 Quick Setup

To initialize the environment variables, run:

```bash
. ./init.sh
```

You can run this from any working directory — the script will configure everything automatically.

---

## 🌐 Environment Variables

| Variable             | Description                         |
| -------------------- | ----------------------------------- |
| `TX_FILES`           | Root path to this test directory    |
| `NFT_CORRECT_NAME`   | Correct NFT name used in tests      |
| `NFT_INCORRECT_NAME` | Legacy NFT name used for comparison |
| `PO_ASSET_NAME`      | Asset name for payout token (EMP)   |
| `EXCH_TIME`          | Exchange timestamp (mocked)         |
| `RECALL_TIME`        | Recall timestamp (mocked)           |

---

## 🔑 Keys & Addresses

Each entity has associated variables for vkey, skey, and id/address/script:

| Entity | Prefix   | Purpose                                 |
| ------ | -------- | --------------------------------------- |
| NFT    | `NFT_`   | NFT policy keys and script              |
| POA    | `POA_`   | Policy for payout asset (EMP)           |
| User   | `USER_`  | User's address and keys                 |
| Owner  | `OWNER_` | Contract owner's address, keys, keyhash |

---

## 🧾 Redeemers

| Variable        | Description               |
| --------------- | ------------------------- |
| `BOOTSTRAP_RDM` | Redeemer for bootstrap TX |
| `EXCHANGE_RDM`  | Redeemer for exchange TX  |
| `RECALL_RDM`    | Redeemer for recall TX    |

---

