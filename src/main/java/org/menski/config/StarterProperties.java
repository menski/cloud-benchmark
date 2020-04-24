package org.menski.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.zeebe.model.bpmn.Bpmn;
import io.zeebe.model.bpmn.BpmnModelInstance;
import java.io.IOException;
import java.io.InputStream;
import lombok.Data;
import lombok.SneakyThrows;
import org.menski.Payload;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties("zeebe.starter")
@Data
public class StarterProperties {

  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

  public String bpmn = "parallel-tasks.bpmn";
  public String payload = "loop.json";

  public int ratePerMinute = 60;

  @Bean
  @SneakyThrows
  public BpmnModelInstance bpmnModelInstance() {
    return Bpmn.readModelFromStream(readResourceAsStream("/bpmn/" + bpmn));
  }

  @Bean
  @SneakyThrows
  public Payload payload() {
    return OBJECT_MAPPER.readValue(readResourceAsStream("/payload/" + payload), Payload.class);
  }

  private InputStream readResourceAsStream(String name) throws IOException {
    final InputStream resourceAsStream = StarterProperties.class.getResourceAsStream(name);
    if (resourceAsStream == null) {
      throw new IOException("Unable to find resource with name " + name);
    }
    return resourceAsStream;
  }

}
