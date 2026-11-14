import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import ChatPresentationInterfaceState
import ItemListUI
import PresentationDataUtils
import SavedTagNameAlertController

// Local catalogue and assignment sheet. Filtered results stay in native chat bubbles.
struct JerkgramSavedTagsStrings {
    let ru: Bool
    init(_ strings: PresentationStrings) { self.ru = strings.jerkgram.languageCode.hasPrefix("ru") }
    func text(_ en: String, _ ru: String) -> String { return self.ru ? ru : en }
    var title: String { return self.text("Local tags", "Локальные теги") }
    var locality: String {
        return self.text("Stored only for this account on this device. No cloud sync. Local tags are NOT included in current Jerkgram backups. Removing the account or reinstalling the app can lose them.", "Хранятся только для этого аккаунта на этом устройстве. Нет синхронизации с облаком. Локальные теги НЕ входят в текущие резервные копии Jerkgram. При удалении аккаунта или переустановке приложения они могут быть потеряны.")
    }
    var query: String { return self.text("Text search within a local tag is unavailable. Choose Search in Saved Messages for ordinary search.", "Поиск по тексту внутри локального тега недоступен. Для обычного поиска выберите «Поиск» в Избранном.") }
    func error(_ error: LocalSavedTagsError) -> String {
        switch error {
        case .invalidName: return self.text("Use a nonempty name, up to 64 characters / 256 UTF-8 bytes, without control characters.", "Введите непустое имя: до 64 символов / 256 байт UTF-8, без управляющих символов.")
        case .duplicateName: return self.text("A tag with this name already exists.", "Тег с таким именем уже существует.")
        case .tagLimit: return self.text("Limit: 256 local tags per account.", "Лимит: 256 локальных тегов на аккаунт.")
        case .messageTagLimit: return self.text("Limit: 16 tags per message. The entire assignment was rejected.", "Лимит: 16 тегов на сообщение. Всё назначение отклонено.")
        case .membershipLimit: return self.text("Limit: 100,000 tag assignments per account. The entire assignment was rejected.", "Лимит: 100 000 назначений тегов на аккаунт. Всё назначение отклонено.")
        case .batchLimit: return self.text("Select at most 1,000 messages. Nothing was truncated or assigned.", "Выберите не более 1000 сообщений. Список не обрезан, теги не назначены.")
        case .invalidMessage: return self.text("Some selected messages are unavailable or are not current Saved cloud messages. The entire assignment was rejected.", "Часть выбранных сообщений недоступна или не является текущими облачными сообщениями Избранного. Всё назначение отклонено.")
        case .wrongAccount: return self.text("This account is no longer active. Reopen Local tags in the current account.", "Этот аккаунт больше не активен. Откройте локальные теги в текущем аккаунте.")
        case .invalidPage: return self.text("Tags changed while loading. Retry to restart the local filter.", "Теги изменились во время загрузки. Повторите, чтобы начать фильтр заново.")
        case .invalidTag, .tagNotFound: return self.text("This tag no longer exists. Choose another tag.", "Этот тег больше не существует. Выберите другой.")
        case .corruptStore: return self.text("Local tags could not be read safely. No changes were applied.", "Не удалось безопасно прочитать локальные теги. Изменения не внесены.")
        case .unavailable: return self.text("Local tags are unavailable. Retry or reopen this screen.", "Локальные теги недоступны. Повторите или откройте этот экран заново.")
        }
    }
}

private enum JerkgramSavedTagsAction: Equatable {
    case create, save, cancel, retry
    case tag(String)
}

