import SwiftUI

/// A `TextField` wrapper that keeps typing 100% local at frame rate and only
/// commits changes to the upstream `Binding<String>` after a short pause, on
/// submit, or on disappear. This prevents heavy SwiftUI tree invalidations
/// and disk writes on every keystroke.
struct DebouncedTextField: View {
    private let title: String
    @Binding private var text: String
    private let delayMilliseconds: Int
    private let onSubmitAction: (() -> Void)?

    @State private var draft: String
    @State private var lastCommitted: String
    @State private var debounceTask: Task<Void, Never>?

    init(
        _ title: String,
        text: Binding<String>,
        delayMilliseconds: Int = 180,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self._text = text
        self.delayMilliseconds = delayMilliseconds
        self.onSubmitAction = onSubmit
        let initial = text.wrappedValue
        self._draft = State(initialValue: initial)
        self._lastCommitted = State(initialValue: initial)
    }

    var body: some View {
        TextField(title, text: $draft)
            .onSubmit {
                flush()
                onSubmitAction?()
            }
            .onChange(of: draft) { _, newValue in
                guard newValue != lastCommitted else { return }
                scheduleCommit(newValue)
            }
            .onChange(of: text) { _, newExternal in
                guard newExternal != lastCommitted else { return }
                debounceTask?.cancel()
                debounceTask = nil
                lastCommitted = newExternal
                if draft != newExternal {
                    draft = newExternal
                }
            }
            .onDisappear {
                flush()
            }
    }

    private func scheduleCommit(_ value: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            commit(value)
        }
    }

    private func flush() {
        debounceTask?.cancel()
        debounceTask = nil
        commit(draft)
    }

    private func commit(_ value: String) {
        guard value != lastCommitted else { return }
        lastCommitted = value
        if text != value {
            text = value
        }
    }
}

/// A `TextEditor` wrapper that buffers typing locally and flushes to the upstream
/// binding after a short pause or on disappear.
struct DebouncedTextEditor<Placeholder: View>: View {
    @Binding private var text: String
    private let delayMilliseconds: Int
    private let placeholder: Placeholder

    @State private var draft: String
    @State private var lastCommitted: String
    @State private var debounceTask: Task<Void, Never>?

    init(
        text: Binding<String>,
        delayMilliseconds: Int = 280,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self._text = text
        self.delayMilliseconds = delayMilliseconds
        self.placeholder = placeholder()
        let initial = text.wrappedValue
        self._draft = State(initialValue: initial)
        self._lastCommitted = State(initialValue: initial)
    }

    var body: some View {
        TextEditor(text: $draft)
            .overlay {
                if draft.isEmpty {
                    placeholder
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: draft) { _, newValue in
                guard newValue != lastCommitted else { return }
                scheduleCommit(newValue)
            }
            .onChange(of: text) { _, newExternal in
                guard newExternal != lastCommitted else { return }
                debounceTask?.cancel()
                debounceTask = nil
                lastCommitted = newExternal
                if draft != newExternal {
                    draft = newExternal
                }
            }
            .onDisappear {
                flush()
            }
    }

    private func scheduleCommit(_ value: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            commit(value)
        }
    }

    private func flush() {
        debounceTask?.cancel()
        debounceTask = nil
        commit(draft)
    }

    private func commit(_ value: String) {
        guard value != lastCommitted else { return }
        lastCommitted = value
        if text != value {
            text = value
        }
    }
}

extension DebouncedTextEditor where Placeholder == EmptyView {
    init(text: Binding<String>, delayMilliseconds: Int = 280) {
        self.init(text: text, delayMilliseconds: delayMilliseconds) {
            EmptyView()
        }
    }
}
