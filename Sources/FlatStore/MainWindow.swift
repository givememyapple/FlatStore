import Foundation
import Gtk

final class MainWindow {
    private var window: ApplicationWindow?
    private var listBox: Box?
    private var statusLabel: Label?
    private var searchEntry: Entry?
    private var pageSpin: SpinButton?
    private var scrolled: ScrolledWindow?

    private var currentSession: Session?
    private var sessions: [Session] = []

    func run() {
        Application.run(startupHandler: nil) { app in
            self.buildUI(app: app)
        }
    }

    private func buildUI(app: ApplicationRef) {
        MainQueue.shared.start()

        let session = Session(login: config.userName)
        currentSession = session
        sessions.append(session)

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
        statusLabel?.label = apps.isEmpty
            ? "No results for «\(query)»"
            : "Found \(apps.count) apps — «\(query)» p.\(page)"

        guard let list = listBox else { return }

        for app in apps {
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
            IconLoader.load(urlStr) { pixbuf in
                MainQueue.shared.async { [weak self] in
                    iconBox.remove(widget: placeholder)
                    if let pixbuf = pixbuf {
                        let img = Image(pixbuf: pixbuf)
                        iconBox.packStart(child: img, expand: true, fill: true, padding: 0)
                    } else {
                        iconBox.packStart(child: Label(str: "❓"), expand: true, fill: true, padding: 0)
                    }
                    iconBox.showAll()
                    self?.window?.showAll()
                }
            }
        }

        return btn
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
        installBtn.connect(signal: .clicked) {
            TerminalLauncher.run("flatpak install flathub \(app.appId)")
        }
        box.packStart(child: installBtn, expand: false, fill: false, padding: 4)

        win.add(widget: box)
        win.showAll()
        win.present()
    }

    private func saveReport() {
        currentSession?.timeOut = Foundation.Date()
        ReportWriter.save(sessions: sessions, path: config.reportPath)
    }
}
