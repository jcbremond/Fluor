//
//  StatusMenuController.swift
//  Fluor
//
//  Created by Pierre TACCHI on 02/09/16.
//  Copyright © 2016 Pyrolyse. All rights reserved.
//

import Cocoa

extension Notification.Name {
    public static let StateViewDidChangeState = Notification.Name("kStateViewDidChangeState")
    public static let BehaviorDidChangeForApp = Notification.Name("kBehaviorDidChangeForApp")
}

class StatusMenuController: NSObject {
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var stateView: StateView!
    @IBOutlet weak var currentAppView: CurrentAppView!
    
    private var rulesController: RulesEditorWindowController?
    private var aboutController: AboutWindowController?
    private var preferencesController: PreferencesWindowController?
    private var runningAppsController: RunningAppsWindowController?
    
    private var currentState: KeyboardState = .error
    private var onLaunchKeyboardState: KeyboardState = .error
    private var currentID: String = ""
    private var currentBehavior: AppBehavior = .infered
    
    let statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)
    
    deinit {
        resignAsObserver()
    }
    
    override func awakeFromNib() {
        onLaunchKeyboardState = BehaviorManager.default.getActualStateAccordingToPreferences()
        currentState = onLaunchKeyboardState
        setupStatusItem()
        applyAsObserver()
    }
    
    // MARK: Operations callbacks
    
    
    /// React to active application change.
    ///
    /// - parameter notification: The notification.
    @objc private func activeAppDidChange(notification: NSNotification) {
        guard let app = notification.userInfo?[NSWorkspaceApplicationKey] as? NSRunningApplication,
            let id = app.bundleIdentifier else { return }
        currentID = id
        updateAppBehaviorViewFor(app: app, id: id)
        adaptBehaviorForApp(id: id)
    }
    
    
    /// React to the change of default function keys behavior in the dedicated view.
    ///
    /// - parameter notification: The notification.
    @objc private func stateViewDidChangeState(notification: NSNotification) {
        guard let passedState = notification.userInfo?["state"] as? KeyboardState else { return }
        BehaviorManager.default.defaultKeyboardState = passedState
        adaptBehaviorForApp(id: currentID)
    }
    
    
    /// React to the change of the function keys behavior for one app.
    ///
    /// - parameter notification: The notification.
    @objc private func behaviorDidChangeForApp(notification: NSNotification) {
        func updateIfCurrent(id: String, behavior: AppBehavior) {
            if id == currentID {
                adaptBehaviorForApp(id: id)
                currentAppView.updateBehaviorForCurrentApp(behavior)
            }
        }
        
        guard let userInfo = notification.userInfo,
            let info = StatusMenuController.behaviorDidChangeUserInfoFor(dict: userInfo) else { return }
        setBehaviorForApp(id: info.id, behavior: info.behavior, url: info.url)
        switch notification.object! {
        case is CurrentAppView:
            rulesController?.loadRules()
            runningAppsController?.updateBehaviorForApp(id: info.id, behavior: info.behavior)
            adaptBehaviorForApp(id: info.id)
        case is RunningAppItem:
            rulesController?.loadRules()
            updateIfCurrent(id: info.id, behavior: info.behavior)
        default:
            runningAppsController?.updateBehaviorForApp(id: info.id, behavior: info.behavior)
            updateIfCurrent(id: info.id, behavior: info.behavior)
        }
    }
    
    
    /// When a window was closed this methods takes care of the releasing of its controller.
    ///
    /// - parameter notification: The notification.
    @objc private func someWindowWillClose(notification: Notification) {
        guard let object = notification.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(self, name: Notification.Name.NSWindowWillClose, object: object)
        if object.isEqual(rulesController?.window) {
            rulesController = nil
        } else if object.isEqual(aboutController?.window) {
            aboutController = nil
        } else if object.isEqual(preferencesController?.window) {
            preferencesController = nil
        } else if object.isEqual(runningAppsController?.window) {
            runningAppsController = nil
        }
    }
    
    // MARK: Private functions
    
    /// Setup the status bar's item
    private func setupStatusItem() {
        statusItem.menu = statusMenu
        statusItem.image = #imageLiteral(resourceName: "iconAppleModeTemplate")
        let statePlaceHolder = statusMenu.item(withTitle: "State")
        let currentPlaceHolder = statusMenu.item(withTitle: "Current")
        statePlaceHolder?.view = stateView
        currentPlaceHolder?.view = currentAppView
        stateView.setState(flag: BehaviorManager.default.defaultKeyboardState)
    }
    
    
    /// Register self as an observer for some notifications.
    private func applyAsObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(stateViewDidChangeState(notification:)), name: Notification.Name.StateViewDidChangeState, object: stateView)
        NotificationCenter.default.addObserver(self, selector: #selector(behaviorDidChangeForApp(notification:)), name: Notification.Name.BehaviorDidChangeForApp, object: nil)
        NSWorkspace.shared().notificationCenter.addObserver(self, selector: #selector(activeAppDidChange(notification:)), name: NSNotification.Name.NSWorkspaceDidActivateApplication, object: nil)
    }
    
    
    /// Unregister self as an observer for some notifications.
    private func resignAsObserver() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared().notificationCenter.removeObserver(self)
    }
    
    
    /// Set function key behavior in the current running app view.
    ///
    /// - parameter app: The running app.
    /// - parameter id:  The app's bundle id.
    private func updateAppBehaviorViewFor(app: NSRunningApplication, id: String) {
        currentAppView.enabled(id != Bundle.main.bundleIdentifier!)
        currentAppView.setCurrent(app: app, behavior: BehaviorManager.default.behaviorForApp(id: id))
    }
    
    private func setBehaviorForApp(id: String, behavior: AppBehavior, url: URL) {
        BehaviorManager.default.setBehaviorForApp(id: id, behavior: behavior, url: url)
    }
    
    
    /// Set the function keys' behavior for the given app.
    ///
    /// - parameter id: The app's bundle id.
    private func adaptBehaviorForApp(id: String) {
        let behavior = BehaviorManager.default.behaviorForApp(id: id)
        let state = BehaviorManager.default.keyboardStateFor(behavior: behavior)
        guard state != currentState else { return }
        currentState = state
        switch state {
        case .apple:
            NSLog("Switch to Apple Mode for %@", id)
            statusItem.image = #imageLiteral(resourceName: "iconAppleModeTemplate")
            setFnKeysToAppleMode()
        case .other:
            NSLog("Switch to Other Mode for %@", id)
            statusItem.image = #imageLiteral(resourceName: "iconOtherModeTemplate")
            setFnKeysToOtherMode()
        default:
            // Soneone should handle this, no ?
            return
        }
    }
    
    /// Pack app's information in a dictionnary suitable for Notification's use.
    ///
    /// - parameter id:       The app's bundle id.
    /// - parameter url:      The app's bundle URL.
    /// - parameter behavior: The app's function keys behavior.
    ///
    /// - returns: A dictionnary usable as Notification's userInfo.
    static func behaviorDidChangeUserInfoConstructor(id: String, url: URL, behavior: AppBehavior) -> [String: Any] {
        return ["id": id, "url": url, "behavior": behavior]
    }
    
    
    /// Try to unpack Notification's userInfo with app's information.
    ///
    /// - parameter dict: The userInfo dictionnary provided by a Notification object.
    ///
    /// - returns: A tupple containing all app's information if the userInfo dictionnary contained required keys. Nil otherwise.
    static func behaviorDidChangeUserInfoFor(dict: [AnyHashable: Any]) -> (id: String, url: URL, behavior: AppBehavior)? {
        guard let behavior = dict["behavior"] as? AppBehavior,
            let url = dict["url"] as? URL,
            let id = dict["id"] as? String else { return nil }
        return (id, url, behavior)
    }
    
    // MARK: IBActions
    @IBAction func editRules(_ sender: AnyObject) {
        guard rulesController == nil else {
            rulesController?.window?.orderFrontRegardless()
            return
        }
        rulesController = RulesEditorWindowController(windowNibName: "RulesEditorWindowController")
        rulesController?.loadRules()
        NotificationCenter.default.addObserver(self, selector: #selector(someWindowWillClose(notification:)), name: Notification.Name.NSWindowWillClose, object: rulesController?.window)
        rulesController?.window?.orderFrontRegardless()
    }
    
    @IBAction func showAbout(_ sender: AnyObject) {
        guard aboutController == nil else {
            aboutController?.window?.orderFrontRegardless()
            return
        }
        aboutController = AboutWindowController(windowNibName: "AboutWindowController")
        NotificationCenter.default.addObserver(self, selector: #selector(someWindowWillClose(notification:)), name: Notification.Name.NSWindowWillClose, object: aboutController?.window)
        aboutController?.window?.orderFrontRegardless()
    }
    
    @IBAction func showPreferences(_ sender: AnyObject) {
        guard preferencesController == nil else {
            preferencesController?.window?.orderFrontRegardless()
            return
        }
        preferencesController = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        NotificationCenter.default.addObserver(self, selector: #selector(someWindowWillClose(notification:)), name: Notification.Name.NSWindowWillClose, object: preferencesController?.window)
        preferencesController?.window?.orderFrontRegardless()
    }
    
    @IBAction func showRunningApps(_ sender: AnyObject) {
        guard runningAppsController == nil else {
            runningAppsController?.window?.orderFrontRegardless()
            return
        }
        runningAppsController = RunningAppsWindowController(windowNibName: "RunningAppsWindowController")
        NotificationCenter.default.addObserver(self, selector: #selector(someWindowWillClose(notification:)), name: Notification.Name.NSWindowWillClose, object: runningAppsController?.window)
        runningAppsController?.window?.orderFrontRegardless()
    }
    
    @IBAction func quitApplication(_ sender: AnyObject) {
        if BehaviorManager.default.shouldRestoreStateOnQuit() {
            let state: KeyboardState
            if BehaviorManager.default.shouldRestorePreviousState() {
                state = onLaunchKeyboardState
            } else {
                state = BehaviorManager.default.onQuitState()
            }
            switch state {
            case .apple:
                setFnKeysToAppleMode()
            default:
                setFnKeysToOtherMode()
            }
        }
        NSApp.terminate(self)
    }
}
