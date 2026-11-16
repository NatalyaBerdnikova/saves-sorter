import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic

    var id: String { rawValue }

    var keychainAccount: String {
        switch self {
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-haiku-latest"
        }
    }
}

enum AIClientError: Error {
    case rejected
    case empty
    case badResponse(String)
}

enum AIClient {
    static let rules = """
    You extract travel notes from an Instagram caption. Return ONLY a JSON object, no markdown, with this exact shape:
    {"category":"visit"|"buy"|"both"|"none","places":[{"name":string,"city":string|null,"country":string|null}],"items":[{"what":string,"where":string|null,"city":string|null,"country":string|null}]}
    Rules:
    - places are places to visit. items are things to buy. items.where is the shop name.
    - Prefer Russian names for countries and cities when you know them.
    - A caption may contain several places or several shops. Return all of them.
    - Do not invent places, shops, cities, or countries that the caption does not support.
    - If the caption says the list is only in the video or only via a link in the profile and gives no concrete names, return category "none" and empty arrays.
    - If a shopping item has no city, set city and country to null.
    """

    static func classify(caption: String, provider: AIProvider, apiKey: String, model: String) async throws -> AIPayload {
        let clipped = String(caption.prefix(8000))
        switch provider {
        case .openAI:
            return try await openAI(caption: clipped, apiKey: apiKey, model: model)
        case .anthropic:
            return try await anthropic(caption: clipped, apiKey: apiKey, model: model)
        }
    }

    private static func openAI(caption: String, apiKey: String, model: String) async throws -> AIPayload {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": rules],
                ["role": "user", "content": caption],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfRejected(response)
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, let payload = AIResponseParser.parse(text: text) else {
            throw AIClientError.empty
        }
        return payload
    }

    private static func anthropic(caption: String, apiKey: String, model: String) async throws -> AIPayload {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "temperature": 0,
            "system": rules,
            "messages": [
                ["role": "user", "content": caption],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfRejected(response)
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard let payload = AIResponseParser.parse(text: text) else { throw AIClientError.empty }
        return payload
    }

    private static func throwIfRejected(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw AIClientError.rejected }
        if !(200..<300).contains(http.statusCode) {
            throw AIClientError.badResponse("HTTP \(http.statusCode)")
        }
    }
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String? }
        var message: Message
    }
    var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
    struct Block: Decodable {
        var type: String
        var text: String?
    }
    var content: [Block]
}
