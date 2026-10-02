package com.teamdaisy.server.project.domain;

import java.util.Map;

/**
 * 환경 화면(W-10)에 보여 줄 대상 구성 설명이에요 (WR-04 선택 필드, #13).
 *
 * <p><b>대상 {@code config} 에 두지 않아요.</b> {@code config} 는 배포를 만들 때 {@code target_snapshot} 으로 고정되고
 * {@code input_hash} 와 재시도 검사({@code config_revision})에 들어가요. 표시용 값 때문에 실행 입력을 바꾸면 진행 중인 배포의 재시도가
 * 409 가 돼요. 데모 대상 설명은 여기 표로 두고, 실제 대상 등록 절차가 생기면 저장 위치를 정해요.
 *
 * <p>값은 인프라 공유 구성이에요 (채준 10/2 정리와 #89). Azure는 준비 예정 구성이며, 이 표는 실행 준비나 연결 성공을 보장하지 않아요.
 *
 * @param locationLabel 웹 {@code types.ts} 의 {@code '위치' | '리전'} 중 하나예요
 */
public record TargetProfile(
    String runtime,
    String location,
    String locationLabel,
    String accessMethod,
    String exposure,
    String stateBackend) {

  private static final Map<String, TargetProfile> DEMO =
      Map.of(
          "tgt_demo_aws",
          new TargetProfile(
              "ECS Fargate · ALB",
              "ap-northeast-2 서울",
              "리전",
              "Jenkins → AWS API",
              "https://aws.unibloom.cloud",
              "S3 (잠금)"),
          "tgt_demo_gcp",
          new TargetProfile(
              "Cloud Run",
              "asia-northeast1 도쿄",
              "리전",
              "Jenkins → GCP API",
              "https://gcp.unibloom.cloud",
              "GCS (잠금)"),
          "tgt_demo_azure",
          new TargetProfile(
              "Container Apps",
              "koreacentral 서울",
              "리전",
              "Jenkins → Azure API",
              "https://azure.unibloom.cloud",
              "Azure Blob (잠금)"),
          "tgt_demo_onprem",
          new TargetProfile(
              "Docker · Proxmox Service VM",
              "172.16.1.5",
              "위치",
              "Jenkins → SSH",
              "https://onprem.unibloom.cloud (ngrok)",
              "Jenkins 러너 로컬 (flock)"));

  /** 표에 없는 대상은 null 이에요. 빈 값으로 채우지 않아요. */
  public static TargetProfile of(String targetId) {
    return targetId == null ? null : DEMO.get(targetId);
  }
}
