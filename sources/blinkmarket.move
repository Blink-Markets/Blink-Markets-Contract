/// Module: blinkmarket
/// Real-time micro-prediction market for ultra-fast betting on micro-events
module blinkmarket::blinkmarket;


use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::clock::{Self, Clock};
use sui::event;
use sui::vec_map::{Self, VecMap};

// ============== Error Constants ==============

// Access control errors
const ENotAuthorized: u64 = 0;
const ENotOracle: u64 = 1;

// State errors
const EMarketNotActive: u64 = 100;
const EEventNotOpen: u64 = 101;
const EEventNotResolved: u64 = 103;
const EEventNotCancelled: u64 = 104;
const EPositionAlreadyClaimed: u64 = 105;
const ENotWinningOutcome: u64 = 106;

// Validation errors
const EInvalidOutcome: u64 = 200;
const EStakeTooLow: u64 = 202;
const EStakeTooHigh: u64 = 203;
const ETooFewOutcomes: u64 = 205;
const ETooManyOutcomes: u64 = 206;
const EEventMismatch: u64 = 207;

// Timing errors
const EBettingNotStarted: u64 = 300;
const EBettingClosed: u64 = 301;
const EEventAlreadyLocked: u64 = 302;

// Event status constants
const STATUS_CREATED: u8 = 0;
const STATUS_OPEN: u8 = 1;
const STATUS_LOCKED: u8 = 2;
const STATUS_RESOLVED: u8 = 3;
const STATUS_CANCELLED: u8 = 4;

// Configuration constants
const MIN_OUTCOMES: u64 = 2;
const MAX_OUTCOMES: u64 = 10;
const CANCELLATION_FEE_BPS: u64 = 100; // 1% = 100 basis points
const BPS_DENOMINATOR: u64 = 10000;

// ============== Core Structs ==============

/// Platform admin capability - grants full administrative control
public struct AdminCap has key, store {
    id: UID,
}

/// Capability to create events for a specific market
public struct MarketCreatorCap has key, store {
    id: UID,
    market_id: ID,
}

/// Market category container (e.g., NBA, eSports)
public struct Market has key, store {
    id: UID,
    name: vector<u8>,
    description: vector<u8>,
    min_stake: u64,
    max_stake: u64,
    platform_fee_bps: u64, // Platform fee in basis points
    is_active: bool,
    oracles: VecMap<address, bool>, // Authorized oracles
}

/// Individual prediction event with outcome pools
public struct PredictionEvent has key, store {
    id: UID,
    market_id: ID,
    description: vector<u8>,
    outcome_labels: vector<vector<u8>>,
    outcome_pools: vector<Balance<SUI>>,
    total_pool: u64,
    status: u8,
    betting_start_time: u64,
    betting_end_time: u64,
    winning_outcome: u8,
    creator: address,
}

/// User's stake on a specific outcome
public struct Position has key, store {
    id: UID,
    event_id: ID,
    outcome_index: u8,
    stake_amount: u64,
    is_claimed: bool,
    owner: address,
}

/// Platform fee collection treasury
public struct Treasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_collected: u64,
}

// ============== Events ==============

public struct MarketCreated has copy, drop {
    market_id: ID,
    name: vector<u8>,
}

public struct EventCreated has copy, drop {
    event_id: ID,
    market_id: ID,
    description: vector<u8>,
    num_outcomes: u64,
}

public struct BetPlaced has copy, drop {
    event_id: ID,
    position_id: ID,
    outcome_index: u8,
    stake_amount: u64,
    bettor: address,
}

public struct BetCancelled has copy, drop {
    event_id: ID,
    position_id: ID,
    refund_amount: u64,
    fee_amount: u64,
}

public struct EventResolved has copy, drop {
    event_id: ID,
    winning_outcome: u8,
    total_pool: u64,
}

public struct WinningsClaimed has copy, drop {
    event_id: ID,
    position_id: ID,
    payout_amount: u64,
    claimer: address,
}

public struct RefundClaimed has copy, drop {
    event_id: ID,
    position_id: ID,
    refund_amount: u64,
    claimer: address,
}

