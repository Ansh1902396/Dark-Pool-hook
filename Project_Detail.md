# DarkCoW — Project Detail

**A privacy-preserving dark-pool CoW hook for Uniswap v4.**
Orders are intercepted by a v4 hook, escrowed as ERC-6909 claims, matched off-chain by an EigenLayer AVS operator network, proven valid in a zero-knowledge (SP1) circuit, and settled as one net result through the pool.

- **Author:** Ayush Petwal
- **Built in:** Uniswap Hook Incubator (UHI) cohort — Atrium Academy
- **Languages:** Solidity · Rust · TypeScript
- **Repo:** https://github.com/1Ayush-Petwal/Dark-Pool-hook
- **Demo (Loom):** https://www.loom.com/share/7842254d0a8e49a1820b263b215090f0

> ⚠️ **Note for the author:** Sections 1–7 are post-ready narrative. **Section 8 (Implementation status) and Section 9 (Claim guide) are the source of truth for what to say publicly** — read them before writing the post. This file lives in `website/public/`, which is **served at your deployed URL** (e.g. `…/Project_Detail.md`). If you don't want the status/roadmap reachable publicly, move this file out of `public/` or gitignore it.

---

## 1. The problem

On a public AMM, your order sits in the mempool in plain sight — size, direction, and the slippage you'll tolerate. Searchers read it and front-run, sandwich, and back-run you. The larger the trade, the heavier the MEV tax.

TradFi solved this with **dark pools**: venues where large orders match privately, away from the public book. DarkCoW brings that idea on-chain and aims to remove the trusted operator — matching is done by a restaking-secured network and order validity is *proven*, not trusted.

## 2. What it is

A **dark pool expressed as a Uniswap v4 hook**. Instead of routing a swap straight onto the curve, the hook escrows the input and hands the order to an operator network that looks for **coincidences of wants** (CoW) — two or more traders whose orders cancel out — and settles the net. Anything unmatched falls back to the AMM.

## 3. Architecture at a glance

| Component | Path | Role |
|---|---|---|
| **DarkCoWHook** | `hook/src/DarkCoWHook.sol` | v4 hook: `beforeSwap` escrow (ERC-6909), task creation, `unlockCallback`/`settleBalances` net settlement |
| **OrderServiceManager** | `avs/contract/src/OrderServiceManager.sol` | EigenLayer AVS: task lifecycle, operator registration, batched ECDSA responses, proof-verification hook |
| **Operator / CoW engine** | `operator/index.ts`, `operator/matching.ts` | Off-chain batching (~10 blocks), direct + circular match detection, AMM quoting, signing |
| **ZK circuit** | `order-engine/program`, `order-engine/lib` | SP1 zkVM guest: nullifier, Merkle inclusion, order-validity checks |
| **Proving service** | `order-engine/server` | Rust/axum server: generates + verifies Groth16 proofs via the SP1 SDK |
| **CrossChainRouter** | `hook/src/CrossChainRouter.sol` | Across-based bridging — **design scaffold, not yet wired** (see §8) |

## 4. How it works — the order lifecycle

1. **A swap arrives.** The user routes a swap; PoolManager unlocks and fires the hook's `beforeSwap`, with the intent in `hookData`.
2. **Escrow as ERC-6909.** The hook mints ERC-6909 claim tokens for the input and takes custody, so the order can be matched privately instead of hitting the curve immediately.
3. **Create a task.** The hook calls the AVS service manager, which records the order as a task and emits `NewTaskCreated`.
4. **Batch & match.** Operators collect tasks over a ~10-block window and search for coincidences of wants — direct 2-party pairs and 3-party circular matches via cycle detection — with an AMM quote as fallback.
5. **Prove validity.** Each order is checked inside an SP1 zkVM circuit: a fresh nullifier (replay protection), Merkle inclusion of the commitment, and balance / price / deadline checks.
6. **Respond on-chain.** Operators sign the batch (ECDSA) and call `respondToBatch`; the contract is designed to verify the Groth16 proof through `ISP1Verifier` before settling.
7. **Settle the net.** `settleBalances` re-locks PoolManager: burn claims, pay matched traders directly, route only the residual through the pool.
8. **Bridge (future).** For cross-chain intents, a router would hand the output to an Across spoke pool. *(Planned — see §8.)*

## 5. What I built — by skill area