private struct JerkgramSavedTagsEntry: ItemListNodeEntry {
    enum Kind: Equatable { case text, action, input }
    let stableId: String
    let index: Int
    let section: ItemListSectionId
    let kind: Kind
    let title: String
    let value: String
    let action: JerkgramSavedTagsAction?

    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.index < rhs.index }
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.index == rhs.index && lhs.section == rhs.section
            && lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.value == rhs.value
            && lhs.action == rhs.action
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let session = arguments as! JerkgramSavedTagsSession
        switch self.kind {
        case .text:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .action:
            return ItemListDisclosureItem(presentationData: presentationData, title: self.title, enabled: self.action != nil, label: self.value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: self.action.map { action in { [weak session] in session?.perform(action) } })
        case .input:
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: self.title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: self.value, placeholder: self.title, type: .regular(capitalization: true, autocorrection: false), returnKeyType: .done, clearType: .always, maxLength: 64, enabled: session.canEdit, sectionId: self.section, textUpdated: { [weak session] text in session?.updateDraft(text) }, action: { [weak session] in session?.perform(.save) })

        }
    }
}

private final class JerkgramSavedTagsSession {
    private enum SheetColor: Equatable { case accent, destructive }
    let context: AccountContext
    let selectedIds: [MessageId]
    weak var controller: ViewController?
    private weak var nativeSheet: ActionSheetController?
    private weak var nativeNamePrompt: AlertController?
    private let nativeRenderer = MetaDisposable()
    private let nativePrompt = MetaDisposable()
    var presentation: PresentationData
    let changes = ValuePromise<Int>(0, ignoreRepeated: false)
    private var serial = 0
    private var visible = false
    private var generation: UInt64 = 0
    private var summaryGeneration: UInt64 = 0
    private var service: LocalSavedTagsService?
    private let accounts = MetaDisposable()
    private let catalogueSubscription = MetaDisposable()
    private let summarySubscription = MetaDisposable()
    private let mutationSubscription = MetaDisposable()
    private var tags: [LocalSavedTag] = []
    private var revision: Int64?
    private var summary: LocalSavedTagsSelectionSummary?
    private var mutating = false
    private var editing = false
    private var editingTag: String?
    private var draft = ""
    private var error: LocalSavedTagsError?
    private var notice: String?

