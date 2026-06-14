import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * EPUB Bridge JS Builder
 * Extracted from EpubWebViewReaderComponent to reduce component state explosion.
 * Contains pure/near-pure JS string builders for WebView bridge injection.
 */

import { EpubPageLayoutKind } from './EpubCssBuilder';

export class BridgeJsBuilder {
  /**
   * Build annotation/highlight/seek/read-aloud bridge JS.
   * Pure string — zero interpolations.
   */
  static buildAnnotationBridgeJs(): string {
    return `
      window.__mnxAnnotationLayerId = '__mnx_epub_highlight_layer';
      window.__mnxHighlightHitRects = [];
      window.__mnxIsAnnotationIgnoredNode = function(node) {
        var current = node;
        while (current) {
          if (current.nodeType === 1 && current.getAttribute) {
            var tag = String(current.tagName || '').toLowerCase();
            if (tag === 'script' || tag === 'style' || tag === 'noscript') {
              return true;
            }
            if (current.getAttribute('data-mnx-ignore-pagination') === 'true' ||
              current.getAttribute('data-mnx-ignore-annotation') === 'true') {
              return true;
            }
          }
          current = current.parentNode;
        }
        return false;
      };
      window.__mnxCreateAnnotationWalker = function() {
        if (!document.body || !document.createTreeWalker) {
          return null;
        }
        return document.createTreeWalker(
          document.body,
          NodeFilter.SHOW_TEXT,
          {
            acceptNode: function(node) {
              if (!node || window.__mnxIsAnnotationIgnoredNode(node)) {
                return NodeFilter.FILTER_REJECT;
              }
              var text = String(node.nodeValue || '');
              return text.length > 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          }
        );
      };
      window.__mnxGetAnnotationText = function() {
        var walker = window.__mnxCreateAnnotationWalker();
        if (!walker) {
          return document.body ? String(document.body.innerText || document.body.textContent || '') : '';
        }
        var parts = [];
        var node = walker.nextNode();
        while (node) {
          parts.push(String(node.nodeValue || ''));
          node = walker.nextNode();
        }
        return parts.join('');
      };
      window.__mnxNativeBoundaryOffset = function(container, offset) {
        if (!document.body || !document.createRange || !container) {
          return -1;
        }
        try {
          var range = document.createRange();
          range.selectNodeContents(document.body);
          range.setEnd(container, offset);
          var length = String(range.toString() || '').length;
          if (range.detach) {
            range.detach();
          }
          return length;
        } catch (_error) {
          return -1;
        }
      };
      window.__mnxGetTextBoundaryOffset = function(container, offset) {
        if (!container) {
          return -1;
        }
        var walker = window.__mnxCreateAnnotationWalker();
        if (!walker) {
          return window.__mnxNativeBoundaryOffset(container, offset);
        }
        var total = 0;
        var node = walker.nextNode();
        while (node) {
          var text = String(node.nodeValue || '');
          if (node === container) {
            var local = Math.max(0, Math.min(text.length, Math.floor(offset || 0)));
            return total + local;
          }
          total += text.length;
          node = walker.nextNode();
        }
        return window.__mnxNativeBoundaryOffset(container, offset);
      };
      window.__mnxFindTextBoundary = function(offset) {
        var safeOffset = Math.max(0, Math.floor(offset || 0));
        var walker = window.__mnxCreateAnnotationWalker();
        if (!walker) {
          return null;
        }
        var total = 0;
        var lastNode = null;
        var node = walker.nextNode();
        while (node) {
          var text = String(node.nodeValue || '');
          lastNode = node;
          if (safeOffset <= total + text.length) {
            return {
              node: node,
              offset: Math.max(0, Math.min(text.length, safeOffset - total))
            };
          }
          total += text.length;
          node = walker.nextNode();
        }
        if (lastNode) {
          return {
            node: lastNode,
            offset: String(lastNode.nodeValue || '').length
          };
        }
        return null;
      };
      window.__mnxCreateRangeFromTextOffsets = function(startOffset, endOffset) {
        var start = window.__mnxFindTextBoundary(startOffset);
        var end = window.__mnxFindTextBoundary(endOffset);
        if (!start || !end || !document.createRange) {
          return null;
        }
        try {
          var range = document.createRange();
          range.setStart(start.node, start.offset);
          range.setEnd(end.node, end.offset);
          return range;
        } catch (_error) {
          return null;
        }
      };
      window.__mnxReadSelectionSnapshot = function() {
        var selection = window.getSelection ? window.getSelection() : null;
        if (!selection || selection.rangeCount <= 0 || selection.isCollapsed) {
          return '';
        }
        var selectedText = String(selection.toString() || '');
        if (selectedText.replace(/\\s+/g, '').length <= 0) {
          return '';
        }
        var range = selection.getRangeAt(0).cloneRange();
        var startOffset = window.__mnxGetTextBoundaryOffset(range.startContainer, range.startOffset);
        var endOffset = window.__mnxGetTextBoundaryOffset(range.endContainer, range.endOffset);
        if (startOffset < 0 || endOffset < 0) {
          return '';
        }
        if (endOffset < startOffset) {
          var swap = startOffset;
          startOffset = endOffset;
          endOffset = swap;
        }
        if (endOffset <= startOffset) {
          return '';
        }
        var allText = window.__mnxGetAnnotationText();
        var contextBefore = allText.substring(Math.max(0, startOffset - 18), startOffset);
        var contextAfter = allText.substring(endOffset, Math.min(allText.length, endOffset + 18));
        var rect = range.getBoundingClientRect ? range.getBoundingClientRect() : null;
        var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
          width: window.innerWidth || 1,
          height: window.innerHeight || 1
        };
        var paginationState = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
          pageCount: 1,
          currentPage: 0
        };
        var pageCount = Math.max(1, Math.floor(paginationState.pageCount || 1));
        var currentPage = Math.max(0, Math.min(pageCount - 1, Math.floor(paginationState.currentPage || 0)));
        var payload = {
          selectedText: selectedText,
          startOffset: startOffset,
          endOffset: endOffset,
          contextBefore: contextBefore,
          contextAfter: contextAfter,
          pageIndex: currentPage,
          pageProgress: pageCount > 0 ? (currentPage + 1) / pageCount : 0,
          rectX: rect ? Math.max(0, Math.min(viewport.width, rect.left || 0)) : 0,
          rectY: rect ? Math.max(0, Math.min(viewport.height, rect.top || 0)) : 0,
          rectWidth: rect ? Math.max(0, rect.width || 0) : 0,
          rectHeight: rect ? Math.max(0, rect.height || 0) : 0
        };
        return JSON.stringify(payload);
      };
      window.__mnxTextRectIntersectsViewport = function(rect, margin) {
        if (!rect) {
          return false;
        }
        var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
          width: window.innerWidth || 1,
          height: window.innerHeight || 1
        };
        var safeMargin = Math.max(0, Number(margin) || 0);
        var left = Number(rect.left) || 0;
        var top = Number(rect.top) || 0;
        var right = Number(rect.right);
        var bottom = Number(rect.bottom);
        if (!isFinite(right)) {
          right = left + (Number(rect.width) || 0);
        }
        if (!isFinite(bottom)) {
          bottom = top + (Number(rect.height) || 0);
        }
        return right >= -safeMargin &&
          bottom >= -safeMargin &&
          left <= viewport.width + safeMargin &&
          top <= viewport.height + safeMargin;
      };
      window.__mnxRangeIntersectsViewport = function(range, margin) {
        if (!range || !range.getClientRects) {
          return false;
        }
        var rects = range.getClientRects();
        for (var i = 0; i < rects.length; i++) {
          var rect = rects[i];
          var width = Math.max(0, rect.width || (rect.right - rect.left) || 0);
          var height = Math.max(0, rect.height || (rect.bottom - rect.top) || 0);
          if (width <= 0 || height <= 0) {
            continue;
          }
          if (window.__mnxTextRectIntersectsViewport(rect, margin)) {
            return true;
          }
        }
        return false;
      };
      window.__mnxTextNodeIntersectsViewport = function(node) {
        if (!node || !document.createRange) {
          return false;
        }
        try {
          var range = document.createRange();
          range.selectNodeContents(node);
          var visible = window.__mnxRangeIntersectsViewport(range, 2);
          if (range.detach) {
            range.detach();
          }
          return visible;
        } catch (_error) {
          return false;
        }
      };
      window.__mnxRangeSliceIntersectsViewport = function(node, start, end) {
        if (!node || !document.createRange) {
          return false;
        }
        var text = String(node.nodeValue || '');
        var safeStart = Math.max(0, Math.min(text.length, Math.floor(start || 0)));
        var safeEnd = Math.max(safeStart, Math.min(text.length, Math.floor(end || 0)));
        if (safeEnd <= safeStart) {
          return false;
        }
        try {
          var range = document.createRange();
          range.setStart(node, safeStart);
          range.setEnd(node, safeEnd);
          var visible = window.__mnxRangeIntersectsViewport(range, 2);
          if (range.detach) {
            range.detach();
          }
          return visible;
        } catch (_error) {
          return false;
        }
      };
      window.__mnxFindVisibleLocalStart = function(node) {
        var text = String(node.nodeValue || '');
        var length = text.length;
        if (length <= 0) {
          return 0;
        }
        var low = 1;
        var high = length;
        while (low < high) {
          var mid = Math.floor((low + high) / 2);
          if (window.__mnxRangeSliceIntersectsViewport(node, 0, mid)) {
            high = mid;
          } else {
            low = mid + 1;
          }
        }
        return Math.max(0, Math.min(length, low - 1));
      };
      window.__mnxFindVisibleLocalEnd = function(node) {
        var text = String(node.nodeValue || '');
        var length = text.length;
        if (length <= 0) {
          return 0;
        }
        var low = 0;
        var high = length - 1;
        while (low < high) {
          var mid = Math.ceil((low + high) / 2);
          if (window.__mnxRangeSliceIntersectsViewport(node, mid, length)) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }
        return Math.max(1, Math.min(length, low + 1));
      };
      window.__mnxFindVisibleTextOffsetRange = function() {
        var walker = window.__mnxCreateAnnotationWalker();
        var allText = window.__mnxGetAnnotationText ? window.__mnxGetAnnotationText() : '';
        var total = 0;
        var start = -1;
        var end = -1;
        if (walker) {
          var node = walker.nextNode();
          while (node) {
            var text = String(node.nodeValue || '');
            var length = text.length;
            if (length > 0 && window.__mnxTextNodeIntersectsViewport(node)) {
              var localStart = window.__mnxFindVisibleLocalStart(node);
              var localEnd = window.__mnxFindVisibleLocalEnd(node);
              if (start < 0) {
                start = total + Math.max(0, Math.min(length, localStart));
              }
              end = total + Math.max(localStart + 1, Math.min(length, localEnd));
            }
            total += length;
            node = walker.nextNode();
          }
        } else {
          total = allText.length;
        }
        if (start < 0 || end <= start) {
          var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
            pageCount: 1,
            currentPage: 0
          };
          var pageCount = Math.max(1, Math.floor(state.pageCount || 1));
          var currentPage = Math.max(0, Math.min(pageCount - 1, Math.floor(state.currentPage || 0)));
          var textLength = allText.length;
          start = Math.max(0, Math.floor(textLength * currentPage / pageCount));
          end = Math.max(start, Math.floor(textLength * (currentPage + 1) / pageCount));
          if (textLength > 0 && end <= start) {
            end = Math.min(textLength, start + 1);
          }
        }
        return {
          start: Math.max(0, start),
          end: Math.max(0, end),
          total: Math.max(total, allText.length)
        };
      };
      window.__mnxReadCurrentTextSnapshot = function() {
        var allText = window.__mnxGetAnnotationText ? window.__mnxGetAnnotationText() : '';
        if (!allText || allText.replace(/\\s+/g, '').length <= 0) {
          return '';
        }
        var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
          pageCount: 1,
          currentPage: 0
        };
        var pageCount = Math.max(1, Math.floor(state.pageCount || 1));
        var currentPage = Math.max(0, Math.min(pageCount - 1, Math.floor(state.currentPage || 0)));
        var rangeInfo = window.__mnxFindVisibleTextOffsetRange();
        var startOffset = Math.max(0, Math.min(allText.length, Math.floor(rangeInfo.start || 0)));
        var endOffset = Math.max(startOffset, Math.min(allText.length, Math.floor(rangeInfo.end || 0)));
        if (allText.length > 0 && endOffset <= startOffset) {
          endOffset = Math.min(allText.length, startOffset + 1);
        }
        var quoteText = allText.substring(startOffset, endOffset).replace(/\\s+/g, ' ').trim();
        if (quoteText.length > 240) {
          quoteText = quoteText.substring(0, 240);
        }
        return JSON.stringify({
          text: allText,
          startOffset: startOffset,
          endOffset: endOffset,
          contextBefore: allText.substring(Math.max(0, startOffset - 18), startOffset),
          contextAfter: allText.substring(endOffset, Math.min(allText.length, endOffset + 18)),
          pageIndex: currentPage,
          pageProgress: pageCount > 0 ? (currentPage + 1) / pageCount : 0,
          quoteText: quoteText
        });
      };
      window.__mnxApplySinglePurifyRule = function(text, rule) {
        var pattern = String(rule.pattern || '');
        if (!pattern) {
          return text;
        }
        var replacement = String(rule.replacement || '');
        try {
          if (rule.isRegex === true) {
            return String(text || '').replace(new RegExp(pattern, 'g'), replacement);
          }
          return String(text || '').split(pattern).join(replacement);
        } catch (_error) {
          return text;
        }
      };
      window.__mnxApplyPurifyRules = function(payloadJson) {
        var rules = [];
        try {
          rules = SafeUtils.parseObj(String(payloadJson || '[]'));
        } catch (_error) {
          rules = [];
        }
        if (!window.__mnxOriginalTextNodeValues && typeof WeakMap !== 'undefined') {
          window.__mnxOriginalTextNodeValues = new WeakMap();
        }
        var walker = window.__mnxCreateAnnotationWalker();
        var changed = 0;
        var visited = 0;
        if (walker) {
          var node = walker.nextNode();
          while (node) {
            visited++;
            var original = String(node.nodeValue || '');
            if (window.__mnxOriginalTextNodeValues) {
              if (!window.__mnxOriginalTextNodeValues.has(node)) {
                window.__mnxOriginalTextNodeValues.set(node, original);
              }
              original = String(window.__mnxOriginalTextNodeValues.get(node) || '');
            }
            var nextText = original;
            for (var i = 0; i < rules.length; i++) {
              nextText = window.__mnxApplySinglePurifyRule(nextText, rules[i] || {});
            }
            if (nextText !== String(node.nodeValue || '')) {
              node.nodeValue = nextText;
              changed++;
            }
            node = walker.nextNode();
          }
        }
        if (window.__mnxClearWebSelection) {
          window.__mnxClearWebSelection();
        }
        var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
          pageCount: 1,
          currentPage: 0,
          currentOffset: 0,
          pageExtent: 0,
          maxOffset: 0
        };
        if (window.__mnxUpdateFootnoteLayer) {
          window.__mnxUpdateFootnoteLayer();
        }
        if (window.__mnxSchedulePaginationNotify) {
          window.__mnxSchedulePaginationNotify('purify_rules');
        }
        return JSON.stringify({
          rules: rules.length,
          visited: visited,
          changed: changed,
          pageIndex: state.currentPage || 0,
          pageCount: state.pageCount || 1
        });
      };
      window.__mnxSeekToTextOffset = function(offset) {
        var allText = window.__mnxGetAnnotationText ? window.__mnxGetAnnotationText() : '';
        var textLength = allText.length;
        if (textLength <= 0) {
          var emptyState = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
            currentPage: 0,
            pageCount: 1,
            currentOffset: 0,
            pageExtent: 0,
            maxOffset: 0
          };
          return JSON.stringify({
            pageIndex: emptyState.currentPage || 0,
            offset: emptyState.currentOffset || 0,
            pageCount: emptyState.pageCount || 1,
            pageExtent: emptyState.pageExtent || 0,
            maxOffset: emptyState.maxOffset || 0,
            requestedOffset: 0,
            physicalOffset: 0,
            usedVirtualOffset: false,
            found: false
          });
        }
        var safeOffset = Math.max(0, Math.min(textLength - 1, Math.floor(offset || 0)));
        var range = window.__mnxCreateRangeFromTextOffsets(safeOffset, Math.min(textLength, safeOffset + 1));
        var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
          currentPage: 0,
          pageCount: 1,
          currentOffset: 0,
          pageExtent: 0,
          maxOffset: 0
        };
        if (!range || !range.getBoundingClientRect) {
          return JSON.stringify({
            pageIndex: state.currentPage || 0,
            offset: state.currentOffset || 0,
            pageCount: state.pageCount || 1,
            pageExtent: state.pageExtent || 0,
            maxOffset: state.maxOffset || 0,
            requestedOffset: 0,
            physicalOffset: 0,
            usedVirtualOffset: false,
            found: false
          });
        }
        var root = window.__mnxResolveScrollRoot ? window.__mnxResolveScrollRoot() : document.scrollingElement;
        var isVertical = window.__mnxIsVerticalLayout ? window.__mnxIsVerticalLayout() : true;
        var rootRect = root && root.getBoundingClientRect ? root.getBoundingClientRect() : { left: 0, top: 0 };
        var rect = range.getBoundingClientRect();
        var currentLeft = window.__mnxGetScrollOffset ? window.__mnxGetScrollOffset(false) : (window.scrollX || 0);
        var currentTop = window.__mnxGetScrollOffset ? window.__mnxGetScrollOffset(true) : (window.scrollY || 0);
        var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
          width: window.innerWidth || 1,
          height: window.innerHeight || 1
        };
        var rectWidth = Math.max(0, rect.width || (rect.right - rect.left) || 0);
        var rectHeight = Math.max(0, rect.height || (rect.bottom - rect.top) || 0);
        var visibilityMargin = Math.max(12, Math.min(48, (isVertical ? viewport.height : viewport.width) * 0.04));
        var visibleNow = rectWidth > 1 && rectHeight > 1 &&
          rect.right >= -visibilityMargin &&
          rect.bottom >= -visibilityMargin &&
          rect.left <= viewport.width + visibilityMargin &&
          rect.top <= viewport.height + visibilityMargin;
        var absoluteOffset = isVertical
          ? (rect.top - rootRect.top + currentTop)
          : (rect.left - rootRect.left + currentLeft);
        absoluteOffset = Math.max(0, Math.round(absoluteOffset));
        if (range.detach) {
          range.detach();
        }
        if (visibleNow) {
          return JSON.stringify({
            pageIndex: state.pageIndex !== undefined ? state.pageIndex : (state.currentPage || 0),
            offset: state.offset !== undefined ? state.offset : (state.currentOffset || 0),
            pageCount: state.pageCount || 1,
            pageExtent: state.pageExtent || 0,
            maxOffset: state.maxOffset || 0,
            requestedOffset: absoluteOffset,
            physicalOffset: state.physicalOffset !== undefined ? state.physicalOffset : 0,
            usedVirtualOffset: state.usedVirtualOffset === true,
            found: true
          });
        }
        if (window.__mnxLayoutKind === 'continuous_vertical' || window.__mnxLayoutKind === 'continuous_horizontal') {
          window.__mnxSetScrollOffset(isVertical, absoluteOffset);
          state = window.__mnxRefreshPagination();
        } else {
          var targetPage = window.__mnxFindContainingPageIndex ? window.__mnxFindContainingPageIndex(absoluteOffset, visibilityMargin) : {
            pageIndex: state.currentPage || 0
          };
          if (window.__mnxGoToPageImmediate && targetPage.pageIndex !== (state.currentPage || 0)) {
            state = SafeUtils.parseObj(window.__mnxGoToPageImmediate(targetPage.pageIndex));
          }
        }
        if (window.__mnxUpdateFootnoteLayer) {
          window.__mnxUpdateFootnoteLayer();
        }
        if (window.__mnxSchedulePaginationNotify) {
          window.__mnxSchedulePaginationNotify('text_offset_seek');
        }
        return JSON.stringify({
          pageIndex: state.pageIndex !== undefined ? state.pageIndex : (state.currentPage || 0),
          offset: state.offset !== undefined ? state.offset : (state.currentOffset || 0),
          pageCount: state.pageCount || 1,
          pageExtent: state.pageExtent || 0,
          maxOffset: state.maxOffset || 0,
          requestedOffset: absoluteOffset,
          physicalOffset: state.physicalOffset !== undefined ? state.physicalOffset : 0,
          usedVirtualOffset: state.usedVirtualOffset === true,
          found: true
        });
      };
      window.__mnxReadAloudLayerId = '__mnx_epub_read_aloud_layer';
      window.__mnxClearReadAloudHighlight = function() {
        var oldLayer = document.getElementById(window.__mnxReadAloudLayerId);
        if (oldLayer && oldLayer.parentNode) {
          oldLayer.parentNode.removeChild(oldLayer);
        }
        return 'ok';
      };
      window.__mnxCreateReadAloudLayer = function() {
        window.__mnxClearReadAloudHighlight();
        var layer = document.createElement('div');
        layer.id = window.__mnxReadAloudLayerId;
        layer.setAttribute('data-mnx-ignore-pagination', 'true');
        layer.setAttribute('data-mnx-ignore-annotation', 'true');
        layer.style.position = 'fixed';
        layer.style.left = '0';
        layer.style.top = '0';
        layer.style.width = '100vw';
        layer.style.height = '100vh';
        layer.style.pointerEvents = 'none';
        layer.style.zIndex = '2147482999';
        layer.style.overflow = 'hidden';
        (document.documentElement || document.body).appendChild(layer);
        return layer;
      };
      window.__mnxDrawReadAloudRange = function(layer, viewport, startOffset, endOffset, background, boxShadow) {
        var start = Math.max(0, Math.floor(startOffset || 0));
        var end = Math.max(start, Math.floor(endOffset || 0));
        if (end <= start) {
          return 0;
        }
        var range = window.__mnxCreateRangeFromTextOffsets(start, end);
        var applied = 0;
        if (range && range.getClientRects) {
          var rects = range.getClientRects();
          for (var i = 0; i < rects.length; i++) {
            var rect = rects[i];
            var width = Math.max(0, rect.width || (rect.right - rect.left) || 0);
            var height = Math.max(0, rect.height || (rect.bottom - rect.top) || 0);
            if (width <= 1 || height <= 1) {
              continue;
            }
            var left = Number(rect.left) || 0;
            var top = Number(rect.top) || 0;
            var right = left + width;
            var bottom = top + height;
            if (right < 0 || bottom < 0 || left > viewport.width || top > viewport.height) {
              continue;
            }
            var clippedLeft = Math.max(0, left);
            var clippedTop = Math.max(0, top);
            var clippedRight = Math.min(viewport.width, right);
            var mark = document.createElement('div');
            mark.style.position = 'fixed';
            mark.style.left = clippedLeft + 'px';
            mark.style.top = clippedTop + 'px';
            mark.style.width = Math.max(1, clippedRight - clippedLeft) + 'px';
            mark.style.height = Math.max(1, height) + 'px';
            mark.style.borderRadius = '3px';
            mark.style.background = background;
            mark.style.boxShadow = boxShadow;
            layer.appendChild(mark);
            applied++;
          }
          if (range.detach) {
            range.detach();
          }
        }
        return applied;
      };
      window.__mnxApplyReadAloudHighlight = function(startOffset, endOffset, follow, progressOffset) {
        var allText = window.__mnxGetAnnotationText ? window.__mnxGetAnnotationText() : '';
        var textLength = allText.length;
        var start = Math.max(0, Math.min(textLength, Math.floor(startOffset || 0)));
        var end = Math.max(start + 1, Math.min(textLength, Math.floor(endOffset || 0)));
        var progress = Math.max(start, Math.min(end, Math.floor(Number(progressOffset) || start)));
        var followed = follow === true;
        var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : {
          currentPage: 0,
          pageCount: 1,
          currentOffset: 0,
          pageExtent: 0,
          maxOffset: 0
        };
        if (textLength <= 0 || end <= start) {
          window.__mnxClearReadAloudHighlight();
          return JSON.stringify({
            pageIndex: state.currentPage || 0,
            offset: state.currentOffset || 0,
            pageCount: state.pageCount || 1,
            pageExtent: state.pageExtent || 0,
            maxOffset: state.maxOffset || 0,
            applied: 0,
            followed: false
          });
        }
        if (followed && window.__mnxSeekToTextOffset) {
          try {
            var followTarget = Math.max(start, Math.min(Math.max(start, end - 1), progress));
            state = SafeUtils.parseObj(window.__mnxSeekToTextOffset(followTarget));
          } catch (_seekError) {
            state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : state;
          }
        }
        var layer = window.__mnxCreateReadAloudLayer();
        var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
          width: window.innerWidth || 1,
          height: window.innerHeight || 1
        };
        var applied = 0;
        applied += window.__mnxDrawReadAloudRange(
          layer,
          viewport,
          start,
          progress,
          'rgba(102, 187, 106, 0.80)',
          '0 0 0 1px rgba(102, 187, 106, 0.28)'
        );
        applied += window.__mnxDrawReadAloudRange(
          layer,
          viewport,
          progress,
          end,
          'rgba(255, 202, 40, 0.80)',
          '0 0 0 1px rgba(255, 202, 40, 0.28)'
        );
        var latestState = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : state;
        return JSON.stringify({
          pageIndex: latestState.pageIndex !== undefined ? latestState.pageIndex : (latestState.currentPage || 0),
          offset: latestState.offset !== undefined ? latestState.offset : (latestState.currentOffset || 0),
          pageCount: latestState.pageCount || 1,
          pageExtent: latestState.pageExtent || 0,
          maxOffset: latestState.maxOffset || 0,
          applied: applied,
          followed: followed,
          progressOffset: progress
        });
      };
      window.__mnxClearWebSelection = function() {
        try {
          var selection = window.getSelection ? window.getSelection() : null;
          if (selection && selection.removeAllRanges) {
            selection.removeAllRanges();
          }
        } catch (_error) {
        }
        return 'ok';
      };
      window.__mnxRemoveEpubHighlights = function() {
        window.__mnxHighlightHitRects = [];
        var oldLayer = document.getElementById(window.__mnxAnnotationLayerId);
        if (oldLayer && oldLayer.parentNode) {
          oldLayer.parentNode.removeChild(oldLayer);
        }
      };
      window.__mnxCreateHighlightLayer = function() {
        window.__mnxRemoveEpubHighlights();
        var layer = document.createElement('div');
        layer.id = window.__mnxAnnotationLayerId;
        layer.setAttribute('data-mnx-ignore-pagination', 'true');
        layer.setAttribute('data-mnx-ignore-annotation', 'true');
        layer.style.position = 'fixed';
        layer.style.left = '0';
        layer.style.top = '0';
        layer.style.width = '100vw';
        layer.style.height = '100vh';
        layer.style.pointerEvents = 'none';
        layer.style.zIndex = '2147483000';
        layer.style.overflow = 'hidden';
        (document.documentElement || document.body).appendChild(layer);
        return layer;
      };
      window.__mnxApplyEpubHighlights = function(payloadJson) {
        var ranges = [];
        try {
          ranges = SafeUtils.parseObj(String(payloadJson || '[]'));
        } catch (_error) {
          ranges = [];
        }
        var layer = window.__mnxCreateHighlightLayer();
        var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
          width: window.innerWidth || 1,
          height: window.innerHeight || 1
        };
        var applied = 0;
        for (var i = 0; i < ranges.length; i++) {
          var item = ranges[i] || {};
          var id = String(item.id || '');
          var start = Math.max(0, Math.floor(Number(item.startOffset) || 0));
          var end = Math.max(start + 1, Math.floor(Number(item.endOffset) || 0));
          if (!id || end <= start) {
            continue;
          }
          var range = window.__mnxCreateRangeFromTextOffsets(start, end);
          if (!range || !range.getClientRects) {
            continue;
          }
          var rects = range.getClientRects();
          var color = String(item.color || '#E8A317');
          var lineType = String(item.lineType || 'underline');
          for (var ri = 0; ri < rects.length; ri++) {
            var rect = rects[ri];
            var width = Math.max(0, rect.width || (rect.right - rect.left) || 0);
            var height = Math.max(0, rect.height || (rect.bottom - rect.top) || 0);
            if (width <= 1 || height <= 1) {
              continue;
            }
            var left = rect.left || 0;
            var top = rect.top || 0;
            var right = left + width;
            var bottom = top + height;
            if (right < 0 || bottom < 0 || left > viewport.width || top > viewport.height) {
              continue;
            }
            var clippedLeft = Math.max(0, left);
            var clippedRight = Math.min(viewport.width, right);
            if (clippedRight - clippedLeft <= 1) {
              continue;
            }
            var mark = document.createElement('div');
            mark.setAttribute('data-mnx-highlight-id', id);
            mark.style.position = 'fixed';
            mark.style.left = clippedLeft + 'px';
            mark.style.top = Math.max(0, bottom - 4) + 'px';
            mark.style.width = Math.max(1, clippedRight - clippedLeft) + 'px';
            mark.style.height = '5px';
            mark.style.pointerEvents = 'none';
            mark.style.opacity = '0.96';
            if (lineType === 'wavy') {
              mark.style.backgroundImage = 'radial-gradient(circle at 2px 2px, ' + color + ' 1.35px, transparent 1.65px)';
              mark.style.backgroundSize = '6px 4px';
              mark.style.backgroundRepeat = 'repeat-x';
              mark.style.backgroundPosition = 'left bottom';
            } else {
              mark.style.borderBottom = '2px solid ' + color;
            }
            layer.appendChild(mark);
            window.__mnxHighlightHitRects.push({
              id: id,
              left: Math.max(0, left),
              top: Math.max(0, top),
              right: Math.min(viewport.width, right),
              bottom: Math.min(viewport.height, bottom)
            });
            applied++;
          }
          if (range.detach) {
            range.detach();
          }
        }
        return JSON.stringify({
          count: ranges.length,
          applied: applied
        });
      };
      window.__mnxHandleHighlightClick = function(event) {
        if (!event || !window.__mnxHighlightHitRects || window.__mnxHighlightHitRects.length <= 0) {
          return false;
        }
        var clientX = typeof event.clientX === 'number' ? event.clientX : 0;
        var clientY = typeof event.clientY === 'number' ? event.clientY : 0;
        for (var i = window.__mnxHighlightHitRects.length - 1; i >= 0; i--) {
          var rect = window.__mnxHighlightHitRects[i];
          if (clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom) {
            if (window.arkts && typeof window.arkts.onEpubHighlightTap === 'function') {
              var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
                width: window.innerWidth || 1,
                height: window.innerHeight || 1
              };
              window.arkts.onEpubHighlightTap(JSON.stringify({
                id: rect.id,
                xRatio: Math.max(0, Math.min(1, clientX / Math.max(1, viewport.width))),
                yRatio: Math.max(0, Math.min(1, clientY / Math.max(1, viewport.height)))
              }));
            }
            if (event.preventDefault) {
              event.preventDefault();
            }
            if (event.stopPropagation) {
              event.stopPropagation();
            }
            return true;
          }
        }
        return false;
      };
    `;
  }

