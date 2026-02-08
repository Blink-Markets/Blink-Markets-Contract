# Blinkmarket Frontend Integration Guide

Complete API reference for integrating Blinkmarket prediction markets into frontend applications.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Event Types](#event-types)
4. [Contract Addresses](#contract-addresses)
5. [View Functions](#view-functions)
6. [Transaction Building](#transaction-building)
7. [Event Listening](#event-listening)
8. [Coin Type Support](#coin-type-support)
9. [Error Handling](#error-handling)
10. [Example Workflows](#example-workflows)

---

## Quick Start

### Installation

```bash
npm install @mysten/sui.js
```

### Basic Setup

```typescript
import { SuiClient, getFullnodeUrl } from '@mysten/sui.js/client';
import { TransactionBlock } from '@mysten/sui.js/transactions';

const client = new SuiClient({ url: getFullnodeUrl('mainnet') });

const PACKAGE_ID = 'YOUR_PACKAGE_ID';
const MARKET_ID = 'YOUR_MARKET_ID';
const TREASURY_SUI = 'YOUR_TREASURY_OBJECT_ID';
```

---

## Core Concepts

### Generic Type Parameters

All core functions require a **CoinType** parameter:

```typescript
// For SUI
const coinType = '0x2::sui::SUI';

// For USDC
const coinType = 'USDC_PACKAGE_ID::usdc::USDC';
```

### Object IDs You'll Need

| Object | Required For | How to Get |
|--------|--------------|------------|
| `Market` | All operations | Query shared objects filtered by `Market` type |
| `Treasury<CoinType>` | Place bets | Query shared objects filtered by `Treasury` + coin type |
| `PredictionEvent<CoinType>` | Event operations | Emitted in `EventCreated` event |
| `Position<CoinType>` | Claims/cancellations | Returned when placing bet, owned by user |
| `AdminCap` | Admin operations | Owned by admin address |
| `MarketCreatorCap` | Create events | Returned when creating market |

---

## Event Types

### 1. Manual Events (Sports, Custom Markets)

**Outcome labels:** User-defined (2-10 outcomes)  
**Resolution:** Oracle manually sets winning outcome  
**Use cases:** Sports betting, political predictions, custom markets

### 2. Crypto Events (Price Predictions)

**Outcome labels:** Always `["Above", "Below"]` (binary)  
**Resolution:** Automated via Stork oracle price feed  
**Use cases:** BTC/ETH/SOL/SUI price predictions

---

## Contract Addresses

### Stork Oracle (Required for Crypto Events)

```typescript
const STORK_STATE = '0x...'; // StorkState shared object
const STORK_FEED_IDS = {
  BTCUSD: '0x7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de',
  ETHUSD: '0x59102b37de83bdda9f38ac8254e596f0d9ac61d2035c07936675e87342817160',
  SOLUSD: '0x1dcd89dfded9e8a9b0fa1745a8ebbacbb7c81e33d5abc81616633206d932e837',
  SUIUSD: '0xa24cc95a4f3d70a0a2f7ac652b67a4a73791631ff06b4ee7f729097311169b81',
};
```

---

## View Functions

### Read Event Data

```typescript
// Get event status (0=CREATED, 1=OPEN, 2=LOCKED, 3=RESOLVED, 4=CANCELLED)
const status = await client.devInspectTransactionBlock({
  transactionBlock: tx,
  sender: '0x...',
});

// Get current odds (pool balances)
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_odds`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});

// Get total pool amount
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_total_pool`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});

// Calculate potential payout for a stake
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::calculate_potential_payout`,
  typeArguments: [coinType],
  arguments: [
    tx.object(eventId),
    tx.pure(outcomeIndex, 'u8'),
    tx.pure(stakeAmount, 'u64'),
  ],
});

// Check if betting is open (considers time window)
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::is_betting_open`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId), tx.object('0x6')], // Clock
});

// Get event type (0=CRYPTO, 1=MANUAL)
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_event_type`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});

// For crypto events: get oracle data
tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_oracle_feed_id`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});

tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_target_price`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});

