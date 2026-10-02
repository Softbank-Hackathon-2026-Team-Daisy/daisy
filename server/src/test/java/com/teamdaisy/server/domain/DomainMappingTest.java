package com.teamdaisy.server.domain;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.ai.domain.AiUsage;
import com.teamdaisy.server.deployment.domain.Approval;
import com.teamdaisy.server.deployment.domain.Deployment;
import com.teamdaisy.server.deployment.domain.DeploymentStatus;
import com.teamdaisy.server.deployment.domain.DeploymentTarget;
import com.teamdaisy.server.deployment.domain.DeploymentTargetStatus;
import com.teamdaisy.server.deployment.domain.PlanRevision;
import com.teamdaisy.server.history.domain.DeploymentLog;
import com.teamdaisy.server.history.domain.ProjectEvent;
import com.teamdaisy.server.idempotency.domain.Idempotency;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.jenkins.domain.ExecutionTarget;
import com.teamdaisy.server.jenkins.domain.ExecutionTargetId;
import com.teamdaisy.server.jenkins.domain.JenkinsExecution;
import com.teamdaisy.server.jenkins.domain.TargetLock;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberId;
import com.teamdaisy.server.project.domain.SourceVersion;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.script.domain.Script;
import jakarta.persistence.AttributeConverter;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Arrays;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.hibernate.boot.Metadata;
import org.hibernate.boot.MetadataSources;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.hibernate.boot.spi.MetadataImplementor;
import org.hibernate.mapping.Column;
import org.hibernate.mapping.SimpleValue;
import org.junit.jupiter.api.Test;

class DomainMappingTest {
  private static final Class<?>[] ENTITIES = {
    Account.class,
    Project.class,
    ProjectMember.class,
    Target.class,
    SourceVersion.class,
    Deployment.class,
    DeploymentTarget.class,
    JenkinsExecution.class,
    ExecutionTarget.class,
    PlanRevision.class,
    Approval.class,
    Script.class,
    AiUsage.class,
    DeploymentLog.class,
    ProjectEvent.class,
    Idempotency.class,
    TargetLock.class
  };

  @Test
  void allMappingsMatchTheCheckedInDictionaryWithoutDatabaseAccess() throws IOException {
    var registry =
        new StandardServiceRegistryBuilder()
            .applySetting("hibernate.boot.allow_jdbc_metadata_access", false)
            .applySetting("hibernate.dialect", "org.hibernate.dialect.PostgreSQLDialect")
            .build();
    try {
      var sources = new MetadataSources(registry);
      for (var entity : ENTITIES) {
        sources.addAnnotatedClass(entity);
      }
      Metadata metadata = sources.buildMetadata();
      ((MetadataImplementor) metadata).validate();
      var dictionary = dictionary();
      assertEquals(17, dictionary.size());
      var mappedTables =
          metadata.getEntityBindings().stream()
              .map(binding -> binding.getTable().getName())
              .collect(Collectors.toSet());
      assertEquals(dictionary.keySet(), mappedTables);
      for (var binding : metadata.getEntityBindings()) {
        var table = binding.getTable();
        String section = dictionary.get(table.getName());
        var columnRows =
            Pattern.compile("(?m)^\\| ([a-z_]+) \\| ([^|]+) \\| (NN|NULL) / [^|]+ \\|.*$")
                .matcher(section);
        Map<String, ColumnSpec> expected = new LinkedHashMap<>();
        while (columnRows.find()) {
          expected.put(
              columnRows.group(1),
              new ColumnSpec(columnRows.group(2).trim(), columnRows.group(3).equals("NULL")));
        }
        assertFalse(expected.isEmpty(), table.getName());
        assertEquals(expected.keySet(), columnNames(table.getColumns()), table.getName());
        for (Column column : table.getColumns()) {
          var spec = expected.get(column.getName());
          String label = table.getName() + "." + column.getName();
          assertEquals(spec.nullable(), column.isNullable(), label);
          String sqlType =
              spec.type().equals("ID") ? "varchar(64)" : spec.type().replace(" identity", "");
          assertEquals(sqlType, column.getSqlType(metadata), label);
          if (spec.type().equals("jsonb")) {
            assertEquals(JsonNode.class, column.getValue().getType().getReturnedClass(), label);
          } else if (spec.type().equals("timestamptz")) {
            assertEquals(Instant.class, column.getValue().getType().getReturnedClass(), label);
          } else if (spec.type().equals("numeric(20,10)")) {
            assertEquals(BigDecimal.class, column.getValue().getType().getReturnedClass(), label);
            assertEquals(20, column.getPrecision(), label);
            assertEquals(10, column.getScale(), label);
          }
        }
        String constraints =
            section.lines().filter(line -> line.startsWith("PK(")).findFirst().orElseThrow();
        var primaryKey = Pattern.compile("^PK\\(([^)]+)\\)").matcher(constraints);
        assertTrue(primaryKey.find(), table.getName());
        assertEquals(csv(primaryKey.group(1)), columnNames(table.getPrimaryKey().getColumns()));
        Set<Set<String>> expectedUnique = new java.util.HashSet<>();
        var unique = Pattern.compile("(?<!부분 )UNIQUE\\(([^)]+)\\)").matcher(constraints);
        while (unique.find()) {
          expectedUnique.add(csv(unique.group(1)));
        }
        var actualUnique =
            table.getUniqueKeys().values().stream()
                .map(key -> columnNames(key.getColumns()))
                .collect(Collectors.toSet());
        assertEquals(expectedUnique, actualUnique, table.getName() + " UNIQUE");
        boolean versioned =
            table.getName().equals("deployment") || table.getName().equals("deployment_target");
        assertEquals(versioned, binding.getVersion() != null, table.getName() + " version");
        if (versioned) {
          assertEquals("version", binding.getVersion().getName());
        }
        if (binding.getIdentifier() instanceof SimpleValue identifier) {
          String strategy = identifier.getIdentifierGeneratorStrategy();
          boolean generated =
              expected.values().stream().anyMatch(c -> c.type().equals("bigint identity"));
          assertEquals(
              generated ? "identity" : "assigned", strategy, table.getName() + " identifier");
        }
        assertTrue(table.getForeignKeys().isEmpty(), "Scalar IDs defer FK DDL to Flyway");
      }
    } finally {
      StandardServiceRegistryBuilder.destroy(registry);
    }
  }

