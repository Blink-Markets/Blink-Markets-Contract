export interface PredictionEvent {
  id: string;
  marketId: string;
  status: number;
  eventType: number;
  description: string;
  outcomeLabels: string[];
  bettingStartTime: number;
  bettingEndTime: number;
  oracleFeedId: string;
  targetPrice: string;
  totalPool: number;
}

export interface PythPriceUpdateData {
  id: string;
  fetchedAt: number;
  priceFeedUpdateData: Buffer[];
}

export interface ResolutionTask {
  eventId: string;
  feedId: string;
  targetPrice: string;
  priority: number;
  createdAt: number;
}

export interface ResolutionResult {
  eventId: string;
  success: boolean;
  txDigest?: string;
  winningOutcome?: number;
  oraclePrice?: string;
  error?: string;
  gasUsed?: number;
  timestamp: number;
}

export enum EventStatus {
  CREATED = 0,
  OPEN = 1,
  LOCKED = 2,
  RESOLVED = 3,
  CANCELLED = 4,
}

export enum EventType {
  CRYPTO = 0,
  MANUAL = 1,
}

export const FEED_ID_TO_SYMBOL: Record<string, string> = {
  // SUI/USD (Pyth Sui testnet)
  '0x50c67b8caa9a5ef62431dab6e49f05e38f39d6acb39116c52def86f2c14825a9': 'SUI/USD',
};