tx.moveCall({
  target: `${PACKAGE_ID}::blink_event::get_oracle_price_at_resolution`,
  typeArguments: [coinType],
  arguments: [tx.object(eventId)],
});
```

### Read Position Data

```typescript
// Get stake amount
tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::get_position_stake`,
  typeArguments: [coinType],
  arguments: [tx.object(positionId)],
});

// Get outcome index
tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::get_position_outcome`,
  typeArguments: [coinType],
  arguments: [tx.object(positionId)],
});

// Check if claimed
tx.moveCall({
  target: `${PACKAGE_ID}::blink_position::is_position_claimed`,
  typeArguments: [coinType],
  arguments: [tx.object(positionId)],
});
```

### Read Market Configuration

```typescript
// Get market setup
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::get_market_min_stake`,
  arguments: [tx.object(marketId)],
});

tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::get_market_max_stake`,
  arguments: [tx.object(marketId)],
});

tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::get_market_fee_bps`,
  arguments: [tx.object(marketId)],
});

tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::is_market_active`,
  arguments: [tx.object(marketId)],
});

// Check oracle authorization
tx.moveCall({
  target: `${PACKAGE_ID}::blink_config::is_oracle`,
  arguments: [tx.object(marketId), tx.pure(oracleAddress, 'address')],
});
```

---

## Transaction Building

### 1. Place Bet

```typescript
async function placeBet(
  userAddress: string,
  eventId: string,
  marketId: string,
  treasuryId: string,
  outcomeIndex: number,
  stakeAmount: number,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  // Split coin for stake
  const [stakeCoin] = tx.splitCoins(tx.gas, [tx.pure(stakeAmount, 'u64')]);
  
  // Place bet and receive Position NFT
  const position = tx.moveCall({
    target: `${PACKAGE_ID}::blink_position::place_bet`,
    typeArguments: [coinType],
    arguments: [
      tx.object(eventId),
      tx.object(marketId),
      tx.object(treasuryId),
      tx.pure(outcomeIndex, 'u8'),
      stakeCoin,
      tx.object('0x6'), // Clock
    ],
  });
  
  // Transfer Position to user
  tx.transferObjects([position], tx.pure(userAddress, 'address'));
  
  return tx;
}

// Usage
const tx = await placeBet(
  '0xUSER_ADDRESS',
  '0xEVENT_ID',
  '0xMARKET_ID',
  '0xTREASURY_ID',
  0, // Outcome index
  100_000_000, // 0.1 SUI
  '0x2::sui::SUI'
);

const result = await client.signAndExecuteTransactionBlock({
  transactionBlock: tx,
  signer: keypair,
  options: { showEffects: true, showEvents: true },
});
```

### 2. Cancel Bet (Before Event Locked)

```typescript
async function cancelBet(
  userAddress: string,
  eventId: string,
  positionId: string,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  // Cancel bet and receive refund (minus 1% fee)
  const refund = tx.moveCall({
    target: `${PACKAGE_ID}::blink_position::cancel_bet`,
    typeArguments: [coinType],
    arguments: [
      tx.object(eventId),
      tx.object(positionId), // Position is consumed
    ],
  });
  
  // Transfer refund to user
  tx.transferObjects([refund], tx.pure(userAddress, 'address'));
  
  return tx;
}
```

### 3. Claim Winnings

```typescript
async function claimWinnings(
  userAddress: string,
  eventId: string,
  positionId: string,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  // Claim winnings
  const payout = tx.moveCall({
    target: `${PACKAGE_ID}::blink_position::claim_winnings`,
    typeArguments: [coinType],
    arguments: [
      tx.object(eventId),
      tx.object(positionId), // Position is marked claimed (not consumed)
    ],
  });
  
  // Transfer payout to user
  tx.transferObjects([payout], tx.pure(userAddress, 'address'));
  
  return tx;
}
```

### 4. Claim Refund (Event Cancelled)

```typescript
async function claimRefund(
  userAddress: string,
  eventId: string,
  positionId: string,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  // Claim full refund
  const refund = tx.moveCall({
    target: `${PACKAGE_ID}::blink_position::claim_refund`,
    typeArguments: [coinType],
    arguments: [
      tx.object(eventId),
      tx.object(positionId), // Position is consumed
    ],
  });
  
  // Transfer refund to user
  tx.transferObjects([refund], tx.pure(userAddress, 'address'));
  
  return tx;
}
```

### 5. Create Manual Event (Market Creator)

```typescript
async function createManualEvent(
  creatorCapId: string,
  marketId: string,
  description: string,
  outcomeLabels: string[],
  durationMs: number,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  tx.moveCall({
    target: `${PACKAGE_ID}::blink_event::create_manual_event`,
    typeArguments: [coinType],
    arguments: [
      tx.object(creatorCapId),
      tx.object(marketId),
      tx.pure(description, 'string'),
      tx.pure(outcomeLabels, 'vector<string>'),
      tx.pure(durationMs, 'u64'),
    ],
  });
  
  return tx;
}

