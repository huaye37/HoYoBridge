import BridgeCore
import Darwin
import Foundation

func fail(_ message: String, status: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
  exit(status)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, arguments[0] == "validate" else {
  fail("usage: bridge-catalog validate <unsigned-development-catalog.json>", status: 2)
}

let path = arguments[1]
let data: Data
do {
  data = try Data(contentsOf: URL(fileURLWithPath: path))
} catch {
  fail("unable to read \(path): \(error.localizedDescription)")
}

do {
  let catalog = try SignedCatalogLoader.loadUnsignedDevelopmentCatalog(data)
  print("VALID — unsigned development catalog")
  print("This file passed semantic validation but is not trusted for remote updates.")
  print("Catalog:  \(catalog.catalogVersion) (schema \(catalog.schemaVersion))")
  print("Games:    \(catalog.games.count)")
  print("Runtimes: \(catalog.runtimes.count)")
  print("Profiles: \(catalog.profiles.count)")
  for runtime in catalog.runtimes.sorted(by: { $0.id < $1.id }) {
    print(
      "- runtime \(runtime.id): \(runtime.backend.rawValue) \(runtime.version), \(runtime.acquisition.rawValue)"
    )
  }
  if catalog.profiles.isEmpty {
    print("No game-version profile is enabled; the launcher must refuse to claim compatibility.")
  }
} catch CatalogLoadError.invalidCatalog(let issues) {
  for issue in issues {
    FileHandle.standardError.write(Data("\(issue.path) [\(issue.code)]: \(issue.message)\n".utf8))
  }
  exit(1)
} catch {
  fail("catalog validation failed: \(error)")
}
