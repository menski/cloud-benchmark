package org.menski;

import io.zeebe.client.ZeebeClient;
import io.zeebe.client.api.worker.JobHandler;
import java.time.Duration;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import lombok.extern.slf4j.Slf4j;
import org.menski.config.WorkerProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Component;

@Component
@Slf4j
@ConditionalOnExpression("${workerEnabled:false}")
public class JobWorkerRunner implements CommandLineRunner {

  @Autowired public ZeebeClient zeebeClient;

  @Autowired public WorkerProperties workerProperties;

  @Autowired public JobHandler jobHandler;

  @Override
  public void run(final String... args) {
    log.info("Worker configuration: {}", workerProperties);
    log.info("Zeebe client configuration: {}", zeebeClient.getConfiguration());
    log.info("Topology: {}", zeebeClient.newTopologyRequest().send().join());

    final ExecutorService executorService =
        Executors.newFixedThreadPool(workerProperties.getThreads());

    for (int i = 0; i < workerProperties.getThreads(); i++) {
      executorService.execute(this::activateJobs);
    }
  }

  private void activateJobs() {
    while (true) {
      try {
        zeebeClient
            .newActivateJobsCommand()
            .jobType(workerProperties.getTaskType())
            .maxJobsToActivate(workerProperties.getCapacity())
            .timeout(workerProperties.getCompletionDelay().multipliedBy(10))
            .requestTimeout(Duration.ofSeconds(1))
            .send()
            .get()
            .getJobs()
            .forEach(
                activatedJob -> {
                  try {
                    jobHandler.handle(zeebeClient, activatedJob);
                  } catch (Exception e) {
                    log.warn("Failed to handle job {}", activatedJob.getKey(), e);
                  }
                });
      } catch (InterruptedException | ExecutionException e) {
        log.warn("Failed to activate jobs", e);
      }
    }
  }
}
