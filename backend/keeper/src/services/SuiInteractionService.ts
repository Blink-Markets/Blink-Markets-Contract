import { TransactionBlock } from '@mysten/sui.js/transactions';
import { SuiClient } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { config, createSuiClient } from '../config';
import logger from '../utils/logger';
import { gasUsedHistogram, resolutionDurationHistogram } from '../utils/metrics';
import { StorkPriceData, ResolutionResult, PredictionEvent } from '../types';

export class SuiInteractionService {
  private client: SuiClient;
  private keypair: Ed25519Keypair;

  constructor() {
    this.client = createSuiClient();
    
    // Parse oracle private key
    const keyData = config.oraclePrivateKey.replace('suiprivkey1', '');
    this.keypair = Ed25519Keypair.fromSecretKey(Buffer.from(keyData, 'base64'));

    logger.info('SuiInteractionService initialized', {
      network: config.suiNetwork,
      oracleAddress: config.oracleAddress,
    });
  }

  /**
   * Build PTB for crypto event resolution (atomic update + resolve)
   */
  async buildResolutionTransaction(
    eventId: string,
    coinType: string,
    storkPriceData: StorkPriceData
  ): Promise<TransactionBlock> {
    const tx = new TransactionBlock();

    try {
      // Set gas budget
      tx.setGasBudget(config.gasBudget);

      // Step 1: Allocate fee coin for Stork update
      const [feeCoin] = tx.splitCoins(tx.gas, [tx.pure(1000000, 'u64')]);

      // Step 2: Update Stork price feed
      tx.moveCall({
        target: `${config.storkPackageId}::stork::update_single_temporal_numeric_value_evm`,
        arguments: [
          tx.object(config.storkStateId),
          tx.pure(Array.from(storkPriceData.encodedSignedData), 'vector<u8>'),
          feeCoin,
        ],
      });

      // Step 3: Resolve crypto event (reads price atomically)
      tx.moveCall({
        target: `${config.packageId}::blink_event::resolve_crypto_event`,
        typeArguments: [coinType],
        arguments: [
          tx.object(eventId),
          tx.object(config.marketId),
          tx.object(config.storkStateId),
          tx.object('0x6'), // Clock
        ],
      });

      logger.debug('Built resolution transaction', {
        eventId,
        coinType,
        feedId: storkPriceData.id,
      });

      return tx;
    } catch (error: any) {
      logger.error('Failed to build resolution transaction', {
        eventId,
        error: error.message,
      });
      throw error;
    }
  }

  /**
   * Execute resolution transaction
   */
  async executeResolution(
    eventId: string,
    coinType: string,
    storkPriceData: StorkPriceData
  ): Promise<ResolutionResult> {
    const end = resolutionDurationHistogram.startTimer();
    const startTime = Date.now();

    try {
      logger.info('Executing resolution transaction', {
        eventId,
        coinType,
        feedId: storkPriceData.id,
      });

      const tx = await this.buildResolutionTransaction(
        eventId,
        coinType,
        storkPriceData
      );

      const result = await this.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: this.keypair,
        options: {
          showEffects: true,
          showEvents: true,
          showBalanceChanges: true,
        },
      });

      end();

      if (result.effects?.status?.status !== 'success') {
        const error = result.effects?.status?.error || 'Unknown error';
        logger.error('Resolution transaction failed', {
          eventId,
          error,
          digest: result.digest,
        });

        return {
          eventId,
          success: false,
          txDigest: result.digest,
          error,
          timestamp: Date.now(),
        };
      }

      // Extract gas used
      const gasUsed = result.effects?.gasUsed?.computationCost || 0;
      gasUsedHistogram.observe(gasUsed);

      // Parse EventResolved event
      const resolvedEvent = result.events?.find(
        (e) => e.type.includes('EventResolved')
      );

      let winningOutcome: number | undefined;
      let oraclePrice: string | undefined;