    init(context: AccountContext, selectedIds: [MessageId]) {
        self.context = context
        // Keep raw count: never truncate to satisfy the 1000-ID quota.
        self.selectedIds = selectedIds
        self.presentation = context.sharedContext.currentPresentationData.with { $0 }
    }
    deinit { self.stop() }
    private func changed() { self.serial &+= 1; self.changes.set(self.serial) }
    var canEdit: Bool { return !self.mutating && JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) }
    private var strings: JerkgramSavedTagsStrings { return JerkgramSavedTagsStrings(self.presentation.strings) }
    func start() {
        guard !self.visible else { return }
        self.visible = true
        self.generation &+= 1
        let generation = self.generation
        self.accounts.set((self.context.sharedContext.activeAccountContexts |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, self.visible, self.generation == generation else { return }
            guard let primary = value.primary, primary.account.id == self.context.account.id,
                primary.account.peerId == self.context.account.peerId,
                primary.account.testingEnvironment == self.context.account.testingEnvironment else {
                self.stop()
                self.error = .wrongAccount
                self.changed()
                return
            }
            guard self.service == nil else { return }
            self.error = nil
            self.service = LocalSavedTagsService(account: self.context.account)
            self.observeCatalogue()
        }))
    }
    func stop() {
        self.nativeNamePrompt?.dismissAnimated(); self.nativeNamePrompt = nil
        self.nativeSheet?.dismissAnimated(); self.nativeSheet = nil
        self.nativeRenderer.set(nil); self.nativePrompt.set(nil)
        self.visible = false
        self.generation &+= 1
        self.summaryGeneration &+= 1
        self.accounts.set(nil)
        self.catalogueSubscription.set(nil)
        self.summarySubscription.set(nil)
        self.mutationSubscription.set(nil)
        self.service?.dispose(); self.service = nil
        self.summary = nil; self.revision = nil; self.tags.removeAll()
        self.mutating = false
    }
    // Native Telegram action sheet and SavedTagNameAlertController, sharing the
    // existing session/service/account guards. No second catalogue screen/store.
    func presentNative() {
        let sheet = ActionSheetController(presentationData: self.presentation)
        self.nativeSheet = sheet; self.controller = sheet
        self.nativeRenderer.set((self.changes.get() |> deliverOnMainQueue).start(next: { [weak self] _ in self?.renderNative() }))
        self.renderNative()
        self.start()
        guard self.visible else { return }
        self.context.sharedContext.mainWindow?.present(sheet, on: .root)
    }
    private func nativeName(_ tag: LocalSavedTag?) {
        let generation = self.generation
        self.nativePrompt.set((self.context.availableReactions |> filter { $0 != nil } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] available in
            guard let self, self.visible, self.generation == generation,
                let reaction = available?.reactions.first(where: { $0.value == .builtin("👍") }) ?? available?.reactions.first else { return }
            let prompt = savedTagNameAlertController(context: self.context,
                text: tag == nil ? self.presentation.strings.Chat_EditTagTitle_TitleSet : self.presentation.strings.Chat_EditTagTitle_TitleEdit,
                subtext: self.presentation.strings.Chat_EditTagTitle_Text, value: tag?.name ?? "",
                reaction: reaction.value, file: reaction.selectAnimation._parse(), characterLimit: 64,
                apply: { [self] value in
                    guard self.visible, self.generation == generation, self.canEdit, let service = self.service, let value else { return }
                    if let tag { self.run(service.rename(tagId: tag.id, name: value)) }
                    else { self.run(service.create(name: value)) }
                })
            self.nativeNamePrompt = prompt
            self.controller?.present(prompt, in: .window(.root))
        }))
    }
    private func renderNative() {
        guard let sheet = self.nativeSheet else { return }
        var rows: [ActionSheetItem] = [ActionSheetTextItem(title: self.strings.text("Local tags · this device only", "Локальные теги · только на этом устройстве"))]
        if let error = self.error {
            rows.append(ActionSheetTextItem(title: self.strings.error(error)))
        }
        rows.append(ActionSheetButtonItem(title: self.strings.text("Create tag", "Создать тег"), color: .accent, action: { [self] in
            guard self.canEdit else { return }; self.nativeName(nil)
        }))
        for tag in self.tags {
            let assigned = self.summary?.assignedCounts[tag.id] ?? 0
            let all = !self.selectedIds.isEmpty && assigned == self.summary?.selectedCount
            let title = (all ? "✓ " : "") + tag.name
            rows.append(ActionSheetButtonItem(title: title, color: .accent, action: { [self] in
                guard self.canEdit, let service = self.service else { return }
                if self.selectedIds.isEmpty { self.nativeName(tag) }
                else {
                    guard self.summary != nil else { return }
                    self.run(service.set(tagId: tag.id, messageIds: self.selectedIds, assigned: !all))
                }
            }))
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: rows), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.presentation.strings.Common_Done, color: .accent, action: { [self] in
            self.stop()
        })])])
    }

    private func observeCatalogue() {
        guard let service = self.service else { return }
        let generation = self.generation
        self.catalogueSubscription.set((service.catalogueUpdates() |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.visible, self.generation == generation else { return }
            switch result {
            case let .failure(error):
                self.error = error
                if !JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) {
                    self.tags = []; self.revision = nil; self.summary = nil
                }
            case let .success(catalogue):
                guard self.revision != catalogue.revision else { return }
                self.revision = catalogue.revision
                self.tags = catalogue.tags
                self.refreshSummary()
            }
            self.changed()
        }))
    }
    private func refreshSummary() {
        self.summaryGeneration &+= 1
        self.summarySubscription.set(nil)
        self.summary = nil
        guard !self.selectedIds.isEmpty, let service = self.service else { return }
        guard self.selectedIds.count <= 1000 else { self.error = .batchLimit; return }
        let generation = self.generation, summaryGeneration = self.summaryGeneration
        // One aggregate transaction for all actual selected IDs, including albums.
        self.summarySubscription.set((service.selectionSummary(messageIds: self.selectedIds) |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.visible, self.generation == generation, self.summaryGeneration == summaryGeneration else { return }
            switch result {
            case let .success(summary): self.summary = summary
            case let .failure(error):
                self.error = error
                if !JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) {
                    self.tags = []; self.revision = nil; self.summary = nil
                }
            }
            self.changed()
        }))
    }
    private func run<T>(_ signal: Signal<Result<T, LocalSavedTagsError>, NoError>, success: @escaping () -> Void = {}) {
        guard !self.mutating else { return }
        self.mutating = true; self.error = nil; self.notice = nil
        let generation = self.generation
        self.changed()
        self.mutationSubscription.set((signal |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.visible, self.generation == generation else { return }
            self.mutating = false
            switch result {
            case .success:
                self.notice = self.strings.text("Saved locally.", "Сохранено локально.")
                success()
            case let .failure(error):
                self.error = error
                if !JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) {
                    self.tags = []; self.revision = nil; self.summary = nil
                }
            }
            self.changed()
        }))
    }
    func updateDraft(_ value: String) { guard !self.mutating else { return }; self.draft = value; self.changed() }
    func perform(_ action: JerkgramSavedTagsAction) {
        guard self.visible, !self.mutating, let service = self.service else { return }
        self.notice = nil
        switch action {
        case .create: self.editing = true; self.editingTag = nil; self.draft = ""; self.error = nil; self.changed()
        case .cancel: self.editing = false; self.editingTag = nil; self.draft = ""; self.error = nil; self.changed()
        case .save:
            guard self.editing else { return }
            let saved: () -> Void = { [weak self] in self?.editing = false; self?.editingTag = nil; self?.draft = "" }
            if let tag = self.editingTag { self.run(service.rename(tagId: tag, name: self.draft), success: saved) }
            else { self.run(service.create(name: self.draft), success: saved) }
        case .retry:
            if self.revision == nil { self.observeCatalogue() }
            self.refreshSummary(); self.changed()
        case let .tag(id): self.tagMenu(id)
        }
    }
    private func sheet(_ rows: [(String, SheetColor, () -> Void)]) {
        guard let controller = self.controller else { return }
        let sheet = ActionSheetController(presentationData: self.presentation)
        let generation = self.generation
        sheet.setItemGroups([ActionSheetItemGroup(items: rows.map { title, color, action in
            ActionSheetButtonItem(title: title, color: color == .destructive ? .destructive : .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                guard let self, self.visible, self.generation == generation, !self.mutating else { return }
                action()
            })
        }), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.presentation.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
        controller.present(sheet, in: .window(.root))
    }
    private func tagMenu(_ id: String) {
        guard let tag = self.tags.first(where: { $0.id == id }) else { return }
        let strings = self.strings
        var rows: [(String, SheetColor, () -> Void)] = []
        if !self.selectedIds.isEmpty, let summary = self.summary {
            let count = summary.assignedCounts[id] ?? 0
            if count < summary.selectedCount {
                rows.append((strings.text("Add to all selected (\(summary.selectedCount))", "Добавить ко всем выбранным (\(summary.selectedCount))"), .accent, { [weak self] in
                    guard let self, let service = self.service else { return }
                    self.run(service.set(tagId: id, messageIds: self.selectedIds, assigned: true))
                }))
            }
            if count > 0 {
                rows.append((strings.text("Remove from all selected", "Убрать со всех выбранных"), .destructive, { [weak self] in
                    guard let self, let service = self.service else { return }
                    self.run(service.set(tagId: id, messageIds: self.selectedIds, assigned: false))
                }))
            }
        }
        rows.append((strings.text("Rename", "Переименовать"), .accent, { [weak self] in
            guard let self else { return }
            self.editing = true; self.editingTag = id; self.draft = tag.name; self.changed()
        }))
        rows.append((strings.text("Delete tag…", "Удалить тег…"), .destructive, { [weak self] in
            guard let self else { return }
            self.sheet([(strings.text("Delete tag and its local assignments", "Удалить тег и его локальные назначения"), .destructive, { [weak self] in
                guard let self, let service = self.service else { return }
                self.run(service.delete(tagId: id))
            })])
        }))
        self.sheet(rows)
    }
    func render(_ presentation: PresentationData) -> (ItemListControllerState, (ItemListNodeState, JerkgramSavedTagsSession)) {
        self.presentation = presentation
        let strings = self.strings
        var entries: [JerkgramSavedTagsEntry] = []
        func add(_ id: String, _ section: ItemListSectionId, _ kind: JerkgramSavedTagsEntry.Kind, _ title: String, value: String = "", action: JerkgramSavedTagsAction? = nil) {
            entries.append(JerkgramSavedTagsEntry(stableId: id, index: entries.count, section: section, kind: kind, title: title, value: value, action: action))
        }
        add("locality", 0, .text, strings.locality)
        if !self.selectedIds.isEmpty {
            add("selection", 0, .text, strings.text("Assign tags to the entire selection (\(self.summary?.selectedCount ?? self.selectedIds.count)). ○ none · − mixed · ✓ all. Adding or removing one tag preserves other tags.", "Назначение тегов всему выбору (\(self.summary?.selectedCount ?? self.selectedIds.count)). ○ нет · − частично · ✓ всем. Добавление или удаление одного тега сохраняет остальные теги."))
        }
        if let error = self.error {
            add("error", 0, .text, strings.error(error))
            add("retry", 0, .action, strings.text("Retry", "Повторить"), action: .retry)
        }
        if let notice = self.notice { add("notice", 0, .text, notice) }
        if self.mutating { add("saving", 0, .text, strings.text("Saving…", "Сохранение…")) }
        if self.editing {
            add("name", 1, .input, strings.text("Tag name", "Имя тега"), value: self.draft)
            add("nameLimit", 1, .text, strings.text("Up to 64 characters / 256 UTF-8 bytes. Names must be unique.", "До 64 символов / 256 байт UTF-8. Имена должны быть уникальны."))
            add("save", 1, .action, presentation.strings.Common_Save, action: self.mutating ? nil : .save)
            add("cancel", 1, .action, presentation.strings.Common_Cancel, action: self.mutating ? nil : .cancel)
        } else {
            add("create", 1, .action, strings.text("Create local tag", "Создать локальный тег"), action: self.mutating ? nil : .create)
        }
        if self.revision == nil { add("loadingCatalogue", 1, .text, strings.text("Loading local tags…", "Загрузка локальных тегов…")) }
        else if self.tags.isEmpty { add("emptyCatalogue", 1, .text, strings.text("No local tags yet. Create your first tag above.", "Локальных тегов пока нет. Создайте первый тег выше.")) }
        for tag in self.tags {
            var label = "\(tag.count)"
            if !self.selectedIds.isEmpty {
                if let summary = self.summary {
                    let count = summary.assignedCounts[tag.id] ?? 0
                    let mark = count == 0 ? "○" : (count == summary.selectedCount ? "✓" : "−")
                    label = "\(mark) \(count)/\(summary.selectedCount) · \(tag.count)"
                } else { label = "… · \(tag.count)" }
            }
            let title = tag.name
            add("tag:\(tag.id)", 1, .action, title, value: label, action: self.mutating ? nil : .tag(tag.id))
        }
        return (ItemListControllerState(presentationData: ItemListPresentationData(presentation), title: .text(strings.title), leftNavigationButton: ItemListNavigationButton(content: .icon(.close), style: .regular, enabled: true, action: { [weak self] in self?.controller?.navigationController?.dismiss(animated: true, completion: nil) }), rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentation.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentation), entries: entries, style: .blocks, animateChanges: false), self))
    }
}

