package com.teamdaisy.server.common.json;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.DoubleNode;
import com.fasterxml.jackson.databind.node.POJONode;
import com.teamdaisy.server.common.error.DaisyException;
import org.junit.jupiter.api.Test;

class CanonicalJsonTest {
  private final ObjectMapper mapper = new ObjectMapper();
  private final CanonicalJson json = new CanonicalJson(mapper);

  @Test
  void sortedObjectsPreserveArrayOrderAndExplicitNull() throws Exception {
    var a = mapper.readTree("{\"z\":[{\"b\":2,\"a\":1},null],\"a\":null}");
    var b = mapper.readTree("{\"a\":null,\"z\":[{\"a\":1,\"b\":2},null]}");
    assertEquals(json.canonicalize(a), json.canonicalize(b));
    assertEquals(json.hash(a), json.hash(b));
    assertTrue(json.hash(a).matches("sha256:[0-9a-f]{64}"));
    assertNotEquals(json.hash(mapper.readTree("{}")), json.hash(mapper.readTree("{\"a\":null}")));
    assertNotEquals(json.hash(mapper.readTree("[1,2]")), json.hash(mapper.readTree("[2,1]")));
    assertEquals(
        "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
        json.hash(mapper.readTree("{}")));
  }

  @Test
  void rejectsNonJsonNonFiniteAndOversizedUtf8AndCopiesDeeply() {
    assertThrows(DaisyException.class, () -> json.hash(DoubleNode.valueOf(Double.NaN)));
    assertThrows(DaisyException.class, () -> json.copy(new POJONode(new Object())));
    assertThrows(
        DaisyException.class, () -> json.hash(mapper.getNodeFactory().textNode("한".repeat(90000))));
    var original = mapper.createObjectNode().set("nested", mapper.createObjectNode().put("a", 1));
    var copy = json.copy(original);
    ((com.fasterxml.jackson.databind.node.ObjectNode) original.get("nested")).put("a", 2);
    assertEquals(1, copy.path("nested").path("a").asInt());
  }
}
