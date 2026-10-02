package com.teamdaisy.server.history.application;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;

/** Only sanitized, public callback fields belong here; never raw plan/state/console bodies. */
public record DeploymentEvent(
    String source,
    String sourceEventId,
    Long sourceSequence,
    String executionId,
    String deploymentTargetId,
    String eventType,
    String stageOccurrenceId,
    String step,
    String level,
    String message,
    JsonNode payload,
    String processingResult,
    String sourceStream,
    Long sourceOffset,
    Long sourceEndOffset,
    Instant occurredAt) {}