// Usage
const tx = await createManualEvent(
  '0xCREATOR_CAP_ID',
  '0xMARKET_ID',
  'Lakers vs Warriors - Who wins?',
  ['Lakers', 'Warriors'],
  3600000, // 1 hour
  '0x2::sui::SUI'
);
```

### 6. Create Crypto Event (Market Creator)

```typescript
async function createCryptoEvent(
  creatorCapId: string,
  marketId: string,
  description: string,
  feedId: string, // 32-byte hex string
  targetPrice: string, // u128 with 18 decimals
  durationMs: number,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  // Convert feed ID to bytes
  const feedIdBytes = Array.from(Buffer.from(feedId.slice(2), 'hex'));
  
  tx.moveCall({
    target: `${PACKAGE_ID}::blink_event::create_crypto_event`,
    typeArguments: [coinType],
    arguments: [
      tx.object(creatorCapId),
      tx.object(marketId),
      tx.pure(description, 'string'),
      tx.pure(feedIdBytes, 'vector<u8>'),
      tx.pure(targetPrice, 'u128'),
      tx.pure(durationMs, 'u64'),
    ],
  });
  
  return tx;
}

// Usage: Create BTC > $62,000 prediction
const targetPrice = '62000000000000000000000'; // $62,000 * 10^18
const tx = await createCryptoEvent(
  '0xCREATOR_CAP_ID',
  '0xMARKET_ID',
  'BTC above $62,000 in 1 hour?',
  STORK_FEED_IDS.BTCUSD,
  targetPrice,
  3600000,
  '0x2::sui::SUI'
);
```

### 7. Open Event (Market Creator)

```typescript
async function openEvent(
  creatorCapId: string,
  eventId: string,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  tx.moveCall({
    target: `${PACKAGE_ID}::blink_event::open_event`,
    typeArguments: [coinType],
    arguments: [
      tx.object(creatorCapId),
      tx.object(eventId),
      tx.object('0x6'), // Clock
    ],
  });
  
  return tx;
}
```

### 8. Resolve Manual Event (Oracle Only)

```typescript
async function resolveManualEvent(
  eventId: string,
  marketId: string,
  winningOutcome: number,
  coinType: string
) {
  const tx = new TransactionBlock();
  
  tx.moveCall({
    target: `${PACKAGE_ID}::blink_event::resolve_manual_event`,
    typeArguments: [coinType],
    arguments: [
      tx.object(eventId),
      tx.object(marketId),
      tx.pure(winningOutcome, 'u8'),
      tx.object('0x6'), // Clock
    ],
  });
  
  return tx;
}
```

### 9. Resolve Crypto Event (Automated by Backend Keeper)

**⚠️ Important: Crypto events are automatically resolved by the backend keeper service.**

**Frontend should NOT directly resolve crypto events** because:
- ❌ Requires Stork API authentication (API keys)
- ❌ Needs oracle private key for signing
- ❌ Must execute atomic PTB (update + resolve)
- ❌ Security risk exposing credentials to frontend

**Backend keeper handles:**
- ✅ Monitors pending crypto events
- ✅ Fetches signed price data from Stork API
- ✅ Builds and executes atomic PTB
- ✅ Signed with authorized oracle keypair

**Frontend role for crypto events:**
- Query event status (via view functions)
- Display resolution results after keeper completes
- Listen to `EventResolved` events for real-time updates

**Example: Monitor event resolution**
```typescript
// Query event status
async function checkEventStatus(eventId: string) {
  const event = await client.getObject({
    id: eventId,
    options: { showContent: true },
  });
  
  const content = event.data.content as any;
  const fields = content.fields;
  
  return {
    status: fields.status, // 3 = RESOLVED
    winningOutcome: fields.winning_outcome,
    oraclePriceAtResolution: fields.oracle_price_at_resolution,
    resolvedAt: fields.resolved_at,
  };
}

