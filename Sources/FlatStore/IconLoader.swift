import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GdkPixBuf

enum IconLoader {
    static func load(_ urlString: String, completion: @escaping (Pixbuf?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, response, error in
            guard
                error == nil,
                let data = data, !data.isEmpty,
                let http = response as? HTTPURLResponse, http.statusCode == 200
            else {
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
}
