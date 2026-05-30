/* ───────────────────────────────────────────────────────────────
   Single source of truth for all copy + structured data.
   Edit here; every section reads from these exports.
   ─────────────────────────────────────────────────────────────── */

export const site = {
  name: "DarkCoW",
  title: "DarkCoW — a private dark-pool CoW hook for Uniswap v4",
  description:
    "A privacy-preserving dark-pool hook for Uniswap v4. Orders are escrowed, matched off-chain by an EigenLayer AVS, and proven valid in zero-knowledge with SP1 — instead of broadcasting your swap to the public mempool.",
  url: "https://darkcow.vercel.app",
  author: "Ayush Petwal",
  // ↓ Contact details — confirm / replace these.
  email: "ayushpetwal.0105@gmail.com",
  links: {
    github: "https://github.com/1Ayush-Petwal/Dark-Pool-hook",
    loomShare: "https://www.loom.com/share/7842254d0a8e49a1820b263b215090f0",
    loomEmbed:
      "https://www.loom.com/embed/7842254d0a8e49a1820b263b215090f0?hide_owner=true&hide_share=true&hideEmbedTopBar=true",
    uhi: "https://atriumacademy.notion.site/hook-directory?p=21f5f0444abe8182bffad59409f74925&pm=c",
    // Optional — set to a string to render, or leave null to hide.
    linkedin: "https://www.linkedin.com/in/ayushpetwal/" as string | null,
    x: "https://x.com/ayush_P_145" as string | null,
    resume:
      "https://drive.google.com/file/d/1dTaHfcRVbEBxFH1n7RpmHfccTc_GByop/view" as string | null,
  },
} as const;

export const nav = [
  { id: "problem", label: "Problem" },
  { id: "overview", label: "Overview" },
  { id: "flow", label: "How it works" },
  { id: "pillars", label: "Build" },
  { id: "demo", label: "Demo" },
  { id: "skills", label: "Skills" },
] as const;

export const hero = {
  kicker: "Uniswap Hook Incubator · UHI cohort",
  titleLead: "Private order flow",
  titleRest: "for Uniswap v4.",
  subtitle:
    "DarkCoW is a dark-pool hook that escrows orders, matches them off-chain through an EigenLayer AVS, and proves each order valid in zero-knowledge — so you can trade size without broadcasting your intent to the public mempool.",
  chips: ["Uniswap v4 Hook", "EigenLayer AVS", "SP1 zero-knowledge", "CoW matching"],
};

export const problem = {
  index: "01",
  label: "The problem",
  heading: "Every swap you broadcast is public before it executes.",
  body: [
    "On a public AMM your order sits in the mempool in plain sight — size, direction, and the slippage you'll tolerate. Searchers read it, then front-run, sandwich, and back-run you. The larger the trade, the heavier the tax.",
    "TradFi solved this with dark pools: venues where large orders match privately, away from the public book. DarkCoW brings that idea on-chain — and removes the trusted operator.",
  ],
  points: [
    "Orders are escrowed and matched off the curve",
    "Matched flow settles as one net transfer",
    "Order validity is proven in zero-knowledge",
  ],
};

export const overview = {
  index: "02",
  label: "What it is",
  heading: "A dark pool, expressed as a Uniswap v4 hook.",
  body: [
    "DarkCoW intercepts swaps in beforeSwap, escrows the input as ERC-6909 claims, and hands the order to a network of EigenLayer operators.",
    "They find coincidences of wants — direct and circular matches — across a batch, prove each order valid in zero-knowledge, and settle the net result back through the pool. Anything unmatched falls back to the AMM.",
  ],
  figure: {
    src: "/diagrams/architecture.png",
    alt: "DarkCoW architecture: routers and pools feeding a shared EigenLayer service manager, an operator set, and an SP1 proving service.",
    caption: "System architecture — the hook, EigenLayer AVS, and SP1 proving service. (The diagram also sketches a cross-chain path, which is a planned extension.)",
  },
};

export type FlowStep = {
  n: string;
  actor: string;
  title: string;
  body: string;
};

