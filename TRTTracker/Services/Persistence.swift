import Foundation
import SwiftData

/// Contêiner SwiftData local (RF-DAD-02): sem iCloud, com migração versionada e
/// proteção de dados "até a primeira autenticação", para permitir o reagendamento em segundo plano.
@MainActor
enum Persistence {
    static let container: ModelContainer = makeContainer()

    private static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TRTTracker", directoryHint: .isDirectory)
    }

    private static func makeContainer() -> ModelContainer {
        let fm = FileManager.default
        let directory = storeDirectory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema,
                                               url: directory.appending(path: "TRTTracker.store"),
                                               cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: TRTMigrationPlan.self,
                                               configurations: configuration)
            applyFileProtection()
            return container
        } catch {
            fatalError("Não foi possível abrir o banco de dados local: \(error)")
        }
    }

    /// Garante o nível de proteção no diretório e nos arquivos do banco (inclusive -wal e -shm).
    static func applyFileProtection() {
        let fm = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.setAttributes(attributes, ofItemAtPath: storeDirectory.path)
        let files = (try? fm.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? fm.setAttributes(attributes, ofItemAtPath: file.path)
        }
    }
}