      if (resolvedEvent && resolvedEvent.parsedJson) {
        winningOutcome = resolvedEvent.parsedJson.winning_outcome;
        oraclePrice = resolvedEvent.parsedJson.oracle_price;
      }

      logger.info('Successfully resolved crypto event', {
        eventId,
        txDigest: result.digest,
        winningOutcome,
        oraclePrice,
        gasUsed,
        duration: Date.now() - startTime,
      });

      return {
        eventId,
        success: true,
        txDigest: result.digest,
        winningOutcome,
        oraclePrice,
        gasUsed,
        timestamp: Date.now(),
      };
    } catch (error: any) {
      end();
      logger.error('Failed to execute resolution transaction', {
        eventId,
        error: error.message,
        stack: error.stack,
      });

      return {
        eventId,
        success: false,
        error: error.message,
        timestamp: Date.now(),
      };
    }
  }

  /**
   * Query pending crypto events that need resolution
   */
  async queryPendingEvents(): Promise<PredictionEvent[]> {
    try {
      const currentTime = Date.now();

      // Query all events with STATUS_OPEN (1) and EVENT_TYPE_CRYPTO (0)
      const response = await this.client.queryEvents({
        query: {
          MoveEventType: `${config.packageId}::blink_event::EventCreated`,
        },
        limit: 100,
      });

      const pendingEvents: PredictionEvent[] = [];

      for (const event of response.data) {
        if (!event.parsedJson) continue;

        const eventData = event.parsedJson as any;

        // Filter: must be crypto event, open status, and past betting end time
        if (
          eventData.event_type === 0 && // CRYPTO
          eventData.status === 1 && // OPEN
          eventData.betting_end_time < currentTime
        ) {
          pendingEvents.push({
            id: eventData.event_id,
            marketId: eventData.market_id,
            status: eventData.status,
            eventType: eventData.event_type,
            description: eventData.description,
            outcomeLabels: eventData.outcome_labels,
            bettingStartTime: eventData.betting_start_time,
            bettingEndTime: eventData.betting_end_time,
            oracleFeedId: eventData.oracle_feed_id,
            targetPrice: eventData.target_price,
            totalPool: eventData.total_pool || 0,
          });
        }
      }

      logger.debug('Queried pending events', {
        total: response.data.length,
        pending: pendingEvents.length,
      });

      return pendingEvents;
    } catch (error: any) {
      logger.error('Failed to query pending events', {
        error: error.message,
      });
      return [];
    }
  }

  /**
   * Get event details by ID
   */
  async getEventDetails(eventId: string): Promise<PredictionEvent | null> {
    try {
      const response = await this.client.getObject({
        id: eventId,
        options: {
          showContent: true,
        },
      });

      if (!response.data || !response.data.content) {
        return null;
      }

      const content = response.data.content as any;
      const fields = content.fields;

      return {
        id: eventId,
        marketId: fields.market_id,
        status: fields.status,
        eventType: fields.event_type,
        description: fields.description,
        outcomeLabels: fields.outcome_labels,
        bettingStartTime: parseInt(fields.betting_start_time),
        bettingEndTime: parseInt(fields.betting_end_time),
        oracleFeedId: fields.oracle_feed_id,
        targetPrice: fields.target_price,
        totalPool: parseInt(fields.total_pool || '0'),
      };
    } catch (error: any) {
      logger.error('Failed to get event details', {
        eventId,
        error: error.message,
      });
      return null;
    }
  }

  /**
   * Estimate gas for resolution transaction
   */
  async estimateGas(tx: TransactionBlock): Promise<number> {
    try {
      const dryRunResult = await this.client.dryRunTransactionBlock({
        transactionBlock: await tx.build({ client: this.client }),
      });

      const gasUsed = dryRunResult.effects.gasUsed.computationCost || 0;
      return gasUsed;
    } catch (error: any) {
      logger.warn('Failed to estimate gas', { error: error.message });
      return config.gasBudget;
    }
  }
}
