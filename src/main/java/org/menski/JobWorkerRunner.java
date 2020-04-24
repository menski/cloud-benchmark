package org.menski;

import io.zeebe.client.ZeebeClient;
import io.zeebe.client.api.response.ActivatedJob;
import java.time.Duration;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
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

  @Autowired private Metrics metrics;

  private ScheduledExecutorService completionExecutor;
  private Semaphore pendingJobsSemaphore;

  @Override
  public void run(final String... args) {
    log.info("Worker configuration: {}", workerProperties);
    log.info("Zeebe client configuration: {}", zeebeClient.getConfiguration());
    log.info("Topology: {}", zeebeClient.newTopologyRequest().send().join());

    final int workerThreads = workerProperties.getThreads();
    final int workerCapacity = workerProperties.getCapacity();

    final ExecutorService executorService = Executors.newFixedThreadPool(workerThreads);

    completionExecutor = Executors.newScheduledThreadPool(workerThreads);
    pendingJobsSemaphore = new Semaphore(workerThreads * workerCapacity * 2);

    for (int i = 0; i < workerThreads; i++) {
      executorService.execute(this::runJobWorker);
    }
  }

  private void runJobWorker() {
    final long completionDelayMs = workerProperties.getCompletionDelay().toMillis();
    final int capacity = workerProperties.getCapacity();

    while (true) {
      try {
        pendingJobsSemaphore.acquire(capacity);
      } catch (InterruptedException e) {
        log.warn("Failed to acquire permit to acquire jobs", e);
        continue;
      }

      final List<ActivatedJob> jobs = activateJobs();

      if (jobs.size() < capacity) {
        pendingJobsSemaphore.release(capacity - jobs.size());
      }

      if (!jobs.isEmpty()) {
        completeJobs(jobs, completionDelayMs);
      }
    }
  }

  private List<ActivatedJob> activateJobs() {
    try {
      return zeebeClient
          .newActivateJobsCommand()
          .jobType(workerProperties.getTaskType())
          .maxJobsToActivate(workerProperties.getCapacity())
          .timeout(Duration.ofMinutes(5))
          .requestTimeout(Duration.ofSeconds(1))
          .send()
          .get()
          .getJobs();
    } catch (Exception e) {
      log.warn("Failed to activate jobs", e);
      return Collections.emptyList();
    }
  }

  private void completeJobs(final List<ActivatedJob> jobs, long completionDelayMs) {
    completionExecutor.schedule(
        () -> {
          jobs.forEach(
              j -> {
                metrics.incrementJobPartitionId(j.getKey());
                zeebeClient
                    .newCompleteCommand(j.getKey())
                    .send()
                    .whenCompleteAsync(
                        (completeJobResponse, throwable) -> {
                          final long workflowKey = j.getWorkflowKey();
                          if (throwable == null) {
                            metrics.jobCompleted(workflowKey);
                          } else {
                            metrics.jobFailed(workflowKey);
                            metrics.recordError(workflowKey, throwable);
                          }
                        });
                pendingJobsSemaphore.release(jobs.size());
              });
        },
        completionDelayMs,
        TimeUnit.MILLISECONDS);
  }
}
