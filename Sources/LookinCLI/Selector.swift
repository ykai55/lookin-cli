import CoreGraphics
import Foundation
import LookinCore

public enum Selector: Equatable {
    case oid(UInt)
    case point(CGPoint)
    case axe(String)

    public static func parse(_ raw: String) throws -> Selector {
        guard let colon = raw.firstIndex(of: ":") else {
            throw SelectorError.badFormat(raw)
        }
        let scheme = String(raw[..<colon])
        let value = String(raw[raw.index(after: colon)...])
        switch scheme {
        case "oid":
            guard let n = UInt(value) else { throw SelectorError.badValue(raw) }
            return .oid(n)
        case "point":
            let parts = value.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1].trimmingCharacters(in: .whitespaces))
            else { throw SelectorError.badValue(raw) }
            return .point(CGPoint(x: x, y: y))
        case "axe":
            guard !value.isEmpty else { throw SelectorError.badValue(raw) }
            return .axe(value)
        default:
            throw SelectorError.badFormat(raw)
        }
    }
}

public enum SelectorError: Error, CustomStringConvertible {
    case badFormat(String)
    case badValue(String)
    case noMatch(String)
    case axeNotInstalled
    case noSimulatorUDID

    public var description: String {
        switch self {
        case let .badFormat(r):
            "bad selector '\(r)': expected oid:<n>, point:<x>,<y>, or axe:<id>"
        case let .badValue(r):
            "bad selector value '\(r)'"
        case let .noMatch(r):
            "selector '\(r)' matched no element"
        case .axeNotInstalled:
            "'axe' not found on PATH (needed for axe: selectors)"
        case .noSimulatorUDID:
            "session has no simulator UDID; re-run `lookin attach`"
        }
    }
}

public struct ResolvedElement {
    public let raw: String // the original selector string
    public let item: LookinDisplayItem
    public let oid: UInt
}

/// Resolves a parsed selector to a concrete display item within `hierarchy`.
/// The axe: path shells out to the axe CLI (soft dependency).
public func resolveSelector(
    raw: String,
    selector: Selector,
    hierarchy: Hierarchy,
    session: Session,
) throws -> ResolvedElement {
    switch selector {
    case let .oid(n):
        guard let item = hierarchy.item(oid: n) else {
            throw SelectorError.noMatch(raw)
        }
        return ResolvedElement(raw: raw, item: item, oid: n)

    case let .point(p):
        guard let item = hierarchy.hitTest(point: p),
              let oid = Hierarchy.oid(of: item)
        else {
            throw SelectorError.noMatch(raw)
        }
        return ResolvedElement(raw: raw, item: item, oid: oid)

    case let .axe(axId):
        guard AxeBridge.isInstalled else { throw SelectorError.axeNotInstalled }
        guard let udid = session.simulatorUDID else { throw SelectorError.noSimulatorUDID }
        let elements = try AxeBridge.describeUI(udid: udid)
        guard let el = elements.first(where: { $0.axId == axId }) else {
            throw SelectorError.noMatch(raw)
        }
        let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
        guard let item = hierarchy.hitTest(point: center),
              let oid = Hierarchy.oid(of: item)
        else {
            throw SelectorError.noMatch("\(raw) (no view at \(center))")
        }
        return ResolvedElement(raw: raw, item: item, oid: oid)
    }
}
