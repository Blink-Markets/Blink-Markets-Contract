# Blinkmarket

<div align="center">

**High-Speed Micro-Prediction Market Protocol on Sui Blockchain**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Sui Move](https://img.shields.io/badge/Sui-Move-blue)](https://sui.io)
[![Tests](https://img.shields.io/badge/tests-46%20passing-brightgreen)](tests/)

*Real-time prediction markets for sports, crypto prices, and custom events with instant settlement and parimutuel pooling*

[Quick Start](#quick-start) • [Documentation](#documentation) • [API Reference](FRONTEND_API.md) • [Examples](#examples)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Core Concepts](#core-concepts)
- [Pool Mathematics](#pool-mathematics)
- [Event Types](#event-types)
- [Contract Design](#contract-design)
- [Fee Structure](#fee-structure)
- [State Machine](#state-machine)
- [Security Model](#security-model)
- [Backend Keeper Service](#backend-keeper-service)
- [Quick Start](#quick-start)
- [Testing](#testing)
- [Deployment](#deployment)
- [Examples](#examples)
- [Contributing](#contributing)

---

## Overview

**Blinkmarket** is a decentralized prediction market protocol built on the Sui blockchain, enabling ultra-fast betting on micro-events through **parimutuel pooling** and **oracle-based resolution**. The protocol supports two distinct event types:

1. **Manual Events** — Sports betting, political predictions, custom markets (2-10 outcomes)
2. **Crypto Events** — Automated price predictions using Stork oracle feeds (binary: Above/Below)

Built with Sui's **object-centric model**, Blinkmarket leverages:
- ✅ **Generic coin types** — Support SUI, USDC, and any custom tokens
- ✅ **NFT positions** — Composable stake management via Position objects
- ✅ **Atomic oracle resolution** — Price feed updates and event settlement in single PTB
- ✅ **Parimutuel mathematics** — Automatic odds calculation and proportional payouts
- ✅ **Multi-market support** — Independent markets with separate treasuries and fee structures

---

## Features

### For Users
- 🎯 **Prediction Markets** — Bet on sports, crypto prices, politics, custom events
- ⚡ **Instant Settlement** — Claim winnings immediately after resolution
- 💰 **Fair Odds** — Parimutuel pooling eliminates house edge
- 🎨 **NFT Positions** — Tradable, transferable betting positions
- 🔄 **Multi-Coin Support** — Use SUI, USDC, or any token
- 🚫 **Bet Cancellation** — Cancel bets before event locks (1% fee)
- 💸 **Full Refunds** — Get stake back if event is cancelled

### For Creators
- 🏗️ **Custom Markets** — Create prediction markets for any niche
- 🎛️ **Flexible Configuration** — Set min/max stakes, platform fees
- 📊 **Oracle Integration** — Automated resolution via Stork price feeds
- 🔐 **Access Control** — Admin capabilities and oracle authorization
- 💵 **Revenue Streams** — Collect platform fees in any coin type

### For Developers
- 🧩 **Modular Design** — Three independent modules (config, event, position)
- 🔢 **Generic Types** — Full type safety with generic coin parameters
- 📜 **Rich Events** — Comprehensive on-chain event emission
- 🛠️ **View Functions** — Extensive read-only query interface
- ✅ **Tested** — 46 comprehensive unit tests
- 📚 **Documented** — Complete API reference and integration guide

---

## Architecture

### Module Structure

The protocol is split into three independent Move modules:

```
┌─────────────────────────────────────────────────────────────┐
│                       Blinkmarket Protocol                   │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  blink_config   │  │   blink_event   │  │blink_position││
│  │                 │  │                 │  │             │ │
│  │ • AdminCap      │  │ • Event CRUD    │  │ • Place bet │ │
│  │ • Market        │  │ • State machine │  │ • Cancel bet│ │
│  │ • Treasury<T>   │  │ • Resolution    │  │ • Claim     │ │
│  │ • Oracle auth   │  │ • Pool logic    │  │ • Refund    │ │
│  │ • Fee config    │  │ • Oracle price  │  │ • Position  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│         ↓                     ↓                    ↓         │
│    Governance            Event Lifecycle        User Actions │
└─────────────────────────────────────────────────────────────┘
```

### Object Model

```
                    ┌──────────────┐
                    │   AdminCap   │ (owned)
                    └──────┬───────┘
                           │ controls
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌─────────┐       ┌───────────────┐      ┌──────────────┐
│ Market  │◄──────┤MarketCreatorCap│      │Treasury<CT> │(shared)
│(shared) │       │    (owned)     │      │  (shared)   │
└────┬────┘       └───────┬────────┘      └──────────────┘
     │ contains           │ creates
     │ oracles            │ events
     ▼                    ▼
┌────────────────────────────────┐
│   PredictionEvent<CoinType>    │ (shared)
│                                 │
│  • Outcome pools (Balance<CT>) │
│  • Event type (manual/crypto)  │
│  • Oracle data (feed_id, price)│
│  • State (created→open→resolved)│
└────────────┬────────────────────┘
             │ users bet on
             ▼
    ┌───────────────────┐
    │  Position<CT>     │ (owned by user)
    │                   │
    │  • Stake amount   │
    │  • Outcome index  │
    │  • Is claimed     │
    └───────────────────┘
```

---

## Core Concepts

### 1. Generic Coin Types

All core structures are **generic over coin type**, enabling multi-currency support:

```move
public struct Treasury<phantom CoinType> has key { ... }
public struct PredictionEvent<CoinType> has key, store { ... }
public struct Position<CoinType> has key, store { ... }
```

**Example:**
- `PredictionEvent<SUI>` — Event denominated in SUI
- `PredictionEvent<USDC>` — Event denominated in USDC
- `Position<SUI>` — Position holding SUI stake

### 2. Parimutuel Pooling

Unlike traditional bookmakers, Blinkmarket uses **parimutuel pooling**, where:

- All bets on the same outcome go into a shared pool
- Losers' stakes are distributed to winners proportionally
- No house edge — only a small platform fee (e.g., 2%)

**Benefits:**
- ✅ Fair odds determined by market participation
- ✅ No counterparty risk (protocol can't lose)
- ✅ Scales to any bet size without liquidity concerns

### 3. Position NFTs

When users place a bet, they receive a **Position object** (NFT):

```move
public struct Position<phantom CoinType> has key, store {
    id: UID,
    event_id: ID,
    outcome_index: u8,
    stake_amount: u64,
    is_claimed: bool,
    owner: address,
}
```

**Capabilities:**
- ✅ **Tradable** — Sell your position to others
- ✅ **Transferable** — Gift or move between wallets
- ✅ **Composable** — Use in DeFi protocols as collateral
- ✅ **Verifiable** — Query on-chain for ownership proof

### 4. Oracle Integration

**Manual Events:** Authorized oracles manually set winning outcome  
**Crypto Events:** Automated via [Stork oracle](https://stork.network/) price feeds

**Supported Assets:**
- BTC/USD
- ETH/USD
- SOL/USD
- SUI/USD

---

## Pool Mathematics

### Parimutuel Payout Formula

```
total_pool = sum of all outcome pools (after platform fees)
winning_pool = pool for winning outcome (before losing pools merged)

payout = (user_stake / winning_pool_at_resolution) × total_pool
```

### Example Calculation

**Scenario:**
- User A bets **100 SUI** on YES → net stake: **98 SUI** (2% fee)
- User B bets **200 SUI** on YES → net stake: **196 SUI**
- User C bets **300 SUI** on NO → net stake: **294 SUI**

**Pools before resolution:**
```
YES pool:   98 + 196 = 294 SUI
NO pool:    294 SUI
Total pool: 588 SUI
```

**If YES wins:**
```
Winning pool (at resolution): 294 SUI (YES pool before merge)
Total pool (after merge):     588 SUI (all pools combined)

User A payout: (98 / 294) × 588 = 196 SUI
User B payout: (196 / 294) × 588 = 392 SUI
Total payouts: 196 + 392 = 588 SUI ✅
```

### Key Properties

1. **Conservation of Pool:**
   ```
   sum(all_payouts) = total_pool
   ```

2. **Proportional Distribution:**
   ```
   user_share = user_stake / winning_pool
   user_payout = user_share × total_pool
   ```

3. **Winner-Takes-All:**
   - Losing outcome pools have balance = 0 after resolution
   - All funds transferred to winning pool

4. **Overflow Protection:**
   - Uses `u128` arithmetic for intermediate calculations
   - Prevents overflow even with large stakes

### Odds Calculation

**Implied odds** can be calculated from pool sizes:

```
implied_probability = outcome_pool / total_pool
decimal_odds = total_pool / outcome_pool
```

**Example:**
```
YES pool: 300 SUI
NO pool:  700 SUI
Total:    1000 SUI

YES implied probability: 300 / 1000 = 30%
YES decimal odds:        1000 / 300 = 3.33x

NO implied probability:  700 / 1000 = 70%
NO decimal odds:         1000 / 700 = 1.43x
```

**Note:** These are **dynamic odds** that change with each new bet.

---

## Event Types

### 1. Manual Events

**Characteristics:**
- **Outcomes:** 2-10 custom labels (e.g., "Team A", "Team B", "Draw")
- **Resolution:** Oracle manually sets winning outcome
- **Use cases:** Sports, politics, entertainment, custom markets

**Function:**
```move
public fun create_manual_event<CoinType>(
    creator_cap: &MarketCreatorCap,
    market: &Market,
    description: vector<u8>,
    outcome_labels: vector<vector<u8>>, // 2-10 labels
    duration: u64,                       // in milliseconds
    ctx: &mut TxContext,
)
```

**Resolution:**
```move
public fun resolve_manual_event<CoinType>(
    prediction_event: &mut PredictionEvent<CoinType>,
    market: &Market,
    winning_outcome: u8,  // Oracle picks winner
    clock: &Clock,
    ctx: &mut TxContext,
)
```

### 2. Crypto Events

**Characteristics:**
- **Outcomes:** Always binary — `["Above", "Below"]`
- **Resolution:** Automated via Stork oracle price feed
- **Use cases:** BTC > $60k? ETH > $3k? SOL > $100?

**Function:**
```move
public fun create_crypto_event<CoinType>(
    creator_cap: &MarketCreatorCap,
    market: &Market,
    description: vector<u8>,
    oracle_feed_id: vector<u8>,  // 32-byte Stork feed ID
    target_price: u128,           // Price threshold (18 decimals)
    duration: u64,
    ctx: &mut TxContext,
)
```

**Resolution:**
```move
public fun resolve_crypto_event<CoinType>(
    prediction_event: &mut PredictionEvent<CoinType>,
    market: &Market,
    stork_state: &StorkState,  // Stork oracle state
    clock: &Clock,
    ctx: &mut TxContext,
)
```

**Logic:**
```
oracle_price = read_from_stork(feed_id)
winning_outcome = if oracle_price >= target_price { 0 } else { 1 }
                  // 0 = "Above", 1 = "Below"
```

**Atomic Resolution:**
Backend keeper executes in **single PTB**:
1. `stork::update_temporal_numeric_value()` — Push latest signed price
2. `blink_event::resolve_crypto_event()` — Read price and resolve atomically

---

## Contract Design

### Event State Machine

```
┌─────────────────────────────────────────────────────────────┐
│                     Event Lifecycle                         │
└─────────────────────────────────────────────────────────────┘

   ┌──────────┐
   │ CREATED  │ (0) — Event initialized, not yet open for bets
   └────┬─────┘
        │ open_event()
        ▼
   ┌──────────┐
   │   OPEN   │ (1) — Betting window active
   └────┬─────┘
        │
        ├─────────────────┐
        │                 │ cancel_event()
        │                 ▼
        │            ┌──────────┐
        │            │CANCELLED │ (4) — Event cancelled, refunds enabled
        │            └──────────┘
        │
        │ resolve_manual_event() OR resolve_crypto_event()
        │ (auto-locks internally)
        ▼
   ┌──────────┐
   │ LOCKED   │ (2) — [Transient state during resolution]
   └────┬─────┘
        │ (immediate)
        ▼
   ┌──────────┐
   │ RESOLVED │ (3) — Resolution complete, claims enabled
   └──────────┘
```

**State Transitions:**
- `CREATED → OPEN` — Market creator opens event
- `OPEN → CANCELLED` — Market creator cancels event
- `OPEN → LOCKED → RESOLVED` — Oracle resolves (atomic)

**Key Design Decision:**
- ❌ **No external `lock_event` function** (removed)
- ✅ **Auto-lock during resolution** (atomic state transition)
- ✅ **Minimizes timing attacks** and race conditions

### Module Responsibilities

#### `blink_config` — Governance & Configuration

**Capabilities:**
```move
public struct AdminCap has key, store { ... }
public struct MarketCreatorCap has key, store { ... }
```

**Functions:**
- `create_market()` — Create new market category
- `create_treasury<CoinType>()` — Initialize treasury for coin type
- `add_oracle()` / `remove_oracle()` — Manage authorized oracles
- `set_market_active()` — Enable/disable market
- `withdraw_fees<CoinType>()` — Admin withdraw treasury balance

#### `blink_event` — Event Lifecycle & Resolution

**Core Functions:**
- `create_manual_event<CoinType>()`
- `create_crypto_event<CoinType>()`
- `open_event<CoinType>()`
- `cancel_event<CoinType>()`
- `resolve_manual_event<CoinType>()`
- `resolve_crypto_event<CoinType>()`

**Package-Internal Functions:**
- `add_to_pool()` — Add stake to outcome pool
- `remove_from_pool()` — Remove stake (for cancellations)
- `withdraw_payout()` — Withdraw winnings (for claims)

**View Functions:**
- `get_odds()` — Get pool balances
- `get_total_pool()` — Get total pool size
- `calculate_potential_payout()` — Calculate expected return
- `is_betting_open()` — Check if betting window active
- `get_event_type()` / `get_oracle_feed_id()` / `get_target_price()`

#### `blink_position` — User Actions

**Functions:**
- `place_bet<CoinType>()` → Returns `Position<CoinType>`
- `cancel_bet<CoinType>()` → Returns `Coin<CoinType>` (refund)
- `claim_winnings<CoinType>()` → Returns `Coin<CoinType>` (payout)
- `claim_refund<CoinType>()` → Returns `Coin<CoinType>` (full refund)

**View Functions:**
- `get_position_stake()` / `get_position_outcome()`
- `is_position_claimed()` / `get_position_owner()`

---

## Fee Structure

### Platform Fee

- **Charged on:** Bet placement
- **Rate:** Configurable per market (basis points, e.g., 200 = 2%)
- **Destination:** `Treasury<CoinType>` (shared object)

**Calculation:**
```move
let fee_amount = (stake_value * market.platform_fee_bps) / 10000;
let net_stake = stake_value - fee_amount;
```

**Example:**
```
Stake:         100 SUI
Platform fee:  2% (200 bps)
Fee amount:    2 SUI
Net stake:     98 SUI → Goes to outcome pool
```

### Cancellation Fee

- **Charged on:** Bet cancellation (before event locked)
- **Rate:** 1% (100 basis points) — hardcoded
- **Destination:** Remains in outcome pool (distributed to winners)

**Calculation:**
```move
let cancellation_fee = (stake_amount * 100) / 10000;
let refund_amount = stake_amount - cancellation_fee;
```

**Example:**
```
Original stake: 98 SUI (net after platform fee)
Cancellation:   1% fee
Fee amount:     0.98 SUI → Stays in pool
Refund:         97.02 SUI → Returned to user
```

### No Withdrawal Fees

- ❌ No fee on claiming winnings
- ❌ No fee on claiming refunds (if event cancelled)

---

## State Machine

### Event Status Code Mapping

| Code | Status | Description |
|------|--------|-------------|
| 0 | CREATED | Event initialized, betting not started |
| 1 | OPEN | Betting window active |
| 2 | LOCKED | Event locked for resolution (transient) |
| 3 | RESOLVED | Resolution complete, claims enabled |
| 4 | CANCELLED | Event cancelled, refunds enabled |

### Betting Time Window

Events have **fixed duration** set at creation:

```move
prediction_event.betting_start_time = clock::timestamp_ms(clock);
prediction_event.betting_end_time = start + duration;
```

**Validation:**
```move
current_time >= betting_start_time  // EBettingNotStarted
current_time < betting_end_time     // EBettingClosed
```

### Resolution Timing

Resolution **only allowed** after betting window closes:

```move
assert!(
    event.status == STATUS_OPEN &&
    current_time >= event.betting_end_time,
    EEventNotOpen
);
```

---

## Security Model

### Access Control

| Action | Required Permission |
|--------|-------------------|
| Create market | `AdminCap` |
| Create treasury | `AdminCap` |
| Add/remove oracle | `AdminCap` |
| Withdraw fees | `AdminCap` |
| Create event | `MarketCreatorCap` (for specific market) |
| Open event | `MarketCreatorCap` |
| Cancel event | `MarketCreatorCap` |
| Resolve event | Authorized oracle (via `is_oracle()` check) |
| Place bet | Anyone (market must be active) |
| Cancel bet | Position owner (event must be OPEN) |
| Claim winnings | Position owner (event must be RESOLVED) |
| Claim refund | Position owner (event must be CANCELLED) |

### Validation Checks

**Bet Placement:**
- ✅ Market is active
- ✅ Event is OPEN
- ✅ Current time within betting window
- ✅ Stake >= market minimum
- ✅ Stake <= market maximum
- ✅ Valid outcome index

**Resolution:**
- ✅ Caller is authorized oracle
- ✅ Event is OPEN
- ✅ Betting time expired
- ✅ (Crypto) Event type matches
- ✅ (Manual) Valid winning outcome

**Claims:**
- ✅ Caller owns Position
- ✅ Event is RESOLVED
- ✅ Position outcome matches winning outcome
- ✅ Position not already claimed

### Atomic Operations

**Resolution is atomic:**
1. Check permissions
2. **Lock event** (OPEN → LOCKED)
3. Read oracle price (for crypto)
4. Determine winner
5. Merge losing pools into winning pool
6. **Mark resolved** (LOCKED → RESOLVED)

All steps execute in **single transaction** — no intermediate states visible to other transactions.

---

## Backend Keeper Service

For **automated crypto event resolution**, the protocol requires a **backend keeper service** that monitors events and handles Stork Oracle integration.

### Why Backend Keeper?

**Crypto events cannot be resolved directly from frontend** because:
1. ❌ **Stork API requires authentication** (API keys)
2. ❌ **Price updates must be signed** by authorized oracle
3. ❌ **Atomic PTB execution** needed (update + resolve)
4. ❌ **Security**: Oracle private keys must not be exposed to frontend

### Keeper Architecture

```
┌─────────────────────────────────────────────────────┐
│              Backend Keeper Service                  │
├─────────────────────────────────────────────────────┤
│                                                       │
│  1. Monitor blockchain ─────→ Query pending events  │
│  2. Fetch Stork prices ─────→ Authenticate with API │
│  3. Build PTB ──────────────→ Update price + Resolve │
│  4. Execute transaction ────→ Sign with oracle key  │
│  5. Verify result ──────────→ Log and monitor       │
│                                                       │
└─────────────────────────────────────────────────────┘
            │                            │
            ▼                            ▼
      Sui Network              Stork Oracle API
```

### Key Features

- 🔄 **Automatic monitoring**: Polls blockchain every 3 seconds
- 📦 **Batch processing**: Groups events for efficient resolution
- 🔒 **Distributed locks**: Redis prevents duplicate resolutions
- 📊 **Monitoring**: Prometheus metrics + Grafana dashboards
- ⚡ **PTB atomicity**: Updates Stork price and resolves in single transaction
- 🛡️ **Error recovery**: Retry logic with exponential backoff

### Resolution Flow

```typescript
// Backend keeper executes this PTB atomically:

const tx = new TransactionBlock();

// Step 1: Update Stork price feed with signed data
tx.moveCall({
  target: `${STORK_PACKAGE}::stork::update_single_temporal_numeric_value_evm`,
  arguments: [storkState, signedPriceData, feeCoin],
});

// Step 2: Resolve event (reads fresh price immediately)
tx.moveCall({
  target: `${PACKAGE}::blink_event::resolve_crypto_event`,
  typeArguments: [coinType],
  arguments: [eventId, marketId, storkState, clock],
});

// Execute atomically
await client.signAndExecuteTransactionBlock({
  transactionBlock: tx,
  signer: oracleKeypair,
});
```

### Deployment

**See [backend/keeper/README.md](backend/keeper/README.md) for:**
- Installation and configuration
- Environment setup
- Docker deployment
- Monitoring and troubleshooting
- Security best practices

**Quick Start:**
```bash
cd backend/keeper
npm install
cp .env.example .env
# Edit .env with your credentials
npm run dev
```

**Docker Deployment:**
```bash
cd backend/keeper
docker-compose up -d
```

**Manual events** (sports, politics) still require manual oracle resolution via frontend/admin interface.

---

## Quick Start

### Prerequisites

```bash
# Install Sui CLI
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui

# Verify installation
sui --version
```

### Build Contract

```bash
# Clone repository
git clone https://github.com/Blink-Markets/Blink-Markets-Contract.git
cd Blink-Markets-Contract

# Build
sui move build

# Run tests
sui move test
```

### Deploy

```bash
# Deploy to testnet
sui client publish --gas-budget 100000000

# Save package ID and shared object IDs
export PACKAGE_ID=0x...
export MARKET_ID=0x...
export TREASURY_SUI=0x...
```

---

## Testing

### Test Coverage

**46 comprehensive unit tests** covering:

- ✅ Initialization & market creation
- ✅ Oracle authorization
- ✅ Manual event creation & resolution
- ✅ Crypto event creation & resolution (with test-only oracle mock)
- ✅ Bet placement (valid & invalid stakes)
- ✅ Bet cancellation (before & after lock)
- ✅ Winning claims (single & multiple winners)
- ✅ Refund claims (cancelled events)
- ✅ Access control (oracle, position owner)
- ✅ Edge cases (overflow protection, equal stakes, large values)
- ✅ Generic treasury creation

### Run Tests

```bash
# Run all tests
sui move test

# Run specific test
sui move test test_full_betting_resolution_and_claim

# Run with verbose output
sui move test --verbose
```

### Test Results

```
Test result: OK. Total tests: 46; passed: 46; failed: 0
```

---

## Deployment

### Step 1: Deploy Contract

```bash
sui client publish --gas-budget 100000000
```

**Save addresses:**
- Package ID
- AdminCap object ID
- Treasury<SUI> object ID
- Market object ID(s)

### Step 2: Configure Market

```bash
# Add oracle
sui client call \
  --package $PACKAGE_ID \
  --module blink_config \
  --function add_oracle \
  --args $ADMIN_CAP $MARKET_ID $ORACLE_ADDRESS \
  --gas-budget 10000000
```

### Step 3: Create Treasury for Additional Coins

```bash
# Create USDC treasury
sui client call \
  --package $PACKAGE_ID \
  --module blink_config \
  --function create_treasury \
  --type-args $USDC_TYPE \
  --args $ADMIN_CAP \
  --gas-budget 10000000
```

### Step 4: Create Events

See [FRONTEND_API.md](FRONTEND_API.md) for detailed integration examples.

---

## Examples

### Example 1: Sports Betting (Manual Event)

```typescript
// Create event
const tx = new TransactionBlock();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::create_manual_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(MARKET_ID),
    tx.pure('Lakers vs Warriors - Who wins?', 'string'),
    tx.pure(['Lakers', 'Warriors'], 'vector<string>'),
    tx.pure(7200000, 'u64'), // 2 hours
  ],
});

// Open for betting
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::open_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(EVENT_ID),
    tx.object('0x6'), // Clock
  ],
});

// ... Users place bets ...

// Oracle resolves (Lakers won)
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::resolve_manual_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(EVENT_ID),
    tx.object(MARKET_ID),
    tx.pure(0, 'u8'), // Lakers = outcome 0
    tx.object('0x6'),
  ],
});
```

### Example 2: Crypto Price Prediction (Automated)

```typescript
// Create crypto event
const targetPrice = '62000000000000000000000'; // $62,000 * 10^18

tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::create_crypto_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(MARKET_ID),
    tx.pure('BTC above $62,000 in 1 hour?', 'string'),
    tx.pure(Array.from(Buffer.from(BTC_FEED_ID.slice(2), 'hex')), 'vector<u8>'),
    tx.pure(targetPrice, 'u128'),
    tx.pure(3600000, 'u64'), // 1 hour
  ],
});

// Open for betting
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::open_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(EVENT_ID),
    tx.object('0x6'),
  ],
});

// ... Users place bets ...

// Oracle resolves (automated)
// Step 1: Update Stork price
tx.moveCall({
  target: `${STORK_PACKAGE}::stork::update_single_temporal_numeric_value_evm`,
  arguments: [
    tx.object(STORK_STATE),
    tx.pure(STORK_UPDATE_DATA, 'vector<u8>'),
    feeCoin,
  ],
});

// Step 2: Resolve event (reads price atomically)
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::resolve_crypto_event`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(EVENT_ID),
    tx.object(MARKET_ID),
    tx.object(STORK_STATE),
    tx.object('0x6'),
  ],
});
```

For more examples, see [FRONTEND_API.md](FRONTEND_API.md).

---

## Contributing

We welcome contributions! Please follow these steps:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- ✅ Write comprehensive tests for new features
- ✅ Follow existing code style and conventions
- ✅ Update documentation for API changes
- ✅ Ensure all tests pass (`sui move test`)
- ✅ Add detailed commit messages

---

## Documentation

- 📖 **Frontend API Guide:** [FRONTEND_API.md](FRONTEND_API.md)
- 🧪 **Test Suite:** [tests/blinkmarket_tests.move](tests/blinkmarket_tests.move)
- 📜 **Contract Source:**
  - [sources/blink_config.move](sources/blink_config.move)
  - [sources/blink_event.move](sources/blink_event.move)
  - [sources/blink_position.move](sources/blink_position.move)

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Contact & Support

- **GitHub Issues:** [Report bugs or request features](https://github.com/Blink-Markets/Blink-Markets-Contract/issues)
- **Documentation:** [Frontend Integration Guide](FRONTEND_API.md)
- **Sui Documentation:** https://docs.sui.io/
- **Stork Oracle:** https://docs.stork.network/

---

## Acknowledgments

- **Sui Foundation** — For the Sui blockchain and Move language
- **Stork Network** — For oracle infrastructure
- **Community Contributors** — Thank you for your support!

---

<div align="center">

**Built with ❤️ on Sui**

[⬆ Back to Top](#blinkmarket)

</div>
