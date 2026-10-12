import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum Flathub {
    static func search(query: String, page: Int) async throws -> [FlatApp] {
        let url = URL(string: "https://flathub.org/api/v2/search?locale=\(config.locale)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let escaped = query.replacingOccurrences(of: "\"", with: "\\\"")
        let body = """
        {"query":"\(escaped)","filters":[],"hits_per_page":\(config.perPage),"page":\(page)}
        """
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else {
            return []
        }

        return hits.compactMap { item in
            guard let appId = item["app_id"] as? String,
                  let name = item["name"] as? String else {
                return nil
            }

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
            dataTask(with: request) { data, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let data = data, let response = response {
                    cont.resume(returning: (data, response))
                } else {
                    cont.resume(throwing: URLError(.unknown))
                }
            }.resume()
        }
    }
}
