/**
 * 局域网传书会话管理器
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  TransferSessionInfo,
  cloneTransferSessionInfo
} from '../../Models/TransferModels';

const TAG = 'TransferSessionManager';
const DEFAULT_TTL_MINUTES = 10;
const TOKEN_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789abcdefghijkmnopqrstuvwxyz';

export class TransferSessionManager {
  private static instance: TransferSessionManager;
  private currentSession: TransferSessionInfo | null = null;

  private constructor() {}

  public static getInstance(): TransferSessionManager {
    if (!TransferSessionManager.instance) {
      TransferSessionManager.instance = new TransferSessionManager();
    }
    return TransferSessionManager.instance;
  }

  public createOrRefreshSession(ttlMinutes: number = DEFAULT_TTL_MINUTES): TransferSessionInfo {
    const normalizedTtl = ttlMinutes > 0 ? ttlMinutes : DEFAULT_TTL_MINUTES;
    const now = Date.now();
    if (this.currentSession !== null && this.currentSession.expiresAt > now) {
      this.currentSession.lastAccessAt = now;
      this.currentSession.expiresAt = now + normalizedTtl * 60 * 1000;
      if (this.currentSession.status === 'expired') {
        this.currentSession.status = 'ready';
      }
      logger.info(TAG, `复用现有传书会话: ${this.currentSession.sessionId}`);
      return cloneTransferSessionInfo(this.currentSession) as TransferSessionInfo;
    }
    return this.refreshSession(normalizedTtl);
  }

  public refreshSession(ttlMinutes: number = DEFAULT_TTL_MINUTES): TransferSessionInfo {
    const normalizedTtl = ttlMinutes > 0 ? ttlMinutes : DEFAULT_TTL_MINUTES;
    const now = Date.now();
    const session: TransferSessionInfo = {
      sessionId: this.buildSessionId(),
      pairCode: this.generatePairCode(),
      token: this.generateToken(24),
      status: 'ready',
      createdAt: now,
      expiresAt: now + normalizedTtl * 60 * 1000,
      lastAccessAt: now,
      clientName: '',
      clientIp: ''
    };
    this.currentSession = session;
    logger.info(TAG, `创建新的传书会话: ${session.sessionId}, 配对码=${session.pairCode}`);
    return cloneTransferSessionInfo(session) as TransferSessionInfo;
  }

  public getSessionSnapshot(): TransferSessionInfo | null {
    this.markExpiredIfNeeded();
    return cloneTransferSessionInfo(this.currentSession);
  }

  public clearSession(): void {
    if (this.currentSession !== null) {
      logger.info(TAG, `清理传书会话: ${this.currentSession.sessionId}`);
    }
    this.currentSession = null;
  }

  public validatePairCode(pairCode: string): boolean {
    const session = this.getValidSessionForValidation();
    if (session === null) {
      return false;
    }
    const normalized = pairCode.trim();
    if (normalized.length <= 0) {
      return false;
    }
    const isMatched = session.pairCode === normalized;
    if (isMatched) {
      this.touchSession();
    }
    return isMatched;
  }

  public validateToken(token: string): boolean {
    return this.validateTokenForClient(token, '');
  }

  public validateTokenForClient(token: string, clientIp: string): boolean {
    const session = this.getValidSessionForValidation();
    if (session === null) {
      return false;
    }
    const normalized = token.trim();
    if (normalized.length <= 0) {
      return false;
    }
    const normalizedClientIp = clientIp.trim();
    if (session.clientIp.length > 0 && normalizedClientIp.length > 0 && session.clientIp !== normalizedClientIp) {
      logger.warn(
        TAG,
        `传书令牌客户端校验失败: session=${session.sessionId}, expected=${session.clientIp}, actual=${normalizedClientIp}`
      );
      return false;
    }
    const isMatched = session.token === normalized;
    if (isMatched) {
      this.touchSession();
    }
    return isMatched;
  }

  public canPairClient(clientIp: string): boolean {
    this.markExpiredIfNeeded();
    if (this.currentSession === null) {
      return false;
    }
    const normalizedClientIp = clientIp.trim();
    if (this.currentSession.status !== 'paired') {
      return true;
    }
    if (this.currentSession.clientIp.length <= 0 || normalizedClientIp.length <= 0) {
      return true;
    }
    return this.currentSession.clientIp === normalizedClientIp;
  }

  public markPaired(clientName: string, clientIp: string): TransferSessionInfo | null {
    this.markExpiredIfNeeded();
    if (this.currentSession === null) {
      return null;
    }
    const normalizedClientIp = clientIp.trim();
    if (!this.canPairClient(normalizedClientIp)) {
      logger.warn(
        TAG,
        `拒绝新的配对请求: session=${this.currentSession.sessionId}, existing=${this.currentSession.clientIp}, incoming=${normalizedClientIp}`
      );
      return null;
    }
    this.currentSession.status = 'paired';
    this.currentSession.clientName = clientName.trim();
    this.currentSession.clientIp = normalizedClientIp;
    this.currentSession.lastAccessAt = Date.now();
    logger.info(
      TAG,
      `传书会话已配对: ${this.currentSession.sessionId}, 客户端=${this.currentSession.clientIp}`
    );
    return cloneTransferSessionInfo(this.currentSession);
  }

  public touchSession(): void {
    this.markExpiredIfNeeded();
    if (this.currentSession === null) {
      return;
    }
    this.currentSession.lastAccessAt = Date.now();
    if (this.currentSession.status === 'expired') {
      this.currentSession.status = 'ready';
    }
  }

  private getValidSessionForValidation(): TransferSessionInfo | null {
    this.markExpiredIfNeeded();
    if (this.currentSession === null) {
      return null;
    }
    if (this.currentSession.expiresAt <= Date.now()) {
      this.currentSession.status = 'expired';
      return null;
    }
    return this.currentSession;
  }

  private markExpiredIfNeeded(): void {
    if (this.currentSession === null) {
      return;
    }
    if (this.currentSession.expiresAt <= Date.now()) {
      this.currentSession.status = 'expired';
    }
  }

  private buildSessionId(): string {
    const randomPart = this.generateToken(8).toLowerCase();
    return `transfer_${Date.now()}_${randomPart}`;
  }

  private generatePairCode(): string {
    const numberValue = 100000 + Math.floor(Math.random() * 900000);
    return String(numberValue);
  }

  private generateToken(length: number): string {
    let token = '';
    for (let index = 0; index < length; index++) {
      const randomIndex = Math.floor(Math.random() * TOKEN_ALPHABET.length);
      token += TOKEN_ALPHABET.charAt(randomIndex);
    }
    return token;
  }
}

export function getTransferSessionManager(): TransferSessionManager {
  return TransferSessionManager.getInstance();
}
