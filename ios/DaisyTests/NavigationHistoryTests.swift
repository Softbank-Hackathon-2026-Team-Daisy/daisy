import Testing
@testable import Daisy

/// 뒤로 · 앞으로 (10/3): 웹 브라우저처럼 메뉴 + 경로를 한 줄 기록으로 오가요
@MainActor
struct NavigationHistoryTests {
    private func at(_ tab: AppTab, _ path: [Route] = []) -> NavigationLocation {
        NavigationLocation(tab: tab, path: path)
    }

    // MARK: 기록 모델

    @Test func recordsAndSkipsDuplicates() {
        let history = NavigationHistory()
        #expect(history.current == at(.overview))
        #expect(!history.canGoBack && !history.canGoForward)

        history.record(at(.overview))   // 같은 위치를 다시 써도 그대로
        #expect(history.entries.count == 1)

        history.record(at(.deployments))
        history.record(at(.deployments, [.run("d1")]))
        #expect(history.entries.count == 3)
        #expect(history.canGoBack && !history.canGoForward)
    }

    @Test func backForwardAndTruncate() {
        let history = NavigationHistory()
        history.record(at(.deployments))
        history.record(at(.history))

        #expect(history.back() == at(.deployments))
        #expect(history.back() == at(.overview))
        #expect(history.back() == nil)
        #expect(history.forward() == at(.deployments))
        #expect(history.canGoForward)

        // 뒤로 간 다음 새로 이동하면 앞쪽 기록은 지워요
        history.record(at(.settings))
        #expect(!history.canGoForward)
        #expect(history.entries == [at(.overview), at(.deployments), at(.settings)])
        #expect(history.forward() == nil)
    }

    @Test func noRecordingWhileRestoring() {
        let history = NavigationHistory()
        history.restoring {
            history.record(at(.scripts))
            history.recordPop(at(.overview))
        }
        #expect(history.entries == [at(.overview)])
        #expect(!history.isRestoring)
    }

    @Test func capsAtLimit() {
        let history = NavigationHistory(limit: 5)
        for index in 0..<10 { history.record(at(.deployments, [.run("d\(index)")])) }
        #expect(history.entries.count == 5)
        #expect(history.current == at(.deployments, [.run("d9")]))
        #expect(history.entries.first == at(.deployments, [.run("d5")]))
        #expect(history.index == 4)
        #expect(NavigationHistory().limit == 50)
    }

    @Test func popMatchingPreviousEntryKeepsForward() {
        let history = NavigationHistory()
        history.record(at(.overview, [.run("d1")]))
        history.recordPop(at(.overview))
        #expect(history.index == 0)
        #expect(history.canGoForward)

        // 앞 칸과 다르면 새 이동이에요
        history.record(at(.history, [.run("d1"), .logs(deploymentID: "d1", targetID: nil)]))
        history.recordPop(at(.history, [.run("d1")]))
        #expect(history.current == at(.history, [.run("d1")]))
        #expect(!history.canGoForward)
    }

    @Test func clearKeepsOnlyGivenLocation() {
        let history = NavigationHistory()
        history.record(at(.deployments))
        history.record(at(.history))
        _ = history.back()
        history.clear(at: at(.settings))
        #expect(history.entries == [at(.settings)])
        #expect(!history.canGoBack && !history.canGoForward)
    }

    // MARK: Router

    @Test func routerRecordsEveryNavigation() {
        let router = Router()
        router.tab = .deployments                          // 메뉴 바꾸기
        router.push(.newDeployment)                        // 들어가기
        router.replaceTop(with: .selectTargets(commit: "c1"))
        router.open(.plan("d1"), in: .overview)            // 메뉴 + 화면을 한 칸으로
        router.popToRoot()
        #expect(router.history.entries == [
            at(.overview),
            at(.deployments),
            at(.deployments, [.newDeployment]),
            at(.deployments, [.selectTargets(commit: "c1")]),
            at(.overview, [.plan("d1")]),
            at(.overview),
        ])
    }

    @Test func backAcrossTabsAndForward() {
        let router = Router()
        router.push(.run("d1"))
        router.tab = .history
        router.push(.run("d2"))

        router.goBack()
        #expect(router.location == at(.history))
        router.goBack()                                    // 메뉴를 건너 돌아가요 (Mac)
        #expect(router.tab == .overview)
        #expect(router.location == at(.overview, [.run("d1")]))
        #expect(router.canGoForward)

        router.goForward()
        router.goForward()
        #expect(router.location == at(.history, [.run("d2")]))
        #expect(!router.canGoForward)
        // 되돌리는 동안의 변화는 기록되지 않았어요
        #expect(router.history.entries.count == 4)
    }

    @Test func iPhoneBackStaysInTab() {
        let router = Router()
        router.tab = .history
        router.push(.run("d2"))
        router.goBack(crossingTabs: false)
        #expect(router.location == at(.history))
        router.goBack(crossingTabs: false)                 // 메뉴 첫 화면에서는 다른 메뉴로 가지 않아요
        #expect(router.location == at(.history))
        #expect(router.canGoBack)
    }

    @Test func newNavigationAfterBackTruncates() {
        let router = Router()
        router.tab = .deployments
        router.tab = .history
        router.goBack()
        #expect(router.tab == .deployments)
        router.push(.newDeployment)
        #expect(!router.canGoForward)
        #expect(router.history.entries.last == at(.deployments, [.newDeployment]))
    }

    /// NavigationStack이 경로를 바꿀 때: 링크로 들어가면 새 기록, 시스템 뒤로(쓸기)면 기록에서도 뒤로
    @Test func stackPathChangesFollowHistory() {
        let router = Router()
        let path = router.path(for: .overview)
        path.wrappedValue = [.run("d1")]                   // NavigationLink(value:)
        #expect(router.history.entries == [at(.overview), at(.overview, [.run("d1")])])

        path.wrappedValue = []                             // 가장자리 쓸기
        #expect(router.location == at(.overview))
        #expect(router.history.index == 0)
        #expect(router.canGoForward)

        router.goForward()
        #expect(router.location == at(.overview, [.run("d1")]))
        path.wrappedValue = [.run("d1")]                   // 같은 값을 다시 써도 기록하지 않아요
        #expect(router.history.entries.count == 2)
    }

    @Test func clearHistoryKeepsCurrentLocation() {
        let router = Router()
        router.open(.run("d1"))
        router.tab = .settings
        router.clearHistory()
        #expect(router.history.entries == [at(.settings)])
        #expect(!router.canGoBack)
    }
}