// Listen for resolution events
client.subscribeEvent({
  filter: {
    MoveEventType: `${PACKAGE_ID}::blink_event::EventResolved`,
  },
  onMessage: (event) => {
    const { event_id, winning_outcome, oracle_price } = event.parsedJson;
    console.log('Event resolved:', {
      eventId: event_id,
      winningOutcome: winning_outcome,
      oraclePrice: oracle_price,
    });
  },
});
```

**For manual event resolution (sports, politics), see function above.**

**Backend keeper setup:** See [backend/keeper/README.md](../backend/keeper/README.md)

---

## Event Listening

### Subscribe to On-Chain Events

```typescript
// Event types emitted by the contract
interface EventCreated {
  event_id: string;
  market_id: string;
  description: string;
  num_outcomes: number;
  event_type: number; // 0=CRYPTO, 1=MANUAL
  oracle_feed_id: number[];
  target_price: string;
}

interface BetPlaced {
  event_id: string;
  position_id: string;
  outcome_index: number;
  stake_amount: string;
  bettor: string;
}

interface EventResolved {
  event_id: string;
  winning_outcome: number;
  total_pool: string;
  event_type: number;
  oracle_price: string;
}

interface WinningsClaimed {
  event_id: string;
  position_id: string;
  payout_amount: string;
  claimer: string;
}

// Subscribe to events
const unsubscribe = await client.subscribeEvent({
  filter: { Package: PACKAGE_ID },
  onMessage: (event) => {
    console.log('Event:', event);
    
    if (event.type.includes('EventCreated')) {
      handleEventCreated(event.parsedJson as EventCreated);
    } else if (event.type.includes('BetPlaced')) {
      handleBetPlaced(event.parsedJson as BetPlaced);
    } else if (event.type.includes('EventResolved')) {
      handleEventResolved(event.parsedJson as EventResolved);
    }
  },
});
```

---

## Coin Type Support

### Working with Different Coins

```typescript
// SUI
const suiType = '0x2::sui::SUI';
const suiTreasury = 'TREASURY_SUI_OBJECT_ID';

// USDC (example)
const usdcType = 'USDC_PACKAGE::usdc::USDC';
const usdcTreasury = 'TREASURY_USDC_OBJECT_ID';

