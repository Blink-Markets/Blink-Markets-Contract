import dotenv from 'dotenv';
import { SuiClient } from '@mysten/sui.js/client';

dotenv.config();

export interface Config {
  // Network
  suiNetwork: string;
  suiRpcUrl: string;
  
  // Contract Addresses
  packageId: string;
  storkPackageId: string;
  storkStateId: string;
  marketId: string;
  
  // Oracle
  oraclePrivateKey: string;
  oracleAddress: string;
  
  // Stork API
  storkApiUrl: string;
  storkAuthKey: string;
  storkFeedIds: {
    BTC_USD: string;
    ETH_USD: string;
    SOL_USD: string;
    SUI_USD: string;
  };
  
  // Redis
  redis: {
    host: string;
    port: number;
    password?: string;
    db: number;
  };
  
  // Service
  pollingIntervalMs: number;
  batchWindowMs: number;
  maxBatchSize: number;
  resolutionLockTtlSec: number;
  
  // Gas
  gasBudget: number;
  maxGasPrice: number;
  
  // Monitoring
  prometheusPort: number;
  logLevel: string;
  
  // Retry
  maxRetries: number;
  retryDelayMs: number;
  storkTimeoutMs: number;
}

function validateEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function getEnv(key: string, defaultValue: string): string {
  return process.env[key] || defaultValue;
}

export const config: Config = {
  // Network
  suiNetwork: getEnv('SUI_NETWORK', 'testnet'),
  suiRpcUrl: validateEnv('SUI_RPC_URL'),
  
  // Contract Addresses
  packageId: validateEnv('PACKAGE_ID'),
  storkPackageId: validateEnv('STORK_PACKAGE_ID'),
  storkStateId: validateEnv('STORK_STATE_ID'),
  marketId: validateEnv('MARKET_ID'),
  
  // Oracle
  oraclePrivateKey: validateEnv('ORACLE_PRIVATE_KEY'),
  oracleAddress: validateEnv('ORACLE_ADDRESS'),
  
  // Stork API
  storkApiUrl: getEnv('STORK_API_URL', 'https://rest.jp.stork-oracle.network'),
  storkAuthKey: validateEnv('STORK_AUTH_KEY'),
  storkFeedIds: {
    BTC_USD: validateEnv('STORK_FEED_BTC_USD'),
    ETH_USD: validateEnv('STORK_FEED_ETH_USD'),
    SOL_USD: validateEnv('STORK_FEED_SOL_USD'),
    SUI_USD: validateEnv('STORK_FEED_SUI_USD'),
  },
  
  // Redis
  redis: {
    host: getEnv('REDIS_HOST', 'localhost'),
    port: parseInt(getEnv('REDIS_PORT', '6379'), 10),
    password: process.env.REDIS_PASSWORD,
    db: parseInt(getEnv('REDIS_DB', '0'), 10),
  },
  
  // Service
  pollingIntervalMs: parseInt(getEnv('POLLING_INTERVAL_MS', '3000'), 10),
  batchWindowMs: parseInt(getEnv('BATCH_WINDOW_MS', '5000'), 10),
  maxBatchSize: parseInt(getEnv('MAX_BATCH_SIZE', '10'), 10),
  resolutionLockTtlSec: parseInt(getEnv('RESOLUTION_LOCK_TTL_SEC', '30'), 10),
  
  // Gas
  gasBudget: parseInt(getEnv('GAS_BUDGET', '100000000'), 10),
  maxGasPrice: parseInt(getEnv('MAX_GAS_PRICE', '1000'), 10),
  
  // Monitoring
  prometheusPort: parseInt(getEnv('PROMETHEUS_PORT', '9090'), 10),
  logLevel: getEnv('LOG_LEVEL', 'info'),
  
  // Retry
  maxRetries: parseInt(getEnv('MAX_RETRIES', '3'), 10),
  retryDelayMs: parseInt(getEnv('RETRY_DELAY_MS', '1000'), 10),
  storkTimeoutMs: parseInt(getEnv('STORK_TIMEOUT_MS', '10000'), 10),
};

export function createSuiClient(): SuiClient {
  return new SuiClient({ url: config.suiRpcUrl });
}
