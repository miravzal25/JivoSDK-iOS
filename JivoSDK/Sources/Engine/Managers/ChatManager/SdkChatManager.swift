//
//  SdkChatManager.swift
//  JivoSDK
//
//  Created by Anton Karpushko on 15.09.2020.
//  Copyright © 2020 jivosite.mobile. All rights reserved.
//

import Foundation
import JMCodingKit

import SwiftMime

let MESSAGE_CONTACT_FORM_LOCAL_ID = "MESSAGE_CONTACT_FORM_LOCAL_ID"
fileprivate let notificationPrefix = "jivo:"

extension Notification.Name {
    static let jv_turnContactFormSnapshot = Self.init(rawValue: "jv_turnContactFormSnapshot")
}

enum SdkChatHistoryRequestBehavior {
    case force
    case actualize
}

enum SdkChatEvent {
    case sessionInitialized(isFirst: Bool)
    case chatObtained(_ chat: JVDatabaseModelRef<JVChat>)
    case chatAgentsUpdated(agents: [JVDatabaseModelRef<JVAgent>])
    case channelAgentsUpdated(agents: [JVDatabaseModelRef<JVAgent>])
    case attachmentsStartedToUpload
    case attachmentsUploadSucceded
    case mediaUploadFailure(withError: MediaUploadError)
    case exception(payload: IProtoEventSubjectPayloadAny)
    case enableReplying
    case disableReplying(reason: String)
}

protocol ISdkChatManager: ISdkManager {
    var sessionDelegate: JVSessionDelegate? { get set }
    var notificationsDelegate: JVNotificationsDelegate? { get set }
    var eventObservable: JVBroadcastTool<SdkChatEvent> { get }
    var contactInfoStatusObservable: JVBroadcastTool<SdkChatContactInfoStatus> { get }
    var subOffline: ISdkChatSubOffline { get }
    var subHello: ISdkChatSubHello { get }
    var hasActiveChat: Bool { get set }
    var hasMessagesInQueue: Bool { get }
    var inactivityPlaceholder: String? { get }
    func restoreChat()
    func makeAllAgentsOffline()
    func sendTyping(text: String)
    func sendMessage(text: String, attachments: [ChatPhotoPickerObject])
    func copy(message: JVMessage)
    func resendMessage(uuid: String)
    func deleteMessage(uuid: String)
    func requestMessageHistory(fromMessageWithId lastMessageId: Int?, behavior: SdkChatHistoryRequestBehavior)
    func markSeen(message: JVMessage)
    func informContactInfoStatus()
    func toggleContactForm(message: JVMessage)
    func handleNotification(userInfo: [AnyHashable : Any]) -> Bool
    func prepareToPresentNotification(_ notification: UNNotification, completionHandler: @escaping JVNotificationsOptionsOutput, resolver: @escaping JVNotificationsOptionsResolver)
    func handleNotification(response: UNNotificationResponse) -> Bool
}

enum SdkChatContactInfoStatus {
    case omit
    case askRequired
    case askDesired
    case sent
}

extension RemoteStorageTarget.Purpose {
    static let exchange = RemoteStorageTarget.Purpose(name: "exchange")
}

final class SdkChatManager: SdkManager, ISdkChatManager {
    var sessionDelegate: JVSessionDelegate?
    var notificationsDelegate: JVNotificationsDelegate?
    let contactInfoStatusObservable = JVBroadcastTool<SdkChatContactInfoStatus>()
    
    private struct SyncState {
        enum Activity { case initial, requested, synced }
        var activity = Activity.initial
        var earliestMessageId = Int.max
        var latestMessageId = Int.min
        var latestMessageDate = Date.distantPast
    }
    
    // MARK: - Constants
    
    let AGENT_DEFAULT_DISPLAY_NAME_LOC_KEY = "agent_name_default"
    
    let subOffline: ISdkChatSubOffline
    let subHello: ISdkChatSubHello

    // MARK: - Private properties
    
    private var chatMessages: [JVDatabaseModelRef<JVMessage>] = []
    private var isFirstSessionInitialization = true
    private var hasProceedToHistory = false
    private var userDataReceivingMode: AgentDataReceivingMode = .channel {
        didSet {
            subOffline.userDataReceivingMode = userDataReceivingMode
        }
    }
    private var syncState = SyncState()
    
    let eventObservable: JVBroadcastTool<SdkChatEvent>
    
    private let sessionContext: ISdkSessionContext
    private let clientContext: ISdkClientContext
    private let chatContext: ISdkChatContext
    private let messagingContext: ISdkMessagingContext
    private let subStorage: ISdkChatSubStorage
    private let subTyping: ISdkChatSubLivetyping
    private let subSender: ISdkChatSubSender
    private let subUploader: ISdkChatSubUploader
    
    private let typingCacheService: ITypingCacheService
    private let apnsService: ISdkApnsService
    private let preferencesDriver: IPreferencesDriver
    private let keychainDriver: IKeychainDriver
    
    private var applicationState = UIApplication.shared.applicationState
    private var foregroundNotificationOptions = UNNotificationPresentationOptions()
    private var lastKnownMessageId: Int?
    private var unreadNumber: Int?
    
