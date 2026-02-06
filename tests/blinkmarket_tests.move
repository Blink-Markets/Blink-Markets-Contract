#[test_only]
module blinkmarket::blinkmarket_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::clock;
use sui::test_utils;

use blinkmarket::blink_config::{
    Self,
    AdminCap,
    MarketCreatorCap,
    Market,
    Treasury,
};
use blinkmarket::blink_event::{
    Self,
    PredictionEvent,
};
use blinkmarket::blink_position::{
    Self,
    Position,
};

// Test addresses
const ADMIN: address = @0xAD;
const ORACLE: address = @0x0AC1E;
const USER_A: address = @0xA;
const USER_B: address = @0xB;
const USER_C: address = @0xC;

// Test constants
const MIN_STAKE: u64 = 1_000_000; // 0.001 SUI
const MAX_STAKE: u64 = 1_000_000_000; // 1 SUI
const PLATFORM_FEE_BPS: u64 = 200; // 2%

// ============== Helper Functions ==============

fun setup_test(): Scenario {
    let mut scenario = ts::begin(ADMIN);
    {
        blink_config::init_for_testing(ts::ctx(&mut scenario));
    };
    scenario
}

fun create_test_market(scenario: &mut Scenario): MarketCreatorCap {
    ts::next_tx(scenario, ADMIN);
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);

    let creator_cap = blink_config::create_market(
        &admin_cap,
        b"NBA",
        b"NBA Basketball Predictions",
        MIN_STAKE,
        MAX_STAKE,
        PLATFORM_FEE_BPS,
        ts::ctx(scenario),
    );

    ts::return_to_sender(scenario, admin_cap);
    creator_cap
}

fun add_oracle_to_market(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    let mut market = ts::take_shared<Market>(scenario);

    blink_config::add_oracle(&admin_cap, &mut market, ORACLE);

    ts::return_shared(market);
    ts::return_to_sender(scenario, admin_cap);
}

fun create_test_event(scenario: &mut Scenario, creator_cap: &MarketCreatorCap) {
    ts::next_tx(scenario, ADMIN);
    let market = ts::take_shared<Market>(scenario);

    let outcome_labels = vector[b"Yes", b"No"];
    blink_event::create_event(
        creator_cap,
        &market,
        b"Will the next shot be a 3-pointer?",
        outcome_labels,
        0, // betting starts immediately
        1000000000000, // betting ends far in the future
        ts::ctx(scenario),
    );

    ts::return_shared(market);
}

fun mint_sui(amount: u64, ctx: &mut sui::tx_context::TxContext): Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ctx)
}

// ============== Initialization Tests ==============

#[test]
fun test_init_creates_admin_cap_and_treasury() {
    let mut scenario = setup_test();

    // Check AdminCap was transferred to admin
    ts::next_tx(&mut scenario, ADMIN);
    {
        assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
    };

    // Check Treasury was shared
    ts::next_tx(&mut scenario, ADMIN);
    {
        let treasury = ts::take_shared<Treasury>(&scenario);
        assert!(blink_config::get_treasury_balance(&treasury) == 0, 1);
        assert!(blink_config::get_total_fees_collected(&treasury) == 0, 2);
        ts::return_shared(treasury);
    };

    ts::end(scenario);
}

// ============== Market Management Tests ==============

#[test]
fun test_create_market() {
    let mut scenario = setup_test();

    let creator_cap = create_test_market(&mut scenario);

    // Verify market was created
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);
        assert!(blink_config::get_market_min_stake(&market) == MIN_STAKE, 0);
        assert!(blink_config::get_market_max_stake(&market) == MAX_STAKE, 1);
        assert!(blink_config::get_market_fee_bps(&market) == PLATFORM_FEE_BPS, 2);
        assert!(blink_config::is_market_active(&market), 3);
        ts::return_shared(market);
    };

    // Clean up
    ts::next_tx(&mut scenario, ADMIN);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