private final class JerkgramSavedTagsController: ItemListController {
    private let session: JerkgramSavedTagsSession
    init(context: AccountContext, selectedIds: [MessageId]) {
        let session = JerkgramSavedTagsSession(context: context, selectedIds: selectedIds)
        self.session = session
        let presentation = context.sharedContext.currentPresentationData.with { $0 }
        let state = combineLatest(context.sharedContext.presentationData, session.changes.get())
        |> deliverOnMainQueue
        |> map { [session] presentation, _ in session.render(presentation) }
        super.init(presentationData: ItemListPresentationData(presentation), updatedPresentationData: context.sharedContext.presentationData |> map { ItemListPresentationData($0) }, state: state, tabBarItem: nil)
        session.controller = self
    }
    required init(coder: NSCoder) { preconditionFailure() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); self.session.start() }
    override func viewWillDisappear(_ animated: Bool) { self.session.stop(); super.viewWillDisappear(animated) }
    deinit { self.session.stop() }
}

func jerkgramSavedTagsController(context: AccountContext, selectedMessageIds: [MessageId] = []) -> NavigationController {
    let controller = JerkgramSavedTagsController(context: context, selectedIds: selectedMessageIds)
    let theme = context.sharedContext.currentPresentationData.with { $0.theme }
    let navigation = NavigationController(mode: .single, theme: NavigationControllerTheme(presentationTheme: theme))
    navigation.setViewControllers([controller], animated: false)
    return navigation
}

