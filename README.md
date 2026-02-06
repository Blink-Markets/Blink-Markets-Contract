# Blinkmarket

A high-speed micro-prediction market protocol built on Sui blockchain for ultra-fast betting on micro-events.

## Overview

Blinkmarket enables real-time prediction markets for micro-events — short-lived, rapidly-resolved events that demand instant participation and settlement. Built on Sui's object-centric model, it uses parimutuel pooling for automatic odds calculation and Position NFTs for composable stake management.

## Architecture

The protocol consists of three independent modules:

```
blink_config    → Governance, treasury, market configuration
blink_event     → Event lifecycle, oracle resolution, pool mechanics
blink_position  → User actions, betting, claims
```

### Event State Machine

```
CREATED (0) → OPEN (1) → LOCKED (2) → RESOLVED (3)
                ↓            ↓
             CANCELLED (4) ←─┘
```

### Payout Mechanics (Parimutuel)

```
Total Pool = Sum of all outcome pools (net of platform fees)
Payout = (user_stake / winning_pool) × total_pool
```

**Example:**
```
YES pool: 40 SUI, NO pool: 60 SUI → Total: 100 SUI
If YES wins → Each 1 SUI on YES returns 2.5 SUI (100/40)
If NO wins  → Each 1 SUI on NO returns 1.67 SUI (100/60)
```

## Fee Structure

| Fee Type | Rate | Destination |
|----------|------|-------------|
| Platform Fee | Configurable per market (basis points, e.g. 200 = 2%) | Treasury (shared object) |
| Cancellation Fee | 1% (100 basis points) | Stays in outcome pool |

## On-chain Objects

| Object | Type | Description |
|--------|------|-------------|
| `AdminCap` | Owned | Root admin capability, created at init |
| `MarketCreatorCap` | Owned | Scoped capability for creating events in a market |
| `Market` | Shared | Market category config (min/max stake, fee, oracles) |
| `Treasury` | Shared | Platform fee collection |
| `PredictionEvent` | Shared | Event with outcome pools, status, timestamps |
| `Position` | Owned | User's stake on a specific outcome (NFT) |

## Frontend Integration Guide

### Object IDs You Need

After deployment, record the following object IDs:
- **Package ID**: The published package address
- **AdminCap ID**: Owned by deployer (from `init`)
- **Treasury ID**: Shared object (from `init`)
- **Market ID**: Shared object (from `create_market`)
- **MarketCreatorCap ID**: Owned by admin (from `create_market`)

### Transaction Building

