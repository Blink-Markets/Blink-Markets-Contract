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

export interface StorkPriceData {
  id: string;
  timestamp: number;
  quantizedValue: string;
  encodedSignedData: Uint8Array;
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
  '0x7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de': 'BTC/USD',
  '0x59102b37de83bdda9f38ac8254e596f0d9ac61d2035c07936675e87342817160': 'ETH/USD',
  '0x1dcd89dfded9e8a9b0fa1745a8ebbacbb7c81e33d5abc81616633206d932e837': 'SOL/USD',
  '0xa24cc95a4f3d70a0a2f7ac652b67a4a73791631ff06b4ee7f729097311169b81': 'SUI/USD',
};
