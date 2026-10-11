import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Gtk
import GdkPixBuf
import GLib


struct AppConfig {
    var userName = "SwiftUser"
    var locale = "en-GB"
    var perPage = 21
    var windowWidth = 720
    var windowHeight = 640
    var reportPath = "session_report.txt"
}

var config = AppConfig()

class FlatApp {
    let appId: String
    var name: String
    var summary: String
    var iconURL: String?
    var developer: String
    var installs: Int
    var license: String
    var description: String

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

class Session {
    let login: String
    let timeIn: Foundation.Date
    var timeOut: Foundation.Date?

    init(login: String) {
        self.login = login
        self.timeIn = Foundation.Date()
    }

    func toLine() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM.yyyy HH:mm:ss"
        let out = timeOut.map { fmt.string(from: $0) } ?? fmt.string(from: Foundation.Date())
        return "| \(login) | \(fmt.string(from: timeIn)) | \(out) |"
    }
}



class MainQueue {
    static let shared = MainQueue()
    private var tasks: [() -> Void] = []
    private let lock = NSLock()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        _ = GLib.idleAdd { _ in
            MainQueue.shared.drain()
            return GLib.sourceContinue
        }
    }

    func async(_ block: @escaping () -> Void) {
        lock.lock()
        tasks.append(block)
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let pending = tasks
        tasks.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }
}