fun test_add_and_remove_oracle() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);

    // Add oracle
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut market = ts::take_shared<Market>(&scenario);

        blink_config::add_oracle(&admin_cap, &mut market, ORACLE);
        assert!(blink_config::is_oracle(&market, ORACLE), 0);

        ts::return_shared(market);
        ts::return_to_sender(&scenario, admin_cap);
    };

    // Remove oracle
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut market = ts::take_shared<Market>(&scenario);

        blink_config::remove_oracle(&admin_cap, &mut market, ORACLE);
        assert!(!blink_config::is_oracle(&market, ORACLE), 1);

        ts::return_shared(market);
        ts::return_to_sender(&scenario, admin_cap);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
fun test_set_market_active() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);

    // Deactivate market
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut market = ts::take_shared<Market>(&scenario);

        blink_config::set_market_active(&admin_cap, &mut market, false);
        assert!(!blink_config::is_market_active(&market), 0);

        ts::return_shared(market);
        ts::return_to_sender(&scenario, admin_cap);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Event Lifecycle Tests ==============

#[test]
fun test_event_lifecycle_created_to_open() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Verify event is created
    ts::next_tx(&mut scenario, ADMIN);
    {
        let event = ts::take_shared<PredictionEvent>(&scenario);
        assert!(blink_event::get_event_status(&event) == blink_event::get_status_created(), 0);
        ts::return_shared(event);
    };

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        assert!(blink_event::get_event_status(&event) == blink_event::get_status_open(), 1);
        ts::return_shared(event);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
fun test_event_lifecycle_open_to_locked() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open then lock
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        blink_event::lock_event(&creator_cap, &mut event);
        assert!(blink_event::get_event_status(&event) == blink_event::get_status_locked(), 0);
        ts::return_shared(event);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
fun test_event_cancellation() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open then cancel
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        blink_event::cancel_event(&creator_cap, &mut event);
        assert!(blink_event::get_event_status(&event) == blink_event::get_status_cancelled(), 0);
        ts::return_shared(event);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Betting Tests ==============

#[test]
fun test_place_bet() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    // Create clock
    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Place bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario)); // 0.1 SUI
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0, // outcome index (Yes)
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Verify position
        assert!(blink_position::get_position_stake(&position) == 98_000_000, 0); // 2% fee deducted
        assert!(blink_position::get_position_outcome(&position) == 0, 1);
        assert!(!blink_position::is_position_claimed(&position), 2);

        // Verify treasury collected fee
        assert!(blink_config::get_treasury_balance(&treasury) == 2_000_000, 3); // 2% of 100M

        // Verify event pool
        assert!(blink_event::get_total_pool(&event) == 98_000_000, 4);

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 202, location = blink_position)] // EStakeTooLow
fun test_place_bet_stake_too_low() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Try to place bet with stake below minimum
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100, ts::ctx(&mut scenario)); // Too low
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        test_utils::destroy(position);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 101, location = blink_event)] // EEventNotOpen
fun test_place_bet_event_not_open() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Event is in CREATED state (not opened)
    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        test_utils::destroy(position);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 301, location = blink_event)] // EBettingClosed
fun test_place_bet_after_betting_window() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);

    // Create event with short betting window
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        let outcome_labels = vector[b"Yes", b"No"];
        blink_event::create_event(
            &creator_cap,
            &market,
            b"Test event",
            outcome_labels,
            0, // betting starts at 0
            100, // betting ends at 100ms
            ts::ctx(&mut scenario),
        );

        ts::return_shared(market);
    };

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    // Create clock set after betting window
    ts::next_tx(&mut scenario, USER_A);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 200); // After betting window

    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        test_utils::destroy(position);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Resolution and Payout Tests ==============

