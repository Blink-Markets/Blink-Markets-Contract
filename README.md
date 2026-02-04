# Blinkmarket

A high-speed micro-prediction market protocol built on Sui blockchain for ultra-fast betting on micro-events.

## Overview

Blinkmarket enables real-time prediction markets for micro-events—short-lived, rapidly-resolved events that demand instant participation and settlement. Unlike traditional prediction markets that operate on timescales of days or weeks, Blinkmarket is designed for events measured in seconds or minutes: a basketball player's next shot, a gaming round outcome, or a split-second market movement.

## The Core Idea

Traditional prediction markets suffer from three fundamental limitations:

1. **Slow settlement cycles** - Events take days or weeks to resolve
2. **High barrier to entry** - Complex interfaces and high minimum stakes
3. **Centralized oracle dependencies** - Single points of failure in resolution

Blinkmarket addresses these by introducing:

- **Micro-events**: Events with betting windows measured in seconds, resolved immediately
- **Parimutuel pooling**: Efficient price discovery through automatic odds calculation based on pool distribution
- **Composable oracle system**: Flexible authorization allowing multiple trusted resolvers per market
- **Position NFTs**: User stakes are represented as owned objects, enabling transferability and composability

## What Makes This Special

### 1. Modular Architecture

The protocol is architected as three independent modules with clear separation of concerns:

```
blink_config    → Governance, treasury, market configuration
blink_event     → Event lifecycle, oracle resolution, pool mechanics
blink_position  → User actions, betting, claims
```

This design enables:
- Independent module upgrades without touching unrelated code
- Clear security boundaries between administrative and user functions
- Easy integration for external protocols to build on specific modules

### 2. Dynamic Parimutuel Pricing

Unlike orderbook-based markets, Blinkmarket uses parimutuel pooling where:
- Odds update in real-time based on pool distribution
- No need for counterparty matching
- Automatic price discovery through market participation
- All losing stakes contribute to winning pool (zero-sum with house fee)

**Example:** 
```
Event: "Will the next shot be a 3-pointer?"
- YES pool: 40 SUI
- NO pool: 60 SUI
- Total pool: 100 SUI (after fees)

If YES wins → Each 1 SUI bet returns 2.5 SUI (100/40 ratio)
If NO wins  → Each 1 SUI bet returns 1.67 SUI (100/60 ratio)
```

### 3. Position-as-NFT Model

User positions are represented as owned objects (`Position` struct), not balances in a shared pool. This provides:

- **Transferability**: Positions can be traded or transferred before resolution
- **Composability**: Other protocols can build on top (position derivatives, lending)
- **Verifiable ownership**: Cryptographic proof of stake without database lookups
- **Cancellation flexibility**: Users can exit positions before event lock (with penalty)

### 4. Flexible Oracle Architecture

Markets support multiple authorized oracles rather than a single resolver:
- Market creators can add/remove oracle addresses
- Any authorized oracle can resolve events
- Oracle set is stored on-chain in a `VecMap` for efficient lookup
- Enables redundancy and decentralized resolution models

### 5. Sui-Native Optimizations

The protocol leverages Sui's unique features:

- **Parallel execution**: Independent bets on different events process concurrently
- **Owned vs Shared objects**: Positions are owned (no contention), events are shared (multi-user access)
- **Balance vs Coin**: Internal accounting uses `Balance<SUI>` for efficiency, user-facing uses `Coin<SUI>`
- **Object-centric design**: Everything is an object with a UID, enabling rich composability

## Architecture Deep Dive

### Module: blink_config

**Purpose:** Platform governance and economic configuration

**Key Components:**
- `AdminCap`: Root administrative capability (created at init)
- `Market`: Container for a category of events (e.g., "NBA", "eSports")
- `Treasury`: Shared object collecting platform fees
- `MarketCreatorCap`: Scoped capability to create events within a specific market

**Design Pattern:** Capability-based access control with scoped permissions. The `MarketCreatorCap` pattern allows delegation of event creation rights without granting full admin access.

### Module: blink_event

**Purpose:** Event lifecycle and pool mechanics

**Key Components:**
- `PredictionEvent`: Shared object containing outcome pools, status, and metadata
- Status state machine: `CREATED → OPEN → LOCKED → RESOLVED/CANCELLED`
- Pool manipulation: Package-internal functions for adding/removing stake

**Design Pattern:** State machine with strict transitions. Events cannot skip states, ensuring predictable behavior and preventing manipulation.

**Pool Accounting:**
```
Total Pool = Sum of all outcome pools (net of fees)
Payout = (user_stake / winning_pool) * total_pool
```

### Module: blink_position

**Purpose:** User-facing betting and claim operations

**Key Components:**
- `Position`: Owned object representing a user's stake
- Bet placement with automatic fee deduction
- Cancellation with penalty before lock
- Winning claims and refund claims

**Design Pattern:** Command pattern where positions are tickets. Claims consume or mutate positions, creating clear ownership semantics.

## Economic Model

### Fee Structure

1. **Platform Fee**: Configurable per-market basis points (e.g., 2% = 200 BPS)
   - Deducted on bet placement
   - Sent directly to Treasury
   - Does not enter outcome pools