enum Flathub {
    static func search(query: String, page: Int) async throws -> [FlatApp] {
        let url = URL(string: "https://flathub.org/api/v2/search?locale=\(config.locale)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let body = """
        {"query":"\(query.replacingOccurrences(of: "\"", with: "\\\""))","filters":[],"hits_per_page":\(config.perPage),"page":\(page)}
        """
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else {
            return []
        }

        return hits.compactMap { item in
            guard let appId = item["app_id"] as? String,
                  let name = item["name"] as? String else { return nil }

            return FlatApp(
                appId: appId,
                name: name,
                summary: item["summary"] as? String ?? "",
                iconURL: item["icon"] as? String,
                developer: item["developer_name"] as? String ?? "",
                installs: item["installs_last_month"] as? Int ?? 0,
                license: item["project_license"] as? String ?? "",
                description: item["description"] as? String ?? ""
            )
        }
    }
}

extension URLSession {
    func data(for request: URLRequest) async throws -> (Foundation.Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = dataTask(with: request) { data, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let data = data, let response = response {
                    cont.resume(returning: (data, response))
                } else {
                    cont.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    }
}


class FlatStoreApp {
    private var window: ApplicationWindow?
    private var listBox: Box?
    private var statusLabel: Label?
    private var searchEntry: Entry?
    private var pageSpin: SpinButton?
    private var scrolled: ScrolledWindow?

    private var currentSession: Session?
    private var sessions: [Session] = []


    func run() {
        _ = Application.run(startupHandler: nil) { app in
            self.buildUI(app: app)
        }
    }

    private func buildUI(app: ApplicationRef) {
        MainQueue.shared.start()

        currentSession = Session(login: config.userName)
        sessions.append(currentSession!)

        let win = ApplicationWindow(application: app)
        win.title = "FlatStore — Flathub"
        win.setDefaultSize(width: config.windowWidth, height: config.windowHeight)
        win.connect(signal: .destroy) { [weak self] in
            self?.saveReport()
        }
        window = win

        let root = Box(orientation: .vertical, spacing: 8)
        win.add(widget: root)

        let toolbar = Box(orientation: .horizontal, spacing: 6)

        let entry = Entry()
        entry.placeholderText = "Search apps… (e.g. telegram)"
        searchEntry = entry
        toolbar.packStart(child: entry, expand: true, fill: true, padding: 4)

        toolbar.packStart(child: Label(str: "Page:"), expand: false, fill: false, padding: 2)

        let spin = SpinButton(
            adjustment: Adjustment(value: 1, lower: 1, upper: 999,
                                   stepIncrement: 1, pageIncrement: 5, pageSize: 0),
            climbRate: 1, digits: 0
        )
        pageSpin = spin
        toolbar.packStart(child: spin, expand: false, fill: false, padding: 2)

        let searchBtn = Button(label: "Search")
        searchBtn.connect(signal: .clicked) { [weak self] in
            self?.doSearch()
        }
        toolbar.packStart(child: searchBtn, expand: false, fill: false, padding: 4)

        entry.connect(signal: .activate) { [weak self] in
            self?.doSearch()
        }

        root.packStart(child: toolbar, expand: false, fill: false, padding: 6)

        let status = Label(str: "Type a query and press Search")
        statusLabel = status
        root.packStart(child: status, expand: false, fill: false, padding: 4)

        let sc = ScrolledWindow()
        scrolled = sc
        let list = Box(orientation: .vertical, spacing: 6)
        listBox = list
        sc.add(widget: list)
        root.packStart(child: sc, expand: true, fill: true, padding: 0)

        win.showAll()
        win.present()
    }

    private func doSearch() {
        let query = (searchEntry?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let page = Int(pageSpin?.value ?? 1)

        guard !query.isEmpty else {
            statusLabel?.label = "Enter a search query"
            return
        }

        statusLabel?.label = "Searching «\(query)» page \(page)…"
        clearList()

        Task {
            do {
                let apps = try await Flathub.search(query: query, page: page)
                MainQueue.shared.async { [weak self] in
                    self?.showResults(apps, query: query, page: page)
                }
            } catch {
                MainQueue.shared.async { [weak self] in
                    self?.statusLabel?.label = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearList() {
        guard let sc = scrolled else { return }
        if let old = listBox {
            sc.remove(widget: old)
        }
        let newList = Box(orientation: .vertical, spacing: 6)
        listBox = newList
        sc.add(widget: newList)
        sc.showAll()
    }

    private func showResults(_ apps: [FlatApp], query: String, page: Int) {
        let toShow = apps

        statusLabel?.label = apps.isEmpty
            ? "No results for «\(query)»"
            : "Found \(apps.count) apps — «\(query)» p.\(page)"

        guard let list = listBox else { return }

        for app in toShow {
            list.packStart(child: makeRow(app), expand: false, fill: true, padding: 2)
        }
        window?.showAll()
    }

    private func makeRow(_ app: FlatApp) -> Button {
        let btn = Button()
        let row = Box(orientation: .horizontal, spacing: 10)

        let iconBox = Box(orientation: .vertical, spacing: 0)
        iconBox.setSizeRequest(width: 56, height: 56)
        let placeholder = Label(str: "⏳")
        iconBox.packStart(child: placeholder, expand: true, fill: true, padding: 0)
        row.packStart(child: iconBox, expand: false, fill: false, padding: 4)

        let text = Box(orientation: .vertical, spacing: 2)

        let title = Label(str: app.name)
        title.setHalign(align: .start)
        text.packStart(child: title, expand: false, fill: false, padding: 2)

        let summary = Label(str: app.summary)
        summary.setHalign(align: .start)
        summary.setMaxWidthChars(nChars: 60)
        text.packStart(child: summary, expand: false, fill: false, padding: 2)

        let meta = Label(str: app.shortMeta)
        meta.setHalign(align: .start)
        text.packStart(child: meta, expand: false, fill: false, padding: 2)

        row.packStart(child: text, expand: true, fill: true, padding: 4)
        btn.add(widget: row)

        btn.connect(signal: .clicked) { [weak self] in
            self?.showDetail(app)
        }

        if let urlStr = app.iconURL, !urlStr.isEmpty {
            loadIcon(urlStr) { pixbuf in
                MainQueue.shared.async {
                    iconBox.remove(widget: placeholder)
                    if let pixbuf = pixbuf {
                        let scaled = self.scale(pixbuf, maxSize: 48)
                        let img = Image(pixbuf: scaled)
                        iconBox.packStart(child: img, expand: true, fill: true, padding: 0)
                    } else {
                        iconBox.packStart(child: Label(str: "❓"), expand: true, fill: true, padding: 0)
                    }
                    iconBox.showAll()
                    self.window?.showAll()
                }
            }
        }

        return btn
    }

    private func scale(_ pixbuf: Pixbuf, maxSize: Int) -> Pixbuf {
        return pixbuf
    }

    private func loadIcon(_ urlString: String, completion: @escaping (Pixbuf?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, response, error in
            guard error == nil,
                  let data = data, !data.isEmpty,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(nil)
                return
            }

            do {
                let loader = PixbufLoader()
                let bytes = [UInt8](data)
                _ = try loader.write(buf: bytes, count: bytes.count)
                _ = try loader.close()
                if let ref = loader.getPixbuf() {
                    completion(Pixbuf(pixbuf: ref))
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }

    private func showDetail(_ app: FlatApp) {
        let win = Window(type: .toplevel)
        win.title = app.name
        win.setDefaultSize(width: 480, height: 360)

        let box = Box(orientation: .vertical, spacing: 8)

        let name = Label(str: app.name)
        name.setHalign(align: .center)
        box.packStart(child: name, expand: false, fill: false, padding: 8)

        let idLabel = Label(str: app.appId)
        idLabel.setHalign(align: .center)
        box.packStart(child: idLabel, expand: false, fill: false, padding: 4)

        let desc = Label(str: String(app.description.prefix(700)))
        desc.setHalign(align: .start)
        desc.setMaxWidthChars(nChars: 55)
        box.packStart(child: desc, expand: true, fill: true, padding: 8)

        let hint = Label(str: "Install: flatpak install flathub \(app.appId)")
        hint.setHalign(align: .start)
        box.packStart(child: hint, expand: false, fill: false, padding: 8)

        let installBtn = Button(label: "▶ Install in terminal")
        installBtn.connect(signal: .clicked) { [weak self] in
            self?.runInTerminal("flatpak install flathub \(app.appId)")
        }
        box.packStart(child: installBtn, expand: false, fill: false, padding: 4)

        win.add(widget: box)
        win.showAll()
        win.present()
    }
    
    private func runInTerminal(_ command: String) {
        let script = "\(command); echo; read -n1 -p 'Press any key to close...'"
        let process = Process()

        if FileManager.default.isExecutableFile(atPath: "/usr/bin/xdg-terminal-exec") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-terminal-exec")
            process.arguments = ["bash", "-c", script]
        } else if FileManager.default.isExecutableFile(atPath: "/usr/bin/x-terminal-emulator") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/x-terminal-emulator")
            process.arguments = ["-e", "bash", "-c", script]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("Failed to launch terminal: \(error)")
        }
    }

    private func saveReport() {
        currentSession?.timeOut = Foundation.Date()

        var lines = [
            "+---------------------+---------------------+---------------------+",
            "| login               | time_in             | time_out            |",
            "+---------------------+---------------------+---------------------+"
        ]

        for s in sessions {
            lines.append(s.toLine())
        }
        lines.append("+---------------------+---------------------+---------------------+")

        do {
            try lines.joined(separator: "\n").write(toFile: config.reportPath, atomically: true, encoding: .utf8)
            print("Session report saved to \(config.reportPath)")
        } catch {
            print("Failed to save report: \(error)")
        }
    }
}


FlatStoreApp().run()
