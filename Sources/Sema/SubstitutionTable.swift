import AST

private final class MappingRef {

  init(_ value: [TypeVariable: TypeBase] = [:]) {
    self.value = value
  }

  var value: [TypeVariable: TypeBase]

}

public struct SubstitutionTable {

  public init(_ mappings: [TypeVariable: TypeBase] = [:]) {
    self.mappingsRef = MappingRef(mappings)
  }

  private var mappingsRef: MappingRef
  private var mappings: [TypeVariable: TypeBase] {
    get { return mappingsRef.value }
    set {
      guard isKnownUniquelyReferenced(&mappingsRef) else {
        mappingsRef = MappingRef(newValue)
        return
      }
      mappingsRef.value = newValue
    }
  }

  public func substitution(for type: TypeBase) -> TypeBase {
    if let var_ = type as? TypeVariable {
      return mappings[var_].map { substitution(for: $0) } ?? var_
    }
    return type
  }

  public mutating func set(substitution: TypeBase, for var_: TypeVariable) {
    let walked = self.substitution(for: var_)
    guard let key = walked as? TypeVariable else {
      assert(walked == substitution, "inconsistent substitution")
      return
    }
    assert(key != substitution, "occur check failed")
    mappings[key] = substitution
  }

  public func reified(in context: ASTContext) -> SubstitutionTable {
    var visited: [TupleType] = []
    var reifiedMappings: [TypeVariable: TypeBase] = [:]
    for (key, value) in mappings {
      reifiedMappings[key] = reify(type: value, in: context, skipping: &visited)
    }
    return SubstitutionTable(reifiedMappings)
  }

  public func reify(type: TypeBase, in context: ASTContext) -> TypeBase {
    var visited: [TupleType] = []
    return reify(type: type, in: context, skipping: &visited)
  }

  public func reify(type: TypeBase, in context: ASTContext, skipping visited: inout [TupleType])
    -> TypeBase
  {
    let walked = substitution(for: type)
    if let result = visited.first(where: { $0 == walked }) {
      return result
    }

    switch walked {
    case let t as Metatype    : return reify(type: t, in: context, skipping: &visited)
    case let t as FunctionType: return reify(type: t, in: context, skipping: &visited)
    case let t as TupleType   : return reify(type: t, in: context, skipping: &visited)
    case let t as UnionType   : return reify(type: t, in: context, skipping: &visited)
    default:
      return walked
    }
  }

  public func reify(type: Metatype, in context: ASTContext, skipping visited: inout [TupleType])
    -> Metatype
  {
    return reify(type: type.type, in: context, skipping: &visited).metatype
  }

  public func reify(type: FunctionType, in context: ASTContext, skipping visited: inout [TupleType])
    -> FunctionType
  {
    return context.getFunctionType(
      from: reify(type: type.domain, in: context, skipping: &visited),
      to: reify(type: type.codomain, in: context, skipping: &visited))
  }

  public func reify(type: TupleType, in context: ASTContext, skipping visited: inout [TupleType])
    -> TupleType
  {
    // Note that reifying a nominal type actually mutates said type.
    visited.append(type)
    type.elements = type.elements.map {
      TupleTypeElem(label: $0.label, type: reify(type: $0.type, in: context, skipping: &visited))
    }
    return type
  }

  public func reify(type: UnionType, in context: ASTContext, skipping visited: inout [TupleType])
    -> TypeBase
  {
    return context.getUnionType(cases: Set(type.cases.map({
      reify(type: $0, in: context, skipping: &visited)
    })))
  }

  /// Determines whether this substitution table is equivalent to another one, up to the variables
  /// they share.
  ///
  /// Let a substitution table be a partial function `V -> T` where `V` is the set of type variables
  /// and `T` the set of types. Two tables `t1`, `t2` are equivalent if for all variable `v` such
  /// both `t1` and `t2` are defined `t1(v) = t2(v)`. Variables outside of represent intermediate
  /// results introduced by the solver, and irrelevant after reification.
  public func isEquivalent(to other: SubstitutionTable) -> Bool {
    if self.mappingsRef === other.mappingsRef {
      // Nothing to do if both tables are trivially equal.
      return true
    }

    for key in Set(mappings.keys).intersection(other.mappings.keys) {
      guard mappings[key] == other.mappings[key]
        else { return false }
    }
    return true
  }

}

extension SubstitutionTable: Hashable {

  public var hashValue: Int {
    return mappings.keys.reduce(17) { h, key in 31 &* h &+ key.hashValue }
  }

  public static func == (lhs: SubstitutionTable, rhs: SubstitutionTable) -> Bool {
    return lhs.mappingsRef === rhs.mappingsRef || lhs.mappings == rhs.mappings
  }

}

extension SubstitutionTable: Sequence {

  public func makeIterator() -> Dictionary<TypeVariable, TypeBase>.Iterator {
    return mappings.makeIterator()
  }

}

extension SubstitutionTable: ExpressibleByDictionaryLiteral {

  public init(dictionaryLiteral elements: (TypeVariable, TypeBase)...) {
    self.init(Dictionary(uniqueKeysWithValues: elements))
  }

}

extension SubstitutionTable: CustomDebugStringConvertible {

  public var debugDescription: String {
    var result = ""
    for (v, t) in self.mappings {
      result += "\(v) => \(t)\n"
    }
    return result
  }

}