    // MARK: - Init
    
    init(
        pipeline: SdkManagerPipeline,
        thread: JVIDispatchThread,
        sessionContext: ISdkSessionContext,
        clientContext: ISdkClientContext,
        messagingContext: ISdkMessagingContext,
        proto: SdkChatProto,
        eventObservable: JVBroadcastTool<SdkChatEvent>,
        chatContext: ISdkChatContext,
        chatSubStorage: ISdkChatSubStorage,
        subTyping: ISdkChatSubLivetyping,
        chatSubSender: ISdkChatSubSender,
        subUploader: ISdkChatSubUploader,
        subOfflineStateFeature: ISdkChatSubOffline,
        subHelloStateFeature: ISdkChatSubHello,
        systemMessagingService: ISystemMessagingService,
        networkEventDispatcher: INetworkingEventDispatcher,
        typingCacheService: ITypingCacheService,
        apnsService: ISdkApnsService,
        preferencesDriver: IPreferencesDriver,
        keychainDriver: IKeychainDriver
    ) {
        self.sessionContext = sessionContext
        self.clientContext = clientContext
        self.chatContext = chatContext
        self.messagingContext = messagingContext
        self.eventObservable = eventObservable
        self.subStorage = chatSubStorage
        self.subTyping = subTyping
        self.subSender = chatSubSender
        self.subUploader = subUploader
        self.subOffline = subOfflineStateFeature
        self.subHello = subHelloStateFeature

        self.typingCacheService = typingCacheService
        self.apnsService = apnsService
        self.preferencesDriver = preferencesDriver
        self.keychainDriver = keychainDriver
        
        super.init(
            pipeline: pipeline,
            thread: thread,
            userContext: clientContext,
            proto: proto,
            networkEventDispatcher: networkEventDispatcher)
    }
    
    var userContext: ISdkClientContext {
        return userContextAny as! ISdkClientContext
    }
    
    var proto: ISdkChatProto {
        return protoAny as! ISdkChatProto
    }
    
