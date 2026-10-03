package com.teamdaisy.server.common.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.core.converter.ModelConverters;
import io.swagger.v3.core.jackson.ModelResolver;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.responses.ApiResponse;
import java.util.List;
import java.util.Set;
import org.springdoc.core.customizers.OpenApiCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfiguration {
  @Bean
  ModelResolver apiModelResolver(ObjectMapper mapper) {
    // Use the HTTP mapper's naming/modules so documented fields match real JSON.
    return new ModelResolver(mapper).openapi31(true);
  }

  @Bean
  OpenApiCustomizer apiDocumentation() {
    return api -> {
      api.setInfo(
          new Info()
              .title("Unibloom 서버 API")
              .version("v1")
              .description(
                  "REST는 Bearer 인증을 사용해요. 준비된 데모 계정이나 POST /auth/signup 으로 만든 계정으로 로그인해요. "
                      + "SSE는 Last-Event-ID로 재연결하며, Jenkins 내부 콜백은 별도 서비스 토큰이 필요해요. "
                      + "null은 미확인/미제공이에요. Swagger에 경로가 있다고 실제 외부 인프라 연결까지 완료된 것은 아니에요."));
      ModelConverters.getInstance(true)
          .read(ErrorResponse.class)
          .forEach(api.getComponents()::addSchemas);
      // swagger-core emits nullable record references as type:null + $ref (an impossible
      // intersection).
      // OpenAPI 3.1 needs a union; leave ordinary references and nullable scalars/arrays unchanged.
      api.getComponents()
          .getSchemas()
          .values()
          .forEach(
              model -> {
                Schema<?> typedModel = model;
                if (typedModel.getProperties() == null) return;
                typedModel
                    .getProperties()
                    .values()
                    .forEach(
                        property -> {
                          if (property.get$ref() != null
                              && property.getTypes() != null
                              && property.getTypes().contains("null")) {
                            String reference = property.get$ref();
                            property.set$ref(null);
                            property.setTypes(null);
                            property.setType(null);
                            property.setAnyOf(
                                List.of(
                                    new Schema<>().$ref(reference),
                                    new Schema<>().types(Set.of("null"))));
                          }
                        });
              });
      api.getPaths()
          .values()
          .forEach(
              path ->
                  path.readOperations()
                      .forEach(
                          operation ->
                              operation
                                  .getResponses()
                                  .addApiResponse(
                                      "default",
                                      new ApiResponse()
                                          .description(
                                              "오류 봉투예요. 400 입력 오류, 401 인증, 403 쓰기 권한, 404 접근 가능한 대상 없음, "
                                                  + "409 상태/멱등 충돌, 429 연결 한도, 500 내부 오류를 구분해요. 지원하지 않는 메서드/본문 형식은 405/415예요.")
                                          .content(
                                              new Content()
                                                  .addMediaType(
                                                      "application/json",
                                                      new MediaType()
                                                          .schema(
                                                              new Schema<>()
                                                                  .$ref(
                                                                      "#/components/schemas/ErrorResponse")))))));
    };
  }
}
