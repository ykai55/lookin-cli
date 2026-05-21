import Foundation
import LookinCore

// MARK: - Public Node (stable JSON shape for `tree` and `find`)

public struct PublicNode: Encodable {
    public let oid: UInt
    public let `class`: String
    public let address: String
    public let axId: String?
    public let figmaRef: String?
    public let label: String?
    public let frame: PublicRect
    public let hidden: Bool
    public let alpha: Double
    public let children: [PublicNode]

    public init(from item: LookinDisplayItem, depth: Int) {
        let obj = item.viewObject ?? item.layerObject
        oid = obj?.oid ?? 0
        `class` = obj?.rawClassName() ?? "(unknown)"
        address = obj?.memoryAddress ?? ""

        // specialTrace carries the accessibilityIdentifier on LookinObject
        let rawAxId = obj?.specialTrace
        axId = (rawAxId?.isEmpty == false) ? rawAxId : nil

        // figmaRef: strip "figma:" prefix from axId
        if let ax = axId, ax.hasPrefix("figma:") {
            figmaRef = String(ax.dropFirst("figma:".count))
        } else {
            figmaRef = nil
        }

        // customDisplayTitle or nil
        label = item.customDisplayTitle?.isEmpty == false ? item.customDisplayTitle : nil

        frame = PublicRect(rect: item.frame)
        hidden = item.isHidden
        alpha = Double(item.alpha)

        if depth <= 0 {
            children = []
        } else {
            children = (item.subitems ?? []).map { PublicNode(from: $0, depth: depth - 1) }
        }
    }
}

public struct PublicRect: Encodable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }
}

// MARK: - Public Attribute (stable JSON shape for `attributes`)

public struct PublicAttribute: Encodable {
    public let group: String
    /// Human-readable group label; `nil` when `group` is already a custom title.
    public let groupName: String?
    public let section: String
    public let identifier: String
    /// Human-readable attribute label decoded from `identifier`; `nil` if unknown.
    public let name: String?
    public let attrType: Int
    public let value: PublicAttributeValue
}

public enum PublicAttributeValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case rect(x: Double, y: Double, width: Double, height: Double)
    case point(x: Double, y: Double)
    case size(width: Double, height: Double)
    case color(r: Double, g: Double, b: Double, a: Double)
    case raw(String)
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(s):
            try container.encode(s)
        case let .number(n):
            try container.encode(n)
        case let .bool(b):
            try container.encode(b)
        case let .rect(x, y, w, h):
            try container.encode(["x": x, "y": y, "width": w, "height": h])
        case let .point(x, y):
            try container.encode(["x": x, "y": y])
        case let .size(w, h):
            try container.encode(["width": w, "height": h])
        case let .color(r, g, b, a):
            try container.encode(["r": r, "g": g, "b": b, "a": a])
        case let .raw(s):
            try container.encode(s)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - Attribute extraction helpers

public func publicAttributes(from item: LookinDisplayItem) -> [PublicAttribute] {
    var result: [PublicAttribute] = []
    let allGroups = item.queryAllAttrGroupList() ?? []
    for group in allGroups {
        let groupKey = group.identifier ?? group.userCustomTitle ?? "(group)"
        for section in group.attrSections ?? [] {
            let sectionKey = section.identifier ?? "(section)"
            for attr in section.attributes ?? [] {
                let attrId = attr.identifier ?? "(attr)"
                let value = publicValue(from: attr)
                // `displayTitle` is set only for user-custom attrs; otherwise
                // decode the closed-set short code via the static label table.
                let humanName = attr.displayTitle?.isEmpty == false
                    ? attr.displayTitle
                    : AttributeLabels.name(for: attrId)
                result.append(PublicAttribute(
                    group: groupKey,
                    groupName: AttributeLabels.groupName(for: groupKey),
                    section: sectionKey,
                    identifier: attrId,
                    name: humanName,
                    attrType: Int(attr.attrType.rawValue),
                    value: value,
                ))
            }
        }
    }
    return result
}

private func publicValue(from attr: LookinAttribute) -> PublicAttributeValue {
    guard let v = attr.value else { return .null }
    // LookinAttrType raw values from LookinAttrType.h (NS_ENUM bridged by raw value in Swift)
    // 0=None, 1=Void, 2=Char, 3=Int, 4=Short, 5=Long, 6=LongLong,
    // 7=UnsignedChar, 8=UnsignedInt, 9=UnsignedShort, 10=UnsignedLong, 11=UnsignedLongLong,
    // 12=Float, 13=Double, 14=BOOL, 15=Sel, 16=Class,
    // 17=CGPoint, 18=CGVector, 19=CGSize, 20=CGRect, 21=CGAffineTransform,
    // 22=UIEdgeInsets, 23=UIOffset, 24=NSString, 25=EnumInt, 26=EnumLong,
    // 27=UIColor, 28=CustomObj, 29=EnumString, 30=Shadow, 31=Json
    switch attr.attrType.rawValue {
    case 24: // NSString
        return .string((v as? String) ?? "\(v)")
    case 14: // BOOL
        if let n = v as? NSNumber { return .bool(n.boolValue) }
        return .raw("\(v)")
    case 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13: // Int through Double
        if let n = v as? NSNumber { return .number(n.doubleValue) }
        return .raw("\(v)")
    case 25, 26, 29: // EnumInt, EnumLong, EnumString
        if let s = v as? String { return .string(s) }
        if let n = v as? NSNumber { return .number(n.doubleValue) }
        return .raw("\(v)")
    case 20: // CGRect
        if let arr = v as? [NSNumber], arr.count >= 4 {
            return .rect(x: arr[0].doubleValue, y: arr[1].doubleValue,
                         width: arr[2].doubleValue, height: arr[3].doubleValue)
        }
        return .raw("\(v)")
    case 17: // CGPoint
        if let arr = v as? [NSNumber], arr.count >= 2 {
            return .point(x: arr[0].doubleValue, y: arr[1].doubleValue)
        }
        return .raw("\(v)")
    case 19: // CGSize
        if let arr = v as? [NSNumber], arr.count >= 2 {
            return .size(width: arr[0].doubleValue, height: arr[1].doubleValue)
        }
        return .raw("\(v)")
    case 27: // UIColor
        if let arr = v as? [NSNumber], arr.count >= 4 {
            return .color(r: arr[0].doubleValue, g: arr[1].doubleValue,
                          b: arr[2].doubleValue, a: arr[3].doubleValue)
        }
        return .raw("\(v)")
    default:
        return .raw("\(v)")
    }
}

// MARK: - Flat list helper

public func flatItems(from roots: [LookinDisplayItem]) -> [LookinDisplayItem] {
    var result: [LookinDisplayItem] = []
    func visit(_ item: LookinDisplayItem) {
        result.append(item)
        for child in item.subitems ?? [] {
            visit(child)
        }
    }
    for root in roots {
        visit(root)
    }
    return result
}
