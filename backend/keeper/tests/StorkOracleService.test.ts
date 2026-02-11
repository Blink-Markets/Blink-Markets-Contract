/// <reference types="jest" />

import { StorkOracleService } from '../src/services/StorkOracleService';
import { config } from '../src/config';

describe('StorkOracleService', () => {
  let service: StorkOracleService;

  beforeEach(() => {
    service = new StorkOracleService();
  });

  describe('isValidFeedId', () => {
    it('should validate correct feed IDs', () => {
      const validFeedId = '0x7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de';
      expect(service.isValidFeedId(validFeedId)).toBe(true);
    });

    it('should validate feed IDs without 0x prefix', () => {
      const validFeedId = '7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de';
      expect(service.isValidFeedId(validFeedId)).toBe(true);
    });

    it('should reject invalid feed IDs', () => {
      expect(service.isValidFeedId('0x123')).toBe(false);
      expect(service.isValidFeedId('invalid')).toBe(false);
      expect(service.isValidFeedId('')).toBe(false);
    });
  });

  describe('feedIdToBytes', () => {
    it('should convert feed ID to byte array', () => {
      const feedId = '0x7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de';
      const bytes = service.feedIdToBytes(feedId);
      
      expect(bytes).toHaveLength(32);
      expect(bytes[0]).toBe(0x74);
      expect(bytes[1]).toBe(0x04);
      expect(bytes[31]).toBe(0xde);
    });

    it('should handle feed ID without 0x prefix', () => {
      const feedId = '7404e3d104ea7841c3d9e6fd20adfe99b4ad586bc08d8f3bd3afef894cf184de';
      const bytes = service.feedIdToBytes(feedId);
      
      expect(bytes).toHaveLength(32);
    });
  });

  // Note: Actual API tests require valid credentials and should be integration tests
  describe('getLatestPrice', () => {
    it('should return null on invalid feed ID', async () => {
      const result = await service.getLatestPrice('invalid_feed_id');
      expect(result).toBeNull();
    });
  });
});
