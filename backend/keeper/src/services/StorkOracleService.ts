import axios, { AxiosInstance } from 'axios';
import { config } from '../config';
import logger from '../utils/logger';
import { storkApiCallsTotal, storkApiDurationHistogram } from '../utils/metrics';
import { StorkPriceData } from '../types';

export class StorkOracleService {
  private client: AxiosInstance;
  private authHeader: string;

  constructor() {
    // Create Basic Auth header
    this.authHeader = `Basic ${Buffer.from(config.storkAuthKey).toString('base64')}`;
    
    this.client = axios.create({
      baseURL: config.storkApiUrl,
      timeout: config.storkTimeoutMs,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': this.authHeader,
      },
    });

    logger.info('StorkOracleService initialized', {
      apiUrl: config.storkApiUrl,
    });
  }

  /**
   * Fetch latest price data for a specific feed ID
   */
  async getLatestPrice(feedId: string): Promise<StorkPriceData | null> {
    const end = storkApiDurationHistogram.startTimer();
    
    try {
      logger.debug('Fetching price from Stork', { feedId });
      
      const response = await this.client.post('/v1/evm/update_data', {
        temporalNumericValues: [
          {
            id: feedId,
            timestamp: Math.floor(Date.now() / 1000),
          },
        ],
      });

      storkApiCallsTotal.inc({ status: 'success' });
      end();

      const data = response.data;
      
      if (!data || !data.encoded_data) {
        logger.warn('Invalid response from Stork API', { feedId, data });
        return null;
      }

      // Parse the encoded data
      const encodedData = Buffer.from(data.encoded_data, 'base64');
      
      logger.info('Successfully fetched price from Stork', {
        feedId,
        timestamp: data.timestamp,
        dataSize: encodedData.length,
      });

      return {
        id: feedId,
        timestamp: data.timestamp || Date.now(),
        quantizedValue: data.quantized_value || '0',
        encodedSignedData: new Uint8Array(encodedData),
      };
    } catch (error: any) {
      end();
      storkApiCallsTotal.inc({ status: 'error' });
      
      logger.error('Failed to fetch price from Stork', {
        feedId,
        error: error.message,
        status: error.response?.status,
        data: error.response?.data,
      });

      return null;
    }
  }

  /**
   * Fetch multiple prices in a single batch request
   */
  async getBatchPrices(feedIds: string[]): Promise<Map<string, StorkPriceData>> {
    const end = storkApiDurationHistogram.startTimer();
    const results = new Map<string, StorkPriceData>();

    try {
      logger.debug('Fetching batch prices from Stork', {
        feedIds,
        count: feedIds.length,
      });

      const temporalNumericValues = feedIds.map(id => ({
        id,
        timestamp: Math.floor(Date.now() / 1000),
      }));

      const response = await this.client.post('/v1/evm/update_data', {
        temporalNumericValues,
      });

      storkApiCallsTotal.inc({ status: 'success' });
      end();

      const data = response.data;

      if (!data || !Array.isArray(data.prices)) {
        logger.warn('Invalid batch response from Stork API', { data });
        return results;
      }

      // Process each price in the batch
      for (const priceData of data.prices) {
        const encodedData = Buffer.from(priceData.encoded_data, 'base64');
        
        results.set(priceData.id, {
          id: priceData.id,
          timestamp: priceData.timestamp || Date.now(),
          quantizedValue: priceData.quantized_value || '0',
          encodedSignedData: new Uint8Array(encodedData),
        });
      }

      logger.info('Successfully fetched batch prices from Stork', {
        requested: feedIds.length,
        received: results.size,
      });

      return results;
    } catch (error: any) {
      end();
      storkApiCallsTotal.inc({ status: 'error' });
      
      logger.error('Failed to fetch batch prices from Stork', {
        feedIds,
        error: error.message,
        status: error.response?.status,
      });

      return results;
    }
  }

  /**
   * Retry wrapper for API calls with exponential backoff
   */
  async fetchWithRetry(
    feedId: string,
    maxRetries: number = config.maxRetries
  ): Promise<StorkPriceData | null> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        const result = await this.getLatestPrice(feedId);
        if (result) {
          return result;
        }
      } catch (error: any) {
        lastError = error;
        
        if (attempt < maxRetries - 1) {
          const delay = config.retryDelayMs * Math.pow(2, attempt);
          logger.warn('Retrying Stork API call', {
            feedId,
            attempt: attempt + 1,
            maxRetries,
            delayMs: delay,
          });
          await this.sleep(delay);
        }
      }
    }

    logger.error('All retry attempts failed for Stork API call', {
      feedId,
      maxRetries,
      lastError: lastError?.message,
    });

    return null;
  }

  /**
   * Validate feed ID format (must be 32 bytes hex)
   */
  isValidFeedId(feedId: string): boolean {
    // Remove 0x prefix if present
    const cleanFeedId = feedId.startsWith('0x') ? feedId.slice(2) : feedId;
    
    // Must be exactly 64 hex characters (32 bytes)
    return /^[0-9a-fA-F]{64}$/.test(cleanFeedId);
  }

  /**
   * Convert feed ID to array of bytes for Move contract
   */
  feedIdToBytes(feedId: string): number[] {
    const cleanFeedId = feedId.startsWith('0x') ? feedId.slice(2) : feedId;
    const bytes: number[] = [];
    
    for (let i = 0; i < cleanFeedId.length; i += 2) {
      bytes.push(parseInt(cleanFeedId.substr(i, 2), 16));
    }
    
    return bytes;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
