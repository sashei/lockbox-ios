/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import RxSwift
import RxCocoa
import UIKit

protocol RootViewProtocol: class {
    func topViewIs<T: UIViewController>(_ type: T.Type) -> Bool
    func modalViewIs<T: UIViewController>(_ type: T.Type) -> Bool
    func mainStackIs<T: UINavigationController>(_ type: T.Type) -> Bool
    func modalStackIs<T: UINavigationController>(_ type: T.Type) -> Bool

    func startMainStack<T: UINavigationController>(_ type: T.Type)
    func startModalStack<T: UINavigationController>(_ type: T.Type)
    func dismissModals()

    func pushLoginView(view: LoginRouteAction)
    func pushMainView(view: MainRouteAction)
    func pushSettingView(view: SettingRouteAction)
}

struct KeyInit {
    let scopedKey: String?
    let initialized: Bool
}

struct InfoOpenLock {
    let profileInfo: ProfileInfo?
    let opened: Bool
    let visualLocked: Bool
}

struct KeyDataStoreLock {
    let scopedKey: String?
    let dataStoreLocked: Bool
}

class RootPresenter {
    private weak var view: RootViewProtocol?
    private let disposeBag = DisposeBag()

    fileprivate let routeStore: RouteStore
    fileprivate let userInfoStore: UserInfoStore
    fileprivate let dataStore: DataStore
    fileprivate let userDefaults: UserDefaults
    fileprivate let routeActionHandler: RouteActionHandler
    fileprivate let dataStoreActionHandler: DataStoreActionHandler

    init(view: RootViewProtocol,
         routeStore: RouteStore = RouteStore.shared,
         userInfoStore: UserInfoStore = UserInfoStore.shared,
         dataStore: DataStore = DataStore.shared,
         userDefaults: UserDefaults = UserDefaults.standard,
         routeActionHandler: RouteActionHandler = RouteActionHandler.shared,
         dataStoreActionHandler: DataStoreActionHandler = DataStoreActionHandler.shared
    ) {
        self.view = view
        self.routeStore = routeStore
        self.userInfoStore = userInfoStore
        self.dataStore = dataStore
        self.userDefaults = userDefaults
        self.routeActionHandler = routeActionHandler
        self.dataStoreActionHandler = dataStoreActionHandler

        // request init & lock status update on app launch
        self.dataStoreActionHandler.updateInitialized()
        self.dataStoreActionHandler.updateLocked()

        Observable.combineLatest(self.userInfoStore.profileInfo, self.dataStore.onOpened, self.userDefaults.onLock)
                .map { (latest: (ProfileInfo?, Bool, Bool)) -> InfoOpenLock in
                    return InfoOpenLock(profileInfo: latest.0, opened: latest.1, visualLocked: latest.2)
                }
                .subscribe(onNext: { (latest: InfoOpenLock) in
                    guard let uid = latest.profileInfo?.uid, !latest.visualLocked else {
                        self.routeActionHandler.invoke(LoginRouteAction.welcome)
                        return
                    }

                    if !latest.opened {
                        self.dataStoreActionHandler.open(uid: uid)
                        self.routeActionHandler.invoke(MainRouteAction.list)
                    }
                }).disposed(by: self.disposeBag)

        Observable.combineLatest(self.userInfoStore.scopedKey, self.dataStore.onInitialized)
                .map { (latest: (String?, Bool)) -> KeyInit in
                    return KeyInit(scopedKey: latest.0, initialized: latest.1)
                }
                .filter { latest in
                    return (latest.scopedKey != nil)
                }
                .subscribe(onNext: { (latest: KeyInit) in
                    guard let scopedKey = latest.scopedKey else {
                        return
                    }

                    if !latest.initialized {
                        self.dataStoreActionHandler.initialize(scopedKey: scopedKey)
                        return
                    } else {
                        self.dataStoreActionHandler.populateTestData()
                    }
                })
                .disposed(by: self.disposeBag)

        self.unlockBlindly()
    }

