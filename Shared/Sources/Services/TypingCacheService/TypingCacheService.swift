//
// Created by Stan Potemkin on 30/03/2018.
// Copyright (c) 2018 JivoSite. All rights reserved.
//

import Foundation


struct TypingContext: Codable, Equatable {
    enum Kind: String, Codable { case chat, agent }
    let kind: Kind
    let ID: Int
    
    init(kind: Kind, ID: Int) {
        self.kind = kind
        self.ID = ID
    }
}

enum TypingCacheAttachmentReaction {
    case accept
    case reject
    case ignore
}

enum InputMode: Int, Codable {
    case regular = 0
    case editing
    case comment
    case sms
    case whatsapp
    case email
}

struct TypingCacheInput {
    let text: String?
    let attachments: [ChatPhotoPickerObject]
    let mode: InputMode?
}

protocol ITypingCacheService: AnyObject {
    var currentInput: TypingCacheInput { get }
    var canAttachMore: Bool { get }
    func cache(mode: InputMode)
    func cache(text: String?)
    func cache(attachment: ChatPhotoPickerObject) -> TypingCacheAttachmentReaction
    func uncache(attachmentAt index: Int)
    func saveInput(context: TypingContext, flush: Bool)
    func obtainInput(context: TypingContext) -> TypingCacheRecord?
    func activateInput(context: TypingContext) -> TypingCacheInput?
    func resetInput(context: TypingContext)
}

final class TypingCacheService: ITypingCacheService {
    private let fileURL: URL?
    private let attachmentsNumberLimit: Int
    private let databaseDriver: JVIDatabaseDriver

    private var records = [TypingCacheRecord]()
    private var currentText: String?
    private var currentAttachments = [ChatPhotoPickerObject]()
    private var currentMode: InputMode?
    
    init(fileURL: URL?, attachmentsNumberLimit: Int, databaseDriver: JVIDatabaseDriver) {
        self.fileURL = fileURL
        self.attachmentsNumberLimit = attachmentsNumberLimit
        self.databaseDriver = databaseDriver

        read()
    }
    
    var currentInput: TypingCacheInput {
        return TypingCacheInput(
            text: currentText,
            attachments: currentAttachments,
            mode: currentMode
        )
    }
    
    var canAttachMore: Bool {
        return (currentAttachments.count < attachmentsNumberLimit)
    }
    
    func cache(mode: InputMode) {
        currentMode = mode
    }
    
    func cache(text: String?) {
        currentText = text?.jv_valuable
    }

    func cache(attachment: ChatPhotoPickerObject) -> TypingCacheAttachmentReaction {
        if let index = findAttachmentIndex(uuid: attachment.uuid) {
            currentAttachments[index] = attachment
            return .ignore
        }
        else if !canAttachMore {
            return .reject
        }
        else {
            currentAttachments.append(attachment)
            return .accept
        }
    }
    
    func uncache(attachmentAt index: Int) {
        currentAttachments.remove(at: index)
    }
    
    func saveInput(context: TypingContext, flush: Bool) {
        let record = TypingCacheRecord(
            context: context,
            text: currentText,
            attachments: currentAttachments,
            mode: currentMode
        )
        
        if let index = recordIndex(context: context) {
            if record != records[index] {
                records[index] = record
                applyDraft(currentText, to: context)
                save()
            }
            else if record.isEmpty {
                records.remove(at: index)
                applyDraft(nil, to: context)
                save()
            }
        }
        else if !record.isEmpty {
            records.append(record)
            applyDraft(currentText, to: context)
            save()
        }
        
        if flush {
            currentText = nil
            currentAttachments = []
        }
    }

    func obtainInput(context: TypingContext) -> TypingCacheRecord? {
        if let index = recordIndex(context: context) {
            return records[index]
        }
        else {
            return nil
        }
    }
    
    func activateInput(context: TypingContext) -> TypingCacheInput? {
        if let input = obtainInput(context: context) {
            currentText = input.text
            currentAttachments = input.attachments
            currentMode = input.mode
        }
        else {
            currentText = nil
            currentAttachments = []
        }

        return currentInput
    }

    func resetInput(context: TypingContext) {
        currentText = nil
        currentAttachments = []
        
        if let index = recordIndex(context: context) {
            records.remove(at: index)
            applyDraft(nil, to: context)
            save()
        }
    }

    private func findAttachmentIndex(uuid: UUID) -> Int? {
        return currentAttachments.firstIndex { $0.uuid == uuid }
    }

    private func read() {
        guard let url = fileURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let records = try? JSONDecoder().decode([TypingCacheRecord].self, from: data) else { return }
        self.records = records
    }

    private func save() {
        guard let url = fileURL else { return }
        
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: .atomic)
        }
        catch {
        }
    }

    private func recordIndex(context: TypingContext) -> Int? {
        return records.firstIndex(where: { $0.context == context })
    }
    
    private func applyDraft(_ draft: String?, to context: TypingContext) {
        switch context.kind {
        case .chat:
            let change = JVChatDraftChange(ID: context.ID, draft: currentText)
            _ = databaseDriver.update(of: JVChat.self, with: change)
        case .agent:
            let change = JVAgentDraftChange(ID: context.ID, draft: currentText)
            _ = databaseDriver.update(of: JVAgent.self, with: change)
        }
    }
}