**I · Uniswap v4 Hook** — Solidity, ERC-6909, Foundry
`beforeSwap` + `beforeSwapReturnDelta` take over execution from the pool; ERC-6909 claim accounting holds orders mid-flight; custom settlement through `unlockCallback` nets matched balances.

**II · EigenLayer AVS** — EigenLayer, ECDSA, Solidity, TypeScript
`ECDSAServiceManagerBase` task lifecycle (create → respond); restaking-based operator registration; batched responses gated by signature recovery; a proof-verification entry point and a slashing surface.

**III · Zero-Knowledge order validity** — Rust, SP1 zkVM, Groth16
An SP1 guest circuit proves order validity without revealing the secret inputs: nullifier hashes (replay/double-spend protection), Merkle commitment-inclusion, and balance/price/deadline checks. A Rust/axum service produces and verifies genuine Groth16 proofs.

**IV · CoW matching** — TypeScript, viem/ethers, graph cycle detection
A coincidence-of-wants engine that finds direct pairs and 3-party circular matches by graph traversal, with v4 Quoter AMM fallback.

## 6. Tech stack

`Solidity ^0.8.26` · `Uniswap v4 (v4-core / v4-periphery)` · `Foundry` · `EigenLayer middleware (ECDSAServiceManagerBase)` · `SP1 zkVM + SP1 SDK (Groth16)` · `Rust (axum, tokio, sha2)` · `TypeScript (viem, ethers)` · `Anvil`

## 7. Skills demonstrated

- **Smart contracts:** Uniswap v4 internals (hooks, flash accounting, ERC-6909, custom settlement), Solidity delta math & transient locks, Foundry scripting/forking/tests.
- **Cryptography & ZK:** SP1 zkVM guest authoring, Groth16 prove/verify pipeline, commitment schemes (Merkle inclusion + nullifier replay protection).
- **Protocol & infra:** EigenLayer AVS / restaking, MEV mitigation via private batch matching, intent-based design.
- **Systems & full-stack:** Rust axum/tokio proving service, event-driven TS operator, distributed batching/signing/verification.

---

## 8. Implementation status

> **Decision (2026-05-30):** the A+B upgrades (real CoW settlement + real on-chain Groth16 verification) are **deferred** — not funding the Succinct Prover Network for now. The rows below reflect the **true current state**, and the website has been aligned to only what's genuinely built: the cross-chain section and the "proof verified on-chain before settlement" / "order stays secret" / slashing claims were **removed or softened**.

Legend: ✅ **Working today** · 🟡 **Partially wired** · 🧪 **Prototype (standalone)** · 📐 **Designed / future work**

| Area | Status | Detail |
|---|---|---|
| v4 hook: escrow + task creation | ✅ | `beforeSwap` mints ERC-6909 and calls `createNewTask`; `afterInitialize` stores the pool key. Solid and demoable. |
| AVS: task lifecycle + operator registration | ✅ | `createNewTask → NewTaskCreated`, ECDSA stake-registry registration, signature recovery in `respondToBatch`. Covered by Foundry tests. |
| CoW match **detection** (direct + circular) | ✅ | `operator/index.ts` detects 2-party direct and 3-party circular matches and quotes the v4 Quoter. Genuinely works. |
| SP1 ZK circuit + proving server | ✅🧪 | The guest circuit (nullifier, Merkle, order validity) is real, and `order-engine/server` generates **and verifies a genuine Groth16 proof** via the SP1 SDK. Standalone today; integrated on-chain by **Fix B**. |
| v4 hook: net settlement (funds move) | 🟡 | `unlockCallback`/`settleBalances` implement real burn/take/swap netting, but the operator currently submits **empty** balance arrays, so nothing settles in the live path. *(Would be Fix A — deferred.)* |
| CoW match **settlement** | 🟡 | Matches are detected and logged, but `computeBalances` is never called, so funds don't move. *(Would be Fix A — deferred.)* |
| ZK **end-to-end integration** | ❌📐 | Not wired: prover fed hardcoded mock data; proof generated off-chain after settlement; on-chain `verifyProof` is fed the ECDSA signature against an unrouted `SP1VerifierGateway(address(1))`; `:3000`/`:8080` port mismatch. *(Would be Fix B — deferred.)* |
| On-chain **order hiding** | 📐 | Even after A+B: order params (`zeroForOne`, `amountSpecified`, `sqrtPriceLimit`, `sender`, `poolId`) are still emitted in **plaintext** in `NewTaskCreated`. The ZK proves validity without revealing the trader's **balance/nullifier/secret**, but the order itself is not hidden on-chain. Full order hiding is future work. |
| Operator slashing | 📐 | `slashOperator` is commented out — registration + signatures only, no economic slashing yet. |
| Cross-chain (Across) | 📐 | `CrossChainRouter.sol` is an isolated draft — **never imported, deployed, or called**. Not part of the running system. |

