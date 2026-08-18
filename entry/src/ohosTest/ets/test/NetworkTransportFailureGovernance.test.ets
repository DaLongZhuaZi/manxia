import { describe, expect, it } from '@ohos/hypium';
import {
  NetworkTransportCircuitDecision,
  NetworkTransportFailureCoordinator,
  NetworkTransportFailureDescriptor,
  NetworkTransportFailureKind
} from '../../../main/ets/Framework/Network/NetworkTransportFailureCoordinator';
import {
  buildMangaImageRetryKey,
  MangaImageRetryCoordinator,
  MangaImageRetryDecision,
  MangaImageRetryPhase
} from '../../../main/ets/Framework/Reader/MangaImageRetryCoordinator';

export default function networkTransportFailureGovernanceTest() {
  describe('NetworkTransportFailureGovernance', () => {
    it('groupsDnsFailuresByHostWithoutUrlData', 0, () => {
      const coordinator: NetworkTransportFailureCoordinator =
        NetworkTransportFailureCoordinator.createIsolatedForTesting();
      const first: NetworkTransportFailureDescriptor = coordinator.describe(
        'https://cdn.example.test/chapter/1.jpg?token=secret',
        'Could not resolve the host name',
        '2300006'
      );
      const second: NetworkTransportFailureDescriptor = coordinator.describe(
        'https://cdn.example.test/chapter/2.jpg',
        'curlCode result 6',
        '2300006'
      );

      expect(first.kind).assertEqual(NetworkTransportFailureKind.DNS);
      expect(first.fingerprint).assertEqual(second.fingerprint);
      expect(first.fingerprint.includes('https://')).assertFalse();
      expect(first.fingerprint.includes('/chapter/')).assertFalse();
      expect(first.fingerprint.includes('token=')).assertFalse();
      expect(first.fingerprint.includes('cdn.example.test')).assertTrue();
    });

    it('suppressesOnlyBackgroundRequestsWhileCircuitIsOpen', 0, () => {
      const coordinator: NetworkTransportFailureCoordinator =
        NetworkTransportFailureCoordinator.createIsolatedForTesting();
      const url: string = 'https://cdn.example.test/chapter/page.jpg';
      coordinator.recordFailure(url, 'Could not resolve host', '2300006', 1000);

      const background: NetworkTransportCircuitDecision = coordinator.shouldSuppress(url, true, false, 1100);
      const visible: NetworkTransportCircuitDecision = coordinator.shouldSuppress(url, false, false, 1100);
      const manual: NetworkTransportCircuitDecision = coordinator.shouldSuppress(url, true, true, 1100);
      const expired: NetworkTransportCircuitDecision = coordinator.shouldSuppress(url, true, false, 22000);
      const tlsUrl: string = 'https://secure.example.test/chapter/page.jpg';
      coordinator.recordFailure(tlsUrl, 'TLS certificate handshake failed', '2300060', 1000);
      const tlsActive: NetworkTransportCircuitDecision = coordinator.shouldSuppress(tlsUrl, true, false, 30000);
      const tlsExpired: NetworkTransportCircuitDecision = coordinator.shouldSuppress(tlsUrl, true, false, 47000);

      expect(background.suppressed).assertTrue();
      expect(visible.suppressed).assertFalse();
      expect(manual.suppressed).assertFalse();
      expect(expired.suppressed).assertFalse();
      expect(tlsActive.suppressed).assertTrue();
      expect(tlsExpired.suppressed).assertFalse();
    });

    it('keepsDiagnosticAndLedgerDedupeWindowsIndependent', 0, () => {
      const coordinator: NetworkTransportFailureCoordinator =
        NetworkTransportFailureCoordinator.createIsolatedForTesting();
      const descriptor: NetworkTransportFailureDescriptor = coordinator.describe(
        'https://cdn.example.test/a.jpg',
        'Could not resolve host',
        '2300006'
      );

      expect(coordinator.claimDiagnosticError(descriptor.fingerprint, 1000)).assertTrue();
      expect(coordinator.claimDiagnosticError(descriptor.fingerprint, 1100)).assertFalse();
      expect(coordinator.claimDiagnosticError(descriptor.fingerprint, 32000)).assertTrue();
      expect(coordinator.claimLedgerRecord(descriptor.canonicalMessage, 1000)).assertTrue();
      expect(coordinator.claimLedgerRecord(descriptor.canonicalMessage, 59000)).assertFalse();
      expect(coordinator.claimLedgerRecord(descriptor.canonicalMessage, 61001)).assertTrue();
    });

    it('normalizesBareFingerprintLogProjectionAcrossLayers', 0, () => {
      const coordinator: NetworkTransportFailureCoordinator =
        NetworkTransportFailureCoordinator.createIsolatedForTesting();
      const logProjection: string =
        '请求最终失败（已按传输根因聚合）: fingerprint=network_transport|dns|cdn.example.test|2300006, background=true';
      const expectedFingerprint: string = 'network_transport|dns|cdn.example.test|2300006';

      expect(coordinator.extractFingerprint(logProjection)).assertEqual(expectedFingerprint);
      expect(coordinator.claimLedgerRecord(logProjection, 1000)).assertTrue();
      expect(coordinator.claimLedgerRecord(logProjection, 1100)).assertFalse();
    });

    it('classifiesLocalizedReaderTimeoutForPresentation', 0, () => {
      const coordinator: NetworkTransportFailureCoordinator =
        NetworkTransportFailureCoordinator.createIsolatedForTesting();
      const descriptor: NetworkTransportFailureDescriptor = coordinator.describe(
        'https://cdn.example.test/chapter/page.jpg?token=secret',
        '图片加载超时，请稍后重试'
      );

      expect(descriptor.kind).assertEqual(NetworkTransportFailureKind.TIMEOUT);
      expect(descriptor.fingerprint.includes('/chapter/')).assertFalse();
      expect(descriptor.fingerprint.includes('token=')).assertFalse();
    });

    it('doesNotAutomaticallyRetryBackgroundPageFailures', 0, () => {
      const coordinator: MangaImageRetryCoordinator = new MangaImageRetryCoordinator();
      const key: string = buildMangaImageRetryKey('chapter-1', 'background-page');
      const decision: MangaImageRetryDecision = coordinator.recordFailure(key, 'transport failed', false);

      expect(decision.shouldRetry).assertFalse();
      expect(decision.showTerminalError).assertTrue();
      expect(coordinator.getPhase(key)).assertEqual(MangaImageRetryPhase.TERMINAL);
      expect(coordinator.isLoading(key)).assertFalse();
    });
  });
}
