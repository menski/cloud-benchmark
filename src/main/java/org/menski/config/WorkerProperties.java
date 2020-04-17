package org.menski.config;

import java.time.Duration;
import lombok.Data;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "zeebe.worker")
@Data
public class WorkerProperties {

  private int threads = 1;

  private int capacity = 30;

  private int concurrency = 4;

  private Duration completionDelay = Duration.ofMillis(100);

  private String taskType = "task";

  private Duration pollInterval = Duration.ofMillis(100);


}