    func onViewReady() {
        self.routeStore.onRoute
                .filterByType(class: LoginRouteAction.self)
                .asDriver(onErrorJustReturn: .welcome)
                .drive(showLogin)
                .disposed(by: disposeBag)

        self.routeStore.onRoute
                .filterByType(class: MainRouteAction.self)
                .asDriver(onErrorJustReturn: .list)
                .drive(showList)
                .disposed(by: disposeBag)

        self.routeStore.onRoute
                .filterByType(class: SettingRouteAction.self)
                .asDriver(onErrorJustReturn: .list)
                .drive(self.showSetting)
                .disposed(by: self.disposeBag)
    }

    lazy private var showLogin: AnyObserver<LoginRouteAction> = { [unowned self] in
        return Binder(self) { target, loginAction in
            guard let view = target.view else {
                return
            }

            view.dismissModals()

            if !view.mainStackIs(LoginNavigationController.self) {
                view.startMainStack(LoginNavigationController.self)
            }

            switch loginAction {
            case .welcome:
                if !view.topViewIs(WelcomeView.self) {
                    view.pushLoginView(view: .welcome)
                }
            case .fxa:
                if !view.topViewIs(FxAView.self) {
                    view.pushLoginView(view: .fxa)
                }
            case .onboardingBiometrics:
                if !view.topViewIs(BiometryOnboardingView.self) {
                    view.pushLoginView(view: .onboardingBiometrics)
                }
            }
        }.asObserver()
    }()

    lazy private var showList: AnyObserver<MainRouteAction> = { [unowned self] in
        return Binder(self) { target, mainAction in
            guard let view = target.view else {
                return
            }

            view.dismissModals()

            if !view.mainStackIs(MainNavigationController.self) {
                view.startMainStack(MainNavigationController.self)
            }

            switch mainAction {
            case .list:
                if !view.topViewIs(ItemListView.self) {
                    view.pushMainView(view: .list)
                }
            case .detail(let id):
                if !view.topViewIs(ItemDetailView.self) {
                    view.pushMainView(view: .detail(itemId: id))
                }
            }
        }.asObserver()
    }()

    lazy private var showSetting: AnyObserver<SettingRouteAction> = { [unowned self] in
        return Binder(self) { target, settingAction in
            guard let view = target.view else {
                return
            }

            if !view.modalStackIs(SettingNavigationController.self) {
                view.startModalStack(SettingNavigationController.self)
            }

            switch settingAction {
            case .list:
                if !view.modalViewIs(SettingListView.self) {
                    view.pushSettingView(view: .list)
                }
            case .account:
                if !view.modalViewIs(AccountSettingView.self) {
                    view.pushSettingView(view: .account)
                }
            case .autoLock:
                if !view.modalViewIs(AutoLockSettingView.self) {
                    view.pushSettingView(view: .autoLock)
                }
            case .preferredBrowser:
                if !view.modalViewIs(PreferredBrowserSettingView.self) {
                    view.pushSettingView(view: .preferredBrowser)
                }
            case .faq:
                view.pushSettingView(view: .faq)
            case .provideFeedback:
                view.pushSettingView(view: .provideFeedback)
            default: break
            }

        }.asObserver()
    }()
}

extension RootPresenter {
    private func unlockBlindly() {
        Observable.combineLatest(self.dataStore.onInitialized, self.userInfoStore.scopedKey, self.dataStore.onLocked)
                .filter { (latest: (Bool, String?, Bool)) -> Bool in
                    return latest.0
                }
                .map { (latest: (Bool, String?, Bool)) -> KeyDataStoreLock in
                    return KeyDataStoreLock(scopedKey: latest.1, dataStoreLocked: latest.2)
                }
                .subscribe(onNext: { (latest: KeyDataStoreLock) in
                    guard let scopedKey = latest.scopedKey else {
                        return
                    }

                    if latest.dataStoreLocked {
                        self.dataStoreActionHandler.unlock(scopedKey: scopedKey)
                    } else {
                        self.dataStoreActionHandler.list()
                    }
                })
                .disposed(by: self.disposeBag)
    }
}
