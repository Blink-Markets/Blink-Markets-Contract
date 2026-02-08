# Blinkmarket Keeper Service

Backend keeper service for automating Stork Oracle price updates and crypto event resolution in the Blinkmarket prediction market protocol.

## Overview

The Keeper service monitors the Sui blockchain for crypto prediction events that require resolution, fetches signed price data from Stork Oracle, and executes atomic transactions to update prices and resolve events automatically.

### Key Features

- 🔄 **Automatic Resolution**: Monitors and resolves crypto events when betting windows close
- 🔐 **Secure Authentication**: Stork Oracle API authentication with private key management
- 🚀 **Batch Processing**: Efficient batch resolution with configurable windows
- 🔒 **Distributed Locks**: Redis-based locking prevents duplicate resolutions
- 📊 **Monitoring**: Prometheus metrics and Grafana dashboards
- 🛡️ **Error Handling**: Comprehensive retry logic and failover mechanisms
- ⚡ **PTB Atomicity**: Updates Stork price and resolves in single transaction block

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Blinkmarket Keeper                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────┐      ┌──────────────────┐           │
│  │ EventMonitor      │─────→│ StorkOracle      │           │
│  │ Service           │      │ Service          │           │
│  │                   │      │                  │           │
│  │ • Poll events     │      │ • Fetch prices   │           │
│  │ • Queue batches   │      │ • Auth API       │           │
│  │ • Trigger resolve │      │ • Parse data     │           │
│  └─────────┬─────────┘      └──────────────────┘           │
│            │                                                 │
│            ▼                                                 │
│  ┌───────────────────┐      ┌──────────────────┐           │
│  │ SuiInteraction    │─────→│ResolutionLock    │           │
│  │ Service           │      │ Service          │           │
│  │                   │      │                  │           │
│  │ • Build PTB       │      │ • Acquire lock   │           │
│  │ • Execute tx      │      │ • Release lock   │           │
│  │ • Query events    │      │ • Check status   │           │
│  └───────────────────┘      └──────────────────┘           │
│                                                               │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    Sui Network       Stork Oracle API       Redis Cache
```

## Installation

### Prerequisites

- Node.js >= 18.0.0
- npm >= 9.0.0
- Redis >= 7.0
- Docker & Docker Compose (optional)

### Local Setup

```bash
# Clone repository
cd backend/keeper

# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

### Environment Configuration

Configure the following in `.env`:

```bash
# Network
SUI_NETWORK=testnet
SUI_RPC_URL=https://fullnode.testnet.sui.io:443

# Contract Addresses (from your deployment)
PACKAGE_ID=0x...
STORK_PACKAGE_ID=0x...
STORK_STATE_ID=0x...
MARKET_ID=0x...

# Oracle Credentials
ORACLE_PRIVATE_KEY=suiprivkey1...
ORACLE_ADDRESS=0x...

# Stork API
STORK_API_URL=https://rest.jp.stork-oracle.network
STORK_AUTH_KEY=your_api_key_here

# Feed IDs
STORK_FEED_BTC_USD=0x7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de
STORK_FEED_ETH_USD=0x59102b37de83bdda9f38ac8254e596f0d9ac61d2035c07936675e87342817160
STORK_FEED_SOL_USD=0x1dcd89dfded9e8a9b0fa1745a8ebbacbb7c81e33d5abc81616633206d932e837
STORK_FEED_SUI_USD=0xa24cc95a4f3d70a0a2f7ac652b67a4a73791631ff06b4ee7f729097311169b81

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Service Configuration
POLLING_INTERVAL_MS=3000           # Check for events every 3 seconds
BATCH_WINDOW_MS=5000               # Process batch every 5 seconds
MAX_BATCH_SIZE=10                  # Max events per batch
RESOLUTION_LOCK_TTL_SEC=30         # Lock expiry (prevents stuck locks)
```

## Usage

### Development

```bash
# Run in development mode with auto-reload
npm run dev
```

### Production

```bash
# Build TypeScript
npm run build

# Start production server
npm start
```

### Docker Deployment

```bash
# Start all services (keeper, redis, prometheus, grafana)
docker-compose up -d

# View logs
docker-compose logs -f keeper

# Stop services
docker-compose down
```

### Health Checks

```bash
# Health endpoint
curl http://localhost:9090/health

# Service status
curl http://localhost:9090/status

# Prometheus metrics
curl http://localhost:9090/metrics
```

## Service Flow

### Resolution Workflow

1. **Event Discovery**
   - Poll Sui blockchain every 3 seconds
   - Query events with `STATUS_OPEN` and `EVENT_TYPE_CRYPTO`
   - Filter events past `betting_end_time`

2. **Batch Queue**
   - Add pending events to batch queue
   - Group by feed ID for efficient price fetching
   - Sort by priority (time since betting ended)

3. **Lock Acquisition**
   - Try to acquire Redis lock for each event
   - Prevents duplicate resolution by multiple keeper instances
   - Lock TTL: 30 seconds (auto-expires if service crashes)

4. **Price Fetching**
   - Batch request to Stork API for all required feeds
   - Parse signed price data (encoded Base64)
   - Retry with exponential backoff on failure

5. **Transaction Execution**
   - Build PTB with two operations:
     ```typescript
     1. stork::update_single_temporal_numeric_value_evm(signed_data)
     2. blink_event::resolve_crypto_event(event_id)
     ```
   - Sign with oracle keypair
   - Execute atomically on Sui

6. **Result Handling**
   - Parse `EventResolved` event from transaction
   - Extract winning outcome and oracle price
   - Record metrics (gas used, duration)
   - Release Redis lock

