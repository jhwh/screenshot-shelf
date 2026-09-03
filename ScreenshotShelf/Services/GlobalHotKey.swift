import Carbon

final class GlobalHotKey {
    private static let signature: OSType = 0x53485346
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    @discardableResult
    func update(_ hotKey: ShelfHotKey?, handler: @escaping () -> Void) -> Bool {
        unregisterHotKey()
        callback = handler
        guard let hotKey else { return true }
        return register(hotKey)
    }

    func pressed() {
        DispatchQueue.main.async { [callback] in
            callback?()
        }
    }

    deinit {
        unregisterHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    private func register(_ hotKey: ShelfHotKey) -> Bool {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        var identifier = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            userData,
            &ref
        )
        handlerRef = ref
    }
}

private func carbonHotKeyHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == 0x53485346 else {
        return OSStatus(eventNotHandledErr)
    }

    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().pressed()
    return noErr
}