// Create event with USDC
const tx = await createManualEvent(
  creatorCapId,
  marketId,
  'Test event with USDC',
  ['Yes', 'No'],
  3600000,
  usdcType // Use USDC instead of SUI
);
```

### Admin: Create Treasury for New Coin Type

```typescript
async function createTreasury(adminCapId: string, coinType: string) {
  const tx = new TransactionBlock();
  
  tx.moveCall({
    target: `${PACKAGE_ID}::blink_config::create_treasury`,
    typeArguments: [coinType],
    arguments: [tx.object(adminCapId)],
  });
  
  return tx;
}
```

---

## Error Handling

### Common Error Codes

| Code | Location | Error | Reason |
|------|----------|-------|--------|
| 0 | blink_config | ENotAuthorized | Caller is not authorized |
| 1 | blink_event | ENotOracle | Caller is not an authorized oracle |
| 100 | blink_config | EMarketNotActive | Market is deactivated |
| 101 | blink_event | EEventNotOpen | Event is not in OPEN state |
| 103 | blink_event | EEventNotResolved | Event is not resolved yet |
| 104 | blink_event | EEventNotCancelled | Event is not cancelled |
| 105 | blink_position | EPositionAlreadyClaimed | Position winnings already claimed |
| 106 | blink_position | ENotWinningOutcome | Position is for losing outcome |
| 107 | blink_position | ENotAuthorized | Caller doesn't own the position |
| 200 | blink_event | EInvalidOutcome | Outcome index out of bounds |
| 202 | blink_position | EStakeTooLow | Stake below market minimum |
| 203 | blink_position | EStakeTooHigh | Stake above market maximum |
| 205 | blink_event | ETooFewOutcomes | Less than 2 outcomes |
| 206 | blink_event | ETooManyOutcomes | More than 10 outcomes |
| 207 | blink_event/position | EEventMismatch | Event ID doesn't match |
| 208 | blink_event | ENotCryptoEvent | Not a crypto event |
| 209 | blink_event | ENotManualEvent | Not a manual event |
| 210 | blink_event | EInvalidFeedId | Feed ID is not 32 bytes |
| 211 | blink_event | ETargetPriceZero | Target price is zero |
| 212 | blink_event | ENegativeOraclePrice | Oracle returned negative price |
| 300 | blink_event | EBettingNotStarted | Before betting start time |
| 301 | blink_event | EBettingClosed | After betting end time |
| 302 | blink_position | EEventAlreadyLocked | Event is locked/resolved |

### Error Handling Example

```typescript
try {
  const result = await client.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    signer: keypair,
  });
  
  if (result.effects?.status?.status !== 'success') {
    const error = result.effects?.status?.error;
    console.error('Transaction failed:', error);
    
    // Parse error code
    if (error?.includes('202')) {
      alert('Stake too low. Minimum: ' + minStake);
    } else if (error?.includes('301')) {
      alert('Betting window has closed');
    }
  }
} catch (error) {
  console.error('Error:', error);
}
```

---

## Example Workflows

### Complete Betting Flow

```typescript
async function completeBettingFlow() {
  // 1. Fetch event data
  const event = await client.getObject({
    id: eventId,
    options: { showContent: true },
  });
  
  // 2. Check if betting is open
  const isOpen = await checkBettingOpen(eventId);
  if (!isOpen) {
    throw new Error('Betting is closed');
  }
  
  // 3. Get current odds
  const odds = await getOdds(eventId);
  console.log('Current odds:', odds);
  
  // 4. Calculate potential payout
  const payout = await calculatePotentialPayout(eventId, outcomeIndex, stakeAmount);
  console.log('Potential payout:', payout);
  
  // 5. Place bet
  const tx = await placeBet(
    userAddress,
    eventId,
    marketId,
    treasuryId,
    outcomeIndex,
    stakeAmount,
    coinType
  );
  
  const result = await client.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    signer: keypair,
    options: { showObjectChanges: true },
  });
  
  // 6. Extract Position ID from result
  const positionId = result.objectChanges?.find(
    (obj) => obj.type === 'created' && obj.objectType.includes('Position')
  )?.objectId;
  
  console.log('Position created:', positionId);
  return positionId;
}
```

### Claim Winnings Flow

```typescript
async function claimWinningsFlow(positionId: string) {
  // 1. Get position data
  const position = await client.getObject({
    id: positionId,
    options: { showContent: true },
  });
  
  const positionData = position.data?.content as any;
  const eventId = positionData.fields.event_id;
  
  // 2. Check event is resolved
  const event = await client.getObject({
    id: eventId,
    options: { showContent: true },
  });
  
  const eventData = event.data?.content as any;
  if (eventData.fields.status !== 3) { // 3 = RESOLVED
    throw new Error('Event not resolved yet');
  }
  
  // 3. Check if position is winning
  const winningOutcome = eventData.fields.winning_outcome;
  const positionOutcome = positionData.fields.outcome_index;
  
  if (winningOutcome !== positionOutcome) {
    throw new Error('Position is not a winning position');
  }
  
  // 4. Check if already claimed
  if (positionData.fields.is_claimed) {
    throw new Error('Position already claimed');
  }
  
  // 5. Claim winnings
  const tx = await claimWinnings(userAddress, eventId, positionId, coinType);
  
  const result = await client.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    signer: keypair,
    options: { showBalanceChanges: true },
  });
  
  console.log('Winnings claimed:', result.balanceChanges);
}
```

### Crypto Event Resolution (Handled by Backend Keeper)

**⚠️ Crypto events are automatically resolved by the backend keeper service.**

**Frontend should monitor resolution status:**

```typescript
async function monitorCryptoEventResolution(eventId: string) {
  // Poll event status
  const checkStatus = setInterval(async () => {
    const event = await client.getObject({
      id: eventId,
      options: { showContent: true },
    });
    
    const fields = (event.data.content as any).fields;
    
    if (fields.status === 3) { // RESOLVED
      clearInterval(checkStatus);
      
      console.log('Event resolved:', {
        eventId,
        winningOutcome: fields.winning_outcome,
        oraclePrice: fields.oracle_price_at_resolution,
        resolvedAt: fields.resolved_at,
      });
      
      // Notify UI to refresh
      notifyEventResolved(eventId, fields.winning_outcome);
    }
  }, 2000); // Check every 2 seconds
}

