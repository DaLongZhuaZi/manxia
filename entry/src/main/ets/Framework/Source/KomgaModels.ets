import { ComicDetailInfo, PageInfo } from './SourceExecutor';

export type KomgaAuthMode = 'NONE' | 'BASIC' | 'API_KEY';
export type KomgaContentType = 'SERIES' | 'READLISTS' | 'BOOKS';
export type KomgaBrowseMode = 'library' | 'discover';
export type KomgaFeedType = 'POPULAR' | 'LATEST' | 'SEARCH';
export type KomgaReadStatusMode = 'ANY' | 'UNREAD' | 'IN_PROGRESS' | 'READ';
export type KomgaSortKey = 'RELEVANCE' | 'ALPHABETICAL' | 'DATE_ADDED' | 'DATE_UPDATED' | 'RANDOM';

export interface KomgaSortOption {
  key: KomgaSortKey;
  label: string;
  ascending: boolean;
}

export const KOMGA_SORT_OPTIONS: KomgaSortOption[] = [
  { key: 'RELEVANCE', label: '???', ascending: false },
  { key: 'ALPHABETICAL', label: '?? A-Z', ascending: true },
  { key: 'DATE_ADDED', label: '????', ascending: false },
  { key: 'DATE_UPDATED', label: '????', ascending: false },
  { key: 'RANDOM', label: '??', ascending: false }
];

export const KOMGA_DEFAULT_CHAPTER_TEMPLATE: string = '{number} - {title} ({size})';

export interface KomgaInstanceConfig {
  id: string;
  displayName: string;
  serverUrl: string;
  authMode: KomgaAuthMode;
  username: string;
  password: string;
  apiKey: string;
  defaultLibraryIds: string[];
  chapterTitleTemplate: string;
  enabled: boolean;
}

export interface KomgaConfig {
  instances: KomgaInstanceConfig[];
  currentInstanceId: string;
  useBrowsePageAsEntry: boolean;
}

export interface KomgaLibraryOption {
  id: string;
  name: string;
}

export interface KomgaCollectionOption {
  id: string;
  name: string;
}

export interface KomgaAuthorOption {
  name: string;
  role: string;
}

export interface KomgaFilterOptions {
  libraries: KomgaLibraryOption[];
  collections: KomgaCollectionOption[];
  genres: string[];
  tags: string[];
  publishers: string[];
  authorsByRole: Record<string, KomgaAuthorOption[]>;
}

export interface KomgaBrowseFilters {
  selectedLibraryIds: string[];
  collectionId: string;
  readStatusMode: KomgaReadStatusMode;
  selectedStatuses: string[];
  selectedGenres: string[];
  selectedTags: string[];
  selectedPublishers: string[];
  selectedAuthorRole: string;
  selectedAuthorName: string;
  sortKey: KomgaSortKey;
}

export interface KomgaBrowseRequest {
  instanceId?: string;
  contentType: KomgaContentType;
  browseMode: KomgaBrowseMode;
  feedType: KomgaFeedType;
  page: number;
  query: string;
  filters: KomgaBrowseFilters;
}

export interface KomgaPaginatedResult<T> {
  items: T[];
  totalCount: number;
  hasMore: boolean;
}

export interface KomgaDetailRequest {
  instanceId?: string;
  itemId: string;
  contentType: KomgaContentType;
}

export interface KomgaDetailCacheEntry {
  detail: ComicDetailInfo;
  timestamp: number;
}

export interface KomgaPagesCacheEntry {
  pages: PageInfo[];
  timestamp: number;
}

export interface KomgaReaderProgress {
  itemKey: string;
  bookId: string;
  chapterIndex: number;
  pageIndex: number;
  timestamp: number;
}

export function createDefaultKomgaBrowseFilters(): KomgaBrowseFilters {
  return {
    selectedLibraryIds: [],
    collectionId: '',
    readStatusMode: 'ANY',
    selectedStatuses: [],
    selectedGenres: [],
    selectedTags: [],
    selectedPublishers: [],
    selectedAuthorRole: '',
    selectedAuthorName: '',
    sortKey: 'ALPHABETICAL'
  };
}

export function normalizeKomgaBrowseFilters(raw: ESObject | null | undefined): KomgaBrowseFilters {
  const defaults = createDefaultKomgaBrowseFilters();
  if (!raw) {
    return defaults;
  }

  const data: ESObject = raw;
  const readStatusMode = typeof data['readStatusMode'] === 'string' ? String(data['readStatusMode']) : defaults.readStatusMode;
  const sortKey = typeof data['sortKey'] === 'string' ? String(data['sortKey']) : defaults.sortKey;

  return {
    selectedLibraryIds: Array.isArray(data['selectedLibraryIds'])
      ? (data['selectedLibraryIds'] as Object[]).map(item => String(item))
      : defaults.selectedLibraryIds,
    collectionId: typeof data['collectionId'] === 'string' ? String(data['collectionId']) : defaults.collectionId,
    readStatusMode: readStatusMode === 'UNREAD' || readStatusMode === 'IN_PROGRESS' || readStatusMode === 'READ'
      ? readStatusMode
      : 'ANY',
    selectedStatuses: Array.isArray(data['selectedStatuses'])
      ? (data['selectedStatuses'] as Object[]).map(item => String(item))
      : defaults.selectedStatuses,
    selectedGenres: Array.isArray(data['selectedGenres'])
      ? (data['selectedGenres'] as Object[]).map(item => String(item))
      : defaults.selectedGenres,
    selectedTags: Array.isArray(data['selectedTags'])
      ? (data['selectedTags'] as Object[]).map(item => String(item))
      : defaults.selectedTags,
    selectedPublishers: Array.isArray(data['selectedPublishers'])
      ? (data['selectedPublishers'] as Object[]).map(item => String(item))
      : defaults.selectedPublishers,
    selectedAuthorRole: typeof data['selectedAuthorRole'] === 'string'
      ? String(data['selectedAuthorRole'])
      : defaults.selectedAuthorRole,
    selectedAuthorName: typeof data['selectedAuthorName'] === 'string'
      ? String(data['selectedAuthorName'])
      : defaults.selectedAuthorName,
    sortKey: sortKey === 'RELEVANCE' || sortKey === 'ALPHABETICAL' || sortKey === 'DATE_ADDED' || sortKey === 'DATE_UPDATED' || sortKey === 'RANDOM'
      ? sortKey
      : defaults.sortKey
  };
}

export function createEmptyKomgaFilterOptions(): KomgaFilterOptions {
  return {
    libraries: [],
    collections: [],
    genres: [],
    tags: [],
    publishers: [],
    authorsByRole: {}
  };
}