## 9. Claim guide for the post

**✅ Safe to claim (true today):**
- "Built a custom **Uniswap v4 hook** that intercepts swaps in `beforeSwap` and escrows input as **ERC-6909** claim tokens using v4 flash accounting, instead of hitting the AMM directly."
- "Built an **EigenLayer AVS** (`ECDSAServiceManagerBase`): restaking-based operator registration, an on-chain task lifecycle, and ECDSA-signed batched operator responses."
- "Built a **coincidence-of-wants matching engine** that detects **direct 2-party and 3-party circular** matches over a batched window, with a Uniswap v4 Quoter AMM fallback."
- "Wrote a **zero-knowledge circuit for the SP1 zkVM** proving order validity — nullifier replay-protection, Merkle commitment inclusion, and balance/price/deadline checks — plus a Rust/axum service that **generates and verifies real Groth16 proofs**."
- "Spans **Solidity, Rust, and TypeScript**; designed end-to-end in the **Uniswap Hook Incubator**."

**🟡 Soften / don't claim (not built):**
- ❌ "Matched orders settle trustlessly on-chain." → ✅ *"CoW match detection works; net on-chain settlement isn't wired yet (the operator submits empty balances)."*
- ❌ "ZK proof verified on-chain before settlement." → ✅ *"A standalone SP1 service generates real Groth16 proofs of order validity; on-chain verification gating settlement isn't wired."*
- ❌ "End-to-end privacy / the order stays secret on-chain." → ✅ *"The ZK proof shows each order is **valid without revealing the trader's balance or secret (nullifier)**, and orders match **off the public AMM curve**. Order parameters are still recorded on-chain in the task event — full order hiding is future work."*
- ❌ "Cross-chain settlement via Across." → ✅ *"Cross-chain delivery is scaffolded for a future version (not built)."*
- ❌ "Slashing-secured operator network." → ✅ *"Restaking-registered operators with ECDSA-signed responses (slashing is future work)."*

**One honest, recruiter-strong framing (current state):**
> "DarkCoW is a dark-pool **CoW hook for Uniswap v4**: a working v4 hook + ERC-6909 escrow, an **EigenLayer AVS** operator network with on-chain task lifecycle, a **CoW matching engine** (direct + circular), and a **zero-knowledge order-validity circuit** on the SP1 zkVM with a real Groth16 prover. On-chain proof-gated settlement and cross-chain delivery are the roadmap."

## 10. A demo you can actually record (all real)

1. `anvil` → deploy EigenLayer core + AVS → deploy the hook → `setHook`.
2. `npx ts-node operator/index.ts` — operator registers with the AVS and starts monitoring.
3. `npx ts-node operator/createNewTasks.ts` — fire swaps; show the **hook escrowing input as ERC-6909** and **`NewTaskCreated`** firing.
4. Show the operator console **detecting direct + circular CoW matches** and AMM-quoting the batch.
5. In a separate panel, hit the **SP1 proving server** directly and show it **producing and verifying a real Groth16 proof** of order validity (cycle count, `valid: true`, proof bytes).

> This shows everything that genuinely works **today** — hook, AVS task flow, CoW match detection, and real ZK proving — without implying on-chain proof-gated settlement or cross-chain, which aren't wired.

## 11. Links & credits

- **Repo:** https://github.com/1Ayush-Petwal/Dark-Pool-hook
- **Loom demo:** https://www.loom.com/share/7842254d0a8e49a1820b263b215090f0
- **UHI hook directory:** https://atriumacademy.notion.site/hook-directory
- **Certificate of completion (onchain):** https://explorer.zora.energy/token/0xbd28D087baEAAA860d9a251536d07657B16491aB/instance/76
- **LinkedIn:** https://www.linkedin.com/in/ayushpetwal/ · **X:** https://x.com/ayush_P_145