// ============== Initialization ==============

/// Initialize the module - creates AdminCap and Treasury
fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin_cap, tx_context::sender(ctx));

    let treasury = Treasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_collected: 0,
    };
    transfer::share_object(treasury);
}

// ============== Market Management ==============

/// Create a new market category (admin only)
public fun create_market(
    _admin: &AdminCap,
    name: vector<u8>,
    description: vector<u8>,
    min_stake: u64,
    max_stake: u64,
    platform_fee_bps: u64,
    ctx: &mut TxContext,
): MarketCreatorCap {
    let market = Market {
        id: object::new(ctx),
        name,
        description,
        min_stake,
        max_stake,
        platform_fee_bps,
        is_active: true,
        oracles: vec_map::empty(),
    };

    let market_id = object::id(&market);

    event::emit(MarketCreated {
        market_id,
        name: market.name,
    });

    transfer::share_object(market);

    MarketCreatorCap {
        id: object::new(ctx),
        market_id,
    }
}

/// Add an oracle to the market
public fun add_oracle(
    _admin: &AdminCap,
    market: &mut Market,
    oracle_address: address,
) {
    if (!vec_map::contains(&market.oracles, &oracle_address)) {
        vec_map::insert(&mut market.oracles, oracle_address, true);
    };
}

/// Remove an oracle from the market
public fun remove_oracle(
    _admin: &AdminCap,
    market: &mut Market,
    oracle_address: address,
) {
    if (vec_map::contains(&market.oracles, &oracle_address)) {
        vec_map::remove(&mut market.oracles, &oracle_address);
    };
}

/// Set market active status
public fun set_market_active(
    _admin: &AdminCap,
    market: &mut Market,
    is_active: bool,
) {
    market.is_active = is_active;
}

/// Check if an address is an authorized oracle
public fun is_oracle(market: &Market, addr: address): bool {
    vec_map::contains(&market.oracles, &addr)
}

// ============== Event Management ==============

/// Create a new prediction event
public fun create_event(
    creator_cap: &MarketCreatorCap,
    market: &Market,
    description: vector<u8>,
    outcome_labels: vector<vector<u8>>,
    betting_start_time: u64,
    betting_end_time: u64,
    ctx: &mut TxContext,
) {
    assert!(market.is_active, EMarketNotActive);
    assert!(object::id(market) == creator_cap.market_id, ENotAuthorized);

    let num_outcomes = outcome_labels.length();
    assert!(num_outcomes >= MIN_OUTCOMES, ETooFewOutcomes);
    assert!(num_outcomes <= MAX_OUTCOMES, ETooManyOutcomes);

    // Initialize outcome pools
    let mut outcome_pools = vector::empty<Balance<SUI>>();
    let mut i = 0;
    while (i < num_outcomes) {
        outcome_pools.push_back(balance::zero());
        i = i + 1;
    };

    let prediction_event = PredictionEvent {
        id: object::new(ctx),
        market_id: object::id(market),
        description,
        outcome_labels,
        outcome_pools,
        total_pool: 0,
        status: STATUS_CREATED,
        betting_start_time,
        betting_end_time,
        winning_outcome: 0,
        creator: tx_context::sender(ctx),
    };

    event::emit(EventCreated {
        event_id: object::id(&prediction_event),
        market_id: object::id(market),
        description: prediction_event.description,
        num_outcomes,
    });

    transfer::share_object(prediction_event);
}

/// Open an event for betting
public fun open_event(
    creator_cap: &MarketCreatorCap,
    prediction_event: &mut PredictionEvent,
) {
    assert!(prediction_event.market_id == creator_cap.market_id, ENotAuthorized);
    assert!(prediction_event.status == STATUS_CREATED, EEventNotOpen);
    prediction_event.status = STATUS_OPEN;
}

