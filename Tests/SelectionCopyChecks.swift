import AppKit

@main
struct SelectionCopyChecks {
    @MainActor
    static func main() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let original = "Previously copied text"
        let selection = "A sentence selected by dragging."
        let extraType = NSPasteboard.PasteboardType("com.yuyanpo.ben.copy-check")
        let extraData = Data([1, 2, 3])
        precondition(pasteboard.setString(original, forType: .string))
        precondition(pasteboard.setData(extraData, forType: extraType))

        func writeSelection() {
            pasteboard.clearContents()
            precondition(pasteboard.setString(selection, forType: .string))
        }

        let menuFallback = SelectionCopyFallback(
            pasteboard: pasteboard, isCurrentApplication: { true }, requiresEditorMetadata: false,
            copyMenu: {
                writeSelection()
                return .performed
            },
            copyKeyboard: { preconditionFailure("Successful menu copy must not post a keyboard event") }
        )
        let fromMenu = try await menuFallback.readSelection { _ in
            preconditionFailure("Menu copy must not wait for modifier release")
        }
        precondition(fromMenu == selection)
        precondition(pasteboard.string(forType: .string) == original)
        precondition(pasteboard.data(forType: extraType) == extraData)

        var waitedForRelease = false
        let keyboardFallback = SelectionCopyFallback(
            pasteboard: pasteboard, isCurrentApplication: { true }, requiresEditorMetadata: false,
            copyMenu: { .unavailable }, copyKeyboard: {
                precondition(waitedForRelease)
                writeSelection()
                return true
            }
        )
        do {
            _ = try await keyboardFallback.readSelection { _ in false }
            preconditionFailure("Keyboard copy must not run before modifier release")
        } catch BenError.selectionUnavailable {
            precondition(pasteboard.string(forType: .string) == original)
        }
        let fromKeyboard = try await keyboardFallback.readSelection { _ in
            waitedForRelease = true
            return true
        }
        precondition(fromKeyboard == selection)
        precondition(pasteboard.string(forType: .string) == original)
        precondition(pasteboard.data(forType: extraType) == extraData)

        var sourceIsFrontmost = true
        let changingFocus = SelectionCopyFallback(
            pasteboard: pasteboard, isCurrentApplication: { sourceIsFrontmost }, requiresEditorMetadata: false,
            copyMenu: { .unavailable },
            copyKeyboard: { preconditionFailure("Keyboard copy must not target a different application") }
        )
        do {
            _ = try await changingFocus.readSelection { _ in
                sourceIsFrontmost = false
                return true
            }
            preconditionFailure("Losing the source application must abort copy")
        } catch BenError.selectionUnavailable {
            precondition(pasteboard.string(forType: .string) == original)
        }

        let noCopy = SelectionCopyFallback(
            pasteboard: pasteboard, isCurrentApplication: { true }, requiresEditorMetadata: false,
            copyMenu: { .unavailable }, copyKeyboard: { true }
        )
        do {
            _ = try await noCopy.readSelection { _ in true }
            preconditionFailure("Unchanged clipboard must not be read as the selection")
        } catch BenError.selectionUnavailable {
            precondition(pasteboard.string(forType: .string) == original)
        }
        do {
            _ = try await keyboardFallback.readSelection { _ in
                pasteboard.clearContents()
                precondition(pasteboard.setString("A newer user copy", forType: .string))
                return true
            }
            preconditionFailure("A clipboard change while waiting must abort keyboard copy")
        } catch BenError.selectionUnavailable {
            precondition(pasteboard.string(forType: .string) == "A newer user copy")
        }
        print("Selection copy checks passed")
    }
}