  @Test
  void compositeKeysUseBothPartsForEqualityAndHashing() {
    var member = new ProjectMemberId("prj_1", "account_1");
    assertEquals(member, new ProjectMemberId("prj_1", "account_1"));
    assertEquals(member.hashCode(), new ProjectMemberId("prj_1", "account_1").hashCode());
    assertNotEquals(member, new ProjectMemberId("prj_2", "account_1"));
    assertNotEquals(member, new ProjectMemberId("prj_1", "account_2"));
    assertNotEquals(member, null);
    assertNotEquals(member, "prj_1");
    var execution = new ExecutionTargetId("job_1", "dt_1");
    assertEquals(execution, new ExecutionTargetId("job_1", "dt_1"));
    assertEquals(execution.hashCode(), new ExecutionTargetId("job_1", "dt_1").hashCode());
    assertNotEquals(execution, new ExecutionTargetId("job_2", "dt_1"));
    assertNotEquals(execution, new ExecutionTargetId("job_1", "dt_2"));
    assertNotEquals(execution, null);
    assertNotEquals(execution, member);
  }

  @Test
  void settledStatusesPersistTheirExactLowercaseCodes() {
    checkConverter(
        new DeploymentStatus.Converter(),
        DeploymentStatus.values(),
        new String[] {
          "queued",
          "running",
          "awaiting_approval",
          "succeeded",
          "partially_succeeded",
          "failed",
          "cancelled"
        });
    checkConverter(
        new DeploymentTargetStatus.Converter(),
        DeploymentTargetStatus.values(),
        new String[] {
          "waiting",
          "generating",
          "validating",
          "awaiting_approval",
          "applying",
          "verifying",
          "succeeded",
          "failed",
          "cancelled"
        });
  }

  private static <T> void checkConverter(
      AttributeConverter<T, String> converter, T[] values, String[] codes) {
    assertEquals(codes.length, values.length);
    for (int i = 0; i < codes.length; i++) {
      assertEquals(codes[i], converter.convertToDatabaseColumn(values[i]));
      assertEquals(values[i], converter.convertToEntityAttribute(codes[i]));
    }
    assertNull(converter.convertToDatabaseColumn(null));
    assertNull(converter.convertToEntityAttribute(null));
    for (String invalid : new String[] {"", "SUCCEEDED", "canceled", "unknown", " succeeded "}) {
      assertThrows(
          IllegalArgumentException.class, () -> converter.convertToEntityAttribute(invalid));
    }
  }

  // Read only §5 dictionary tables, excluding diagrams, state prose, and the optional device
  // appendix.
  private static Map<String, String> dictionary() throws IOException {
    String document = Files.readString(Path.of("docs/database-design.md"));
    var sections =
        Pattern.compile("(?ms)^### 5\\.\\d+ ([a-z_]+)[^\\n]*\\n(.*?)(?=^### 5\\.|^## 6\\.)")
            .matcher(document);
    Map<String, String> result = new LinkedHashMap<>();
    while (sections.find()) {
      assertNull(result.put(sections.group(1), sections.group(2)), "Duplicate dictionary table");
    }
    return result;
  }

  private static Set<String> columnNames(Collection<Column> columns) {
    return columns.stream().map(Column::getName).collect(Collectors.toSet());
  }

  private static Set<String> csv(String names) {
    return Arrays.stream(names.split(",")).map(String::trim).collect(Collectors.toSet());
  }

  private record ColumnSpec(String type, boolean nullable) {}
}
