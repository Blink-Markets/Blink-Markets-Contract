/// Module: blink_event
/// Event lifecycle management and oracle operations for prediction markets
module blinkmarket::blink_event;

use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::clock::{Self, Clock};
use sui::event;

use blinkmarket::blink_config::{Self, MarketCreatorCap, Market};

// ============== Error Constants ==============

// State errors
const EEventNotOpen: u64 = 101;
const EEventNotResolved: u64 = 103;
const EEventNotCancelled: u64 = 104;

// Validation errors
const EInvalidOutcome: u64 = 200;
const ETooFewOutcomes: u64 = 205;
const ETooManyOutcomes: u64 = 206;
const EEventMismatch: u64 = 207;

// Timing errors
const EBettingNotStarted: u64 = 300;
const EBettingClosed: u64 = 301;

// Event status constants
const STATUS_CREATED: u8 = 0;
const STATUS_OPEN: u8 = 1;
const STATUS_LOCKED: u8 = 2;
const STATUS_RESOLVED: u8 = 3;
const STATUS_CANCELLED: u8 = 4;

// Configuration constants
const MIN_OUTCOMES: u64 = 2;
const MAX_OUTCOMES: u64 = 10;
const BPS_DENOMINATOR: u64 = 10000;

/// Get BPS denominator (package-internal helper)
public(package) fun get_bps_denominator(): u64 {
    BPS_DENOMINATOR
}

// ============== Core Structs ==============

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

// ============== Events ==============

public struct EventCreated has copy, drop {
    event_id: ID,
    market_id: ID,
    description: vector<u8>,
    num_outcomes: u64,
}

public struct EventResolved has copy, drop {
    event_id: ID,
    winning_outcome: u8,
    total_pool: u64,
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
    blink_config::assert_market_active(market);
    blink_config::assert_market_id_matches(
        market,
        blink_config::get_creator_cap_market_id(creator_cap)
    );

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
    assert!(
        prediction_event.market_id == blink_config::get_creator_cap_market_id(creator_cap),
        EEventMismatch
    );
    assert!(prediction_event.status == STATUS_CREATED, EEventNotOpen);
    prediction_event.status = STATUS_OPEN;
}

/// Lock an event (no more bets accepted)
public fun lock_event(
    creator_cap: &MarketCreatorCap,
    prediction_event: &mut PredictionEvent,
) {
    assert!(
        prediction_event.market_id == blink_config::get_creator_cap_market_id(creator_cap),
        EEventMismatch
    );
    assert!(prediction_event.status == STATUS_OPEN, EEventNotOpen);
    prediction_event.status = STATUS_LOCKED;
}

/// Cancel an event (enables refunds)
public fun cancel_event(
    creator_cap: &MarketCreatorCap,
    prediction_event: &mut PredictionEvent,
) {
    assert!(
        prediction_event.market_id == blink_config::get_creator_cap_market_id(creator_cap),
        EEventMismatch
    );
    assert!(
        prediction_event.status == STATUS_CREATED ||
        prediction_event.status == STATUS_OPEN ||
        prediction_event.status == STATUS_LOCKED,
        EEventNotOpen
    );
    prediction_event.status = STATUS_CANCELLED;
}

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
    assert!(blink_config::is_oracle(market, sender), 1); // ENotOracle

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

// ============== Package-internal Pool Access ==============

/// Add stake to outcome pool (called by blink_position)
public(package) fun add_to_pool(
    prediction_event: &mut PredictionEvent,
    outcome_index: u8,
    stake_balance: Balance<SUI>,
    net_stake: u64,
) {
    let pool = &mut prediction_event.outcome_pools[outcome_index as u64];
    balance::join(pool, stake_balance);
    prediction_event.total_pool = prediction_event.total_pool + net_stake;
}

/// Remove stake from outcome pool (called by blink_position for cancellations)
public(package) fun remove_from_pool(
    prediction_event: &mut PredictionEvent,
    outcome_index: u8,
    amount: u64,
): Balance<SUI> {
    let pool = &mut prediction_event.outcome_pools[outcome_index as u64];
    let withdrawn = balance::split(pool, amount);
    prediction_event.total_pool = prediction_event.total_pool - amount;
    withdrawn
}

/// Withdraw payout from pools (called by blink_position for claims)
public(package) fun withdraw_payout(
    prediction_event: &mut PredictionEvent,
    payout_amount: u64,
): Balance<SUI> {
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

    payout_balance
}

// ============== Validation Helpers (package-internal) ==============

/// Validate event is open for betting
public(package) fun assert_event_open(prediction_event: &PredictionEvent) {
    assert!(prediction_event.status == STATUS_OPEN, EEventNotOpen);
}

/// Validate event timing
public(package) fun assert_betting_time_valid(
    prediction_event: &PredictionEvent,
    clock: &Clock,
) {
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time >= prediction_event.betting_start_time, EBettingNotStarted);
    assert!(current_time < prediction_event.betting_end_time, EBettingClosed);
}

/// Validate outcome index
public(package) fun assert_valid_outcome(
    prediction_event: &PredictionEvent,
    outcome_index: u8,
) {
    let num_outcomes = prediction_event.outcome_labels.length();
    assert!((outcome_index as u64) < num_outcomes, EInvalidOutcome);
}

/// Validate event is resolved
public(package) fun assert_event_resolved(prediction_event: &PredictionEvent) {
    assert!(prediction_event.status == STATUS_RESOLVED, EEventNotResolved);
}

/// Validate event is cancelled
public(package) fun assert_event_cancelled(prediction_event: &PredictionEvent) {
    assert!(prediction_event.status == STATUS_CANCELLED, EEventNotCancelled);
}

/// Check if outcome is the winning outcome
public(package) fun is_winning_outcome(
    prediction_event: &PredictionEvent,
    outcome_index: u8,
): bool {
    prediction_event.winning_outcome == outcome_index
}

/// Get market ID from event
public(package) fun get_event_market_id(prediction_event: &PredictionEvent): ID {
    prediction_event.market_id
}

/// Get winning pool balance
public(package) fun get_winning_pool_balance(
    prediction_event: &PredictionEvent,
    outcome_index: u8,
): u64 {
    balance::value(&prediction_event.outcome_pools[outcome_index as u64])
}

/// Get total pool amount
public(package) fun get_total_pool_amount(prediction_event: &PredictionEvent): u64 {
    prediction_event.total_pool
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

// ============== Test-only Functions ==============

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
