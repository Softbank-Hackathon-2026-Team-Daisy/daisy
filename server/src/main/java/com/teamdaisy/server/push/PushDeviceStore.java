package com.teamdaisy.server.push;

import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * {@code push_device} 를 JDBC 로 읽고 써요.
 *
 * <p>받는 사람 조회는 다른 폴더 테이블(account·project·project_member)을 읽기 전용으로만 봐요. 기준은 {@code
 * ProjectAccessService.requireRead}·{@code AuthService.resolve} 와 같아요: 보관되지 않은 프로젝트, 해제되지 않은 멤버십,
 * 비활성화되지 않은 계정이에요.
 */
@Repository
public class PushDeviceStore {
  private final NamedParameterJdbcTemplate jdbc;

  public PushDeviceStore(NamedParameterJdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  /** 발송 대상 기기예요. 토큰 원문은 로그에 남기지 않아요. */
  public record Device(String apnsToken, String accountId, String platform, String apnsEnv) {
    /** 로그용 토큰 끝 6자리예요. */
    public String tokenTail() {
      return tail(apnsToken);
    }
  }

  static String tail(String token) {
    return token == null || token.length() <= 6 ? "?" : token.substring(token.length() - 6);
  }

  /** 같은 토큰이면 지금 계정으로 옮기고 플랫폼·환경을 바꾸고 다시 켜요. */
  public void upsert(String accountId, String token, String platform, String apnsEnv) {
    jdbc.update(
        """
        insert into push_device(apns_token,account_id,platform,apns_env,created_at,updated_at)
        values(:token,:account,:platform,:env,now(),now())
        on conflict (apns_token) do update set account_id=excluded.account_id,
          platform=excluded.platform, apns_env=excluded.apns_env, updated_at=now(),
          disabled_at=null, last_error=null
        """,
        Map.of("token", token, "account", accountId, "platform", platform, "env", apnsEnv));
  }

  /** 호출한 계정의 토큰만 지워요. 없거나 남의 토큰이면 아무것도 하지 않아요. */
  public void delete(String accountId, String token) {
    jdbc.update(
        "delete from push_device where apns_token=:token and account_id=:account",
        Map.of("token", token, "account", accountId));
  }

  /** 프로젝트를 볼 수 있는 계정들의 켜진 기기예요. */
  public List<Device> recipients(String projectId) {
    return jdbc.query(
        """
        select d.apns_token,d.account_id,d.platform,d.apns_env
        from push_device d
        join account a on a.id=d.account_id and a.disabled_at is null
        join project_member m on m.account_id=d.account_id and m.project_id=:project
          and m.revoked_at is null
        join project p on p.id=m.project_id and p.archived_at is null
        where d.disabled_at is null
        order by d.apns_token
        """,
        Map.of("project", projectId),
        (rs, row) ->
            new Device(
                rs.getString("apns_token"),
                rs.getString("account_id"),
                rs.getString("platform"),
                rs.getString("apns_env")));
  }

  /** APNs 가 더는 받지 않는 토큰을 꺼요. 행은 남겨서 원인을 볼 수 있게 해요. */
  public void disable(String token, String reason) {
    jdbc.update(
        """
        update push_device set disabled_at=now(), last_error=:reason, updated_at=now()
        where apns_token=:token and disabled_at is null
        """,
        Map.of("token", token, "reason", reason));
  }
}