2. **Cancellation Fee**: Fixed 1% (100 BPS)
   - Charged when users cancel bets before lock
   - Remains in outcome pool (benefits remaining bettors)
   - Discourages frivolous betting

### Stake Constraints

Markets define min/max stake boundaries:
- **Minimum stake**: Prevents spam and ensures meaningful participation
- **Maximum stake**: Prevents single-user pool dominance
- Validated on every bet placement

## Security Features

### Access Control Layers

1. **Admin-only operations**: Require `AdminCap` proof
   - Treasury withdrawals
   - Oracle management
   - Market activation toggles

2. **Market-scoped operations**: Require `MarketCreatorCap` proof
   - Event creation
   - Event lifecycle management (open, lock, cancel)

3. **Oracle-only operations**: Require oracle address verification
   - Event resolution with winning outcome

### State Machine Enforcement

Events cannot be resolved until locked:
```
create_event() → status = CREATED
open_event()   → status = OPEN (betting allowed)
lock_event()   → status = LOCKED (betting closed)
resolve_event() → status = RESOLVED (only from LOCKED)
```

### Double-Claim Prevention

Positions track `is_claimed` flag:
- Winning claims mutate position (mark as claimed)
- Refund claims consume position (object deleted)
- Attempting double claim aborts with `EPositionAlreadyClaimed`

### Event-Position Binding

Every operation validates `position.event_id == event.id` to prevent:
- Cross-event claims
- Mismatched refunds
- Position replay attacks

## Technical Specifications

### Build Information
- **Language:** Move 2024.beta
- **Platform:** Sui blockchain
- **Package:** `blinkmarket`
- **Address:** `0x0` (placeholder, set on publish)

### Dependencies
- Sui Framework (standard library, coin, balance, clock)
- Sui System (for TxContext and object primitives)

### Build Commands

```bash
# Compile the package
sui move build

# Run all tests
sui move test

# Build with dev dependencies
sui move build -d

# Check test coverage
sui move coverage

# Generate documentation
sui move --doc
```

### Test Coverage

23 comprehensive tests covering:
- Initialization and setup
- Market lifecycle (creation, activation, oracle management)
- Event lifecycle (creation, opening, locking, cancellation)
- Betting mechanics (placement, validation, fee calculation)
- Cancellation logic (timing, fees, pool updates)
- Resolution and claims (winning payouts, refunds, double-claim prevention)
- Edge cases (invalid outcomes, insufficient stakes, unauthorized access)

## Usage Example

```move
// 1. Admin creates a market
let admin_cap = /* received at init */;
let creator_cap = blink_config::create_market(
    &admin_cap,
    b"NBA Live",
    b"Real-time NBA game predictions",
    1_000_000,      // 0.001 SUI min
    1_000_000_000,  // 1 SUI max
    200,            // 2% platform fee
    ctx
);

// 2. Add an oracle
blink_config::add_oracle(&admin_cap, &mut market, @oracle_address);

// 3. Create an event
blink_event::create_event(
    &creator_cap,
    &market,
    b"Will next shot be a 3-pointer?",
    vector[b"Yes", b"No"],
    current_time,
    current_time + 30_000, // 30 second window
    ctx
);

// 4. Open betting
blink_event::open_event(&creator_cap, &mut event);

// 5. User places bet
let position = blink_position::place_bet(
    &mut event,
    &market,
    &mut treasury,
    0, // outcome index (Yes)
    coin::mint_for_testing(10_000_000, ctx), // 0.01 SUI
    &clock,
    ctx
);

// 6. Lock event (no more bets)
blink_event::lock_event(&creator_cap, &mut event);

// 7. Oracle resolves
blink_event::resolve_event(&mut event, &market, 0, &clock, ctx);

// 8. Winner claims payout
let payout = blink_position::claim_winnings(&mut event, &mut position, ctx);
```

## Future Extensions

The modular architecture enables several extensions without core changes:

1. **Dynamic odds modules**: Alternative pricing mechanisms (AMM curves, order books)
2. **Position derivatives**: Options, futures, or bundles built on Position NFTs
3. **Cross-market aggregators**: Protocols that compose multiple markets
4. **Automated market makers**: Bots that provide liquidity using standardized interfaces
5. **Conditional events**: Nested predictions with dependent outcomes
6. **Social features**: Leaderboards, reputation systems, referral rewards

## Design Philosophy

Blinkmarket is built on three core principles:

1. **Modularity over monoliths**: Small, focused modules that do one thing well
2. **Objects over accounts**: Sui's object model enables rich composability
3. **Speed over complexity**: Simple, predictable mechanics enable rapid execution

The result is a protocol that feels like a primitive—simple enough to understand in minutes, powerful enough to build entire ecosystems on top.

## License

This project is open source. License details to be determined.

## Contributing

Contributions are welcome. Please ensure:
- All tests pass (`sui move test`)
- Code follows Sui Move conventions
- New features include corresponding tests
- Documentation is updated for public API changes

## Contact

For questions, issues, or collaboration inquiries, please open an issue in the repository.
