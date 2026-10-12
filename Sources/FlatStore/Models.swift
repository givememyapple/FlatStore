import Foundation

class BaseRecord {
    let id: String
    let createdAt: Foundation.Date

    init(id: String = UUID().uuidString) {
        self.id = id
        self.createdAt = Foundation.Date()
    }

    func describe() -> String {
        "Record \(id)"
    }
}

class FlatApp {
    let appId: String
    let name: String
    let summary: String
    let iconURL: String?
    let developer: String
    let installs: Int
    let license: String
    let description: String

    init(appId: String, name: String, summary: String = "",
         iconURL: String? = nil, developer: String = "",
         installs: Int = 0, license: String = "", description: String = "") {
        self.appId = appId
        self.name = name
        self.summary = summary
        self.iconURL = iconURL
        self.developer = developer
        self.installs = max(0, installs)
        self.license = license
        self.description = description
    }

    var shortMeta: String {
        "\(developer) · \(installs) installs/mo · \(license)"
    }
}

class Session: BaseRecord {
    let login: String
    var timeOut: Foundation.Date?

    init(login: String) {
        self.login = login
        super.init()
    }

    override func describe() -> String {
        "Session of \(login)"
    }

    func toLine() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM.yyyy HH:mm:ss"
        let out = timeOut.map { fmt.string(from: $0) } ?? fmt.string(from: Foundation.Date())
        return "| \(login) | \(fmt.string(from: timeIn)) | \(out) |"
    }

    var timeIn: Foundation.Date {
        return createdAt
    }
}
