/**
 * Unified annotation models for bookmark/highlight/thought.
 */

import { UnifiedContentType } from './UnifiedContentModels';

/**
 * Annotation record type.
 */
export enum UnifiedAnnotationType {
  BOOKMARK = 'bookmark',
  HIGHLIGHT = 'highlight',
  THOUGHT = 'thought'
}

/**
 * Highlight render style type.
 */
export enum HighlightLineType {
  UNDERLINE = 'underline',
  WAVY = 'wavy'
}

/**
 * Generic location anchor for all content types.
 */
export interface AnnotationAnchor {
  chapterId?: string;
  chapterTitle?: string;
  chapterIndex?: number;
  pageIndex?: number;
  progress?: number;
  startOffset?: number;
  endOffset?: number;
  paragraphIndex?: number;
  paragraphStartOffset?: number;
  paragraphEndOffset?: number;
  quoteText?: string;
  contextBefore?: string;
  contextAfter?: string;
}

/**
 * Highlight style configuration.
 */
export interface HighlightStyle {
  lineType: HighlightLineType;
  color: string;
  thickness?: number;
}

/**
 * Unified annotation database entity.
 */
export interface UnifiedAnnotationRecord {
  id: string;
  contentType: UnifiedContentType;
  contentId: string;
  annotationType: UnifiedAnnotationType;
  title: string;
  textContent: string;
  quoteText: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  pageIndex: number;
  pageProgress: number;
  startOffset: number;
  endOffset: number;
  anchor: AnnotationAnchor;
  styleJson: string;
  linkedAnnotationId: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * Bookmark creation input.
 */
export interface CreateBookmarkInput {
  contentType: UnifiedContentType;
  contentId: string;
  title?: string;
  textContent?: string;
  anchor: AnnotationAnchor;
}

/**
 * Highlight creation input.
 */
export interface CreateHighlightInput {
  contentType?: UnifiedContentType;
  contentId: string;
  anchor: AnnotationAnchor;
  style: HighlightStyle;
}

/**
 * Thought creation input.
 */
export interface CreateThoughtInput {
  contentType?: UnifiedContentType;
  contentId: string;
  anchor: AnnotationAnchor;
  textContent?: string;
  linkedAnnotationId?: string;
}
