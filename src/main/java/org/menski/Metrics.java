package org.menski;

import io.grpc.Status.Code;
import io.grpc.StatusRuntimeException;
import io.micrometer.core.instrument.MeterRegistry;
import io.zeebe.protocol.Protocol;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
@Slf4j
public class Metrics {

  @Autowired private MeterRegistry registry;

  public void recordError(long workflowKey, Throwable throwable) {
    if (throwable instanceof StatusRuntimeException) {
      recordError(workflowKey, ((StatusRuntimeException) throwable).getStatus().getCode());
    } else {
      log.warn("Unexpected exception while creating instance", throwable);
      recordError(workflowKey, Code.UNKNOWN);
    }
  }

  public void recordError(long workflowKey, Code code) {
    incrementCounter(
        "zeebe.benchmark.errors",
        1,
        "workflowKey",
        String.valueOf(workflowKey),
        "code",
        code.name());
  }

  public void instanceStarted(long workflowKey) {
    incrementCounter(
        "zeebe.benchmark.instances",
        1,
        "workflowKey",
        String.valueOf(workflowKey),
        "type",
        "started");
  }

  public void instanceFailed(long workflowKey) {
    incrementCounter(
        "zeebe.benchmark.instances",
        1,
        "workflowKey",
        String.valueOf(workflowKey),
        "type",
        "failed");
  }

  public void jobCompleted(long workflowKey) {
    incrementCounter(
        "zeebe.benchmark.jobs", 1, "workflowKey", String.valueOf(workflowKey), "type", "completed");
  }

  public void jobFailed(long workflowKey) {
    incrementCounter(
        "zeebe.benchmark.jobs", 1, "workflowKey", String.valueOf(workflowKey), "type", "failed");
  }

  public void incrementCounter(String name, long count, String... tags) {
    registry.counter(name, tags).increment(count);
  }

  public void incrementInstancePartitionId(long workflowInstanceKey) {
    final int partitionId = Protocol.decodePartitionId(workflowInstanceKey);
    incrementCounter("zeebe.benchmark.instancePartition", 1, "partitionId", String.valueOf(
        partitionId));
  }

  public void incrementJobPartitionId(long jobKey) {
    final int partitionId = Protocol.decodePartitionId(jobKey);
    incrementCounter("zeebe.benchmark.jobPartition", 1, "partitionId", String.valueOf(
        partitionId));
  }
}