func jerkgramPresentSavedTagsController(context: AccountContext, selectedMessageIds: [MessageId] = []) {
    guard JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: context.account.peerId.toInt64()) else { return }
    let session = JerkgramSavedTagsSession(context: context, selectedIds: selectedMessageIds)
    session.presentNative()
}

// All delayed UI clears retain both typed identity and the controller request
// generation. In particular A → B → A must reject the first A's callback.
func jerkgramClearingLocalSavedTagsFilter(_ filter: ChatPresentationInterfaceState.HistoryFilter?, expectedId: String?, generation: UInt64, expectedGeneration: UInt64) -> ChatPresentationInterfaceState.HistoryFilter? {
    guard generation == expectedGeneration, let expectedId, filter?.localSavedTagId == expectedId else { return filter }
    return nil
}

// Clear the history override synchronously before replaying a jump. The later
// interface-state callback is idempotent and cannot restore the previous anchor.
func jerkgramResolveLocalSavedTagsNavigation(clearHistory: () -> Void, replayLocation: () -> Void, notifyFilterCleared: () -> Void) {
    clearHistory()
    replayLocation()
    notifyFilterCleared()
}

// Owned by the existing Saved history node. The accepted indexed provider owns
// the 45-row requests / three-window bound. No chat scan or cloud tag API.
final class JerkgramLocalSavedTagsHistory {
    let tagId: String
    private let context: AccountContext
    private let service: LocalSavedTagsService
    private let provider: LocalSavedTagsPageProvider
    private struct PageRequest {
        let cursor: LocalSavedTagsCursor?
        let direction: LocalSavedTagsDirection
    }
    private let messageDisposable = MetaDisposable()
    private var messageGeneration: UInt64 = 0
    private var observedIds = Set<MessageId>()
    private var observedMessages: [MessageId: Message] = [:]
    // Only retained indexed memberships own retry metadata (at most135 IDs).
    private var rowRequests: [MessageId: PageRequest] = [:]
    private var lastRequest = PageRequest(cursor: nil, direction: .earlier)
    private var failedRequest: PageRequest?
    private var unavailableRequest: PageRequest?
    private let requestDisposable = MetaDisposable()
    private let catalogueDisposable = MetaDisposable()
    private let accountDisposable = MetaDisposable()
    private let views = Promise<(MessageHistoryView, ViewUpdateType)>()
    private var generation: UInt64 = 0
    private var disposed = false
    private var loading = false
    private var content: LocalSavedTagsContentPage?
    private var revision: Int64?
    private var first = true
    private var cleared: () -> Void
    var status: ((String) -> Void)?
    private var strings: JerkgramSavedTagsStrings {
        return JerkgramSavedTagsStrings(self.context.sharedContext.currentPresentationData.with { $0.strings })
    }

