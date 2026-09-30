import Foundation
import Observation

/// 배포 목록(A-03)과 배포 한 건(A-04).
@MainActor
@Observable
final class DeploymentsStore {
    private(set) var list: LoadState<[Deployment]> = .idle

    func refresh(using app: AppModel, state: DeploymentState? = nil) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if list.value == nil { list = .loading }
        do {
            list = .loaded(try await client.send(.deployments(projectID: projectID, state: state)).items)
        } catch {
            app.handle(error)
            if list.value == nil { list = .failed(error.localizedDescription) }
        }
    }
}

@MainActor
@Observable
final class DeploymentDetailStore {
    let deploymentID: String
    private(set) var deployment: LoadState<Deployment> = .idle

    init(deploymentID: String) {
        self.deploymentID = deploymentID
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { return }
        if deployment.value == nil { deployment = .loading }
        do {
            deployment = .loaded(try await client.send(.deployment(id: deploymentID)))
        } catch {
            app.handle(error)
            if deployment.value == nil { deployment = .failed(error.localizedDescription) }
        }
    }

    /// 끝난 배포는 더 폴링하지 않아요.
    var isFinished: Bool { deployment.value?.state.isFinished ?? false }
}