7. **Error Recovery**
   - Log errors with full context
   - Increment error metrics
   - Release lock to allow retry
   - Event remains in OPEN state for next polling cycle

## Monitoring

### Prometheus Metrics

The keeper exposes the following metrics at `/metrics`:

```
# Events resolved
blinkmarket_events_resolved_total{status="success|failure", event_type="crypto"}

# API calls to Stork
blinkmarket_stork_api_calls_total{status="success|error"}

# Resolution errors
blinkmarket_resolution_errors_total{error_type="polling|missing_price|execution|unknown"}

# Pending events gauge
blinkmarket_pending_events

# Active locks gauge
blinkmarket_active_locks

# Resolution duration histogram
blinkmarket_resolution_duration_seconds

# Stork API duration histogram
blinkmarket_stork_api_duration_seconds

# Gas used histogram
blinkmarket_gas_used
```

### Grafana Dashboard

Access Grafana at `http://localhost:3000` (default credentials: admin/admin)

**Dashboard panels:**
- Resolution success rate
- Average resolution time
- Pending events over time
- Stork API latency
- Gas consumption trends
- Error breakdown by type

## Troubleshooting

### Common Issues

**1. "Missing required environment variable"**
```bash
# Ensure all required env vars are set
cat .env | grep -E "PACKAGE_ID|ORACLE_PRIVATE_KEY|STORK_AUTH_KEY"
```

**2. "Failed to fetch price from Stork"**
- Check Stork API key is valid
- Verify network connectivity
- Check Stork API status page

**3. "Could not acquire lock for event"**
- Another keeper instance is resolving the event
- Check Redis connection
- Verify lock TTL hasn't expired prematurely

**4. "Resolution transaction failed"**
- Check oracle is authorized on market
- Verify gas budget is sufficient
- Ensure betting time has ended
- Check event is still in OPEN status

**5. Redis connection errors**
```bash
# Check Redis is running
redis-cli ping

# Test connection
redis-cli -h localhost -p 6379
```

### Logs

Logs are written to:
- `logs/combined.log` - All logs
- `logs/error.log` - Error logs only
- **Console** - Colorized output with timestamps

Log levels: `error`, `warn`, `info`, `debug`

Change log level in `.env`:
```bash
LOG_LEVEL=debug  # For detailed debugging
```

## Testing

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test file
npm test -- StorkOracleService.test.ts

# Watch mode
npm run test:watch
```

## Security

### Private Key Management

**DO NOT:**
- ❌ Commit `.env` file to Git
- ❌ Share private keys in logs or error messages
- ❌ Use production keys in development

**DO:**
- ✅ Use environment variables
- ✅ Store keys in secure vault (AWS KMS, Azure Key Vault)
- ✅ Rotate keys regularly
- ✅ Use separate keys for testnet and mainnet

### API Key Rotation

```bash
# Update Stork API key
export NEW_STORK_AUTH_KEY="new_key_here"

# Update .env
sed -i 's/STORK_AUTH_KEY=.*/STORK_AUTH_KEY='$NEW_STORK_AUTH_KEY'/' .env

# Restart keeper
docker-compose restart keeper
```

## Performance Tuning

### Batch Configuration

Adjust batch parameters based on load:

```bash
# High throughput (many events)
POLLING_INTERVAL_MS=1000     # Poll more frequently
BATCH_WINDOW_MS=3000         # Smaller batches, faster processing
MAX_BATCH_SIZE=20            # Process more events per batch

# Low throughput (few events)
POLLING_INTERVAL_MS=5000     # Poll less frequently
BATCH_WINDOW_MS=10000        # Larger batches, reduce API calls
MAX_BATCH_SIZE=5             # Smaller batches
```

### Gas Optimization

```bash
# Set appropriate gas budget
GAS_BUDGET=50000000          # Lower for simple resolutions
GAS_BUDGET=150000000         # Higher for complex events

# Monitor gas usage
curl http://localhost:9090/metrics | grep blinkmarket_gas_used
```

## Development

### Project Structure

```
backend/keeper/
├── src/
│   ├── config/
│   │   └── index.ts              # Configuration and env validation
│   ├── services/
│   │   ├── StorkOracleService.ts # Stork API integration
│   │   ├── SuiInteractionService.ts # Sui blockchain interaction
│   │   ├── EventMonitorService.ts # Event polling and resolution
│   │   └── ResolutionLockService.ts # Redis distributed locks
│   ├── types/
│   │   └── index.ts              # Type definitions
│   ├── utils/
│   │   ├── logger.ts             # Winston logger
│   │   └── metrics.ts            # Prometheus metrics
│   └── index.ts                  # Main entry point
├── tests/
│   ├── StorkOracleService.test.ts
│   └── ResolutionLockService.test.ts
├── docker-compose.yml
├── Dockerfile
├── package.json
└── tsconfig.json
```

### Adding New Features

**Example: Add support for new coin type**

1. Update event query in `SuiInteractionService.ts`:
```typescript
async queryPendingEvents(coinType?: string): Promise<PredictionEvent[]> {
  // Add coinType filter
}
```

2. Pass coin type to resolution:
```typescript
await this.suiService.executeResolution(
  eventId,
  coinType || '0x2::sui::SUI',
  priceData
);
```

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`npm test`)
4. Commit changes (`git commit -m 'Add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open Pull Request

## License

MIT License - see main project LICENSE file.

## Support

- **GitHub Issues**: https://github.com/Blink-Markets/Blink-Markets-Contract/issues
- **Documentation**: See main README.md and FRONTEND_API.md
- **Stork Oracle Docs**: https://docs.stork.network/

---

**Built with ❤️ for Blinkmarket**
