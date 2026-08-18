import { describe, expect, it } from '@ohos/hypium';
import {
  LegadoExecutionCancellationToken
} from '../../../main/ets/Framework/Novel/LegadoExecutionCancellation';
import {
  awaitNovelSourceValidationTask
} from '../../../main/ets/Framework/Novel/NovelSourceValidationDeadline';
import { LegadoTransportRouter } from '../../../main/ets/Framework/Novel/LegadoRequestPipeline';
import {
  LegadoWorkflowKind,
  RequestSpec
} from '../../../main/ets/Framework/Novel/LegadoCompatibilityTypes';

function waitForFixtureDelay(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, delayMs);
  });
}

export default function legadoCancellationConformanceTest() {
  describe('LegadoCancellationConformance', () => {
    it('notifiesActiveListenersExactlyOnceAndHonorsUnregister', 0, () => {
      const token = new LegadoExecutionCancellationToken();
      let activeCalls = 0;
      let removedCalls = 0;
      let observedReason = '';
      token.register((reason: string): void => {
        activeCalls += 1;
        observedReason = reason;
      });
      const removedId = token.register((_reason: string): void => {
        removedCalls += 1;
      });
      token.unregister(removedId);

      token.cancel('fixture_cancel');
      token.cancel('ignored_second_cancel');

      expect(token.isCancelled()).assertTrue();
      expect(token.getReason()).assertEqual('fixture_cancel');
      expect(observedReason).assertEqual('fixture_cancel');
      expect(activeCalls).assertEqual(1);
      expect(removedCalls).assertEqual(0);
    });

    it('blocksTransportBeforeARequestCanBeDispatched', 0, async () => {
      const request = new RequestSpec(
        'cancel-before-dispatch',
        'https://fixture.invalid/source',
        LegadoWorkflowKind.SEARCH,
        'https://fixture.invalid/must-not-dispatch',
        'GET',
        '',
        [],
        'UTF-8',
        0,
        '',
        false,
        false,
        '',
        '',
        0,
        0,
        'text',
        'follow',
        []
      );
      const token = new LegadoExecutionCancellationToken();
      token.cancel('pre_dispatch');
      let failure = '';
      try {
        await new LegadoTransportRouter().execute(request, token);
      } catch (error) {
        failure = String(error);
      }
      expect(failure).assertContain('LEGADO_EXECUTION_CANCELLED:pre_dispatch');
    });

    it('clearsValidationDeadlineAfterSuccess', 0, async () => {
      const token = new LegadoExecutionCancellationToken();
      await awaitNovelSourceValidationTask(
        async (): Promise<void> => {
          await waitForFixtureDelay(1);
        },
        20,
        token,
        'fixture_timeout'
      );
      await waitForFixtureDelay(40);
      expect(token.isCancelled()).assertFalse();
    });

    it('clearsValidationDeadlineAfterFailure', 0, async () => {
      const token = new LegadoExecutionCancellationToken();
      let failure = '';
      try {
        await awaitNovelSourceValidationTask(
          async (): Promise<void> => {
            throw new Error('fixture_failure');
          },
          20,
          token,
          'fixture_timeout'
        );
      } catch (error) {
        failure = String(error);
      }
      await waitForFixtureDelay(40);
      expect(failure).assertContain('fixture_failure');
      expect(token.isCancelled()).assertFalse();
    });

    it('cancelsActiveValidationTaskWhenDeadlineExpires', 0, async () => {
      const token = new LegadoExecutionCancellationToken();
      let activeCancellationReason = '';
      let failure = '';
      try {
        await awaitNovelSourceValidationTask(
          (): Promise<void> => {
            return new Promise<void>((resolve: () => void): void => {
              token.register((reason: string): void => {
                activeCancellationReason = reason;
                resolve();
              });
            });
          },
          10,
          token,
          'fixture_timeout'
        );
      } catch (error) {
        failure = String(error);
      }
      expect(token.isCancelled()).assertTrue();
      expect(token.getReason()).assertEqual('fixture_timeout');
      expect(activeCancellationReason).assertEqual('fixture_timeout');
      expect(failure).assertContain('LEGADO_EXECUTION_CANCELLED:fixture_timeout');
    });

    it('doesNotStartValidationTaskAfterPreCancellation', 0, async () => {
      const token = new LegadoExecutionCancellationToken();
      token.cancel('pre_validation_cancel');
      let taskStarted = false;
      let failure = '';
      try {
        await awaitNovelSourceValidationTask(
          async (): Promise<void> => {
            taskStarted = true;
          },
          20,
          token,
          'fixture_timeout'
        );
      } catch (error) {
        failure = String(error);
      }
      expect(taskStarted).assertFalse();
      expect(failure).assertContain('LEGADO_EXECUTION_CANCELLED:pre_validation_cancel');
    });
  });
}
