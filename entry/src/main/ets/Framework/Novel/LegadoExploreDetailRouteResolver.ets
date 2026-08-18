import { LegadoBookSource, LegadoBookSourceType } from './LegadoSourceTypes';

export enum LegadoExploreDetailRouteKind {
  MANGA = 'manga',
  NOVEL = 'novel',
  REJECTED = 'rejected'
}

export enum LegadoExploreDetailRouteReason {
  IMAGE_SOURCE = 'image_source',
  NON_IMAGE_SOURCE = 'non_image_source',
  RESULT_SOURCE_ID_EMPTY = 'result_source_id_empty',
  SELECTED_SOURCE_ID_EMPTY = 'selected_source_id_empty',
  SOURCE_IDENTITY_MISMATCH = 'source_identity_mismatch',
  SOURCE_LOOKUP_MISSING = 'source_lookup_missing',
  RESOLVED_SOURCE_IDENTITY_MISMATCH = 'resolved_source_identity_mismatch',
  UNSUPPORTED_SOURCE_TYPE = 'unsupported_source_type'
}

export enum LegadoExploreDetailIdentityStatus {
  MATCHED = 'matched',
  RESULT_EMPTY = 'result_empty',
  SELECTED_EMPTY = 'selected_empty',
  RESULT_SELECTED_MISMATCH = 'result_selected_mismatch',
  LOOKUP_MISSING = 'lookup_missing',
  RESOLVED_MISMATCH = 'resolved_mismatch'
}

export enum LegadoExploreDetailBridgeStatus {
  NOT_APPLICABLE = 'not_applicable',
  NOT_STARTED = 'not_started',
  READY = 'ready',
  UNAVAILABLE = 'unavailable'
}

export class LegadoExploreDetailRouteDecision {
  readonly route: LegadoExploreDetailRouteKind;
  readonly reason: LegadoExploreDetailRouteReason;
  readonly identityStatus: LegadoExploreDetailIdentityStatus;
  readonly sourceType: number;

  constructor(
    route: LegadoExploreDetailRouteKind,
    reason: LegadoExploreDetailRouteReason,
    identityStatus: LegadoExploreDetailIdentityStatus,
    sourceType: number
  ) {
    this.route = route;
    this.reason = reason;
    this.identityStatus = identityStatus;
    this.sourceType = sourceType;
  }

  toSafeDiagnostic(bridgeStatus: LegadoExploreDetailBridgeStatus): string {
    return `identity=${this.identityStatus};sourceType=${this.sourceType};` +
      `route=${this.route};reason=${this.reason};bridge=${bridgeStatus}`;
  }
}

/**
 * Resolves the content route from the exact result identity and the source
 * object that is currently held by the runtime manager. A missing lookup is a
 * rejection because treating it as TEXT would silently corrupt IMAGE routing.
 */
export class LegadoExploreDetailRouteResolver {
  resolve(
    resultSourceId: string,
    selectedSourceId: string,
    source: LegadoBookSource | null
  ): LegadoExploreDetailRouteDecision {
    if (resultSourceId.length === 0) {
      return this.reject(
        LegadoExploreDetailRouteReason.RESULT_SOURCE_ID_EMPTY,
        LegadoExploreDetailIdentityStatus.RESULT_EMPTY,
        source
      );
    }
    if (selectedSourceId.length === 0) {
      return this.reject(
        LegadoExploreDetailRouteReason.SELECTED_SOURCE_ID_EMPTY,
        LegadoExploreDetailIdentityStatus.SELECTED_EMPTY,
        source
      );
    }
    if (resultSourceId !== selectedSourceId) {
      return this.reject(
        LegadoExploreDetailRouteReason.SOURCE_IDENTITY_MISMATCH,
        LegadoExploreDetailIdentityStatus.RESULT_SELECTED_MISMATCH,
        source
      );
    }
    if (source === null) {
      return this.reject(
        LegadoExploreDetailRouteReason.SOURCE_LOOKUP_MISSING,
        LegadoExploreDetailIdentityStatus.LOOKUP_MISSING,
        source
      );
    }
    if (source.bookSourceUrl !== resultSourceId) {
      return this.reject(
        LegadoExploreDetailRouteReason.RESOLVED_SOURCE_IDENTITY_MISMATCH,
        LegadoExploreDetailIdentityStatus.RESOLVED_MISMATCH,
        source
      );
    }
    if (source.bookSourceType < LegadoBookSourceType.TEXT ||
      source.bookSourceType > LegadoBookSourceType.FILE) {
      return this.reject(
        LegadoExploreDetailRouteReason.UNSUPPORTED_SOURCE_TYPE,
        LegadoExploreDetailIdentityStatus.MATCHED,
        source
      );
    }
    if (source.bookSourceType === LegadoBookSourceType.IMAGE) {
      return new LegadoExploreDetailRouteDecision(
        LegadoExploreDetailRouteKind.MANGA,
        LegadoExploreDetailRouteReason.IMAGE_SOURCE,
        LegadoExploreDetailIdentityStatus.MATCHED,
        source.bookSourceType
      );
    }
    return new LegadoExploreDetailRouteDecision(
      LegadoExploreDetailRouteKind.NOVEL,
      LegadoExploreDetailRouteReason.NON_IMAGE_SOURCE,
      LegadoExploreDetailIdentityStatus.MATCHED,
      source.bookSourceType
    );
  }

  private reject(
    reason: LegadoExploreDetailRouteReason,
    identityStatus: LegadoExploreDetailIdentityStatus,
    source: LegadoBookSource | null
  ): LegadoExploreDetailRouteDecision {
    return new LegadoExploreDetailRouteDecision(
      LegadoExploreDetailRouteKind.REJECTED,
      reason,
      identityStatus,
      source === null ? -1 : source.bookSourceType
    );
  }
}
