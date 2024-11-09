//
//  RealtimeSpeechViewModel.swift
//  RealtimeDemo
//
//  Created by Alex Coundouriotis on 11/8/24.
//

import SwiftUI
import AVFoundation
import Network

class RealtimeSpeechViewModel: NSObject, ObservableObject {
    
    @Published var messages: [ChatMessage] = []
    @Published var isRecording = false
    @Published var textInput = ""

    private var audioEngine: AVAudioEngine?
    private var webSocketTask: URLSessionWebSocketTask?
    private var authToken: String = "YOUR_AUTH_TOKEN"
    private var isConnected = false
    
    private var isAssistantSpeaking = false

    private let serverURL = URL(string: "wss://chitchatserver.com/v1/realtime")!

    // Audio playback
    private var playbackEngine: AVAudioEngine?
    private var playbackPlayerNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?

    override init() {
        super.init()
    }

    func connect() {
        var request = URLRequest(url: serverURL)
        request.addValue(authToken, forHTTPHeaderField: "AuthToken")

        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        listen()
        webSocketTask?.resume()
        isConnected = true

        setupPlayback()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        stopRecording()
        stopPlayback()
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            case .success(let message):
                self?.handleMessage(message)
            }

            if self?.isConnected == true {
                self?.listen()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseServerMessage(text)
        case .data(let data):
            print("Received binary data which is unexpected.")
        @unknown default:
            break
        }
    }

    private func parseServerMessage(_ text: String) {
        // Parse the JSON message using Swift structs
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        do {
            let baseEvent = try decoder.decode(ServerEvent.self, from: data)

            switch baseEvent.type {
            case "response.audio.delta":
                let event = try decoder.decode(ResponseAudioDeltaEvent.self, from: data)
                handleServerEvent(event)
            case "response.audio_transcript.delta":
                let event = try decoder.decode(ResponseAudioTranscriptDeltaEvent.self, from: data)
                handleServerEvent(event)
            case "response.audio_transcript.done":
                let event = try decoder.decode(ResponseAudioTranscriptDoneEvent.self, from: data)
                handleServerEvent(event)
            case "conversation.item.created":
                let event = try decoder.decode(ConversationItemCreatedEvent.self, from: data)
                handleServerEvent(event)
            case "response.created":
                let event = try decoder.decode(ResponseCreatedEvent.self, from: data)
                handleServerEvent(event)
            case "rate_limits.updated":
                let event = try decoder.decode(RateLimitsUpdatedEvent.self, from: data)
                handleServerEvent(event)
            case "response.output_item.added":
                let event = try decoder.decode(ResponseOutputItemAddedEvent.self, from: data)
                handleServerEvent(event)
            case "response.done":
                let event = try decoder.decode(ResponseDoneEvent.self, from: data)
                handleServerEvent(event)
            // Handle other events as necessary
            default:
                print("Received unhandled event type: \(baseEvent.type)")
            }
        } catch {
            print("Failed to decode server message: \(error)")
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case "response.audio.delta":
            if let audioDeltaEvent = event as? ResponseAudioDeltaEvent {
                handleAudioDeltaEvent(audioDeltaEvent)
            }
        case "response.audio_transcript.delta":
            if let transcriptDeltaEvent = event as? ResponseAudioTranscriptDeltaEvent {
                handleTranscriptDeltaEvent(transcriptDeltaEvent)
            }
        case "response.audio_transcript.done":
            if let transcriptDoneEvent = event as? ResponseAudioTranscriptDoneEvent {
                handleTranscriptDoneEvent(transcriptDoneEvent)
            }
        case "conversation.item.created":
            if let itemCreatedEvent = event as? ConversationItemCreatedEvent {
                handleConversationItemCreatedEvent(itemCreatedEvent)
            }
        case "response.created":
            if let responseCreatedEvent = event as? ResponseCreatedEvent {
                handleResponseCreatedEvent(responseCreatedEvent)
            }
        case "rate_limits.updated":
            if let rateLimitsUpdatedEvent = event as? RateLimitsUpdatedEvent {
                // Update rate limit logic if needed
                print("Rate limits updated: \(rateLimitsUpdatedEvent.rate_limits)")
            }
        case "response.output_item.added":
            if let outputItemAddedEvent = event as? ResponseOutputItemAddedEvent {
                // Handle as needed
            }
        case "response.done":
            if let responseDoneEvent = event as? ResponseDoneEvent {
                // Finalize any response handling here
            }
        case "response.content_part.added":
            if let contentPartAddedEvent = event as? ResponseContentPartAddedEvent {
                handleContentPartAddedEvent(contentPartAddedEvent)
            }
        case "response.content_part.done":
            if let contentPartDoneEvent = event as? ResponseContentPartDoneEvent {
                // Handle as needed
            }
        case "response.output_item.done":
            if let outputItemDoneEvent = event as? ResponseOutputItemDoneEvent {
                // Handle as needed
            }
        case "input_audio_buffer.speech_started":
            if let speechStartedEvent = event as? InputAudioBufferSpeechStartedEvent {
                handleSpeechStartedEvent(speechStartedEvent)
            }
        case "input_audio_buffer.speech_stopped":
            if let speechStoppedEvent = event as? InputAudioBufferSpeechStoppedEvent {
                handleSpeechStoppedEvent(speechStoppedEvent)
            }
        case "input_audio_buffer.committed":
            if let committedEvent = event as? InputAudioBufferCommittedEvent {
                handleInputAudioBufferCommittedEvent(committedEvent)
            }
        case "response.audio.done":
            if let audioDoneEvent = event as? ResponseAudioDoneEvent {
                handleResponseAudioDoneEvent(audioDoneEvent)
            }
        case "error":
            if let errorEvent = event as? ErrorEvent {
                print("Error from server: \(errorEvent.error.message)")
            }
        default:
            print("Received unhandled event type: \(event.type)")
        }
    }

    private func handleAudioDeltaEvent(_ event: ResponseAudioDeltaEvent) {
        if !isAssistantSpeaking {
            isAssistantSpeaking = true
            DispatchQueue.main.async {
                self.stopRecording()
            }
        }
        
        guard let base64Audio = event.delta,
              let audioData = Data(base64Encoded: base64Audio) else {
            print("Invalid audio data in delta.")
            return
        }

        // Enqueue the audio data to be played
        playAudioData(audioData)
    }

    private func handleTranscriptDeltaEvent(_ event: ResponseAudioTranscriptDeltaEvent) {
        let deltaText = event.delta
        DispatchQueue.main.async {
            // Find or create the message for the assistant
            if let lastAssistantMessageIndex = self.messages.lastIndex(where: { !$0.isUser }) {
                self.messages[lastAssistantMessageIndex].text += deltaText
            } else {
                let message = ChatMessage(id: UUID(), text: deltaText, isUser: false)
                self.messages.append(message)
            }
        }
    }

    private func handleTranscriptDoneEvent(_ event: ResponseAudioTranscriptDoneEvent) {
        let transcript = event.transcript
        DispatchQueue.main.async {
            // Update the assistant's message with the final transcript
            if let lastAssistantMessageIndex = self.messages.lastIndex(where: { !$0.isUser }) {
                self.messages[lastAssistantMessageIndex].text = transcript
            } else {
                let message = ChatMessage(id: UUID(), text: transcript, isUser: false)
                self.messages.append(message)
            }
        }
    }
    
    private func handleConversationItemCreatedEvent(_ event: ConversationItemCreatedEvent) {
        // You can use this to update your conversation history if needed
        print("Conversation item created: \(event.item)")
    }

    private func handleResponseCreatedEvent(_ event: ResponseCreatedEvent) {
        // Handle the response being created
        print("Response created with ID: \(event.response.id)")
    }
    
    private func handleSpeechStartedEvent(_ event: InputAudioBufferSpeechStartedEvent) {
        print("User speech started, pausing playback.")
        DispatchQueue.main.async {
            self.pausePlayback()
            self.isRecording = true
        }
    }

    private func handleSpeechStoppedEvent(_ event: InputAudioBufferSpeechStoppedEvent) {
        print("User speech stopped.")
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    private func handleInputAudioBufferCommittedEvent(_ event: InputAudioBufferCommittedEvent) {
        print("Input audio buffer committed, item ID: \(event.item_id)")
    }

    private func handleContentPartAddedEvent(_ event: ResponseContentPartAddedEvent) {
        print("Response content part added.")
    }

    private func handleResponseAudioDoneEvent(_ event: ResponseAudioDoneEvent) {
        print("Assistant speech done.")
        DispatchQueue.main.async {
            self.isAssistantSpeaking = false
            // Optionally, resume recording if you want to keep listening for user input
        }
    }

    func sendTextMessage() {
        guard !textInput.isEmpty else { return }

        let message = textInput
        textInput = ""

        DispatchQueue.main.async {
            self.messages.append(ChatMessage(id: UUID(), text: message, isUser: true))
        }

        let jsonMessage: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": message
                    ]
                ]
            ]
        ]

        sendJSON(jsonMessage)

        // Request a response
        sendResponseCreateEvent()
    }

    private func sendResponseCreateEvent() {
        let responseCreateEvent: [String: Any] = [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"],
                "instructions": "Please assist the user."
            ]
        ]

        sendJSON(responseCreateEvent)
    }

    private func sendJSON(_ jsonObject: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []) else { return }
        guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(wsMessage) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    private func pausePlayback() {
        playbackPlayerNode?.pause()
    }

    private func resumePlayback() {
        playbackPlayerNode?.play()
    }

    // MARK: - Audio Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { [weak self] granted in
            if granted {
                do {
                    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    self?.setupAudioEngine()
                    DispatchQueue.main.async {
                        self?.isRecording = true
                    }
                } catch {
                    print("Failed to set up audio session: \(error)")
                }
            } else {
                print("Microphone access denied.")
            }
        }
    }

    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let bus = 0

        // Use the hardware's input format
        let inputFormat = inputNode.inputFormat(forBus: bus)

        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert the buffer to the desired format if necessary
        let desiredSampleRate: Double = 24000.0
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!

        guard let converter = AVAudioConverter(from: buffer.format, to: desiredFormat) else {
            print("Failed to create AVAudioConverter")
            return
        }

        // Calculate frame capacity based on sample rate ratio
        let sampleRateRatio = desiredSampleRate / buffer.format.sampleRate
        let convertedFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: convertedFrameCapacity) else {
            print("Failed to create converted buffer")
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("Error while converting audio buffer: \(error)")
            return
        }

        if status != .haveData {// && status != .inputRanOut {
            print("Conversion ended with status: \(status)")
            return
        }

        // Now access the audio data from convertedBuffer
        guard let channelData = convertedBuffer.int16ChannelData else { return }
        let channelDataPointer = channelData.pointee
        let dataSize = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size

        // Create Data from the buffer
        let data = Data(bytes: channelDataPointer, count: dataSize)

        // Send audio data to the server
        let audioMessage: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]

        sendJSON(audioMessage)
    }

    // MARK: - Audio Playback

    private func setupPlayback() {
        playbackEngine = AVAudioEngine()
        playbackPlayerNode = AVAudioPlayerNode()
        
        guard let playbackEngine = playbackEngine,
              let playbackPlayerNode = playbackPlayerNode else { return }
        
        playbackEngine.attach(playbackPlayerNode)
        
        // Use the hardware's preferred sample rate and format
        let outputFormat = playbackEngine.outputNode.inputFormat(forBus: 0)
        playbackFormat = outputFormat
        
        // Connect the player node to the main mixer node with the output format
        playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        
        do {
            try playbackEngine.start()
        } catch {
            print("Failed to start playback engine: \(error)")
        }
        
        playbackPlayerNode.play()
    }

    private func stopPlayback() {
        playbackPlayerNode?.stop()
        playbackEngine?.stop()
        playbackEngine = nil
        playbackPlayerNode = nil
        playbackFormat = nil
    }

    private func playAudioData(_ data: Data) {
        guard let playbackPlayerNode = playbackPlayerNode,
              let playbackFormat = playbackFormat else { return }

        // Assume that the incoming data is at the sample rate of 24000 Hz
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000.0, channels: 1, interleaved: true)!

        // Convert the data to the playback format
        guard let inputBuffer = dataToPCMBuffer(data: data, format: inputFormat) else { return }

        guard let bufferToPlay = convertBuffer(inputBuffer, to: playbackFormat) else { return }

        // Schedule the buffer for playback
        playbackPlayerNode.scheduleBuffer(bufferToPlay, completionHandler: nil)
    }
    
    private func dataToPCMBuffer(data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBufferPointer in
            guard let rawPointer = rawBufferPointer.baseAddress else { return }
            let audioBufferPointer = buffer.int16ChannelData![0]
            audioBufferPointer.assign(from: rawPointer.assumingMemoryBound(to: Int16.self), count: Int(buffer.frameLength))
        }

        return buffer
    }
    
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            print("Failed to create AVAudioConverter for playback")
            return nil
        }

        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * (outputFormat.sampleRate / inputBuffer.format.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("Audio conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }
    
}

extension RealtimeSpeechViewModel: AVAudioRecorderDelegate {
    // Handle AVAudioRecorder delegate methods if necessary
}
