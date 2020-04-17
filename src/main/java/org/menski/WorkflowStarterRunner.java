package org.menski;

import io.zeebe.client.ZeebeClient;
import io.zeebe.client.api.command.DeployWorkflowCommandStep1.DeployWorkflowCommandBuilderStep2;
import io.zeebe.model.bpmn.BpmnModelInstance;
import java.util.concurrent.Semaphore;
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
    final Semaphore semaphore = new Semaphore(starterProperties.getConcurrency());
    int requestId = 0;

    while (true) {
      semaphore.acquire();
      zeebeClient
          .newCreateInstanceCommand()
          .workflowKey(workflowKey)
          .variables(payload.requestId(requestId++).startTime(System.currentTimeMillis()))
          .send()
          .whenCompleteAsync(
              (workflowInstanceEvent, throwable) -> {
                semaphore.release();
                if (throwable == null) {
                  metrics.instanceStarted(workflowKey);
                } else {
                  metrics.instanceFailed(workflowKey);
                  metrics.recordError(workflowKey, throwable);
                }
              });
    }
  }
}