All examples use the [Sui TypeScript SDK](https://sdk.mystenlabs.com/typescript).

---

### 1. Admin: Create a Market

**Function:** `blink_config::create_market`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::create_market`,
  arguments: [
    tx.object(ADMIN_CAP_ID),             // &AdminCap
    tx.pure.vector('u8', [...new TextEncoder().encode('NBA')]),  // name
    tx.pure.vector('u8', [...new TextEncoder().encode('NBA Basketball')]),  // description
    tx.pure.u64(1_000_000),              // min_stake (0.001 SUI in MIST)
    tx.pure.u64(1_000_000_000),          // max_stake (1 SUI in MIST)
    tx.pure.u64(200),                    // platform_fee_bps (2%)
  ],
});
// Returns: MarketCreatorCap (owned object)
// Side effect: creates shared Market object
```

### 2. Admin: Add Oracle

**Function:** `blink_config::add_oracle`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::add_oracle`,
  arguments: [
    tx.object(ADMIN_CAP_ID),             // &AdminCap
    tx.object(MARKET_ID),                // &mut Market
    tx.pure.address(ORACLE_ADDRESS),     // oracle address
  ],
});
```

### 3. Admin: Remove Oracle

**Function:** `blink_config::remove_oracle`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::remove_oracle`,
  arguments: [
    tx.object(ADMIN_CAP_ID),
    tx.object(MARKET_ID),
    tx.pure.address(ORACLE_ADDRESS),
  ],
});
```

### 4. Admin: Set Market Active/Inactive

**Function:** `blink_config::set_market_active`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::set_market_active`,
  arguments: [
    tx.object(ADMIN_CAP_ID),
    tx.object(MARKET_ID),
    tx.pure.bool(false),                 // is_active
  ],
});
```

### 5. Creator: Create Event

**Function:** `blink_event::create_event`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::create_event`,
  arguments: [
    tx.object(CREATOR_CAP_ID),           // &MarketCreatorCap
    tx.object(MARKET_ID),                // &Market
    tx.pure.vector('u8', [...new TextEncoder().encode('Will next shot be a 3-pointer?')]),
    tx.pure(bcs.vector(bcs.vector(bcs.u8())).serialize([
      [...new TextEncoder().encode('Yes')],
      [...new TextEncoder().encode('No')],
    ])),                                 // outcome_labels: vector<vector<u8>>
    tx.pure.u64(Date.now()),             // betting_start_time (ms)
    tx.pure.u64(Date.now() + 30_000),    // betting_end_time (ms)
  ],
});
// Side effect: creates shared PredictionEvent object
```

### 6. Creator: Open Event

**Function:** `blink_event::open_event`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::open_event`,
  arguments: [
    tx.object(CREATOR_CAP_ID),           // &MarketCreatorCap
    tx.object(EVENT_ID),                 // &mut PredictionEvent
  ],
});
```

### 7. Creator: Lock Event

**Function:** `blink_event::lock_event`

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::lock_event`,
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(EVENT_ID),
  ],
});
```

### 8. Creator: Cancel Event

**Function:** `blink_event::cancel_event`

Can cancel from CREATED, OPEN, or LOCKED states.

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::cancel_event`,
  arguments: [
    tx.object(CREATOR_CAP_ID),
    tx.object(EVENT_ID),
  ],
});
```

### 9. Oracle: Resolve Event

**Function:** `blink_event::resolve_event`

Resolves an event by setting the winning outcome. Only callable by authorized oracles when event is LOCKED.

On resolution:
- All losing outcome pools are merged into the winning pool
- `resolved_at` timestamp is recorded
- `winning_pool_at_resolution` is saved for correct payout calculation

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::resolve_event`,
  arguments: [
    tx.object(EVENT_ID),                 // &mut PredictionEvent
    tx.object(MARKET_ID),                // &Market
    tx.pure.u8(0),                       // winning_outcome (index)
    tx.object('0x6'),                    // Clock (system object)
  ],
});
```

### 10. User: Place Bet

**Function:** `blink_position::place_bet`

```typescript
const tx = new Transaction();
const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(100_000_000)]); // 0.1 SUI
const [position] = tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::place_bet`,
  arguments: [
    tx.object(EVENT_ID),                 // &mut PredictionEvent
    tx.object(MARKET_ID),                // &Market
    tx.object(TREASURY_ID),              // &mut Treasury
    tx.pure.u8(0),                       // outcome_index
    coin,                                // Coin<SUI>
    tx.object('0x6'),                    // Clock
  ],
});
tx.transferObjects([position], tx.pure.address(USER_ADDRESS));
// Returns: Position (owned NFT)
// Note: stake_amount in Position = input amount - platform fee
```

### 11. User: Cancel Bet

**Function:** `blink_position::cancel_bet`

Only available while event is OPEN. 1% cancellation fee is deducted.

```typescript
const tx = new Transaction();
const [refund] = tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::cancel_bet`,
  arguments: [
    tx.object(EVENT_ID),                 // &mut PredictionEvent
    tx.object(POSITION_ID),              // Position (consumed)
  ],
});
tx.transferObjects([refund], tx.pure.address(USER_ADDRESS));
// Returns: Coin<SUI> (refund minus 1% cancellation fee)
```

### 12. User: Claim Winnings

**Function:** `blink_position::claim_winnings`

Only the position owner (original bettor) can claim. Event must be RESOLVED and position must be on the winning outcome.