/// Lock an event (no more bets accepted)
public fun lock_event(
    creator_cap: &MarketCreatorCap,
    prediction_event: &mut PredictionEvent,
) {
    assert!(prediction_event.market_id == creator_cap.market_id, ENotAuthorized);
    assert!(prediction_event.status == STATUS_OPEN, EEventNotOpen);
    prediction_event.status = STATUS_LOCKED;
}

/// Cancel an event (enables refunds)
public fun cancel_event(
    creator_cap: &MarketCreatorCap,
    prediction_event: &mut PredictionEvent,
) {
    assert!(prediction_event.market_id == creator_cap.market_id, ENotAuthorized);
    assert!(
        prediction_event.status == STATUS_CREATED ||
        prediction_event.status == STATUS_OPEN ||
        prediction_event.status == STATUS_LOCKED,
        EEventNotOpen
    );
    prediction_event.status = STATUS_CANCELLED;
}

// ============== Betting ==============

/// Place a bet on an outcome
public fun place_bet(
    prediction_event: &mut PredictionEvent,
    market: &Market,
    treasury: &mut Treasury,
    outcome_index: u8,
    stake: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Position {
    // Validate market and event status
    assert!(market.is_active, EMarketNotActive);
    assert!(prediction_event.market_id == object::id(market), EEventMismatch);
    assert!(prediction_event.status == STATUS_OPEN, EEventNotOpen);

    // Validate timing
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time >= prediction_event.betting_start_time, EBettingNotStarted);
    assert!(current_time < prediction_event.betting_end_time, EBettingClosed);

    // Validate outcome index
    let num_outcomes = prediction_event.outcome_labels.length();
    assert!((outcome_index as u64) < num_outcomes, EInvalidOutcome);

    // Validate stake amount
    let stake_value = coin::value(&stake);
    assert!(stake_value >= market.min_stake, EStakeTooLow);
    assert!(stake_value <= market.max_stake, EStakeTooHigh);

    // Calculate and extract platform fee
    let fee_amount = (stake_value * market.platform_fee_bps) / BPS_DENOMINATOR;
    let net_stake = stake_value - fee_amount;

    let mut stake_balance = coin::into_balance(stake);

    // Transfer fee to treasury
    if (fee_amount > 0) {
        let fee_balance = balance::split(&mut stake_balance, fee_amount);
        balance::join(&mut treasury.balance, fee_balance);
        treasury.total_collected = treasury.total_collected + fee_amount;
    };

    // Add net stake to outcome pool
    let pool = &mut prediction_event.outcome_pools[outcome_index as u64];
    balance::join(pool, stake_balance);
    prediction_event.total_pool = prediction_event.total_pool + net_stake;

    let bettor = tx_context::sender(ctx);
    let position = Position {
        id: object::new(ctx),
        event_id: object::id(prediction_event),
        outcome_index,
        stake_amount: net_stake,
        is_claimed: false,
        owner: bettor,
    };

    event::emit(BetPlaced {
        event_id: object::id(prediction_event),
        position_id: object::id(&position),
        outcome_index,
        stake_amount: net_stake,
        bettor,
    });

    position
}

/// Cancel a bet before event is locked (1% fee)
public fun cancel_bet(
    prediction_event: &mut PredictionEvent,
    position: Position,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Can only cancel when event is still OPEN
    assert!(prediction_event.status == STATUS_OPEN, EEventAlreadyLocked);
    assert!(position.event_id == object::id(prediction_event), EEventMismatch);
    assert!(!position.is_claimed, EPositionAlreadyClaimed);

    let Position { id, event_id: _, outcome_index, stake_amount, is_claimed: _, owner: _ } = position;
    let position_id = object::uid_to_inner(&id);
    object::delete(id);

    // Calculate cancellation fee
    let fee_amount = (stake_amount * CANCELLATION_FEE_BPS) / BPS_DENOMINATOR;
    let refund_amount = stake_amount - fee_amount;

    // Withdraw from outcome pool
    let pool = &mut prediction_event.outcome_pools[outcome_index as u64];
    let refund_balance = balance::split(pool, refund_amount);
    prediction_event.total_pool = prediction_event.total_pool - refund_amount;

    // Fee stays in the pool (distributed to winners)

    event::emit(BetCancelled {
        event_id: object::id(prediction_event),
        position_id,
        refund_amount,
        fee_amount,
    });

    coin::from_balance(refund_balance, ctx)
}