    override func subscribe() {
        super.subscribe()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationGoingToChangeState),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationGoingToChangeState),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTurnContactFormSnapshot),
            name: .jv_turnContactFormSnapshot,
            object: nil)
    }
    
    override func run() -> Bool {
        guard super.run()
        else {
            return false
        }
        
        subStorage.eventSignal.attachObserver { [weak self] in
            self?.handleSubStorageEvent($0)
        }
        
        restoreChatState()
        
        return true
    }
    
    var hasActiveChat: Bool = false {
        didSet {
            if hasActiveChat, syncState.latestMessageId > Int.min {
                proto
                    .sendMessageAck(id: syncState.latestMessageId, date: syncState.latestMessageDate)
            }
        }
    }
    
    var hasMessagesInQueue: Bool {
        guard let chatId = sessionContext.localChatId
        else {
            return false
        }
        
        return !subStorage.retrieveQueuedMessages(chatId: chatId).isEmpty
    }
    
    var inactivityPlaceholder: String? {
        guard !preferencesDriver.retrieveAccessor(forToken: .contactInfoWasEverSent).boolean
        else {
            return nil
        }
        
        guard hasMessagesInQueue
        else {
            return nil
        }
        
        return loc["chat_input.status.contact_info"]
    }
    
    // MARK: - Public methods
    
    func sendTyping(text: String) {
        thread.async { [unowned self] in
            _sendTyping(text: text)
        }
    }
    
    private func _sendTyping(text: String) {
        subTyping.sendTyping(
            clientHash: clientContext.clientHash,
            text: text)
    }
    
    func sendMessage(text: String, attachments: [ChatPhotoPickerObject]) {
        journal {"Sending the message"}
        apnsService.requestForPermission(at: .onSend)
        
        thread.async { [unowned self] in
            _sendMessage(text: text, attachments: attachments)
        }
    }
    
    private func _sendMessage(text: String, attachments: [ChatPhotoPickerObject]) {
        guard let chat = chatContext.chatRef?.resolved
        else {
            journal {"Cannot send message: ChatManager.chat doesn't exist"}
            return
        }
        
        guard subStorage.retrieveQueuedMessages(chatId: chat.ID).isEmpty
        else {
            return
        }
        
        _sendMessage_process(chat: chat, text: text.jv_trimmed())
        _sendMessage_process(attachments: attachments)
    }
    
    private func _sendMessage_process(chat: JVChat, text: String) {
        guard !text.isEmpty
        else {
            journal {"Cannot send message because its text is empty"}
            return
        }
        
        let formBehavior = identifyContactFormBehavior(chatId: chat.ID)
        let message = subStorage.storeOutgoingMessage(
            localID: UUID().uuidString.lowercased(),
            clientID: userContext.clientHash,
            chatID: chat.ID,
            type: .message,
            content: .makeWith(text: text),
            status: (formBehavior == .blocking ? .queued : nil),
            timing: (formBehavior == .blocking ? .frozen : .regular))
        
        if let message = message {
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messageSending(messageRef), onQueue: .main)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
            
            switch formBehavior {
            case .omit:
                break
            case .regular:
                _sendMessage_appendRegularForm(chat: chat)
            case .blocking:
                _sendMessage_appendBlockingForm(chat: chat)
            }
        }
    }
    
    private func _sendMessage_appendRegularForm(chat: JVChat) {
        let systemMessage = subStorage.storeOutgoingMessage(
            localID: UUID().uuidString.lowercased(),
            clientID: userContext.clientHash,
            chatID: chat.ID,
            type: .system,
            content: .makeWith(text: loc["chat.system.contact_form.introduce_in_chat"]),
            status: .historic,
            timing: .regular)
        
        if let message = systemMessage {
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
        }
        
        let formMessage = subStorage.storeOutgoingMessage(
            localID: MESSAGE_CONTACT_FORM_LOCAL_ID,
            clientID: userContext.clientHash,
            chatID: chat.ID,
            type: .contactForm,
            content: .contactForm(status: .inactive),
            status: nil,
            timing: .regular)
        
        if let message = formMessage {
            preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt).date = Date()
            
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
        }
    }
    
    private func _sendMessage_appendBlockingForm(chat: JVChat) {
        let systemMessage = subStorage.storeOutgoingMessage(
            localID: UUID().uuidString.lowercased(),
            clientID: userContext.clientHash,
            chatID: chat.ID,
            type: .system,
            content: .makeWith(text: loc["chat.system.contact_form.must_fill"]),
            status: .historic,
            timing: .regular)
        
        if let message = systemMessage {
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
        }

        let formMessage = subStorage.storeOutgoingMessage(
            localID: MESSAGE_CONTACT_FORM_LOCAL_ID,
            clientID: userContext.clientHash,
            chatID: chat.ID,
            type: .contactForm,
            content: .contactForm(status: .inactive),
            status: nil,
            timing: .regular)
        
        if let message = formMessage {
            preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt).date = Date()
            
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
            notifyObservers(event: .disableReplying(reason: loc["chat_input.status.contact_info"]), onQueue: .main)
        }
    }
    
    private func _sendMessage_process(attachments: [ChatPhotoPickerObject]) {
        guard jv_not(attachments.isEmpty)
        else {
            return
        }
        
        guard let clientNumber = userContext.clientNumber,
              let channelId = sessionContext.accountConfig?.channelId,
              let siteId = sessionContext.accountConfig?.siteId
        else {
            journal {"Failed sending the attachments: no credentials found"}
            return
        }
            
        notifyObservers(event: .attachmentsStartedToUpload, onQueue: .main)
        subUploader.upload(attachments: attachments, clientId: clientNumber, channelId: channelId, siteId: siteId) { [weak self] result in
            self?.hanleAttachmentUploading(result: result)
            
            if self?.subUploader.uploadingAttachments.isEmpty ?? false {
                self?.notifyObservers(event: .attachmentsUploadSucceded, onQueue: .main)
            }
        }
    }

    func copy(message: JVMessage) {
        let messageRef = subStorage.reference(to: message)
        thread.async { [unowned self] in
            guard let message = messageRef.resolved else { return }
            _copy(message: message)
        }
    }
    
    private func _copy(message: JVMessage) {
        guard let object = message.obtainObjectToCopy()
        else {
            return
        }
        
        if let url = object as? URL {
            UIPasteboard.general.url = url
        }
        else if let text = object as? String {
            UIPasteboard.general.string = text
        }
    }
    
    func resendMessage(uuid: String) {
        thread.async { [unowned self] in
            _resendMessage(uuid: uuid)
        }
    }
    
    private func _resendMessage(uuid: String) {
        guard let message = subStorage.messageWithUUID(uuid) else {
            journal {"Cannot find a message with UUID[\(uuid)]"}
            return
        }
        subStorage.resendMessage(message)
        
        let messageRef = subStorage.reference(to: message)
        messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
    }
    
    func deleteMessage(uuid: String) {
        thread.async { [unowned self] in
            _deleteMessage(uuid: uuid)
        }
    }
    
    private func _deleteMessage(uuid: String) {
        guard let message = subStorage.messageWithUUID(uuid) else {
            journal {"Cannot find a message with UUID[\(uuid)]"}
            return
        }
        
        subStorage.deleteMessage(message)
        
        let messageRef = subStorage.reference(to: message)
        messagingContext.broadcast(event: .messagesRemoved([messageRef]), onQueue: .main)
    }
    
    func requestMessageHistory(fromMessageWithId lastMessageId: Int? = nil, behavior: SdkChatHistoryRequestBehavior) {
        thread.async { [unowned self] in
            _requestMessageHistory(fromMessageWithId: lastMessageId, behavior: behavior)
        }
    }
    
    private func _requestMessageHistory(fromMessageWithId lastMessageId: Int? = nil, behavior: SdkChatHistoryRequestBehavior) {
        switch (behavior, syncState.activity) {
        case (_, .requested):
            return
        case (.force, _):
            syncState.activity = .requested
            syncState.earliestMessageId = .max
            proto.requestMessageHistory(fromMessageWithId: lastMessageId)
        case (.actualize, .synced):
            if let messageId = lastMessageId, messageId <= syncState.earliestMessageId {
                syncState.activity = .requested
                proto.requestMessageHistory(fromMessageWithId: max(syncState.earliestMessageId, messageId))
            }
        case (.actualize, .initial):
            return
        default:
            break
        }
    }
    
    func markSeen(message: JVMessage) {
        let messageRef = subStorage.reference(to: message)
        thread.async { [unowned self] in
            guard let message = messageRef.resolved else { return }
            _markSeen(message: message)
        }
    }
    
    private func _markSeen(message: JVMessage) {
        proto.sendMessageAck(id: message.ID, date: message.date)
    }
    
    func informContactInfoStatus() {
        thread.async { [unowned self] in
            _informContactInfoStatus()
        }
    }
    
    private func _informContactInfoStatus() {
        contactInfoStatusObservable.broadcast(detectContactInfoStatus(), async: .main)
    }
    
    private func detectContactInfoStatus() -> SdkChatContactInfoStatus {
        guard let chatId = sessionContext.localChatId,
              let _ = subStorage.history(chatId: chatId, after: nil).first
        else {
            return .omit
        }
        
        let accessorForWasEverSent = preferencesDriver.retrieveAccessor(forToken: .contactInfoWasEverSent)
        let accessorForWasShownAt = preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt)
        
        if accessorForWasEverSent.boolean {
            return .sent
        }
        else if accessorForWasShownAt.date == nil {
            return .omit
        }
        
        let channelAgents = chatContext.channelAgents.values.compactMap(\.resolved)
        
        switch userDataReceivingMode {
        case .channel where channelAgents.map(\.state).contains(.active):
            return .askDesired
        case .channel:
            return .askRequired
        case .chat:
            return .askDesired
        }
    }
    
    func toggleContactForm(message: JVMessage) {
        let messageRef = subStorage.reference(to: message)
        thread.async { [unowned self] in
            guard let message = messageRef.resolved else { return }
            _toggleContactForm(message: message)
        }
    }
    
    private func _toggleContactForm(message: JVMessage) {
        subStorage.turnContactForm(
            message: message,
            status: .editable,
            details: nil)
        
        let messageRef = subStorage.reference(to: message)
        DispatchQueue.main.async { [unowned self] in
            subStorage.refresh()
            guard let message = messageRef.resolved else { return }
            let ref = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([ref]))
        }
    }
    
    func handleNotification(userInfo: [AnyHashable : Any]) -> Bool {
        switch parseRemoteNotification(containingUserInfo: userInfo) {
        case let .success(notification):
            notificationDidTap(notification)
            return true
        case .failure:
            return false
        }
    }
    
    func handleNotification(response: UNNotificationResponse) -> Bool {
        switch parseNotification(response.notification) {
        case .success(let notification):
            notificationDidTap(notification)
            return true
        case .failure:
            return false
        }
    }
    
    func prepareToPresentNotification(_ notification: UNNotification, completionHandler: @escaping JVNotificationsOptionsOutput, resolver: @escaping JVNotificationsOptionsResolver) {
        if notification.request.identifier.hasPrefix(notificationPrefix) {
            completionHandler(resolver(.sdk, .any))
            return
        }
        
        guard case .success(let model) = parseRemoteNotification(containingUserInfo: notification.extractUserInfo())
        else {
            completionHandler(resolver(.app, .any))
            return
        }
        
        switch model {
        case .message(let sender, let text):
            handlePushMessage(
                notification: notification,
                userInfo: notification.extractUserInfo(),
                sender: sender,
                text: text)
        case .other:
            break
        }
        
        completionHandler(.jv_empty)
    }
    
    private func handlePushMessage(notification: UNNotification?, userInfo: [AnyHashable: Any], sender: String, text: String) {
        let content: UNMutableNotificationContent
        if let object = notification?.request.content.copy() as? UNMutableNotificationContent {
            content = object
        }
        else {
            content = UNMutableNotificationContent()
            content.subtitle = sender
            content.body = text
            content.userInfo = userInfo
        }
        
        if let delegate = notificationsDelegate {
            unreadNumber? = 1
            notifyUnreadCounter()
            
            if let result = delegate.jivoNotifications(prepareBanner: .shared, content: content, sender: sender, text: text) {
                UNUserNotificationCenter.current().add(UNNotificationRequest(
                    identifier: notificationPrefix + UUID().uuidString,
                    content: result,
                    trigger: nil
                ))
            }
        }
        else {
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: notificationPrefix + UUID().uuidString,
                content: content,
                trigger: nil
            ))
        }
    }
    
    func restoreChat() {
        restoreChatState()
    }
    
    func makeAllAgentsOffline() {
        thread.async { [unowned self] in
            _makeAllAgentsOffline()
        }
    }
    
    private func _makeAllAgentsOffline() {
        subStorage.makeAllAgentsOffline()
    }
    
    // MARK: BaseManager methods
    
    public override func handleProtoEvent(subject: IProtoEventSubject, context: ProtoEventContext?) {
        switch subject as? SessionProtoEventSubject {
        case .connectionConfig(let meta):
            handleConnectionConfig(meta: meta, context: context)
        case .socketOpen:
            handleSocketOpened()
        case let .socketClose(kind, error):
            handleSocketClosed(kind: kind, error: error)
        default:
            break
        }
        
        switch subject as? SdkChatProtoEventSubject {
        case .recentActivity(let meta):
            handleRecentMessages(meta: meta)
        default:
            break
        }
    }
    
    public override func handleProtoEvent(transaction: [NetworkingEventBundle]) {
        let userTransaction = transaction.filter { $0.payload.type == ProtoTransactionKind.chat(.user) }
        handleUserTransaction(userTransaction)
        
        let meTransaction = transaction.filter { $0.payload.type == ProtoTransactionKind.session(.me) }
        handleMeTransaction(meTransaction)
        
        let messageTransaction = transaction.filter { $0.payload.type == ProtoTransactionKind.chat(.message) }
        handleMessageTransaction(messageTransaction)
    }
    
    override func _handlePipeline(event: SdkManagerPipelineEvent) {
        switch event {
        case .turnActive:
            _handlePipelineTurnActiveEvent()
        case .turnInactive(let subsystems):
            _handlePipelineTurnInactiveEvent(subsystems: subsystems)
        }
    }
    
    private func _handlePipelineTurnActiveEvent() {
        unreadNumber = nil
        notifyUnreadCounter()
    }

    private func _handlePipelineTurnInactiveEvent(subsystems: SdkManagerSubsystem) {
        if subsystems.contains(.connection) {
            subOffline.reactToInactiveConnection()
            subHello.reactToInactiveConnection()
        }
        
        if subsystems.contains(.artifacts) {
            isFirstSessionInitialization = true
            hasProceedToHistory = false
            userDataReceivingMode = .channel
            chatContext.chatAgents = [:]
            chatContext.channelAgents = [:]
            chatMessages = []
            syncState = SyncState()
            messagingContext.broadcast(event: .historyErased, onQueue: .main)
            notifyObservers(event: .chatAgentsUpdated(agents: []), onQueue: .main)
            typingCacheService.resetInput(context: TypingContext(kind: .chat, ID: chatContext.chatRef?.resolved?.ID ?? 0))
            chatContext.chatRef = nil
            subStorage.deleteAllMessages()
            preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt).erase()
            preferencesDriver.retrieveAccessor(forToken: .contactInfoWasEverSent).erase()

            unreadNumber = 0
            notifyUnreadCounter()
        }
    }

    // MARK: - Private methods
    
    // MARK: Proto event handling methods
    
    private func handleMeTransaction(_ transaction: [NetworkingEventBundle]) {
        transaction.forEach { bundle in
            guard case let MeTransactionSubject.meHistory(data) = bundle.payload.subject else { return }
            
            guard data == nil
            else {
                return
            }
            
//            if !hasProceedToHistory {
//                hasProceedToHistory = true
//                manageContactFormAndQueuedMessage()
            informContactInfoStatus()
            
            switch detectContactInfoStatus() {
            case .askRequired:
                break
            case .omit, .askDesired, .sent:
                flushQueuedMessages()
            }
//            }
            
            syncState.earliestMessageId = .min
            syncState.activity = .synced
            
            lastKnownMessageId = nil
            messagingContext.broadcast(event: .allHistoryLoaded, onQueue: .main)
            notifyUnreadCounter()
            
            return
        }
    }
    
    private func handleMessageTransaction(_ transaction: [NetworkingEventBundle]) {
        guard let chat = self.chatContext.chatRef?.resolved else { return }
        
        syncState.activity = .synced
        
        var upsertedMessages: OrderedMap<String, JVMessage> = [:]
        transaction.forEach { bundle in
            guard let subject = bundle.payload.subject as? MessageTransactionSubject else { return }
            
            switch subject {
            case .delivered(let messageId, _, _), .received(let messageId, _, _, _, _):
                syncState.earliestMessageId = min(syncState.earliestMessageId, messageId)
                
                guard let message: JVMessage = {
                    switch bundle.payload.id {
                    case let id as String:
                        return subStorage.upsertMessage(byPrivateId: id, inChatWithId: chat.ID, with: [subject])

                    case let id as Int:
                        let message =  subStorage.upsertMessage(havingId: id, inChatWithId: chat.ID, with: [subject])
                        
                        if let lastSeenMessageId = keychainDriver.retrieveAccessor(forToken: .lastSeenMessageId, usingClientToken: true).number,
                           lastSeenMessageId == id {
                            let seenMessages = markMessagesAsSeen(to: id)
                            seenMessages.forEach { upsertedMessages[$0.UUID] = $0 }
                        }

                        return message

                    default: return nil
                    }
                }() else { return }
                
                upsertedMessages[message.UUID] = message
                
            case let .seen(id, _): // second associated value is date
                let seenMessages = markMessagesAsSeen(to: id)
                seenMessages.forEach { upsertedMessages[$0.UUID] = $0 }
            }
            
            switch subject {
            case .received(let messageId, _, _, _, let sentAt) where hasActiveChat:
                if messageId > syncState.latestMessageId {
                    syncState.latestMessageId = messageId
                    syncState.latestMessageDate = sentAt
                    
                    proto
                        .sendMessageAck(id: messageId, date: sentAt)
                }
            case .received(let messageId, _, _, _, let sentAt):
                if messageId > syncState.latestMessageId {
                    syncState.latestMessageId = messageId
                    syncState.latestMessageDate = sentAt
                }
            default:
                break
            }
        }
        
        let messageReferences = subStorage.reference(to: Array(upsertedMessages.orderedValues))
        messagingContext.broadcast(event: .messagesUpserted(messageReferences), onQueue: .main)
    }
    
    private func markMessagesAsSeen(to messageId: Int) -> [JVMessage] {
        keychainDriver.retrieveAccessor(forToken: .lastSeenMessageId, usingClientToken: true).number = messageId
        
        guard let chatId = self.chatContext.chatRef?.resolved?.ID else { return [] }
        let seenClientMessages = subStorage
            .markMessagesAsSeen(to: messageId, inChatWithId: chatId)
            .filter { !$0.m_is_incoming }
        
        return seenClientMessages
    }
    
    private func handleUserTransaction(_ transaction: [NetworkingEventBundle]) {
        transaction.forEach { bundle in
            guard let subject = bundle.payload.subject as? UserTransactionSubject else { return }
            
            if let id = bundle.payload.id.flatMap(String.init).flatMap(Int.init) {
                guard let agent = subStorage.upsertAgent(havingId: id, with: [subject]) else { return }

                switch userDataReceivingMode {
                case .channel:
                    chatContext.channelAgents[id] = subStorage.reference(to: agent)
                case .chat:
                    chatContext.chatAgents[id] = subStorage.reference(to: agent)
                }
            } else {
                switch subject {
                case .switchingDataReceivingMode:
                    self.userDataReceivingMode = .chat
                    
                default: break
                }
            }
        }
        
        var resolvedChatAgents: [JVDatabaseModelRef<JVAgent>] { Array(chatContext.chatAgents.values) }
        storeChatAgents(resolvedChatAgents.compactMap(\.resolved), exclusive: false)

        switch userDataReceivingMode {
        case .channel:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.subStorage.refresh()
                
                let resolvedChannelAgents = Array(self.chatContext.channelAgents.values)
                self.notifyObservers(event: .channelAgentsUpdated(agents: resolvedChannelAgents))
            }
            
        case .chat:
            guard jv_not(resolvedChatAgents.isEmpty)
            else {
                break
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.subStorage.refresh()
                self?.notifyObservers(event: .chatAgentsUpdated(agents: resolvedChatAgents))
            }
        }
    }
    
    private func manageContactFormAndQueuedMessage() {
        guard userDataReceivingMode == .channel
        else {
            return
        }
        
        guard preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt).hasObject
        else {
            return
        }
        
        let states = chatContext.channelAgents.values.compactMap(\.resolved).map(\.state)
        if states.contains(.active) {
            flushQueuedMessages()
        }
        else if let reason = inactivityPlaceholder {
            DispatchQueue.main.async { [weak self] in
                self?.notifyObservers(event: .disableReplying(reason: reason), onQueue: .main)
            }
        }
    }
    
    private func handleConnectionConfig(meta: ProtoEventSubjectPayload.ConnectionConfig, context: ProtoEventContext?) {
        guard let accountConfig = sessionContext.accountConfig,
           let siteId = accountConfig.siteId,
           let clientId = clientContext.clientId,
           let _ = sessionContext.localChatId
        else {
            return
        }
        
        proto
            .requestRecentActivity(
                siteId: siteId,
                channelId: accountConfig.channelId,
                clientId: clientId)
            .silent()
    }
    
    private func handleSocketOpened() {
        userDataReceivingMode = .channel
        chatContext.channelAgents = [:]
        chatContext.chatAgents = [:]
        storeChatAgents([], exclusive: true)
        
        requestMessageHistory(behavior: .force)
        
        notifyObservers(event: .sessionInitialized(isFirst: isFirstSessionInitialization.getAndDisable()), onQueue: .main)
        notifyObservers(event: .channelAgentsUpdated(agents: []), onQueue: .main)
        notifyObservers(event: .chatAgentsUpdated(agents: []), onQueue: .main)
        
        subOffline.reactToActiveConnection()
        subHello.reactToActiveConnection()
        
        subSender.run()
    }
    
    private func handleSocketClosed(kind: APIConnectionCloseCode, error: Error?) {
        userDataReceivingMode = .channel
        
        subOffline.reactToInactiveConnection()
        subHello.reactToInactiveConnection()
    }
    
    private func handleRecentMessages(meta: ProtoEventSubjectPayload.RecentActivity) {
        lastKnownMessageId = meta.body.latestMessageId
        notifyUnreadCounter()
    }
    
    // MARK: SubStorage event handling methods
    
    private func handleSubStorageEvent(_ event: SdkChatSubStorageEvent) {
        switch event {
        case .messageSendingFailure(let message):
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
            
        case .messageResending(let message):
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messageResend(messageRef), onQueue: .main)
        }
    }
    
    // MARK: SubUploader event handling methods
    private func hanleAttachmentUploading(result: Result<JVMessageContent, ChatMediaUploadingError>) {
        switch result {
        case let .success(attachment):
            guard
                let chat = self.chatContext.chatRef?.resolved,
                let message = self.subStorage.storeOutgoingMessage(
                    localID: UUID().uuidString.lowercased(),
                    clientID: self.userContext.clientHash,
                    chatID: chat.ID,
                    type: .message,
                    content: attachment,
                    status: nil,
                    timing: .regular
                )
            else {
                journal {"Failed sending the message with media"}
                return notifyObservers(event: .mediaUploadFailure(withError: .cannotHandleUploadResult), onQueue: .main)
            }
            
            let messageRef = subStorage.reference(to: message)
            messagingContext.broadcast(event: .messagesUpserted([messageRef]), onQueue: .main)
            
        case let .failure(error):
            switch error {
            case .cannotExtractData:
                notifyObservers(event: .mediaUploadFailure(withError: .extractionFailed), onQueue: .main)
                
            case .networkClientError:
                notifyObservers(event: .mediaUploadFailure(withError: .networkClientError), onQueue: .main)
                
            case let .sizeLimitExceeded(megabytes):
                notifyObservers(event: .mediaUploadFailure(withError: .fileSizeExceeded(megabytes: megabytes)), onQueue: .main)
                
            case .cannotHandleUploadResult:
                notifyObservers(event: .mediaUploadFailure(withError: .cannotHandleUploadResult), onQueue: .main)
                
            case let .uploadDeniedByAServer(errorDescription):
                notifyObservers(event: .mediaUploadFailure(withError: .uploadDeniedByAServer(errorDescription: errorDescription)), onQueue: .main)
                
            case .unsupportedMediaType:
                notifyObservers(event: .mediaUploadFailure(withError: .unsupportedMediaType), onQueue: .main)
                
            case let .unknown(errorDescription):
                notifyObservers(event: .mediaUploadFailure(withError: .unknown(errorDescription: errorDescription)), onQueue: .main)
            }
        }
    }
    
    // MARK: Other private methods
    
    private func notifyObservers(event: SdkChatEvent) {
        eventObservable.broadcast(event)
    }
    
    private func notifyObservers(event: SdkChatEvent, onQueue queue: DispatchQueue) {
        eventObservable.broadcast(event, async: queue)
    }
    
    private func restoreChatState() {
        thread.async { [unowned self] in
            if let chat = obtainChat() {
                let chatID = chat.ID
                journal {"Found active chat[\(chatID)]"}
                
                chatContext.chatRef = subStorage.reference(to: chat)
                chatMessages = subStorage.reference(to: subStorage.history(chatId: chat.ID, after: nil))
                
                messagingContext.broadcast(event: .historyLoaded(history: chatMessages), onQueue: .main)
                notifyObservers(event: .chatObtained(subStorage.reference(to: chat)), onQueue: .main)
                
                chat.agents.forEach { agent in
                    chatContext.chatAgents[agent.ID] = subStorage.reference(to: agent)
                }
                
                let agentsRefs = chat.agents.map { subStorage.reference(to: $0) }
                notifyObservers(event: .chatAgentsUpdated(agents: agentsRefs), onQueue: .main)
            }
        }
    }
    
    private func obtainChat() -> JVChat? {
        guard let crc32EncryptedClientToken = sessionContext.localChatId else {
            journal {"Failed obtaining a chat because clientToken doesn't exists"}
            return nil
        }
        
        if let chat = self.chatContext.chatRef?.resolved { return chat }
        if let chat = subStorage.chatWithID(crc32EncryptedClientToken) { return chat }
        if let chat = subStorage.createChat(withChatID: crc32EncryptedClientToken) {
            return chat
        } else {
            journal {"Failed creating a chat: something went wrong"}
            return nil
        }
    }
    
    private func storeChatAgents(_ agents: [JVAgent], exclusive: Bool) {
        guard let chat = obtainChat() else {
            journal {"Failed obtaining a chat: something went wrong"}
            return
        }
        let chatChange = JVSdkChatAgentsUpdateChange(id: chat.ID, agentIds: agents.map(\.ID), exclusive: exclusive)
        guard let _ = subStorage.storeChat(change: chatChange) else {
            journal {"Failed updating the chat: something went wrong"}
            return
        }
    }
    
    enum CalculatingOutgoingStatusError: Error {
        case hasMessagesInQueue
    }
    
    enum ContactFormBehavior {
        case omit
        case blocking
        case regular
    }
    
    private func identifyContactFormBehavior(chatId: Int) -> ContactFormBehavior {
        guard !preferencesDriver.retrieveAccessor(forToken: .contactInfoWasShownAt).hasObject,
              !preferencesDriver.retrieveAccessor(forToken: .contactInfoWasEverSent).boolean
        else {
            return .omit
        }
        
        let agents = chatContext.channelAgents.values.compactMap(\.resolved)
        let states = agents.map(\.state)
        
        switch userDataReceivingMode {
        case .channel where states.contains(.active):
            return .regular
        case .channel:
            return .blocking
        case .chat:
            return .omit
        }
    }
    
    private func notificationDidTap(_ sender: SdkClientSubPusherNotification) {
        switch sender {
        case .message where jv_not(Jivo.display.isOnscreen):
            Jivo.display.delegate?.jivoDisplay(asksToAppear: .shared)
        case .message:
            break
        default:
            break
        }
    }
    
    @objc private func handleApplicationGoingToChangeState() {
        DispatchQueue.main.async { [unowned self] in
            applicationState = UIApplication.shared.applicationState
            print("applicationState = \(applicationState)")
        }
    }
    
    @objc private func handleTurnContactFormSnapshot(notification: Notification) {
        if let info = notification.object as? JVSessionContactInfo {
            flushContactForm(info: info)
        }
        
        flushQueuedMessages()
        
        DispatchQueue.main.async {
            self.notifyObservers(event: .enableReplying)
        }
    }
    
    private func flushContactForm(info: JVSessionContactInfo) {
        guard let _ = obtainChat()?.ID
        else {
            return
        }
        
        let message = subStorage.message(withLocalId: MESSAGE_CONTACT_FORM_LOCAL_ID)
        let messageRef = subStorage.reference(to: message)
        thread.async { [unowned self] in
            guard let message = messageRef.resolved else { return }
            
            subStorage.turnContactForm(
                message: message,
                status: .snapshot,
                details: [
                    "name": info.name ?? String(),
                    "phone": info.phone ?? String(),
                    "email": info.email ?? String()
                ])
            
            DispatchQueue.main.async { [unowned self] in
                subStorage.refresh()
                messagingContext.broadcast(event: .messagesUpserted([messageRef]))
            }
        }
    }
    
    private func flushQueuedMessages() {
        guard let chatId = obtainChat()?.ID
        else {
            return
        }
        
        thread.async { [unowned self] in
            let queuedMessages = subStorage.retrieveQueuedMessages(chatId: chatId)
            guard jv_not(queuedMessages.isEmpty)
            else {
                return
            }
            
            for message in queuedMessages {
                subStorage.resendMessage(message)
            }
            
            let systemMessageRef = subStorage.reference(
                to: subStorage.storeOutgoingMessage(
                    localID: UUID().uuidString.lowercased(),
                    clientID: userContext.clientHash,
                    chatID: chatId,
                    type: .system,
                    content: .text(message: loc["chat.system.contact_form.status_sent"]),
                    status: nil,
                    timing: .regular
                ))
            
            DispatchQueue.main.async { [unowned self] in
                subStorage.refresh()
                messagingContext.broadcast(event: .messagesUpserted([systemMessageRef]))
            }
        }
    }
    
    func parseRemoteNotification(containingUserInfo userInfo: [AnyHashable : Any]) -> Result<SdkClientSubPusherNotification, SdkClientSubPusherNotificationParsingError> {
        guard userInfo.keys.contains("jivosdk") else {
            return .failure(.notificationSenderIsNotJivo)
        }
        
        let root = JsonElement(userInfo)
        let alert = root["aps"]["alert"]
        let args = alert["loc-args"]
        
        switch alert["loc-key"].stringValue {
        case "JV_MESSAGE":
            let sender = args.arrayValue.prefix(1).last?.string ?? String()
            let text = args.arrayValue.prefix(2).last?.string ?? String()
            return .success(.message(sender: sender, text: text))
        default:
            return .success(.other)
        }
    }
    
    func parseNotification(_ notification: UNNotification) -> Result<SdkClientSubPusherNotification, SdkClientSubPusherNotificationParsingError> {
        return parseRemoteNotification(containingUserInfo: notification.extractUserInfo())
    }
    
    private func notifyUnreadCounter() {
        guard let delegate = sessionDelegate
        else {
            return
        }
        
        func _notify(number: Int) {
            DispatchQueue.main.async {
                delegate.jivoSession(updateUnreadCounter: .shared, number: number)
            }
        }
        
        guard let chatId = sessionContext.localChatId
        else {
            _notify(number: 0)
            return
        }
        
        let lastLocalMessage = subStorage.lastMessage(chatId: chatId)
        
        if lastKnownMessageId == nil {
            _notify(number: 0)
        }
        else if let knownId = lastKnownMessageId, let localId = lastLocalMessage?.ID, localId >= knownId {
            _notify(number: 0)
        }
        else if let _ = lastLocalMessage?.senderClient {
            _notify(number: 0)
        }
        else {
            _notify(number: 1)
        }
    }
}

enum AgentDataReceivingMode {
    case channel
    case chat
}

fileprivate extension UNNotification {
    func extractUserInfo() -> [AnyHashable: Any] {
        return request.content.userInfo
    }
}
