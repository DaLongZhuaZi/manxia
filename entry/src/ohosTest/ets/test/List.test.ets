import legadoCompatibilityConformanceTest from './LegadoCompatibilityConformance.test';
import loggerBackgroundOutputConformanceTest from './LoggerBackgroundOutputConformance.test';
import networkTransportFailureGovernanceTest from './NetworkTransportFailureGovernance.test';
import legadoCancellationConformanceTest from './LegadoCancellationConformance.test';

export default function testsuite() {
  legadoCompatibilityConformanceTest();
  loggerBackgroundOutputConformanceTest();
  networkTransportFailureGovernanceTest();
  legadoCancellationConformanceTest();
}