// Or use WebSocket subscription for real-time updates
async function subscribeToEventResolution(eventId: string) {
  const unsubscribe = await client.subscribeEvent({
    filter: {
      MoveEventType: `${PACKAGE_ID}::blink_event::EventResolved`,
    },
    onMessage: (event) => {
      const data = event.parsedJson as any;
      
      if (data.event_id === eventId) {
        console.log('Event resolved:', {
          eventId: data.event_id,
          winningOutcome: data.winning_outcome,
          oraclePrice: data.oracle_price,
          totalPool: data.total_pool,
        });
        
        // Update UI
        notifyEventResolved(eventId, data.winning_outcome);
        unsubscribe();
      }
    },
  });
  
  return unsubscribe;
}
```

**Backend keeper service:**
- Monitors pending crypto events
- Fetches signed price data from Stork API (with authentication)
- Executes atomic PTB (update price + resolve)
- See [backend/keeper/README.md](../backend/keeper/README.md) for setup

---

## Price Formatting for Crypto Events

### Converting Human-Readable Prices

Stork uses 18-decimal precision for all price feeds.

```typescript
function formatPriceForContract(humanPrice: number): string {
  // Example: $62,000 → '62000000000000000000000'
  const scaled = BigInt(Math.floor(humanPrice * 1e18));
  return scaled.toString();
}

function formatPriceFromContract(contractPrice: string): number {
  // Example: '62507457175499998000000' → 62507.457...
  const scaled = BigInt(contractPrice);
  return Number(scaled) / 1e18;
}

// Usage
const targetPrice = formatPriceForContract(62000); // $62,000
const tx = await createCryptoEvent(
  creatorCapId,
  marketId,
  'BTC above $62,000?',
  STORK_FEED_IDS.BTCUSD,
  targetPrice,
  3600000,
  coinType
);
```

---

## Additional Resources

- **Sui SDK Documentation:** https://sdk.mystenlabs.com/typescript
- **Stork Oracle Docs:** https://docs.stork.network/
- **Contract Source:** https://github.com/Blink-Markets/Blink-Markets-Contract

---

## Support

For integration support:
- GitHub Issues: https://github.com/Blink-Markets/Blink-Markets-Contract/issues
- Discord: [Your Discord]
- Email: [Your Email]