// ============== Resolution ==============

/// Resolve an event with the winning outcome (oracle only)
public fun resolve_event(
    prediction_event: &mut PredictionEvent,
    market: &Market,
    winning_outcome: u8,
    _clock: &Clock,
    ctx: &mut TxContext,
) {
    // Validate caller is authorized oracle
    let sender = tx_context::sender(ctx);
    assert!(is_oracle(market, sender), ENotOracle);

    // Validate event state
    assert!(prediction_event.market_id == object::id(market), EEventMismatch);
    assert!(prediction_event.status == STATUS_LOCKED, EEventNotOpen);

    // Validate winning outcome
    let num_outcomes = prediction_event.outcome_labels.length();
    assert!((winning_outcome as u64) < num_outcomes, EInvalidOutcome);

    // Set resolution
    prediction_event.winning_outcome = winning_outcome;
    prediction_event.status = STATUS_RESOLVED;

    event::emit(EventResolved {
        event_id: object::id(prediction_event),
        winning_outcome,
        total_pool: prediction_event.total_pool,
    });
}

// ============== Claims ==============

/// Claim winnings for a winning position
public fun claim_winnings(
    prediction_event: &mut PredictionEvent,
    position: &mut Position,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Validate event is resolved
    assert!(prediction_event.status == STATUS_RESOLVED, EEventNotResolved);
    assert!(position.event_id == object::id(prediction_event), EEventMismatch);
    assert!(!position.is_claimed, EPositionAlreadyClaimed);
    assert!(position.outcome_index == prediction_event.winning_outcome, ENotWinningOutcome);

    // Calculate payout: (user_stake / winning_pool) * total_pool
    let winning_pool_balance = balance::value(&prediction_event.outcome_pools[position.outcome_index as u64]);
    let total_pool = prediction_event.total_pool;

    // Payout calculation with proper rounding
    let payout_amount = (position.stake_amount * total_pool) / winning_pool_balance;

    // Mark as claimed
    position.is_claimed = true;

    // Withdraw payout from winning pool (all pools contribute to winnings)
    // We take proportionally from all pools
    let mut payout_balance = balance::zero<SUI>();
    let num_pools = prediction_event.outcome_pools.length();
    let mut remaining = payout_amount;
    let mut i = 0;

    while (i < num_pools && remaining > 0) {
        let pool = &mut prediction_event.outcome_pools[i];
        let pool_value = balance::value(pool);
        let take_amount = if (pool_value <= remaining) { pool_value } else { remaining };
        if (take_amount > 0) {
            let taken = balance::split(pool, take_amount);
            balance::join(&mut payout_balance, taken);
            remaining = remaining - take_amount;
        };
        i = i + 1;
    };

    let claimer = tx_context::sender(ctx);
    event::emit(WinningsClaimed {
        event_id: object::id(prediction_event),
        position_id: object::id(position),
        payout_amount: balance::value(&payout_balance),
        claimer,
    });

    coin::from_balance(payout_balance, ctx)
}

/// Claim refund for a cancelled event
public fun claim_refund(
    prediction_event: &mut PredictionEvent,
    position: Position,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Validate event is cancelled
    assert!(prediction_event.status == STATUS_CANCELLED, EEventNotCancelled);
    assert!(position.event_id == object::id(prediction_event), EEventMismatch);
    assert!(!position.is_claimed, EPositionAlreadyClaimed);

    let Position { id, event_id: _, outcome_index, stake_amount, is_claimed: _, owner: _ } = position;
    let position_id = object::uid_to_inner(&id);
    object::delete(id);

    // Withdraw full stake from outcome pool
    let pool = &mut prediction_event.outcome_pools[outcome_index as u64];
    let refund_balance = balance::split(pool, stake_amount);

    let claimer = tx_context::sender(ctx);
    event::emit(RefundClaimed {
        event_id: object::id(prediction_event),
        position_id,
        refund_amount: stake_amount,
        claimer,
    });

    coin::from_balance(refund_balance, ctx)
}