#[test]
fun test_full_betting_resolution_and_claim() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    add_oracle_to_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A bets 100 on Yes (outcome 0)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0, // Yes
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // User B bets 200 on Yes (outcome 0)
    ts::next_tx(&mut scenario, USER_B);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(200_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0, // Yes
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_B);
    };

    // User C bets 300 on No (outcome 1)
    ts::next_tx(&mut scenario, USER_C);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(300_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            1, // No
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_C);
    };

    // Lock the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::lock_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    // Oracle resolves - Yes wins (outcome 0)
    ts::next_tx(&mut scenario, ORACLE);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);

        blink_event::resolve_event(
            &mut event,
            &market,
            0, // Yes wins
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(blink_event::get_event_status(&event) == blink_event::get_status_resolved(), 0);

        ts::return_shared(event);
        ts::return_shared(market);
    };

    // User A claims winnings
    // Total pool = 588M (after 2% fees on each bet: 98 + 196 + 294 = 588)
    // Yes pool = 294M (98 + 196)
    // User A stake = 98M, expected payout = (98/294) * 588 = 196M
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let mut position = ts::take_from_sender<Position>(&scenario);

        let winnings = blink_position::claim_winnings(
            &mut event,
            &mut position,
            ts::ctx(&mut scenario),
        );

        // Verify payout calculation: (98/294) * 588 = 196
        assert!(coin::value(&winnings) == 196_000_000, 1);
        assert!(blink_position::is_position_claimed(&position), 2);

        ts::return_shared(event);
        ts::return_to_sender(&scenario, position);
        test_utils::destroy(winnings);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 105, location = blink_position)] // EPositionAlreadyClaimed
fun test_double_claim_prevention() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    add_oracle_to_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A places bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // Lock and resolve
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::lock_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, ORACLE);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        blink_event::resolve_event(&mut event, &market, 0, &clock, ts::ctx(&mut scenario));
        ts::return_shared(event);
        ts::return_shared(market);
    };

    // First claim (should succeed)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let mut position = ts::take_from_sender<Position>(&scenario);

        let winnings = blink_position::claim_winnings(&mut event, &mut position, ts::ctx(&mut scenario));

        ts::return_shared(event);
        ts::return_to_sender(&scenario, position);
        test_utils::destroy(winnings);
    };

    // Second claim (should fail)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let mut position = ts::take_from_sender<Position>(&scenario);

        let winnings = blink_position::claim_winnings(&mut event, &mut position, ts::ctx(&mut scenario));

        ts::return_shared(event);
        ts::return_to_sender(&scenario, position);
        test_utils::destroy(winnings);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 106, location = blink_position)] // ENotWinningOutcome
fun test_claim_losing_position() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    add_oracle_to_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A bets on No (outcome 1)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            1, // No
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // Lock and resolve - Yes wins (outcome 0)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::lock_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, ORACLE);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        blink_event::resolve_event(&mut event, &market, 0, &clock, ts::ctx(&mut scenario)); // Yes wins
        ts::return_shared(event);
        ts::return_shared(market);
    };

    // User A tries to claim (should fail - they bet on No)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let mut position = ts::take_from_sender<Position>(&scenario);

        let winnings = blink_position::claim_winnings(&mut event, &mut position, ts::ctx(&mut scenario));

        ts::return_shared(event);
        ts::return_to_sender(&scenario, position);
        test_utils::destroy(winnings);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Refund Tests ==============

#[test]
fun test_refund_on_cancelled_event() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A places bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // Cancel the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::cancel_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    // User A claims refund
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let position = ts::take_from_sender<Position>(&scenario);

        let refund = blink_position::claim_refund(&mut event, position, ts::ctx(&mut scenario));

        // Refund should be net stake (after platform fee)
        assert!(coin::value(&refund) == 98_000_000, 0);

        ts::return_shared(event);
        test_utils::destroy(refund);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Cancel Bet Tests ==============

#[test]
fun test_cancel_bet_before_lock() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A places bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // User A cancels bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let position = ts::take_from_sender<Position>(&scenario);

        let refund = blink_position::cancel_bet(&mut event, position, ts::ctx(&mut scenario));

        // 1% cancellation fee: 98M * 0.99 = 97.02M
        assert!(coin::value(&refund) == 97_020_000, 0);

        ts::return_shared(event);
        test_utils::destroy(refund);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 302, location = blink_position)] // EEventAlreadyLocked
fun test_cancel_bet_after_lock_fails() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // User A places bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(
            &mut event,
            &market,
            &mut treasury,
            0,
            stake,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // Lock the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::lock_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    // User A tries to cancel bet (should fail)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let position = ts::take_from_sender<Position>(&scenario);

        let refund = blink_position::cancel_bet(&mut event, position, ts::ctx(&mut scenario));

        ts::return_shared(event);
        test_utils::destroy(refund);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Oracle Authorization Tests ==============