    init(context: AccountContext, tagId: String, cleared: @escaping () -> Void) {
        self.context = context
        self.tagId = tagId
        self.cleared = cleared
        self.service = LocalSavedTagsService(account: context.account)
        self.provider = self.service.makePageProvider(tagId: tagId)
        self.publish(loading: true)
        self.accountDisposable.set((context.sharedContext.activeAccountContexts |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, !self.disposed else { return }
            guard let primary = value.primary, primary.account.id == context.account.id,
                primary.account.peerId == context.account.peerId,
                primary.account.testingEnvironment == context.account.testingEnvironment else {
                self.dispose(); DispatchQueue.main.async { [weak self] in self?.cleared() }; return
            }
        }))
        self.catalogueDisposable.set((self.service.catalogueUpdates() |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, !self.disposed else { return }
            switch result {
            case let .success(catalogue):
                guard catalogue.tags.contains(where: { $0.id == self.tagId }) else {
                    self.dispose(); DispatchQueue.main.async { [weak self] in self?.cleared() }; return
                }
                guard self.revision != catalogue.revision else { return }
                self.revision = catalogue.revision
                self.requestDisposable.set(nil)
                self.generation &+= 1
                self.provider.reset(); self.content = nil; self.loading = false
                self.resetRetainedMessages()
                self.rowRequests.removeAll(); self.failedRequest = nil; self.unavailableRequest = nil
                self.request(cursor: nil, direction: .earlier)
            case .failure:
                if !JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) {
                    self.dispose(); DispatchQueue.main.async { [weak self] in self?.cleared() }; return
                }
                self.status?(self.strings.text("Local tags unavailable. Clear the filter and retry.", "Локальные теги недоступны. Сбросьте фильтр и повторите."))
            }
        }))
    }
    deinit { self.dispose() }
    func dispose() {
        guard !self.disposed else { return }
        self.disposed = true; self.generation &+= 1
        self.resetRetainedMessages()
        self.requestDisposable.dispose(); self.catalogueDisposable.dispose(); self.accountDisposable.dispose()
        self.provider.dispose(); self.service.dispose()
    }
    var signal: Signal<(MessageHistoryView, ViewUpdateType), NoError> { return self.views.get() }
    private func resetRetainedMessages() {
        self.messageGeneration &+= 1
        self.messageDisposable.set(nil)
        self.observedIds.removeAll(); self.observedMessages.removeAll()
    }
    private func observeRetainedMessages() {
        let rows = self.content?.windows.flatMap { $0 } ?? []
        let ids = Set(rows.map { $0.entry.id })
        // Request progress, scrolling, typing and ordinary edits do not rebuild
        // the subscription. One Postbox view follows the bounded retained set.
        guard ids != self.observedIds else { return }
        self.resetRetainedMessages()
        self.observedIds = ids
        for row in rows { if let message = row.message { self.observedMessages[row.entry.id] = message } }
        guard !ids.isEmpty else { return }
        let messageGeneration = self.messageGeneration
        self.messageDisposable.set((self.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Messages(ids: ids)) |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self, !self.disposed, self.messageGeneration == messageGeneration,
                self.observedIds == ids else { return }
            self.observedMessages = messages.filter { ids.contains($0.key) }.mapValues { $0._asMessage() }
            self.selectUnavailableRetry()
            self.publish(loading: self.loading, reportUnavailable: false)
        }))
    }
    private func selectUnavailableRetry() {
        self.unavailableRequest = self.content?.windows.joined().first(where: { self.observedMessages[$0.entry.id] == nil }).flatMap { self.rowRequests[$0.entry.id] }
    }
    private func publish(loading: Bool, reportUnavailable: Bool = true) {
        let rows = self.content?.windows.flatMap { $0 } ?? []
        let messages = rows.compactMap { self.observedMessages[$0.entry.id] }.sorted { $0.index < $1.index }
        // Local boundaries are NOT Postbox holes. Only loadBoundary below may
        // request an adjacent indexed page; ordinary hole filling stays disabled.
        let view = MessageHistoryView(tag: nil, namespaces: .all,
            entries: messages.map { MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)) },
            holeEarlier: false, holeLater: false, isLoading: loading && messages.isEmpty)
        self.views.set(.single((view, self.first ? .Initial : .Generic)))
        self.first = false
        let missing = rows.filter { self.observedMessages[$0.entry.id] == nil }.count
        if reportUnavailable && missing > 0 { self.status?(self.strings.text("\(missing) tagged messages unavailable in this window. Tap Retry; membership is preserved.", "\(missing) сообщений с тегом в этом окне недоступны. Нажмите «Повторить»; назначения тегов сохранены.")) }
    }
    private func request(cursor: LocalSavedTagsCursor?, direction: LocalSavedTagsDirection) {
        guard !self.disposed, !self.loading else { return }
        self.generation &+= 1
        let generation = self.generation
        let request = PageRequest(cursor: cursor, direction: direction)
        self.lastRequest = request
        self.loading = true; self.publish(loading: true)
        self.requestDisposable.set((self.provider.request(cursor: cursor, direction: direction) |> deliverOnMainQueue).start(next: { [weak self] event in
            guard let self, !self.disposed, self.generation == generation else { return }
            switch event {
            case .progress: break
            case let .result(content):
                self.content = content; self.loading = false; self.failedRequest = nil
                let retainedIds = Set(content.windows.flatMap { $0 }.map { $0.entry.id })
                self.rowRequests = self.rowRequests.filter { retainedIds.contains($0.key) }
                for row in content.rows { self.rowRequests[row.entry.id] = request }
                self.observeRetainedMessages()
                self.selectUnavailableRetry()
                self.publish(loading: false)
            case .failure(.invalidPage):
                self.loading = false; self.content = nil; self.provider.reset()
                self.resetRetainedMessages(); self.rowRequests.removeAll(); self.unavailableRequest = nil
                self.failedRequest = PageRequest(cursor: nil, direction: .earlier)
                self.publish(loading: false)
                self.status?(self.strings.text("Tags changed while loading. Tap Retry to refresh the local filter.", "Теги изменились во время загрузки. Нажмите «Повторить», чтобы обновить локальный фильтр."))
            case .failure:
                self.failedRequest = request
                self.loading = false; self.publish(loading: false)
                self.status?(self.strings.text("Local tagged messages could not load. Tap Retry.", "Не удалось загрузить сообщения с локальным тегом. Нажмите «Повторить»."))
            }
        }))
    }
    @discardableResult func loadBoundary(earlier: Bool) -> Bool {
        guard !self.disposed, let content = self.content else { return false }
        if let cursor = earlier ? content.earlier : content.later {
            self.request(cursor: cursor, direction: earlier ? .earlier : .later)
            return true
        }
        return false
    }
    func retry() {
        guard !self.disposed else { return }
        let request = self.failedRequest ?? self.unavailableRequest ?? self.lastRequest
        self.requestDisposable.set(nil); self.generation &+= 1; self.loading = false
        // Reuse the store-issued page boundary. A nonboundary retry may reseed
        // the provider's bounded window, but never substitutes the newest page.
        self.request(cursor: request.cursor, direction: request.direction)
    }
    func contains(_ index: MessageIndex) -> Bool {
        return self.content?.windows.joined().contains(where: { $0.entry.id == index.id }) == true
    }
}
