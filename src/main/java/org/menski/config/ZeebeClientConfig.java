package org.menski.config;

import io.zeebe.client.ZeebeClient;
import io.zeebe.client.ZeebeClientBuilder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;

@Configuration
public class ZeebeClientConfig {

  @Value("${zeebe.address:localhost:26500}")
  private String address;

  @Value("${zeebe.client.id:#{null}}")
  private String clientId;

  @Autowired
  public WorkerProperties workerProperties;

  @Bean
  public ZeebeClient zeebeClient() {
    final ZeebeClientBuilder builder = ZeebeClient.newClientBuilder()
        .brokerContactPoint(address)
        .numJobWorkerExecutionThreads(0);

    if (clientId == null) {
      builder.usePlaintext();
    }

    return builder.build();
  }

}