// ============== View Functions ==============

/// Get current odds for all outcomes (returns pool balances)
public fun get_odds(prediction_event: &PredictionEvent): vector<u64> {
    let mut odds = vector::empty<u64>();
    let num_outcomes = prediction_event.outcome_pools.length();
    let mut i = 0;
    while (i < num_outcomes) {
        odds.push_back(balance::value(&prediction_event.outcome_pools[i]));
        i = i + 1;
    };
    odds
}

/// Calculate potential payout for a given stake on an outcome
public fun calculate_potential_payout(
    prediction_event: &PredictionEvent,
    outcome_index: u8,
    stake_amount: u64,
): u64 {
    let num_outcomes = prediction_event.outcome_labels.length();
    assert!((outcome_index as u64) < num_outcomes, EInvalidOutcome);

    let outcome_pool = balance::value(&prediction_event.outcome_pools[outcome_index as u64]);
    let total_pool = prediction_event.total_pool;

    // If no one has bet yet, return the stake (1:1)
    if (outcome_pool == 0) {
        return stake_amount
    };

    // New pool after this bet
    let new_outcome_pool = outcome_pool + stake_amount;
    let new_total_pool = total_pool + stake_amount;

    // Potential payout: (stake / new_outcome_pool) * new_total_pool
    (stake_amount * new_total_pool) / new_outcome_pool
}

/// Check if betting is currently open
public fun is_betting_open(prediction_event: &PredictionEvent, clock: &Clock): bool {
    if (prediction_event.status != STATUS_OPEN) {
        return false
    };
    let current_time = clock::timestamp_ms(clock);
    current_time >= prediction_event.betting_start_time &&
    current_time < prediction_event.betting_end_time
}

/// Get event status
public fun get_event_status(prediction_event: &PredictionEvent): u8 {
    prediction_event.status
}

/// Get total pool amount
public fun get_total_pool(prediction_event: &PredictionEvent): u64 {
    prediction_event.total_pool
}

/// Get winning outcome (only valid after resolution)
public fun get_winning_outcome(prediction_event: &PredictionEvent): u8 {
    assert!(prediction_event.status == STATUS_RESOLVED, EEventNotResolved);
    prediction_event.winning_outcome
}

/// Get position details
public fun get_position_stake(position: &Position): u64 {
    position.stake_amount
}

public fun get_position_outcome(position: &Position): u8 {
    position.outcome_index
}

public fun is_position_claimed(position: &Position): bool {
    position.is_claimed
}

/// Get treasury balance
public fun get_treasury_balance(treasury: &Treasury): u64 {
    balance::value(&treasury.balance)
}

/// Get total fees collected
public fun get_total_fees_collected(treasury: &Treasury): u64 {
    treasury.total_collected
}

/// Get market configuration
public fun get_market_min_stake(market: &Market): u64 {
    market.min_stake
}

public fun get_market_max_stake(market: &Market): u64 {
    market.max_stake
}

public fun get_market_fee_bps(market: &Market): u64 {
    market.platform_fee_bps
}

public fun is_market_active(market: &Market): bool {
    market.is_active
}

// ============== Admin Functions ==============

/// Withdraw fees from treasury (admin only)
public fun withdraw_fees(
    _admin: &AdminCap,
    treasury: &mut Treasury,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    let withdraw_balance = balance::split(&mut treasury.balance, amount);
    coin::from_balance(withdraw_balance, ctx)
}

// ============== Test-only Functions ==============

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun get_status_created(): u8 { STATUS_CREATED }

#[test_only]
public fun get_status_open(): u8 { STATUS_OPEN }

#[test_only]
public fun get_status_locked(): u8 { STATUS_LOCKED }

#[test_only]
public fun get_status_resolved(): u8 { STATUS_RESOLVED }

#[test_only]
public fun get_status_cancelled(): u8 { STATUS_CANCELLED }