  /**
   * Build pagination/scroll/touch bridge JS.
   * One interpolation: ${layoutKind}.
   */
  static buildBridgeJs(layoutKind: EpubPageLayoutKind): string {
    return `
      window.__mnxLayoutKind = '${layoutKind}';
      window.__mnxGetScrollCandidates = function() {
        var list = [];
        var append = function(node) {
          if (!node) {
            return;
          }
          for (var i = 0; i < list.length; i++) {
            if (list[i] === node) {
              return;
            }
          }
          list.push(node);
        };
        append(document.scrollingElement);
        append(document.documentElement);
        append(document.body);
        return list;
      };
      window.__mnxResolveScrollRoot = function() {
        var candidates = window.__mnxGetScrollCandidates();
        return candidates.length > 0 ? candidates[0] : null;
      };
      window.__mnxIsVerticalLayout = function() {
        return window.__mnxLayoutKind === 'vertical_paged' || window.__mnxLayoutKind === 'continuous_vertical';
      };
      window.__mnxIsContinuousLayout = function() {
        return window.__mnxLayoutKind === 'continuous_vertical' || window.__mnxLayoutKind === 'continuous_horizontal';
      };
      window.__mnxCanUseVirtualOffset = function(isVertical) {
        return !isVertical &&
          (window.__mnxLayoutKind === 'horizontal_paged' ||
           window.__mnxLayoutKind === 'double_page' ||
           window.__mnxLayoutKind === 'continuous_horizontal');
      };
      window.__mnxUseAlignedHorizontalOffsets = function(isVertical) {
        return !isVertical &&
          (window.__mnxLayoutKind === 'horizontal_paged' ||
           window.__mnxLayoutKind === 'double_page' ||
           window.__mnxLayoutKind === 'continuous_horizontal');
      };
      window.__mnxClearVirtualOffset = function(forceStyleReset) {
        var body = document.body;
        window.__mnxUsesVirtualOffset = false;
        window.__mnxVirtualOffset = 0;
        if (!body) {
          return;
        }
        if (forceStyleReset === true) {
          body.style.removeProperty('transform');
          body.style.removeProperty('transform-origin');
        } else if (body.getAttribute('data-mnx-virtual-offset') === 'true') {
          var baseTransform = body.getAttribute('data-mnx-base-transform') || '';
          body.style.transform = baseTransform;
        }
        body.removeAttribute('data-mnx-virtual-offset');
        body.removeAttribute('data-mnx-base-transform');
      };
      window.__mnxApplyVirtualOffset = function(isVertical, targetOffset) {
        if (!window.__mnxCanUseVirtualOffset(isVertical) || !document.body) {
          return false;
        }
        var body = document.body;
        var safeTarget = Math.max(0, Math.round(targetOffset || 0));
        if (body.getAttribute('data-mnx-virtual-offset') !== 'true') {
          var originalTransform = body.style.transform || '';
          body.setAttribute('data-mnx-base-transform', originalTransform === 'none' ? '' : originalTransform);
        }
        var baseTransform = body.getAttribute('data-mnx-base-transform') || '';
        var shift = isVertical
          ? 'translate3d(0px, -' + safeTarget + 'px, 0px)'
          : 'translate3d(-' + safeTarget + 'px, 0px, 0px)';
        body.style.transformOrigin = 'top left';
        body.style.transform = baseTransform.length > 0 ? (baseTransform + ' ' + shift) : shift;
        body.setAttribute('data-mnx-virtual-offset', 'true');
        window.__mnxUsesVirtualOffset = true;
        window.__mnxVirtualOffset = safeTarget;
        return true;
      };
      window.__mnxGetPhysicalScrollOffset = function(isVertical) {
        var value = isVertical
          ? (window.pageYOffset || window.scrollY || 0)
          : (window.pageXOffset || window.scrollX || 0);
        var candidates = window.__mnxGetScrollCandidates();
        for (var i = 0; i < candidates.length; i++) {
          var node = candidates[i];
          var nodeValue = isVertical ? (node.scrollTop || 0) : (node.scrollLeft || 0);
          if (nodeValue > value) {
            value = nodeValue;
          }
        }
        return Math.max(0, Math.round(value));
      };
      window.__mnxGetScrollOffset = function(isVertical) {
        if (window.__mnxUsesVirtualOffset && window.__mnxCanUseVirtualOffset(isVertical)) {
          return Math.max(0, Math.round(window.__mnxVirtualOffset || 0));
        }
        return window.__mnxGetPhysicalScrollOffset(isVertical);
      };
      window.__mnxGetTotalExtent = function(isVertical) {
        var viewport = window.__mnxGetViewportExtent();
        var total = isVertical ? viewport.height : viewport.width;
        var candidates = window.__mnxGetScrollCandidates();
        for (var i = 0; i < candidates.length; i++) {
          var node = candidates[i];
          total = Math.max(
            total,
            isVertical ? (node.scrollHeight || 0) : (node.scrollWidth || 0),
            isVertical ? (node.offsetHeight || 0) : (node.offsetWidth || 0),
            isVertical ? (node.clientHeight || 0) : (node.clientWidth || 0)
          );
        }
        return Math.max(1, Math.round(total));
      };
      window.__mnxGetContentExtent = function(isVertical) {
        var body = document.body;
        var viewport = window.__mnxGetViewportExtent();
        var fallback = isVertical ? viewport.height : viewport.width;
        if (!body) {
          return fallback;
        }
        var root = window.__mnxResolveScrollRoot();
        var rootRect = root && root.getBoundingClientRect ? root.getBoundingClientRect() : { left: 0, top: 0 };
        var currentLeft = window.__mnxGetScrollOffset(false);
        var currentTop = window.__mnxGetScrollOffset(true);
        var maxEnd = 0;
        var collectRect = function(rect) {
          if (!rect) {
            return;
          }
          var width = Math.max(0, rect.width || (rect.right - rect.left) || 0);
          var height = Math.max(0, rect.height || (rect.bottom - rect.top) || 0);
          if (width <= 0 && height <= 0) {
            return;
          }
          var end = isVertical
            ? (rect.bottom - rootRect.top + currentTop)
            : (rect.right - rootRect.left + currentLeft);
          if (end > maxEnd) {
            maxEnd = end;
          }
        };
        try {
          if (document.createRange) {
            var range = document.createRange();
            range.selectNodeContents(body);
            var rangeRects = range.getClientRects ? range.getClientRects() : [];
            for (var ri = 0; ri < rangeRects.length; ri++) {
              collectRect(rangeRects[ri]);
            }
            if (range.detach) {
              range.detach();
            }
          }
        } catch (_rangeError) {
        }
        try {
          var nodes = body.querySelectorAll
            ? body.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table,figure,img,svg,video,canvas')
            : [];
          for (var ni = 0; ni < nodes.length; ni++) {
            if (nodes[ni].getAttribute && nodes[ni].getAttribute('data-mnx-ignore-pagination') === 'true') {
              continue;
            }
            if (nodes[ni].closest && nodes[ni].closest('[data-mnx-ignore-pagination="true"]')) {
              continue;
            }
            var rects = nodes[ni].getClientRects ? nodes[ni].getClientRects() : [];
            for (var nri = 0; nri < rects.length; nri++) {
              collectRect(rects[nri]);
            }
          }
        } catch (_nodeError) {
        }
        return Math.max(fallback, Math.ceil(maxEnd));
      };
      window.__mnxSetScrollOffset = function(isVertical, targetOffset) {
        var safeTarget = Math.max(0, Math.round(targetOffset || 0));
        window.__mnxClearVirtualOffset();
        var candidates = window.__mnxGetScrollCandidates();
        for (var i = 0; i < candidates.length; i++) {
          var node = candidates[i];
          try {
            if (typeof node.scrollTo === 'function') {
              if (isVertical) {
                node.scrollTo({ left: 0, top: safeTarget, behavior: 'auto' });
              } else {
                node.scrollTo({ left: safeTarget, top: 0, behavior: 'auto' });
              }
            }
          } catch (_scrollToError) {
          }
          try {
            if (isVertical) {
              node.scrollTop = safeTarget;
            } else {
              node.scrollLeft = safeTarget;
            }
          } catch (_assignError) {
          }
        }
        try {
          if (isVertical) {
            window.scrollTo(0, safeTarget);
          } else {
            window.scrollTo(safeTarget, 0);
          }
        } catch (_windowScrollError) {
        }
        if (document.documentElement) {
          void document.documentElement.offsetWidth;
        }
        var physicalOffset = window.__mnxGetPhysicalScrollOffset(isVertical);
        if (Math.abs(physicalOffset - safeTarget) > 2 && window.__mnxApplyVirtualOffset(isVertical, safeTarget)) {
          return safeTarget;
        }
        return physicalOffset;
      };
      window.__mnxGetViewportExtent = function() {
        var width = window.innerWidth || (document.documentElement ? document.documentElement.clientWidth : 0) || (document.body ? document.body.clientWidth : 0) || 0;
        var height = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 0) || (document.body ? document.body.clientHeight : 0) || 0;
        return { width: Math.max(1, Math.round(width)), height: Math.max(1, Math.round(height)) };
      };
      window.__mnxRefreshPagination = function() {
        var root = window.__mnxResolveScrollRoot();
        var viewport = window.__mnxGetViewportExtent();
        var contentKind = document.documentElement
          ? (document.documentElement.getAttribute('data-mnx-content-kind') || '')
          : '';
        var isVertical = window.__mnxIsVerticalLayout();
        var pageExtent = isVertical ? viewport.height : viewport.width;
        if (contentKind === 'image_like' || contentKind === 'publisher_layout' || contentKind === 'cover_page') {
          window.__mnxClearVirtualOffset();
          window.__mnxPageOffsets = [0];
          window.__mnxPaginationState = {
            pageCount: 1,
            currentPage: 0,
            currentOffset: 0,
            pageExtent: pageExtent,
            maxOffset: 0,
            contentExtent: pageExtent,
            rootTagName: root && root.tagName ? root.tagName : ''
          };
          return window.__mnxPaginationState;
        }
        var rawTotalExtent = window.__mnxGetTotalExtent(isVertical);
        var contentExtent = window.__mnxGetContentExtent(isVertical);
        var totalExtent = window.__mnxUseAlignedHorizontalOffsets(isVertical)
          ? Math.max(pageExtent, contentExtent)
          : rawTotalExtent;
        var currentOffset = window.__mnxGetScrollOffset(isVertical);
        var maxOffset = Math.max(0, totalExtent - pageExtent);
        var offsets = [];
        if (maxOffset <= 0 || pageExtent <= 0) {
          offsets.push(0);
        } else if (window.__mnxUseAlignedHorizontalOffsets(isVertical)) {
          var alignedTolerance = Math.max(2, Math.min(8, pageExtent * 0.01));
          var alignedPageCount = Math.max(1, Math.ceil(Math.max(1, totalExtent - alignedTolerance) / pageExtent));
          for (var alignedIndex = 0; alignedIndex < alignedPageCount; alignedIndex++) {
            offsets.push(Math.max(0, Math.round(alignedIndex * pageExtent)));
          }
          maxOffset = offsets.length > 0 ? offsets[offsets.length - 1] : 0;
          currentOffset = Math.min(currentOffset, maxOffset);
        } else {
          var probe = 0;
          while (probe < maxOffset) {
            offsets.push(Math.max(0, Math.round(probe)));
            probe += pageExtent;
          }
          if (offsets.length === 0 || offsets[offsets.length - 1] !== Math.round(maxOffset)) {
            offsets.push(Math.round(maxOffset));
          }
        }
        var currentPage = 0;
        var bestDistance = Number.MAX_SAFE_INTEGER;
        for (var i = 0; i < offsets.length; i++) {
          var distance = Math.abs(offsets[i] - currentOffset);
          if (distance < bestDistance) {
            bestDistance = distance;
            currentPage = i;
          }
        }
        window.__mnxPageOffsets = offsets;
        window.__mnxPaginationState = {
          pageCount: offsets.length,
          currentPage: currentPage,
          currentOffset: currentOffset,
          pageExtent: pageExtent,
          maxOffset: Math.round(maxOffset),
          contentExtent: Math.round(contentExtent),
          rootTagName: root && root.tagName ? root.tagName : ''
        };
        return window.__mnxPaginationState;
      };
      window.__mnxNotifyPagination = function(source) {
        if (!window.arkts || typeof window.arkts.onPaginationChanged !== 'function') {
          return;
        }
        var state = window.__mnxRefreshPagination();
        if (window.__mnxUpdateFootnoteLayer) {
          window.__mnxUpdateFootnoteLayer();
        }
        window.arkts.onPaginationChanged(JSON.stringify({
          source: source || 'manual',
          layoutKind: window.__mnxLayoutKind || '',
          pageCount: state.pageCount,
          currentPage: state.currentPage,
          currentOffset: state.currentOffset,
          pageExtent: state.pageExtent,
          maxOffset: state.maxOffset,
          atStart: state.currentOffset <= 2,
          atEnd: state.currentOffset >= Math.max(0, state.maxOffset - 2)
        }));
      };
      window.__mnxSchedulePaginationNotify = function(source) {
        if (window.__mnxNotifyTimer) {
          clearTimeout(window.__mnxNotifyTimer);
        }
        window.__mnxNotifyTimer = setTimeout(function() {
          window.__mnxNotifyTimer = 0;
          window.__mnxNotifyPagination(source || 'deferred');
        }, 56);
      };
      window.__mnxInstallArkBridge = function() {
        var root = window.__mnxResolveScrollRoot();
        if (window.__mnxScrollRoots && window.__mnxScrollHandler) {
          for (var sri = 0; sri < window.__mnxScrollRoots.length; sri++) {
            var oldRoot = window.__mnxScrollRoots[sri];
            if (oldRoot && oldRoot.removeEventListener) {
              oldRoot.removeEventListener('scroll', window.__mnxScrollHandler);
            }
          }
        }
        if (window.__mnxWindowScrollHandler) {
          window.removeEventListener('scroll', window.__mnxWindowScrollHandler);
        }
        if (window.__mnxResizeHandler) {
          window.removeEventListener('resize', window.__mnxResizeHandler);
        }
        if (window.__mnxClickHandler) {
          document.removeEventListener('click', window.__mnxClickHandler, true);
        }
        if (window.__mnxTouchStartHandler) {
          document.removeEventListener('touchstart', window.__mnxTouchStartHandler, true);
        }
        if (window.__mnxTouchMoveHandler) {
          document.removeEventListener('touchmove', window.__mnxTouchMoveHandler, true);
        }
        if (window.__mnxTouchEndHandler) {
          document.removeEventListener('touchend', window.__mnxTouchEndHandler, true);
        }
        if (window.__mnxTouchCancelHandler) {
          document.removeEventListener('touchcancel', window.__mnxTouchCancelHandler, true);
        }
        window.__mnxScrollRoot = root;
        window.__mnxScrollHandler = function() {
          window.__mnxSchedulePaginationNotify('scroll');
        };
        window.__mnxWindowScrollHandler = function() {
          window.__mnxSchedulePaginationNotify('window_scroll');
        };
        window.__mnxResizeHandler = function() {
          window.__mnxSchedulePaginationNotify('resize');
        };
        window.__mnxClickHandler = function(event) {
          if (!window.arkts || typeof window.arkts.onReaderTap !== 'function') {
            return;
          }
          if (window.__mnxSuppressClickUntil && Date.now() < window.__mnxSuppressClickUntil) {
            if (event.preventDefault) {
              event.preventDefault();
            }
            if (event.stopPropagation) {
              event.stopPropagation();
            }
            return;
          }
          if (window.__mnxHandleHighlightClick && window.__mnxHandleHighlightClick(event)) {
            return;
          }
          var viewport = window.__mnxGetViewportExtent();
          var safeWidth = Math.max(1, viewport.width);
          var safeHeight = Math.max(1, viewport.height);
          var clientX = event && typeof event.clientX === 'number' ? event.clientX : 0;
          var clientY = event && typeof event.clientY === 'number' ? event.clientY : 0;
          window.arkts.onReaderTap(JSON.stringify({
            xRatio: Math.max(0, Math.min(1, clientX / safeWidth)),
            yRatio: Math.max(0, Math.min(1, clientY / safeHeight))
          }));
        };
        window.__mnxTouchState = {
          active: false,
          intercepting: false,
          startX: 0,
          startY: 0,
          lastX: 0,
          lastY: 0
        };
        window.__mnxHasActiveSelection = function() {
          try {
            var selection = window.getSelection ? window.getSelection() : null;
            return !!(selection && String(selection.toString() || '').trim().length > 0);
          } catch (_selectionError) {
            return false;
          }
        };
        window.__mnxIsInteractiveTarget = function(target) {
          var node = target;
          while (node && node !== document.body && node !== document.documentElement) {
            if (node.nodeType === 1 && node.tagName) {
              var tag = String(node.tagName || '').toLowerCase();
              if (tag === 'a' || tag === 'button' || tag === 'input' || tag === 'textarea' ||
                tag === 'select' || tag === 'option' || tag === 'video' || tag === 'audio') {
                return true;
              }
              if (node.getAttribute && (
                node.getAttribute('contenteditable') === 'true' ||
                node.getAttribute('data-mnx-ignore-pagination') === 'true'
              )) {
                return true;
              }
            }
            node = node.parentNode;
          }
          return false;
        };
        window.__mnxShouldHandleReaderSwipe = function(event) {
          if (window.__mnxLayoutKind === 'continuous_vertical') {
            return false;
          }
          if (!window.arkts ||
            (typeof window.arkts.onReaderSwipe !== 'function' &&
              typeof window.arkts.onReaderPan !== 'function')) {
            return false;
          }
          if (!event || !event.touches || event.touches.length !== 1) {
            return false;
          }
          if (window.__mnxHasActiveSelection && window.__mnxHasActiveSelection()) {
            return false;
          }
          return !(window.__mnxIsInteractiveTarget && window.__mnxIsInteractiveTarget(event.target));
        };
        window.__mnxShouldLockNativePagingScroll = function() {
          return window.__mnxLayoutKind === 'horizontal_paged' ||
            window.__mnxLayoutKind === 'double_page' ||
            window.__mnxLayoutKind === 'vertical_paged';
        };
        window.__mnxEmitReaderPan = function(phase, x, y, deltaX, deltaY) {
          if (!window.arkts || typeof window.arkts.onReaderPan !== 'function') {
            return;
          }
          var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
            width: window.innerWidth || 1,
            height: window.innerHeight || 1
          };
          var safeWidth = Math.max(1, viewport.width);
          var safeHeight = Math.max(1, viewport.height);
          window.arkts.onReaderPan(JSON.stringify({
            phase: phase,
            xRatio: Math.max(0, Math.min(1, x / safeWidth)),
            yRatio: Math.max(0, Math.min(1, y / safeHeight)),
            deltaXRatio: deltaX / safeWidth,
            deltaYRatio: deltaY / safeHeight
          }));
        };
        window.__mnxTouchStartHandler = function(event) {
          if (!window.__mnxShouldHandleReaderSwipe(event)) {
            window.__mnxTouchState.active = false;
            window.__mnxTouchState.intercepting = false;
            window.__mnxTouchState.panStarted = false;
            return;
          }
          var touch = event.touches[0];
          window.__mnxTouchState.active = true;
          window.__mnxTouchState.intercepting = false;
          window.__mnxTouchState.startX = touch.clientX || 0;
          window.__mnxTouchState.startY = touch.clientY || 0;
          window.__mnxTouchState.lastX = touch.clientX || 0;
          window.__mnxTouchState.lastY = touch.clientY || 0;
          window.__mnxTouchState.panStarted = false;
        };
        window.__mnxTouchMoveHandler = function(event) {
          var state = window.__mnxTouchState;
          if (!state || !state.active || !event || !event.touches || event.touches.length !== 1) {
            return;
          }
          if (window.__mnxHasActiveSelection && window.__mnxHasActiveSelection()) {
            state.active = false;
            state.intercepting = false;
            return;
          }
          var touch = event.touches[0];
          var deltaX = (touch.clientX || 0) - state.startX;
          var deltaY = (touch.clientY || 0) - state.startY;
          state.lastX = touch.clientX || 0;
          state.lastY = touch.clientY || 0;
          var absX = Math.abs(deltaX);
          var absY = Math.abs(deltaY);
          var vertical = window.__mnxIsVerticalLayout && window.__mnxIsVerticalLayout();
          var primary = vertical ? absY : absX;
          var secondary = vertical ? absX : absY;
          var shouldLockNativeScroll = window.__mnxShouldLockNativePagingScroll &&
            window.__mnxShouldLockNativePagingScroll();
          if (shouldLockNativeScroll && primary >= 2 && primary >= secondary * 0.85) {
            state.intercepting = true;
          }
          if (primary >= 12 && primary >= secondary * 1.15) {
            state.intercepting = true;
          }
          if (state.intercepting) {
            if (event.preventDefault) {
              event.preventDefault();
            }
            if (event.stopPropagation) {
              event.stopPropagation();
            }
            if (window.__mnxEmitReaderPan) {
              if (!state.panStarted) {
                state.panStarted = true;
                window.__mnxEmitReaderPan('start', state.startX, state.startY, 0, 0);
              }
              window.__mnxEmitReaderPan('update', state.lastX, state.lastY, deltaX, deltaY);
            }
          }
        };
        window.__mnxTouchEndHandler = function(event) {
          var state = window.__mnxTouchState;
          if (!state || !state.active) {
            return;
          }
          var endX = state.lastX;
          var endY = state.lastY;
          if (event && event.changedTouches && event.changedTouches.length > 0) {
            endX = event.changedTouches[0].clientX || endX;
            endY = event.changedTouches[0].clientY || endY;
          }
          var deltaX = endX - state.startX;
          var deltaY = endY - state.startY;
          var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
            width: window.innerWidth || 1,
            height: window.innerHeight || 1
          };
          var vertical = window.__mnxIsVerticalLayout && window.__mnxIsVerticalLayout();
          var primary = vertical ? Math.abs(deltaY) : Math.abs(deltaX);
          var secondary = vertical ? Math.abs(deltaX) : Math.abs(deltaY);
          var extent = vertical ? viewport.height : viewport.width;
          var threshold = Math.max(42, Math.min(120, extent * 0.14));
          var shouldFlip = state.intercepting && primary >= threshold && primary >= secondary * 1.15;
          var panWasStarted = !!state.panStarted;
          state.active = false;
          state.intercepting = false;
          state.panStarted = false;
          if (panWasStarted && window.__mnxEmitReaderPan) {
            if (event && event.preventDefault) {
              event.preventDefault();
            }
            if (event && event.stopPropagation) {
              event.stopPropagation();
            }
            window.__mnxSuppressClickUntil = Date.now() + 360;
            window.__mnxEmitReaderPan('end', endX, endY, deltaX, deltaY);
          }
          if (shouldFlip) {
            if (event && event.preventDefault) {
              event.preventDefault();
            }
            if (event && event.stopPropagation) {
              event.stopPropagation();
            }
            window.__mnxSuppressClickUntil = Date.now() + 360;
            if (window.arkts && typeof window.arkts.onReaderSwipe === 'function') {
              window.arkts.onReaderSwipe(JSON.stringify({
              deltaX: deltaX,
              deltaY: deltaY
              }));
            }
          }
        };
        window.__mnxTouchCancelHandler = function() {
          if (window.__mnxTouchState) {
            if (window.__mnxTouchState.panStarted && window.__mnxEmitReaderPan) {
              window.__mnxEmitReaderPan(
                'cancel',
                window.__mnxTouchState.lastX,
                window.__mnxTouchState.lastY,
                window.__mnxTouchState.lastX - window.__mnxTouchState.startX,
                window.__mnxTouchState.lastY - window.__mnxTouchState.startY
              );
            }
            window.__mnxTouchState.active = false;
            window.__mnxTouchState.intercepting = false;
            window.__mnxTouchState.panStarted = false;
          }
        };
        window.__mnxScrollRoots = window.__mnxGetScrollCandidates();
        for (var sri2 = 0; sri2 < window.__mnxScrollRoots.length; sri2++) {
          var nextRoot = window.__mnxScrollRoots[sri2];
          if (nextRoot && nextRoot.addEventListener) {
            nextRoot.addEventListener('scroll', window.__mnxScrollHandler, { passive: true });
          }
        }
        window.addEventListener('scroll', window.__mnxWindowScrollHandler, { passive: true });
        window.addEventListener('resize', window.__mnxResizeHandler, { passive: true });
        document.addEventListener('click', window.__mnxClickHandler, true);
        document.addEventListener('touchstart', window.__mnxTouchStartHandler, { capture: true, passive: true });
        document.addEventListener('touchmove', window.__mnxTouchMoveHandler, { capture: true, passive: false });
        document.addEventListener('touchend', window.__mnxTouchEndHandler, { capture: true, passive: false });
        document.addEventListener('touchcancel', window.__mnxTouchCancelHandler, { capture: true, passive: true });
      };
      window.__mnxGetPageCount = function() {
        return window.__mnxRefreshPagination().pageCount;
      };
      window.__mnxGoToPageImmediate = function(pageIndex) {
        var state = window.__mnxRefreshPagination();
        var normalizedIndex = Math.max(0, Math.min(state.pageCount - 1, Math.floor(pageIndex || 0)));
        var targetOffset = state.pageCount > 0 ? (window.__mnxPageOffsets[normalizedIndex] || 0) : 0;
        var isVertical = window.__mnxIsVerticalLayout();
        window.__mnxSetScrollOffset(isVertical, targetOffset);
        state = window.__mnxRefreshPagination();
        window.__mnxPaginationState = state;
        if (window.__mnxUpdateFootnoteLayer) {
          window.__mnxUpdateFootnoteLayer();
        }
        window.__mnxSchedulePaginationNotify('programmatic');
        return JSON.stringify({
          pageIndex: state.currentPage,
          offset: state.currentOffset,
          pageCount: state.pageCount,
          pageExtent: state.pageExtent,
          maxOffset: state.maxOffset,
          requestedOffset: targetOffset,
          physicalOffset: window.__mnxGetPhysicalScrollOffset(isVertical),
          usedVirtualOffset: !!window.__mnxUsesVirtualOffset
        });
      };
      window.__mnxGoToPage = window.__mnxGoToPageImmediate;
      window.__mnxGetCurrentPage = function() {
        return window.__mnxRefreshPagination().currentPage;
      };
      window.__mnxNormalizeFragment = function(fragment) {
        if (fragment === null || fragment === undefined) {
          return '';
        }
        var text = String(fragment).trim();
        if (text.charAt(0) === '#') {
          text = text.substring(1);
        }
        if (!text) {
          return '';
        }
        try {
          return decodeURIComponent(text);
        } catch (_error) {
          return text;
        }
      };
      window.__mnxResolveAnchorElement = function(fragment) {
        var normalized = window.__mnxNormalizeFragment(fragment);
        if (!normalized) {
          return null;
        }
        var target = document.getElementById(normalized);
        if (target) {
          return target;
        }
        if (document.getElementsByName) {
          var named = document.getElementsByName(normalized);
          if (named && named.length > 0) {
            return named[0];
          }
        }
        if (document.querySelectorAll) {
          var all = document.querySelectorAll('[id],[name]');
          for (var i = 0; i < all.length; i++) {
            var candidate = all[i];
            if ((candidate.id && candidate.id === normalized) ||
              (candidate.getAttribute && candidate.getAttribute('name') === normalized)) {
              return candidate;
            }
          }
        }
        return null;
      };
      window.__mnxFindNearestPageIndex = function(targetOffset) {
        var state = window.__mnxRefreshPagination();
        var offsets = window.__mnxPageOffsets || [0];
        var normalizedOffset = Math.max(0, Math.round(targetOffset || 0));
        var pageIndex = 0;
        var bestDistance = Number.MAX_SAFE_INTEGER;
        for (var i = 0; i < offsets.length; i++) {
          var distance = Math.abs((offsets[i] || 0) - normalizedOffset);
          if (distance < bestDistance) {
            bestDistance = distance;
            pageIndex = i;
          }
        }
        return {
          pageIndex: pageIndex,
          state: state
        };
      };
      window.__mnxFindContainingPageIndex = function(targetOffset, tolerance) {
        var state = window.__mnxRefreshPagination();
        var offsets = window.__mnxPageOffsets || [0];
        var normalizedOffset = Math.max(0, Math.round(targetOffset || 0));
        var safeTolerance = Math.max(0, Math.round(tolerance || 0));
        var currentPage = Math.max(0, Math.min((state.currentPage || 0), Math.max(0, offsets.length - 1)));
        var currentStart = offsets.length > 0 ? Math.max(0, Math.round(offsets[currentPage] || 0)) : 0;
        var currentEnd = currentPage + 1 < offsets.length
          ? Math.max(currentStart, Math.round(offsets[currentPage + 1] || currentStart))
          : Math.max(currentStart, Math.round(state.maxOffset || currentStart) + Math.round(state.pageExtent || 0));
        if (normalizedOffset >= Math.max(0, currentStart - safeTolerance) &&
          normalizedOffset < currentEnd + safeTolerance) {
          return {
            pageIndex: currentPage,
            state: state
          };
        }
        var pageIndex = 0;
        for (var i = 0; i < offsets.length; i++) {
          var offset = Math.max(0, Math.round(offsets[i] || 0));
          if (offset <= normalizedOffset + safeTolerance) {
            pageIndex = i;
          } else {
            break;
          }
        }
        pageIndex = Math.max(0, Math.min(pageIndex, Math.max(0, offsets.length - 1)));
        return {
          pageIndex: pageIndex,
          state: state
        };
      };
      window.__mnxGoToFragmentImmediate = function(fragment) {
        var target = window.__mnxResolveAnchorElement(fragment);
        var state = window.__mnxRefreshPagination();
        if (!target) {
          return JSON.stringify({
            found: false,
            pageIndex: state.currentPage,
            offset: state.currentOffset,
            pageCount: state.pageCount,
            pageExtent: state.pageExtent,
            maxOffset: state.maxOffset
          });
        }
        var root = window.__mnxResolveScrollRoot();
        var isVertical = window.__mnxIsVerticalLayout();
        var rootRect = root && root.getBoundingClientRect ? root.getBoundingClientRect() : { left: 0, top: 0 };
        var rect = target.getBoundingClientRect ? target.getBoundingClientRect() : { left: 0, top: 0 };
        var currentLeft = window.__mnxGetScrollOffset(false);
        var currentTop = window.__mnxGetScrollOffset(true);
        var absoluteOffset = isVertical
          ? (rect.top - rootRect.top + currentTop)
          : (rect.left - rootRect.left + currentLeft);
        absoluteOffset = Math.max(0, Math.round(absoluteOffset));
        if (window.__mnxLayoutKind === 'continuous_vertical' || window.__mnxLayoutKind === 'continuous_horizontal') {
          window.__mnxSetScrollOffset(isVertical, absoluteOffset);
          state = window.__mnxRefreshPagination();
          if (window.__mnxUpdateFootnoteLayer) {
            window.__mnxUpdateFootnoteLayer();
          }
          window.__mnxSchedulePaginationNotify('programmatic_fragment');
          return JSON.stringify({
            found: true,
            pageIndex: state.currentPage,
            offset: state.currentOffset,
            pageCount: state.pageCount,
            pageExtent: state.pageExtent,
            maxOffset: state.maxOffset
          });
        }
        var nearest = window.__mnxFindNearestPageIndex(absoluteOffset);
        var response = SafeUtils.parseObj(window.__mnxGoToPageImmediate(nearest.pageIndex));
        response.found = true;
        return JSON.stringify(response);
      };
      window.__mnxClearVirtualOffset(true);
    `;
  }
}
