package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;

import java.time.Clock;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.task.TaskSchedulingAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.transaction.PlatformTransactionManager;

class PushSchedulingTest {
  @Test
  void defaultScheduledTaskRunsWhilePushIsBlocked() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(TaskSchedulingAutoConfiguration.class))
        .withUserConfiguration(PushConfiguration.class, TestConfiguration.class)
        .withPropertyValues(
            "DAISY_APNS_KEY=",
            "DAISY_APNS_KEY_PATH=",
            "DAISY_APNS_KEY_ID=",
            "spring.threads.virtual.enabled=false",
            "daisy.push.dispatch-initial-delay-ms=10",
            "daisy.push.dispatch-delay-ms=60000")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              var probe = context.getBean(Probe.class);
              try {
                assertThat(probe.pushStarted.await(5, TimeUnit.SECONDS)).isTrue();
                assertThat(probe.defaultRan.await(5, TimeUnit.SECONDS)).isTrue();
                assertThat(probe.releasePush.getCount()).isEqualTo(1);
                assertThat(probe.pushThread.get()).startsWith("push-scheduler-");
                assertThat(probe.defaultThread.get()).doesNotStartWith("push-scheduler-");
                assertThat(context.getBean("pushTaskScheduler"))
                    .isNotSameAs(context.getBean("taskScheduler"));
                assertThat(
                        context
                            .getBean("taskScheduler", ThreadPoolTaskScheduler.class)
                            .getPoolSize())
                    .isEqualTo(1);
              } finally {
                probe.releasePush.countDown();
              }
            });
  }

  @Configuration(proxyBeanMethods = false)
  static class TestConfiguration {
    @Bean
    Clock clock() {
      return Clock.systemUTC();
    }

    @Bean
    Probe probe() {
      return new Probe();
    }

    @Bean
    PushDispatcher pushDispatcher(Probe probe) {
      // MOCK: 실제 DB·APNs 대신 발송 주기만 대기시켜 스케줄러 격리를 확인해요.
      var dispatcher =
          spy(
              new PushDispatcher(
                  mock(NamedParameterJdbcTemplate.class),
                  mock(PlatformTransactionManager.class),
                  mock(PushDeviceStore.class),
                  ApnsSender.disabled()));
      doAnswer(
              invocation -> {
                probe.pushThread.set(Thread.currentThread().getName());
                probe.pushStarted.countDown();
                if (!probe.releasePush.await(10, TimeUnit.SECONDS))
                  throw new IllegalStateException("test_push_release_timeout");
                return 0;
              })
          .when(dispatcher)
          .dispatchOnce();
      return dispatcher;
    }
  }

  static class Probe {
    final CountDownLatch pushStarted = new CountDownLatch(1);
    final CountDownLatch releasePush = new CountDownLatch(1);
    final CountDownLatch defaultRan = new CountDownLatch(1);
    final AtomicReference<String> pushThread = new AtomicReference<>();
    final AtomicReference<String> defaultThread = new AtomicReference<>();

    // Jenkins 워커와 같은 무지정 @Scheduled 작업이 푸시 대기 중에도 실행되어야 해요.
    @Scheduled(fixedDelay = 10)
    void tick() {
      if (pushStarted.getCount() == 0 && releasePush.getCount() == 1) {
        defaultThread.set(Thread.currentThread().getName());
        defaultRan.countDown();
      }
    }
  }
}
