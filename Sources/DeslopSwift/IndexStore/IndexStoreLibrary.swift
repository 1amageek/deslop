import CIndexStore
import Foundation

/// libIndexStore's functions, loaded from a toolchain at run time. The
/// library stays loaded for the rest of the process: the functions it hands
/// out are called until the process ends, so it is never closed.
final class IndexStoreLibrary {
    private let errorDescription: cis_error_get_description_f
    private let errorDispose: cis_error_dispose_f
    private let storeCreate: cis_store_create_f
    private let storeDispose: cis_store_dispose_f
    private let storeUnitsApply: cis_store_units_apply_f
    private let unitReaderCreate: cis_unit_reader_create_f
    private let unitReaderDispose: cis_unit_reader_dispose_f
    private let unitReaderIsSystemUnit: cis_unit_reader_bool_f
    private let unitReaderHasMainFile: cis_unit_reader_bool_f
    private let unitReaderMainFile: cis_unit_reader_string_f
    private let unitReaderModificationTime: cis_unit_reader_get_modification_time_f
    private let unitReaderDependenciesApply: cis_unit_reader_dependencies_apply_f
    private let dependencyKind: cis_unit_dependency_get_kind_f
    private let dependencyIsSystem: cis_unit_dependency_is_system_f
    private let dependencyFilePath: cis_unit_dependency_string_f
    private let dependencyName: cis_unit_dependency_string_f
    private let recordReaderCreate: cis_record_reader_create_f
    private let recordReaderDispose: cis_record_reader_dispose_f
    private let recordReaderOccurrencesApply: cis_record_reader_occurrences_apply_f
    private let occurrenceSymbol: cis_occurrence_get_symbol_f
    private let occurrenceRoles: cis_occurrence_get_roles_f
    private let occurrenceLineColumn: cis_occurrence_get_line_col_f
    private let occurrenceRelationsApply: cis_occurrence_relations_apply_f
    private let relationRoles: cis_symbol_relation_get_roles_f
    private let relationSymbol: cis_symbol_relation_get_symbol_f
    private let symbolKind: cis_symbol_get_int_f
    private let symbolSubkind: cis_symbol_get_int_f
    private let symbolProperties: cis_symbol_get_properties_f
    private let symbolName: cis_symbol_get_string_f
    private let symbolUSR: cis_symbol_get_string_f