export const flow = {
  index: "03",
  label: "How it works",
  heading: "The life of a private order.",
  intro:
    "Seven steps, from a swap landing in the pool to a net settlement — without broadcasting the order to the mempool.",
  steps: [
    {
      n: "01",
      actor: "Router → PoolManager",
      title: "A swap arrives",
      body: "The user routes a swap. PoolManager unlocks and fires the hook's beforeSwap, with the intent carried in hookData.",
    },
    {
      n: "02",
      actor: "DarkCoWHook",
      title: "Escrow as ERC-6909",
      body: "The hook mints ERC-6909 claim tokens for the input and takes custody, so the order can be matched privately instead of hitting the curve immediately.",
    },
    {
      n: "03",
      actor: "OrderServiceManager",
      title: "Create a task",
      body: "The hook calls the AVS service manager, which records the order as a task and emits NewTaskCreated for the operator set to pick up.",
    },
    {
      n: "04",
      actor: "Operators · off-chain",
      title: "Batch & match",
      body: "Operators collect tasks over a ~10-block window and search for coincidences of wants — direct pairs and 3-party circular matches via cycle detection — with an AMM quote as fallback.",
    },
    {
      n: "05",
      actor: "SP1 zkVM",
      title: "Prove validity",
      body: "Each order is proven valid in an SP1 zkVM circuit — a fresh nullifier (no replay), Merkle inclusion of the commitment, and balance / price / deadline checks — without revealing the trader's balance or secret.",
    },
    {
      n: "06",
      actor: "OrderServiceManager",
      title: "Respond on-chain",
      body: "Operators sign the matched batch (ECDSA) and call respondToBatch on the service manager, which verifies the signature and hands the batch to the hook to settle.",
    },
    {
      n: "07",
      actor: "DarkCoWHook",
      title: "Settle the net",
      body: "settleBalances re-locks the PoolManager: the hook burns claims, pays matched traders directly, and routes only the residual through the pool — one clean settlement.",
    },
  ] satisfies FlowStep[],
  figures: [
    {
      src: "/diagrams/system-flow.png",
      alt: "System flow: user to router to PoolManager, beforeSwap hook calling the ServiceManager to create a task for operators, with an ERC-6909 transfer into the pool.",
      caption: "Fig. 1 — System flow: routing a swap into a private task.",
    },
    {
      src: "/diagrams/execution-flow.png",
      alt: "Execution flow: ServiceManager coordinating operators and ZKP operators, sending order details and proofs, then triggering settlement of funds.",
      caption: "Fig. 2 — Execution flow: matching, proving, and settlement.",
    },
    {
      src: "/diagrams/verifying-flow.png",
      alt: "Verifying flow: operators send the matched order to a proving service, which generates an SP1 Groth16 proof of order validity.",
      caption: "Fig. 3 — Verifying flow: SP1 Groth16 proof generation.",
    },
  ],
};

export type Pillar = {
  id: string;
  marker: string;
  title: string;
  summary: string;
  tags: string[];
  bullets: string[];
  code: { label: string; lang: string; source: string };
};

export const pillars = {
  index: "04",
  label: "What I built",
  heading: "Four systems, three languages, one settlement.",
  items: [
    {
      id: "hook",
      marker: "I",
      title: "Uniswap v4 Hook",
      summary:
        "A custom-curve hook that escrows, defers, and nets swaps instead of touching the AMM directly.",
      tags: ["Solidity", "Uniswap v4", "ERC-6909", "Foundry"],
      bullets: [
        "beforeSwap + beforeSwapReturnDelta take over execution from the pool",
        "ERC-6909 claim accounting holds orders mid-flight",
        "Custom settlement through unlockCallback nets matched balances",
      ],
      code: {
        label: "DarkCoWHook.sol",
        lang: "solidity",
        source: `// Escrow the input as ERC-6909, then route the order to the AVS.
poolManager.mint(
    address(this),
    (swapParams.zeroForOne ? key.currency0 : key.currency1).toId(),
    uint256(-swapParams.amountSpecified)
);

IOrderServiceManager(serviceManager).createNewTask(
    swapParams.zeroForOne, swapParams.amountSpecified,
    swapParams.sqrtPriceLimitX96, sender, PoolId.unwrap(key.toId())
);`,
      },
    },
    {
      id: "avs",
      marker: "II",
      title: "EigenLayer AVS",
      summary:
        "An operator network that matches orders off-chain, registered through EigenLayer restaking, with signature-verified responses on-chain.",
      tags: ["EigenLayer", "AVS", "ECDSA", "Solidity", "TypeScript"],
      bullets: [
        "ECDSAServiceManagerBase task lifecycle: create → respond",
        "Batched operator responses gated by ECDSA signature recovery",
        "Operator registration secured by EigenLayer restaking",
      ],
      code: {
        label: "OrderServiceManager.sol",
        lang: "solidity",
        source: `function respondToBatch(
    Task[] calldata tasks,
    uint32[] memory referenceTaskIndices,
    TransferBalance[] memory transferBalances,
    SwapBalance[] memory swapBalances,
    bytes memory signature
) external {
    // recover the operator's signature over the matched batch
    address signer = ECDSAUpgradeable.recover(messageHash, signature);
    require(signer == msg.sender, "Invalid signature");
    // then settle the net result through the hook
    IDarkCoWHook(hook).settleBalances(poolId, transferBalances, swapBalances);
}`,
      },
    },
    {
      id: "zk",
      marker: "III",
      title: "Zero-Knowledge Privacy",
      summary:
        "Order validity proven inside an SP1 zkVM with a real Groth16 prover — without revealing the trader's balance or secret.",
      tags: ["Rust", "SP1 zkVM", "Groth16", "Merkle · nullifiers"],
      bullets: [
        "Nullifier hashes prevent replay and double-spend",
        "Merkle commitment-inclusion proofs bind orders to a root",
        "Genuine Groth16 proofs generated and verified by the SP1 SDK",
      ],
      code: {
        label: "program/src/main.rs",
        lang: "rust",
        source: `// Inside the SP1 guest: validity without disclosure.
let nullifier_hash_valid = compute_nullifier_hash(&nullifier) == expected_nullifier_hash;
let merkle_valid = verify_commitment_merkle_proof(&commitment_hash, &siblings, &indices, &root);
let order_executable = verify_nullifier_order(&commitment, &market, &commitment_hash, &expected);

let final_validity = nullifier_hash_valid && merkle_valid && order_executable;
sp1_zkvm::io::commit(&final_validity);`,
      },
    },
    {
      id: "cow",
      marker: "IV",
      title: "CoW Matching",
      summary:
        "A coincidence-of-wants engine that finds direct and 3-party circular matches across a batch, with an AMM fallback.",
      tags: ["TypeScript", "viem / ethers", "Cycle detection", "v4 Quoter"],
      bullets: [
        "Direct pairs and 3-party circular matches via graph traversal",
        "AMM quoting through the v4 Quoter as a fallback path",
        "Tasks batched over a ~10-block window before matching",
      ],
      code: {
        label: "operator/matching.ts",
        lang: "typescript",
        source: `// Close a ring of orders into a circular coincidence of wants.
if (path.length >= 3) {
  const lastOut = lastTask.zeroForOne ? lastTask.poolKey.currency1 : lastTask.poolKey.currency0;
  const firstIn = firstTask.zeroForOne ? firstTask.poolKey.currency0 : firstTask.poolKey.currency1;
  if (lastOut === firstIn) { matches.push([...path]); return; }
}`,
      },
    },
  ] satisfies Pillar[],
};

