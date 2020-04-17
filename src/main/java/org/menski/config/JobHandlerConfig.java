package org.menski.config;

import io.zeebe.client.api.command.CompleteJobCommandStep1;
import io.zeebe.client.api.worker.JobHandler;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.menski.Metrics;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@Slf4j
public class JobHandlerConfig {

  @Autowired public WorkerProperties workerProperties;

  @Autowired private Metrics metrics;

  @Bean
  public JobHandler jobHandler() {
    final ScheduledExecutorService executorService =
        Executors.newScheduledThreadPool(workerProperties.getConcurrency());

    return (client, job) -> {
      final long key = job.getKey();
      final CompleteJobCommandStep1 request =
          client
              .newCompleteCommand(key)
              .variables(
                  Map.of("jobCompleted", Map.of("time", System.currentTimeMillis(), "key", key)));

      executorService.schedule(
          () -> {
            request
                .send()
                .whenCompleteAsync(
                    (completeJobResponse, throwable) -> {
                      final long workflowKey = job.getWorkflowKey();
                      if (throwable == null) {
                        metrics.jobCompleted(workflowKey);
                      } else {
                        metrics.jobFailed(workflowKey);
                        metrics.recordError(workflowKey, throwable);
                      }
                    });
          },
          workerProperties.getCompletionDelay().toMillis(),
          TimeUnit.MILLISECONDS);
    };
  }
}
