package org.menski;

import io.zeebe.client.ZeebeClient;
import io.zeebe.client.api.command.DeployWorkflowCommandStep1.DeployWorkflowCommandBuilderStep2;
import io.zeebe.model.bpmn.BpmnModelInstance;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import lombok.extern.slf4j.Slf4j;
import org.menski.config.StarterProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Component;

@Component
@Slf4j
@ConditionalOnExpression("${starterEnabled:false}")
public class WorkflowStarterRunner implements CommandLineRunner {

  @Autowired public ZeebeClient zeebeClient;

  @Autowired public StarterProperties starterProperties;

  @Autowired public BpmnModelInstance bpmnModelInstance;

  @Autowired public Payload payload;

  @Autowired private Metrics metrics;

  @Override
  public void run(final String... args) throws Exception {
    log.info("Starter configuration: {}", starterProperties);
    log.info("Zeebe client configuration: {}", zeebeClient.getConfiguration());
    log.info("Topology: {}", zeebeClient.newTopologyRequest().send().join());

    var workflowKey = deployWorkflow();
    log.info("Workflow deployed with key {}", workflowKey);

    startWorkflows(workflowKey);
  }

  public long deployWorkflow() {
    final DeployWorkflowCommandBuilderStep2 request =
        zeebeClient.newDeployCommand().addWorkflowModel(bpmnModelInstance, "process.bpmn");

    while (true) {
      try {
        return request.send().get().getWorkflows().get(0).getWorkflowKey();
      } catch (Exception e) {
        log.warn("Failed to deploy workflow", e);
      }
    }
  }

  public void startWorkflows(long workflowKey) throws InterruptedException {
    final ScheduledExecutorService executorService = Executors.newScheduledThreadPool(2);
    final AtomicInteger requestId = new AtomicInteger();

    final long delayMs =
        Duration.ofMinutes(1).dividedBy(starterProperties.getRatePerMinute()).toMillis();

    executorService.scheduleAtFixedRate(() -> {
      zeebeClient
          .newCreateInstanceCommand()
          .workflowKey(workflowKey)
          .variables(payload.requestId(requestId.getAndIncrement()).startTime(System.currentTimeMillis()))
          .send()
          .whenCompleteAsync(
              (workflowInstanceEvent, throwable) -> {
                if (throwable == null) {
                  metrics.instanceStarted(workflowKey);
                  metrics.incrementInstancePartitionId(workflowInstanceEvent.getWorkflowInstanceKey());
                } else {
                  metrics.instanceFailed(workflowKey);
                  metrics.recordError(workflowKey, throwable);
                }
              });

    }, 0, delayMs, TimeUnit.MILLISECONDS);
  }
}