```typescript
const tx = new Transaction();
const [payout] = tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::claim_winnings`,
  arguments: [
    tx.object(EVENT_ID),                 // &mut PredictionEvent
    tx.object(POSITION_ID),              // &mut Position
  ],
});
tx.transferObjects([payout], tx.pure.address(USER_ADDRESS));
// Returns: Coin<SUI> with payout = (user_stake / winning_pool) * total_pool
```

### 13. User: Claim Refund

**Function:** `blink_position::claim_refund`

Only the position owner can claim. Event must be CANCELLED.

```typescript
const tx = new Transaction();
const [refund] = tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::claim_refund`,
  arguments: [
    tx.object(EVENT_ID),                 // &mut PredictionEvent
    tx.object(POSITION_ID),              // Position (consumed)
  ],
});
tx.transferObjects([refund], tx.pure.address(USER_ADDRESS));
// Returns: Coin<SUI> (full net stake refund)
```

### 14. Admin: Withdraw Fees

**Function:** `blink_config::withdraw_fees`

```typescript
const tx = new Transaction();
const [withdrawn] = tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::withdraw_fees`,
  arguments: [
    tx.object(ADMIN_CAP_ID),             // &AdminCap
    tx.object(TREASURY_ID),              // &mut Treasury
    tx.pure.u64(1_000_000),              // amount to withdraw
  ],
});
tx.transferObjects([withdrawn], tx.pure.address(ADMIN_ADDRESS));
```

---

## Read-only (View) Functions

These can be called via `devInspectTransactionBlock` or by reading on-chain object fields directly.

### blink_event

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `get_odds` | `&PredictionEvent` | `vector<u64>` | Pool balances for each outcome |
| `calculate_potential_payout` | `&PredictionEvent, outcome_index: u8, stake_amount: u64` | `u64` | Estimated payout if this outcome wins |
| `is_betting_open` | `&PredictionEvent, &Clock` | `bool` | Whether betting window is active |
| `get_event_status` | `&PredictionEvent` | `u8` | Status code (0–4) |
| `get_total_pool` | `&PredictionEvent` | `u64` | Total pool value (MIST) |
| `get_winning_outcome` | `&PredictionEvent` | `u8` | Winning outcome index (only after RESOLVED) |
| `get_resolved_at` | `&PredictionEvent` | `u64` | Resolution timestamp in ms (only after RESOLVED) |

### blink_position

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `get_position_stake` | `&Position` | `u64` | Net stake amount (after platform fee) |
| `get_position_outcome` | `&Position` | `u8` | Outcome index the bet is on |
| `is_position_claimed` | `&Position` | `bool` | Whether winnings have been claimed |
| `get_position_owner` | `&Position` | `address` | Address of the position owner |

### blink_config

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `get_treasury_balance` | `&Treasury` | `u64` | Current treasury balance (MIST) |
| `get_total_fees_collected` | `&Treasury` | `u64` | Total fees ever collected |
| `get_market_min_stake` | `&Market` | `u64` | Minimum stake per bet |
| `get_market_max_stake` | `&Market` | `u64` | Maximum stake per bet |
| `get_market_fee_bps` | `&Market` | `u64` | Platform fee in basis points |
| `is_market_active` | `&Market` | `bool` | Whether market accepts new events |
| `is_oracle` | `&Market, address` | `bool` | Whether address is an authorized oracle |

---

## Emitted Events

Subscribe to these events to track on-chain activity in real-time.

| Event Struct | Module | Fields | When Emitted |
|-------------|--------|--------|-------------|
| `MarketCreated` | `blink_config` | `market_id: ID`, `name: vector<u8>` | Market created |
| `EventCreated` | `blink_event` | `event_id: ID`, `market_id: ID`, `description: vector<u8>`, `num_outcomes: u64` | Event created |
| `EventResolved` | `blink_event` | `event_id: ID`, `winning_outcome: u8`, `total_pool: u64` | Event resolved |
| `BetPlaced` | `blink_position` | `event_id: ID`, `position_id: ID`, `outcome_index: u8`, `stake_amount: u64`, `bettor: address` | Bet placed |
| `BetCancelled` | `blink_position` | `event_id: ID`, `position_id: ID`, `refund_amount: u64`, `fee_amount: u64` | Bet cancelled |
| `WinningsClaimed` | `blink_position` | `event_id: ID`, `position_id: ID`, `payout_amount: u64`, `claimer: address` | Winnings claimed |
| `RefundClaimed` | `blink_position` | `event_id: ID`, `position_id: ID`, `refund_amount: u64`, `claimer: address` | Refund claimed |

---

## Error Codes

| Code | Constant | Module | Description |
|------|----------|--------|-------------|
| 0 | `ENotAuthorized` | `blink_config` | Caller not authorized |
| 1 | (inline) | `blink_event` | Caller is not an oracle |
| 100 | `EMarketNotActive` | `blink_config` | Market is deactivated |
| 101 | `EEventNotOpen` | `blink_event` | Event not in expected status |
| 103 | `EEventNotResolved` | `blink_event` | Event not resolved yet |
| 104 | `EEventNotCancelled` | `blink_event` | Event not cancelled |
| 105 | `EPositionAlreadyClaimed` | `blink_position` | Position already claimed |
| 106 | `ENotWinningOutcome` | `blink_position` | Position is on losing outcome |
| 107 | `ENotAuthorized` | `blink_position` | Caller is not the position owner |
| 200 | `EInvalidOutcome` | `blink_event` | Invalid outcome index |
| 202 | `EStakeTooLow` | `blink_position` | Stake below market minimum |
| 203 | `EStakeTooHigh` | `blink_position` | Stake above market maximum |
| 205 | `ETooFewOutcomes` | `blink_event` | Less than 2 outcomes |
| 206 | `ETooManyOutcomes` | `blink_event` | More than 10 outcomes |
| 207 | `EEventMismatch` | `blink_event` / `blink_position` | Event/Market/Position ID mismatch |
| 300 | `EBettingNotStarted` | `blink_event` | Betting window not yet open |
| 301 | `EBettingClosed` | `blink_event` | Betting window ended |
| 302 | `EEventAlreadyLocked` | `blink_position` | Cannot cancel bet after lock |

---

## Security Features

### Access Control

| Operation | Required | Validation |
|-----------|----------|------------|
| Create market | `AdminCap` | Capability proof |
| Add/remove oracle | `AdminCap` | Capability proof |
| Withdraw fees | `AdminCap` | Capability proof |
| Create/open/lock/cancel event | `MarketCreatorCap` | Market ID match |
| Resolve event | Oracle address | `is_oracle()` check |
| Claim winnings | Position owner | `tx_context::sender(ctx) == position.owner` |
| Claim refund | Position owner | `tx_context::sender(ctx) == position.owner` |

### Payout Safety

- **u128 arithmetic**: Intermediate payout calculations use `u128` to prevent overflow on large stakes
- **Pool merge on resolve**: Losing pools are merged into the winning pool at resolution time, ensuring payouts only come from a single consolidated pool
- **Double-claim prevention**: Position `is_claimed` flag prevents re-claiming
- **Event-position binding**: All operations verify `position.event_id == event.id`

---

## Build & Test

```bash
# Build
sui move build

# Run all tests (34 tests)
sui move test

# Build in dev mode
sui move build -d
```

## Deployment

```bash
# Publish to network
sui client publish

# Record deployed package address and object IDs
sui move manage-package
```

---

## Typical Flow

```
1. Admin creates Market       → Market (shared), MarketCreatorCap (owned)
2. Admin adds Oracle          → Oracle address registered
3. Creator creates Event      → PredictionEvent (shared, CREATED)
4. Creator opens Event        → Status → OPEN
5. Users place bets           → Position NFTs (owned), funds enter pools
6. Creator locks Event        → Status → LOCKED (no more bets)
7. Oracle resolves Event      → Status → RESOLVED, losing pools merged
8. Winners claim payouts      → Coin<SUI> returned proportionally
   OR
4b. Creator cancels Event     → Status → CANCELLED
5b. Users claim refunds       → Full net stake returned
```

## License

This project is open source. License details to be determined.

## Contributing

Contributions are welcome. Please ensure:
- All tests pass (`sui move test`)
- Code follows Sui Move conventions
- New features include corresponding tests
- Documentation is updated for public API changes