    init(at url: URL) throws(FrontendError) {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            throw .indexStoreLibraryUnavailable("\(url.path): \(reason)")
        }
        func load<Function>(_ name: String, as type: Function.Type) throws(FrontendError) -> Function {
            guard let symbol = dlsym(handle, name) else {
                throw .indexStoreLibraryUnavailable("\(url.path) has no `\(name)`")
            }
            return unsafeBitCast(symbol, to: type)
        }
        errorDescription = try load("indexstore_error_get_description", as: cis_error_get_description_f.self)
        errorDispose = try load("indexstore_error_dispose", as: cis_error_dispose_f.self)
        storeCreate = try load("indexstore_store_create", as: cis_store_create_f.self)
        storeDispose = try load("indexstore_store_dispose", as: cis_store_dispose_f.self)
        storeUnitsApply = try load("indexstore_store_units_apply_f", as: cis_store_units_apply_f.self)
        unitReaderCreate = try load("indexstore_unit_reader_create", as: cis_unit_reader_create_f.self)
        unitReaderDispose = try load("indexstore_unit_reader_dispose", as: cis_unit_reader_dispose_f.self)
        unitReaderIsSystemUnit = try load("indexstore_unit_reader_is_system_unit", as: cis_unit_reader_bool_f.self)
        unitReaderHasMainFile = try load("indexstore_unit_reader_has_main_file", as: cis_unit_reader_bool_f.self)
        unitReaderMainFile = try load("indexstore_unit_reader_get_main_file", as: cis_unit_reader_string_f.self)
        unitReaderModificationTime = try load(
            "indexstore_unit_reader_get_modification_time", as: cis_unit_reader_get_modification_time_f.self
        )
        unitReaderDependenciesApply = try load(
            "indexstore_unit_reader_dependencies_apply_f", as: cis_unit_reader_dependencies_apply_f.self
        )
        dependencyKind = try load("indexstore_unit_dependency_get_kind", as: cis_unit_dependency_get_kind_f.self)
        dependencyIsSystem = try load("indexstore_unit_dependency_is_system", as: cis_unit_dependency_is_system_f.self)
        dependencyFilePath = try load("indexstore_unit_dependency_get_filepath", as: cis_unit_dependency_string_f.self)
        dependencyName = try load("indexstore_unit_dependency_get_name", as: cis_unit_dependency_string_f.self)
        recordReaderCreate = try load("indexstore_record_reader_create", as: cis_record_reader_create_f.self)
        recordReaderDispose = try load("indexstore_record_reader_dispose", as: cis_record_reader_dispose_f.self)
        recordReaderOccurrencesApply = try load(
            "indexstore_record_reader_occurrences_apply_f", as: cis_record_reader_occurrences_apply_f.self
        )
        occurrenceSymbol = try load("indexstore_occurrence_get_symbol", as: cis_occurrence_get_symbol_f.self)
        occurrenceRoles = try load("indexstore_occurrence_get_roles", as: cis_occurrence_get_roles_f.self)
        occurrenceLineColumn = try load("indexstore_occurrence_get_line_col", as: cis_occurrence_get_line_col_f.self)
        occurrenceRelationsApply = try load(
            "indexstore_occurrence_relations_apply_f", as: cis_occurrence_relations_apply_f.self
        )
        relationRoles = try load("indexstore_symbol_relation_get_roles", as: cis_symbol_relation_get_roles_f.self)
        relationSymbol = try load("indexstore_symbol_relation_get_symbol", as: cis_symbol_relation_get_symbol_f.self)
        symbolKind = try load("indexstore_symbol_get_kind", as: cis_symbol_get_int_f.self)
        symbolSubkind = try load("indexstore_symbol_get_subkind", as: cis_symbol_get_int_f.self)
        symbolProperties = try load("indexstore_symbol_get_properties", as: cis_symbol_get_properties_f.self)
        symbolName = try load("indexstore_symbol_get_name", as: cis_symbol_get_string_f.self)
        symbolUSR = try load("indexstore_symbol_get_usr", as: cis_symbol_get_string_f.self)
    }

    /// The index store at `path`, open until `close(_:)`.
    func openStore(at path: String) throws(FrontendError) -> cis_indexstore_t {
        var error: cis_error_t?
        guard let store = storeCreate(path, &error) else {
            throw .indexStoreUnreadable("\(path): \(consume(error))")
        }
        return store
    }

    func close(_ store: cis_indexstore_t) {
        storeDispose(store)
    }

    /// The name of every unit of `store`.
    func unitNames(in store: cis_indexstore_t) -> [String] {
        let context = CallbackContext<String>(library: self)
        withExtendedLifetime(context) {
            _ = storeUnitsApply(store, 0, Unmanaged.passUnretained(context).toOpaque()) { pointer, name in
                guard let pointer else { return false }
                Unmanaged<CallbackContext<String>>.fromOpaque(pointer).takeUnretainedValue()
                    .elements.append(IndexStoreLibrary.string(name))
                return true
            }
        }
        return context.elements
    }

    /// What the unit `name` of `store` says of itself and the records it depends on.
    func unit(_ name: String, in store: cis_indexstore_t) throws(FrontendError) -> IndexUnit {
        var error: cis_error_t?
        guard let unit = unitReaderCreate(store, name, &error) else {
            throw .indexStoreUnreadable("unit \(name): \(consume(error))")
        }
        defer { unitReaderDispose(unit) }
        var seconds: Int64 = 0
        var nanoseconds: Int64 = 0
        unitReaderModificationTime(unit, &seconds, &nanoseconds)
        let context = CallbackContext<IndexUnit.Record>(library: self)
        withExtendedLifetime(context) {
            _ = unitReaderDependenciesApply(unit, Unmanaged.passUnretained(context).toOpaque()) { pointer, dependency in
                guard let pointer else { return false }
                let context = Unmanaged<CallbackContext<IndexUnit.Record>>.fromOpaque(pointer).takeUnretainedValue()
                if let record = context.library.record(dependency) {
                    context.elements.append(record)
                }
                return true
            }
        }
        return IndexUnit(
            isSystem: unitReaderIsSystemUnit(unit),
            mainFile: unitReaderHasMainFile(unit) ? IndexStoreLibrary.string(unitReaderMainFile(unit)) : nil,
            modified: IndexUnit.Time(seconds: seconds, nanoseconds: nanoseconds),
            records: context.elements
        )
    }

    /// The occurrences the record `name` of `store` holds, in its order.
    func occurrences(ofRecord name: String, in store: cis_indexstore_t) throws(FrontendError) -> [IndexOccurrence] {
        var error: cis_error_t?
        guard let reader = recordReaderCreate(store, name, &error) else {
            throw .indexStoreUnreadable("record \(name): \(consume(error))")
        }
        defer { recordReaderDispose(reader) }
        let context = CallbackContext<IndexOccurrence>(library: self)
        withExtendedLifetime(context) {
            _ = recordReaderOccurrencesApply(reader, Unmanaged.passUnretained(context).toOpaque()) { pointer, occurrence in
                guard let pointer, let occurrence else { return false }
                let context = Unmanaged<CallbackContext<IndexOccurrence>>.fromOpaque(pointer).takeUnretainedValue()
                if let read = context.library.occurrence(occurrence) {
                    context.elements.append(read)
                }
                return true
            }
        }
        return context.elements
    }

    /// A non-system record dependency, if `dependency` is one.
    private func record(_ dependency: cis_unit_dependency_t?) -> IndexUnit.Record? {
        guard !dependencyIsSystem(dependency),
              dependencyKind(dependency) == UInt32(CIS_UNIT_DEPENDENCY_RECORD) else { return nil }
        return IndexUnit.Record(
            path: IndexStoreLibrary.string(dependencyFilePath(dependency)),
            name: IndexStoreLibrary.string(dependencyName(dependency))
        )
    }

    private func occurrence(_ occurrence: cis_occurrence_t) -> IndexOccurrence? {
        guard let found = occurrenceSymbol(occurrence) else { return nil }
        var line: UInt32 = 0
        var column: UInt32 = 0
        occurrenceLineColumn(occurrence, &line, &column)
        let context = CallbackContext<IndexOccurrence.Relation>(library: self)
        withExtendedLifetime(context) {
            _ = occurrenceRelationsApply(occurrence, Unmanaged.passUnretained(context).toOpaque()) { pointer, relation in
                guard let pointer, let relation else { return false }
                let context = Unmanaged<CallbackContext<IndexOccurrence.Relation>>.fromOpaque(pointer).takeUnretainedValue()
                if let read = context.library.relation(relation) {
                    context.elements.append(read)
                }
                return true
            }
        }
        return IndexOccurrence(
            symbol: symbol(found),
            roles: SymbolRoles(rawValue: occurrenceRoles(occurrence)),
            line: Int(line),
            column: Int(column),
            relations: context.elements
        )
    }

    private func relation(_ relation: cis_symbol_relation_t) -> IndexOccurrence.Relation? {
        guard let related = relationSymbol(relation) else { return nil }
        return IndexOccurrence.Relation(roles: SymbolRoles(rawValue: relationRoles(relation)), symbol: symbol(related))
    }

    private func symbol(_ symbol: cis_symbol_t) -> IndexSymbol {
        IndexSymbol(
            usr: IndexStoreLibrary.string(symbolUSR(symbol)),
            name: IndexStoreLibrary.string(symbolName(symbol)),
            kind: IndexSymbol.Kind(rawValue: Int(symbolKind(symbol))) ?? .unknown,
            subkind: Int(symbolSubkind(symbol)),
            properties: symbolProperties(symbol)
        )
    }

    /// The text of `reference`, which libIndexStore owns.
    private static func string(_ reference: cis_string_ref_t) -> String {
        guard let data = reference.data, reference.length > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: data, count: reference.length), as: UTF8.self)
    }

    /// The description of `error`, which is then disposed of.
    private func consume(_ error: cis_error_t?) -> String {
        guard let error else { return "unknown error" }
        let description = errorDescription(error).map { String(cString: $0) } ?? "unknown error"
        errorDispose(error)
        return description
    }
}

/// What a C callback collects into, through its context pointer, while the
/// library function that calls it runs.
private final class CallbackContext<Element> {
    let library: IndexStoreLibrary
    var elements: [Element] = []

    init(library: IndexStoreLibrary) {
        self.library = library
    }
}
