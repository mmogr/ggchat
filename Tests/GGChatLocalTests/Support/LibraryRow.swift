import Foundation
import SQLite3

/// The first bytes of a GGUF v3 file of no tensors, holding a chat model's
/// fit keys for `arch`, as gglib-ffi's own tests write one (`test_gguf.rs`).
func syntheticGGUF(arch: String = "llama", trainedCtx: UInt32 = 40_960) -> Data {
    var pairs: [(String, Data)] = []
    func text(_ key: String, _ value: String) { pairs.append((key, uint32(8) + string(value))) }
    func number(_ key: String, _ value: UInt32) { pairs.append((key, uint32(4) + uint32(value))) }
    text("general.architecture", arch)
    text("general.name", "Test model")
    number("\(arch).context_length", trainedCtx)
    number("\(arch).block_count", 16)
    number("\(arch).attention.head_count", 32)
    number("\(arch).attention.head_count_kv", 8)
    number("\(arch).attention.key_length", 64)
    number("\(arch).attention.value_length", 64)

    var file = Data("GGUF".utf8) + uint32(3) + uint64(0) + uint64(UInt64(pairs.count))
    for (key, value) in pairs { file += string(key) + value }
    return file
}

private func uint32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
private func uint64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
private func string(_ text: String) -> Data { uint64(UInt64(text.utf8.count)) + Data(text.utf8) }

/// Stores a model in a library's database as a download leaves one: its
/// weights at `weights`, trained for 40,960 tokens, with the KV shape the
/// synthetic header carries. Answers its id.
///
/// The binding has no call that adds a model, since a phone gets its models
/// by download, so the row is written as gglib's own repository tests write
/// one, into the database gglib made when the library was opened, with the
/// columns its schema requires at this pin. A gglib pin whose schema
/// changes the `models` table fails InstalledLibraryTests here, so a pin
/// bump checks this insert against that release's migrations.
func storeModel(at weights: URL, in database: URL) throws -> Int64 {
    var db: OpaquePointer?
    guard sqlite3_open(database.path(percentEncoded: false), &db) == SQLITE_OK else {
        throw RowError(message: "could not open \(database.lastPathComponent)")
    }
    defer { sqlite3_close(db) }
    let metadata = #"""
        {"llama.block_count":"16","llama.attention.head_count":"32","llama.attention.head_count_kv":"8",\#
        "llama.attention.key_length":"64","llama.attention.value_length":"64"}
        """#
    let insert = """
        INSERT INTO models (name, file_path, param_count_b, architecture, quantization, context_length, \
        metadata, added_at, model_key)
        VALUES ('Test model', ?, 1.0, 'llama', 'Q4_K_M', 40960, ?, '2026-01-01 00:00:00', 'test-model')
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK else {
        throw RowError(message: String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, weights.path(percentEncoded: false), -1, transient)
    sqlite3_bind_text(statement, 2, metadata, -1, transient)
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw RowError(message: String(cString: sqlite3_errmsg(db)))
    }
    return sqlite3_last_insert_rowid(db)
}

struct RowError: Error, CustomStringConvertible {
    let message: String

    var description: String { "the model's row was not stored: \(message)" }
}
