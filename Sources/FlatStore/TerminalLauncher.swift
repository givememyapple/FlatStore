import Foundation

enum TerminalLauncher {
    static func run(_ command: String) {
        let script = "\(command); echo; echo 'Press Enter to close...'; read"

        let candidates: [(String, [String])] = [
            ("/usr/bin/xdg-terminal-exec", ["bash", "-c", script]),
            ("/usr/bin/x-terminal-emulator", ["-e", "bash", "-c", script]),
            ("/usr/bin/gnome-terminal", ["--", "bash", "-c", script]),
            ("/usr/bin/konsole", ["-e", "bash", "-c", script]),
            ("/usr/bin/xfce4-terminal", ["-e", "bash -c '\(script)'"]),
            ("/usr/bin/kitty", ["bash", "-c", script]),
            ("/usr/bin/alacritty", ["-e", "bash", "-c", script]),
            ("/usr/bin/wezterm", ["start", "--", "bash", "-c", script]),
            ("/usr/bin/foot", ["bash", "-c", script]),
            ("/bin/bash", ["-c", command])
        ]

        for (path, args) in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                return
            } catch {
                continue
            }
        }

    }
}
