//
//  ChatMessage.swift
//  RealtimeDemo
//
//  Created by Alex Coundouriotis on 11/8/24.
//

import Foundation

// Base class for server events
class ServerEvent: Codable {
    let type: String
    let event_id: String?

    enum CodingKeys: String, CodingKey {
        case type
        case event_id
    }

    // Use custom decoding to handle different event types
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        event_id = try container.decodeIfPresent(String.self, forKey: .event_id)
    }
}

// Error Event
class ErrorEvent: ServerEvent {
    let error: ServerError

    enum CodingKeys: String, CodingKey {
        case error
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(ServerError.self, forKey: .error)
        try super.init(from: decoder)
    }
}

struct ServerError: Codable {
    let type: String
    let code: String?
    let message: String
    let param: String?
    let event_id: String?
}

// Response Audio Delta Event
class ResponseAudioDeltaEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int
    let delta: String?

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
        case delta
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        try super.init(from: decoder)
    }
}

// Response Audio Transcript Delta Event
class ResponseAudioTranscriptDeltaEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int
    let delta: String

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
        case delta
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        delta = try container.decode(String.self, forKey: .delta)
        try super.init(from: decoder)
    }
}

// Response Audio Transcript Done Event
class ResponseAudioTranscriptDoneEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int
    let transcript: String

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
        case transcript
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        transcript = try container.decode(String.self, forKey: .transcript)
        try super.init(from: decoder)
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    var text: String
    let isUser: Bool
}

class ConversationItemCreatedEvent: ServerEvent {
    let previous_item_id: String?
    let item: RealtimeItem

    enum CodingKeys: String, CodingKey {
        case previous_item_id
        case item
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        previous_item_id = try container.decodeIfPresent(String.self, forKey: .previous_item_id)
        item = try container.decode(RealtimeItem.self, forKey: .item)
        try super.init(from: decoder)
    }
}

struct RealtimeItem: Codable {
    let id: String
    let object: String
    let type: String
    let status: String?
    let role: String?
    let content: [RealtimeContent]?
}

struct RealtimeContent: Codable {
    let type: String
    let text: String?
    let transcript: String?
    let audio: String?
}

// Response Created Event
class ResponseCreatedEvent: ServerEvent {
    let response: ResponseObject

    enum CodingKeys: String, CodingKey {
        case response
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decode(ResponseObject.self, forKey: .response)
        try super.init(from: decoder)
    }
}

struct ResponseObject: Codable {
    let object: String
    let id: String
    let status: String
    let status_details: String?
    let output: [RealtimeItem]
}

// Rate Limits Updated Event
class RateLimitsUpdatedEvent: ServerEvent {
    let rate_limits: [RateLimit]

    enum CodingKeys: String, CodingKey {
        case rate_limits
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rate_limits = try container.decode([RateLimit].self, forKey: .rate_limits)
        try super.init(from: decoder)
    }
}

struct RateLimit: Codable {
    let name: String
    let limit: Int
    let remaining: Int
    let reset_seconds: Double
}

// Response Output Item Added Event
class ResponseOutputItemAddedEvent: ServerEvent {
    let response_id: String
    let output_index: Int
    let item: RealtimeItem

    enum CodingKeys: String, CodingKey {
        case response_id
        case output_index
        case item
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        item = try container.decode(RealtimeItem.self, forKey: .item)
        try super.init(from: decoder)
    }
}

// Response Done Event
class ResponseDoneEvent: ServerEvent {
    let response: ResponseObject

    enum CodingKeys: String, CodingKey {
        case response
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decode(ResponseObject.self, forKey: .response)
        try super.init(from: decoder)
    }
}

// Input Audio Buffer Speech Started Event
class InputAudioBufferSpeechStartedEvent: ServerEvent {
    let audio_start_ms: Double
    let item_id: String

    enum CodingKeys: String, CodingKey {
        case audio_start_ms
        case item_id
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audio_start_ms = try container.decode(Double.self, forKey: .audio_start_ms)
        item_id = try container.decode(String.self, forKey: .item_id)
        try super.init(from: decoder)
    }
}

// Input Audio Buffer Speech Stopped Event
class InputAudioBufferSpeechStoppedEvent: ServerEvent {
    let audio_end_ms: Double
    let item_id: String

    enum CodingKeys: String, CodingKey {
        case audio_end_ms
        case item_id
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audio_end_ms = try container.decode(Double.self, forKey: .audio_end_ms)
        item_id = try container.decode(String.self, forKey: .item_id)
        try super.init(from: decoder)
    }
}

// Input Audio Buffer Committed Event
class InputAudioBufferCommittedEvent: ServerEvent {
    let previous_item_id: String?
    let item_id: String

    enum CodingKeys: String, CodingKey {
        case previous_item_id
        case item_id
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        previous_item_id = try container.decodeIfPresent(String.self, forKey: .previous_item_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        try super.init(from: decoder)
    }
}

// Response Content Part Added Event
class ResponseContentPartAddedEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int
    let part: RealtimeContent

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
        case part
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        part = try container.decode(RealtimeContent.self, forKey: .part)
        try super.init(from: decoder)
    }
}

// Response Content Part Done Event
class ResponseContentPartDoneEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int
    let part: RealtimeContent

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
        case part
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        part = try container.decode(RealtimeContent.self, forKey: .part)
        try super.init(from: decoder)
    }
}

// Response Output Item Done Event
class ResponseOutputItemDoneEvent: ServerEvent {
    let response_id: String
    let output_index: Int
    let item: RealtimeItem

    enum CodingKeys: String, CodingKey {
        case response_id
        case output_index
        case item
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        item = try container.decode(RealtimeItem.self, forKey: .item)
        try super.init(from: decoder)
    }
}

// Response Audio Done Event
class ResponseAudioDoneEvent: ServerEvent {
    let response_id: String
    let item_id: String
    let output_index: Int
    let content_index: Int

    enum CodingKeys: String, CodingKey {
        case response_id
        case item_id
        case output_index
        case content_index
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response_id = try container.decode(String.self, forKey: .response_id)
        item_id = try container.decode(String.self, forKey: .item_id)
        output_index = try container.decode(Int.self, forKey: .output_index)
        content_index = try container.decode(Int.self, forKey: .content_index)
        try super.init(from: decoder)
    }
}

class ConversationItemTruncatedEvent: ServerEvent {
    let item_id: String
    let content_index: Int
    let audio_end_ms: Int

    enum CodingKeys: String, CodingKey {
        case item_id
        case content_index
        case audio_end_ms
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item_id = try container.decode(String.self, forKey: .item_id)
        content_index = try container.decode(Int.self, forKey: .content_index)
        audio_end_ms = try container.decode(Int.self, forKey: .audio_end_ms)
        try super.init(from: decoder)
    }
}
