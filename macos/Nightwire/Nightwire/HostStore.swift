import Foundation
import SQLite3

enum HostStoreError: Error {
    case openFailed(String)
    case executeFailed(String)
}

final class HostStore {
    private var db: OpaquePointer?

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite").path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw HostStoreError.openFailed(message)
        }
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func loadTargets() -> [TrackedTarget] {
        let sql = """
        SELECT id, address, visible, color_index, created_at, label, color_hex, group_name, role
        FROM targets
        ORDER BY created_at ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var targets: [TrackedTarget] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = stringColumn(statement, 0) ?? UUID().uuidString
            let address = stringColumn(statement, 1) ?? ""
            let visible = sqlite3_column_int(statement, 2) == 1
            let colorIndex = Int(sqlite3_column_int(statement, 3))
            let created = sqlite3_column_double(statement, 4)
            let label = stringColumn(statement, 5) ?? ""
            let colorHex = stringColumn(statement, 6)
            let groupName = stringColumn(statement, 7) ?? ""
            let role = TargetRole(rawValue: stringColumn(statement, 8) ?? "") ?? .user
            targets.append(
                TrackedTarget(
                    id: UUID(uuidString: idString) ?? UUID(),
                    address: address,
                    label: label,
                    isVisibleOnChart: visible,
                    colorIndex: colorIndex,
                    colorHex: colorHex,
                    groupName: groupName,
                    role: role,
                    createdAt: Date(timeIntervalSince1970: created)
                )
            )
        }
        return targets
    }

    func upsert(_ target: TrackedTarget) {
        let sql = """
        INSERT INTO targets (id, address, visible, color_index, created_at, label, color_hex, group_name, role)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            address = excluded.address,
            visible = excluded.visible,
            color_index = excluded.color_index,
            label = excluded.label,
            color_hex = excluded.color_hex,
            group_name = excluded.group_name,
            role = excluded.role;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, target.id.uuidString)
        bind(statement, 2, target.address)
        sqlite3_bind_int(statement, 3, target.isVisibleOnChart ? 1 : 0)
        sqlite3_bind_int(statement, 4, Int32(target.colorIndex))
        sqlite3_bind_double(statement, 5, target.createdAt.timeIntervalSince1970)
        bind(statement, 6, target.label)
        if let hex = target.colorHex, !hex.isEmpty {
            bind(statement, 7, hex)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        bind(statement, 8, target.groupName)
        bind(statement, 9, target.role.rawValue)
        sqlite3_step(statement)
    }

    func delete(id: UUID) {
        try? execute("DELETE FROM samples WHERE target_id = '\(id.uuidString)';")
        try? execute("DELETE FROM targets WHERE id = '\(id.uuidString)';")
    }

    func insertSample(targetId: UUID, timestamp: Date, latencyMs: Double?) {
        let sql = """
        INSERT INTO samples (id, target_id, timestamp, latency_ms)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, UUID().uuidString)
        bind(statement, 2, targetId.uuidString)
        sqlite3_bind_double(statement, 3, timestamp.timeIntervalSince1970)
        if let latencyMs {
            sqlite3_bind_double(statement, 4, latencyMs)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_step(statement)
    }

    func loadSamples(targetId: UUID, limit: Int) -> [PingSample] {
        let sql = """
        SELECT id, timestamp, latency_ms
        FROM samples
        WHERE target_id = ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, targetId.uuidString)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var rows: [PingSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = stringColumn(statement, 0)
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let latency: Double?
            if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                latency = nil
            } else {
                latency = sqlite3_column_double(statement, 2)
            }
            rows.append(
                PingSample(
                    id: UUID(uuidString: idString ?? "") ?? UUID(),
                    timestamp: timestamp,
                    latencyMs: latency
                )
            )
        }
        return rows.reversed()
    }

    func loadChartSettings() -> ChartSettings {
        guard let json = loadSetting("chart"),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ChartSettings.self, from: data)
        else {
            return ChartSettings()
        }
        return decoded
    }

    func saveChartSettings(_ settings: ChartSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        saveSetting("chart", json)
    }

    func prune(keepLast: Int) {
        let sql = """
        DELETE FROM samples
        WHERE id NOT IN (
            SELECT id FROM samples
            ORDER BY timestamp DESC
            LIMIT \(max(keepLast, 1))
        );
        """
        try? execute(sql)
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS targets (
            id TEXT PRIMARY KEY,
            address TEXT NOT NULL UNIQUE,
            visible INTEGER NOT NULL DEFAULT 1,
            color_index INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            color_hex TEXT,
            group_name TEXT NOT NULL DEFAULT '',
            role TEXT NOT NULL DEFAULT 'user'
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS samples (
            id TEXT PRIMARY KEY,
            target_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            latency_ms REAL,
            FOREIGN KEY (target_id) REFERENCES targets(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS samples_target_time ON samples(target_id, timestamp);")
        try execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)

        let columns = tableColumns("targets")
        if !columns.contains("label") {
            try execute("ALTER TABLE targets ADD COLUMN label TEXT NOT NULL DEFAULT '';")
        }
        if !columns.contains("color_hex") {
            try execute("ALTER TABLE targets ADD COLUMN color_hex TEXT;")
        }
        if !columns.contains("group_name") {
            try execute("ALTER TABLE targets ADD COLUMN group_name TEXT NOT NULL DEFAULT '';")
        }
        if !columns.contains("role") {
            try execute("ALTER TABLE targets ADD COLUMN role TEXT NOT NULL DEFAULT 'user';")
        }
    }

    private func loadSetting(_ key: String) -> String? {
        let sql = "SELECT value FROM settings WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return stringColumn(statement, 0)
    }

    private func saveSetting(_ key: String, _ value: String) {
        let sql = """
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, key)
        bind(statement, 2, value)
        sqlite3_step(statement)
    }

    private func tableColumns(_ table: String) -> Set<String> {
        var columns = Set<String>()
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return columns
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = stringColumn(statement, 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "execute failed"
            sqlite3_free(error)
            throw HostStoreError.executeFailed(message)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: ptr)
    }
}