export const demo = {
  index: "05",
  label: "Demo",
  heading: "Watch it run, end to end.",
  body: "A walkthrough of the architecture and a full local deployment — anvil, the EigenLayer core + AVS, the hook, the operator set, and the SP1 proving service.",
  runSteps: [
    { cmd: "anvil", note: "local chain" },
    { cmd: "forge script AVSDeployer.s.sol --broadcast", note: "deploy the AVS" },
    { cmd: "forge script HookDeployer.s.sol --broadcast", note: "deploy the hook" },
    { cmd: "npx ts-node operator/index.ts", note: "start the operator" },
    { cmd: "cargo run --release", note: "boot the SP1 prover" },
  ],
};

export type SkillGroup = {
  title: string;
  items: { label: string; note: string }[];
};

export const skills = {
  index: "06",
  label: "Skills demonstrated",
  heading: "Skills I learnt through this:",
  groups: [
    {
      title: "Smart contracts",
      items: [
        { label: "Uniswap v4 internals", note: "hooks, flash accounting, ERC-6909, custom settlement" },
        { label: "Solidity", note: "delta math, transient locks, access control" },
        { label: "Foundry", note: "scripted deploys, forking, tests" },
      ],
    },
    {
      title: "Cryptography & ZK",
      items: [
        { label: "SP1 zkVM", note: "Rust guest program, prove / verify pipeline" },
        { label: "Proof systems", note: "Groth16 proofs via the SP1 SDK" },
        { label: "Commitment schemes", note: "Merkle inclusion + nullifier replay protection" },
      ],
    },
    {
      title: "Protocol & infra",
      items: [
        { label: "EigenLayer AVS", note: "restaking-secured operator network" },
        { label: "MEV mitigation", note: "private matching, batch settlement" },
        { label: "Intent-based design", note: "escrow, off-chain matching, net settlement" },
      ],
    },
    {
      title: "Systems & full-stack",
      items: [
        { label: "Rust", note: "axum + tokio proving service" },
        { label: "TypeScript", note: "viem / ethers event-driven operator" },
        { label: "Distributed design", note: "batching, ECDSA signing, on-chain responses" },
      ],
    },
  ] satisfies SkillGroup[],
};

export const about = {
  index: "07",
  label: "About",
  heading: "Built in the Uniswap Hook Incubator.",
  body: [
    "DarkCoW was designed and built end-to-end during the UHI cohort at Atrium Academy — from the v4 hook and EigenLayer AVS to the SP1 proving circuit and the CoW matching engine.",
    "It spans Solidity, Rust, and TypeScript and pulls together the parts of crypto I care most about: market microstructure, applied cryptography, and trust-minimized systems.",
  ],
};

export const certificate = {
  title: "Certificate of Completion",
  issuer: "Uniswap Hook Incubator · UHI5",
  holder: "Ayush Petwal",
  image: "/certificate.png",
  tokenName: "UHI 5 Grads",
  chain: "Zora Network",
  standard: "ERC-721",
  explorerUrl:
    "https://explorer.zora.energy/token/0xbd28D087baEAAA860d9a251536d07657B16491aB/instance/76",
};