#[test]
#[expected_failure(abort_code = 1, location = blink_event)] // ENotOracle
fun test_non_oracle_cannot_resolve() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open and lock the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        blink_event::lock_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Non-oracle tries to resolve (should fail)
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);

        blink_event::resolve_event(&mut event, &market, 0, &clock, ts::ctx(&mut scenario));

        ts::return_shared(event);
        ts::return_shared(market);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== View Function Tests ==============

#[test]
fun test_get_odds() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Place bets
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake1 = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position1 = blink_position::place_bet(&mut event, &market, &mut treasury, 0, stake1, &clock, ts::ctx(&mut scenario));

        let stake2 = mint_sui(200_000_000, ts::ctx(&mut scenario));
        let position2 = blink_position::place_bet(&mut event, &market, &mut treasury, 1, stake2, &clock, ts::ctx(&mut scenario));

        // Check odds
        let odds = blink_event::get_odds(&event);
        assert!(*odds.borrow(0) == 98_000_000, 0); // 100M - 2% = 98M
        assert!(*odds.borrow(1) == 196_000_000, 1); // 200M - 2% = 196M

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        test_utils::destroy(position1);
        test_utils::destroy(position2);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
fun test_calculate_potential_payout() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Place initial bet
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(&mut event, &market, &mut treasury, 0, stake, &clock, ts::ctx(&mut scenario));

        // Calculate potential payout for a 100M bet on outcome 1
        let potential = blink_event::calculate_potential_payout(&event, 1, 100_000_000);
        // No pool is currently empty (0), so function returns stake_amount directly (1:1 payout)
        assert!(potential == 100_000_000, 0);

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        test_utils::destroy(position);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Admin Tests ==============

#[test]
fun test_withdraw_fees() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);
    create_test_event(&mut scenario, &creator_cap);

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);
        ts::return_shared(event);
    };

    ts::next_tx(&mut scenario, USER_A);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Place bet to generate fees
    ts::next_tx(&mut scenario, USER_A);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        let market = ts::take_shared<Market>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        let stake = mint_sui(100_000_000, ts::ctx(&mut scenario));
        let position = blink_position::place_bet(&mut event, &market, &mut treasury, 0, stake, &clock, ts::ctx(&mut scenario));

        ts::return_shared(event);
        ts::return_shared(market);
        ts::return_shared(treasury);
        transfer::public_transfer(position, USER_A);
    };

    // Admin withdraws fees
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut treasury = ts::take_shared<Treasury>(&scenario);

        assert!(blink_config::get_treasury_balance(&treasury) == 2_000_000, 0);

        let withdrawn = blink_config::withdraw_fees(&admin_cap, &mut treasury, 1_000_000, ts::ctx(&mut scenario));
        assert!(coin::value(&withdrawn) == 1_000_000, 1);
        assert!(blink_config::get_treasury_balance(&treasury) == 1_000_000, 2);

        ts::return_shared(treasury);
        ts::return_to_sender(&scenario, admin_cap);
        test_utils::destroy(withdrawn);
    };

    clock::destroy_for_testing(clock);
    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

// ============== Event with Multiple Outcomes Test ==============

#[test]
fun test_multi_outcome_event() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);

    // Create event with 4 outcomes (Team A, Team B, Draw, Other)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        let outcome_labels = vector[b"Team A", b"Team B", b"Draw", b"Other"];
        blink_event::create_event(
            &creator_cap,
            &market,
            b"Who wins the match?",
            outcome_labels,
            0,
            1000000000000,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(market);
    };

    // Open the event
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut event = ts::take_shared<PredictionEvent>(&scenario);
        blink_event::open_event(&creator_cap, &mut event);

        // Verify 4 outcomes
        let odds = blink_event::get_odds(&event);
        assert!(odds.length() == 4, 0);

        ts::return_shared(event);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 205, location = blink_event)] // ETooFewOutcomes
fun test_too_few_outcomes() {
    let mut scenario = setup_test();
    let creator_cap = create_test_market(&mut scenario);

    // Try to create event with only 1 outcome
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        let outcome_labels = vector[b"Only One"];
        blink_event::create_event(
            &creator_cap,
            &market,
            b"Invalid event",
            outcome_labels,
            0,
            1000000000000,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(market);
    };

    test_utils::destroy(creator_cap);
    ts::end(scenario);
}
