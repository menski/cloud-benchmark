package org.menski;

import java.util.HashMap;

public class Payload extends HashMap<String, Object> {

  public Payload startTime(long startTime) {
    put("startTime", startTime);
    return this;
  }

  public Payload requestId(int requestId) {
    put("requestId", requestId);
    return this;
  }

}
