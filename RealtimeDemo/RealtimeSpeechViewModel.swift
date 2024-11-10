//
// RealtimeSpeechViewModel.swift
// RealtimeDemo
//
// Created by Alex Coundouriotis on 11/8/24.
//

import SwiftUI
import AVFoundation
import Network

/// ViewModel for handling real-time speech interactions using OpenAI's Realtime API.
/// This class manages audio recording, playback, and WebSocket communication with the server.
/// It processes and sends user speech to the server and handles the assistant's text and audio responses.
class RealtimeSpeechViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// An array of chat messages displayed in the UI.
    @Published var messages: [ChatMessage] = []
    
    /// Indicates whether the app is currently recording audio.
    @Published var isRecording = false
    
    /// The text input from the user (for typed messages).
    @Published var textInput = ""
    
    // MARK: - Private Properties
    
    /// The audio engine for recording audio from the microphone.
    private var audioEngine: AVAudioEngine?
    
    /// The WebSocket task for communicating with the server.
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// The authentication token used for authenticating with the server.
    private var authToken: String = "YOUR_AUTH_TOKEN"
    
    /// A flag indicating whether the WebSocket connection is active.
    private var isConnected = false
    
    /// A flag indicating whether the assistant is currently speaking.
    private var isAssistantSpeaking = false
    
    /// The URL of the server to connect to.
    /// Update this with your server's WebSocket URL.
    private let serverURL = URL(string: "wss://chitchatserver.com/v1/realtime")!
    
    // MARK: - Audio Playback Properties
    
    /// The audio engine used for playing back audio received from the assistant.
    private var playbackEngine: AVAudioEngine?
    
    /// The audio player node for scheduling and playing audio buffers.
    private var playbackPlayerNode: AVAudioPlayerNode?
    
    /// The audio format used for playback.
    private var playbackFormat: AVAudioFormat?
    
    private var playbackBufferQueue = DispatchQueue(label: "playbackBufferQueue")
    private var scheduledBufferCount = 0
    private var assistantResponseCompleted = false
    
    private var audioBuffersPending: Int = 0
    private var isAssistantResponseDone: Bool = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Connection Methods
    
    /// Connects to the server via WebSocket and sets up the playback engine.
    func connect() {
        var request = URLRequest(url: serverURL)
        request.addValue(authToken, forHTTPHeaderField: "AuthToken")
        
        // Create the WebSocket task and start listening.
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        listen()
        webSocketTask?.resume()
        isConnected = true
        
        // Set up the audio playback engine.
        setupPlayback()
    }
    
    /// Disconnects from the server and stops recording and playback.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        stopRecording()
        stopPlayback()
    }
    
    // MARK: - WebSocket Communication
    
    /// Listens for incoming messages from the WebSocket connection.
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
    
    /// Handles incoming WebSocket messages.
    /// - Parameter message: The message received from the WebSocket.
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
            case .string(let text):
            parseServerMessage(text)
        case .data(_):
            print("Received binary data which is unexpected.")
            @unknown default:
            break
        }
    }
    
    /// Parses the server's JSON message and dispatches it to the appropriate handler.
    /// - Parameter text: The JSON string received from the server.
    private func parseServerMessage(_ text: String) {
        // Convert the JSON string to Data.
        guard let data = text.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        do {
            // Decode the base event to determine its type.
            let baseEvent = try decoder.decode(ServerEvent.self, from: data)
            
            // Decode and handle the specific event type.
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
            case "response.content_part.added":
                let event = try decoder.decode(ResponseContentPartAddedEvent.self, from: data)
                handleServerEvent(event)
            case "response.content_part.done":
                let event = try decoder.decode(ResponseContentPartDoneEvent.self, from: data)
                handleServerEvent(event)
            case "response.output_item.done":
                let event = try decoder.decode(ResponseOutputItemDoneEvent.self, from: data)
                handleServerEvent(event)
            case "input_audio_buffer.speech_started":
                let event = try decoder.decode(InputAudioBufferSpeechStartedEvent.self, from: data)
                handleServerEvent(event)
            case "input_audio_buffer.speech_stopped":
                let event = try decoder.decode(InputAudioBufferSpeechStoppedEvent.self, from: data)
                handleServerEvent(event)
            case "input_audio_buffer.committed":
                let event = try decoder.decode(InputAudioBufferCommittedEvent.self, from: data)
                handleServerEvent(event)
            case "response.audio.done":
                let event = try decoder.decode(ResponseAudioDoneEvent.self, from: data)
                handleServerEvent(event)
            case "error":
                let event = try decoder.decode(ErrorEvent.self, from: data)
                handleServerEvent(event)
            default:
                print("Received unhandled event type: \(baseEvent.type)")
            }
        } catch {
            print("Failed to decode server message: \(error)")
        }
    }
    
    /// Dispatches the server event to the appropriate handler method.
    /// - Parameter event: The decoded server event.
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
                // Update rate limit logic if needed.
                print("Rate limits updated: \(rateLimitsUpdatedEvent.rate_limits)")
            }
        case "response.output_item.added":
            if let outputItemAddedEvent = event as? ResponseOutputItemAddedEvent {
                // Handle as needed.
            }
        case "response.done":
            if let responseDoneEvent = event as? ResponseDoneEvent {
handleResponseDoneEvent(responseDoneEvent)
            }
        case "response.content_part.added":
            if let contentPartAddedEvent = event as? ResponseContentPartAddedEvent {
                handleContentPartAddedEvent(contentPartAddedEvent)
            }
        case "response.content_part.done":
            if let contentPartDoneEvent = event as? ResponseContentPartDoneEvent {
                // Handle as needed.
            }
        case "response.output_item.done":
            if let outputItemDoneEvent = event as? ResponseOutputItemDoneEvent {
                // Handle as needed.
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
    
    // MARK: - Event Handlers
    
    /// Handles audio delta events by playing incoming audio data.
    /// - Parameter event: The audio delta event from the server.
    private func handleAudioDeltaEvent(_ event: ResponseAudioDeltaEvent) {
        if !isAssistantSpeaking {
            isAssistantSpeaking = true
            isAssistantResponseDone = false // Reset the flag
            DispatchQueue.main.async {
                self.stopRecording()
                self.resumePlayback() // Ensure playback is resumed
            }
        }
        
        // Proceed with processing the audio delta
        guard let base64Audio = event.delta,
              let audioData = Data(base64Encoded: base64Audio) else {
            print("Invalid audio data in delta.")
            return
        }
        
        // Enqueue the audio data to be played.
        playAudioData(audioData)
    }
    
    /// Handles transcript delta events by updating the assistant's message in the UI.
    /// - Parameter event: The transcript delta event from the server.
    private func handleTranscriptDeltaEvent(_ event: ResponseAudioTranscriptDeltaEvent) {
        let deltaText = event.delta
        DispatchQueue.main.async {
            // Find or create the message for the assistant.
            if let lastAssistantMessageIndex = self.messages.lastIndex(where: { !$0.isUser }) {
                self.messages[lastAssistantMessageIndex].text += deltaText
            } else {
                let message = ChatMessage(id: UUID(), text: deltaText, isUser: false)
                self.messages.append(message)
            }
        }
    }

    // HandleResponseDoneEvent
    private func handleResponseDoneEvent(_ event: ResponseDoneEvent) {
        print("Assistant response fully done.")
        DispatchQueue.main.async {
            // Set the flag to indicate the assistant has finished responding
            self.isAssistantResponseDone = true
            // Do not start recording here
        }
    }
    
    /// Handles the completion of the assistant's transcript.
    /// - Parameter event: The transcript done event from the server.
    private func handleTranscriptDoneEvent(_ event: ResponseAudioTranscriptDoneEvent) {
        let transcript = event.transcript
        DispatchQueue.main.async {
            // Update the assistant's message with the final transcript.
            if let lastAssistantMessageIndex = self.messages.lastIndex(where: { !$0.isUser }) {
                self.messages[lastAssistantMessageIndex].text = transcript
            } else {
                let message = ChatMessage(id: UUID(), text: transcript, isUser: false)
                self.messages.append(message)
            }
        }
    }
    
    /// Handles the creation of a new conversation item.
    /// - Parameter event: The conversation item created event from the server.
    private func handleConversationItemCreatedEvent(_ event: ConversationItemCreatedEvent) {
        // You can use this to update your conversation history if needed.
        print("Conversation item created: \(event.item)")
    }
    
    /// Handles the response creation event.
    /// - Parameter event: The response created event from the server.
    private func handleResponseCreatedEvent(_ event: ResponseCreatedEvent) {
        // Handle the response being created.
        print("Response created with ID: \(event.response.id)")
    }
    
    /// Handles the speech started event, indicating the user has started speaking.
    /// - Parameter event: The input audio buffer speech started event.
    private func handleSpeechStartedEvent(_ event: InputAudioBufferSpeechStartedEvent) {
        print("User speech started, pausing playback.")
        DispatchQueue.main.async {
            self.pausePlayback()
            self.isRecording = true
        }
    }
    
    /// Handles the speech stopped event, indicating the user has stopped speaking.
    /// - Parameter event: The input audio buffer speech stopped event.
    private func handleSpeechStoppedEvent(_ event: InputAudioBufferSpeechStoppedEvent) {
        print("User speech stopped.")
        DispatchQueue.main.async {
            self.isRecording = false
            self.resumePlayback() // Resume playback after user stops speaking
        }
    }
    
    /// Handles the input audio buffer committed event.
    /// - Parameter event: The input audio buffer committed event.
    private func handleInputAudioBufferCommittedEvent(_ event: InputAudioBufferCommittedEvent) {
        print("Input audio buffer committed, item ID: \(event.item_id)")
    }
    
    /// Handles when a response content part is added.
    /// - Parameter event: The response content part added event.
    private func handleContentPartAddedEvent(_ event: ResponseContentPartAddedEvent) {
        print("Response content part added.")
    }
    
    /// Handles when the assistant's audio is done playing.
    /// - Parameter event: The response audio done event.
    private func handleResponseAudioDoneEvent(_ event: ResponseAudioDoneEvent) {
        print("Assistant audio segment done.")
        // Do not set isAssistantSpeaking = false here
        // Do not start recording yet
    }
    
    // MARK: - Sending Messages
    
    /// Sends a text message to the assistant and requests a response.
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
        
        // Request a response from the assistant.
        sendResponseCreateEvent()
    }
    
    /// Sends a response create event to signal the assistant to generate a response.
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
    
    /// Sends a JSON message over the WebSocket connection.
    /// - Parameter jsonObject: The JSON object to send.
    private func sendJSON(_ jsonObject: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(wsMessage) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    // MARK: - Audio Control Methods
    
    /// Pauses the audio playback.
    private func pausePlayback() {
        playbackPlayerNode?.pause()
        print("Playback paused.")
    }

    /// Resumes the audio playback
    private func resumePlayback() {
        playbackPlayerNode?.play()
        print("Playback resumed.")
    }
    
    // MARK: - Audio Recording
    
    /// Toggles the audio recording state.
    func toggleRecording() {
        if isAssistantSpeaking {
            print("Cannot start recording while assistant is speaking")
            return
        }
        
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Starts recording audio from the microphone.
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
    
    /// Stops recording audio.
    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    /// Sets up the audio engine for recording.
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let bus = 0
        
        // Use the hardware's input format to avoid format mismatches.
        let inputFormat = inputNode.inputFormat(forBus: bus)
        
        // Install a tap on the input node to capture audio buffers.
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, _) in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Processes the captured audio buffer, converts it to the desired format, and sends it to the server.
    /// - Parameter buffer: The audio buffer captured from the microphone.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Return immediately if the assistant is speaking
        guard !isAssistantSpeaking else {
            return
        }
        
        // Define the desired format (PCM 16-bit, 24 kHz, mono) as expected by the server.
        let desiredSampleRate: Double = 24000.0
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
        
        // Create an audio converter to convert the buffer to the desired format.
        guard let converter = AVAudioConverter(from: buffer.format, to: desiredFormat) else {
            print("Failed to create AVAudioConverter")
            return
        }
        
        // Calculate the frame capacity for the converted buffer.
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
        
        // Perform the conversion.
        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Error while converting audio buffer: \(error)")
            return
        }
        
        if status != .haveData /*&& status != .inputRanOut*/ {
            print("Conversion ended with status: \(status)")
            return
        }
        
        // Access the audio data from the converted buffer.
        guard let channelData = convertedBuffer.int16ChannelData else { return }
        let channelDataPointer = channelData.pointee
        let dataSize = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
        
        // Create a Data object from the audio buffer.
        let data = Data(bytes: channelDataPointer, count: dataSize)
        
        // Send the audio data to the server.
        let audioMessage: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        
        sendJSON(audioMessage)
    }
    
    // MARK: - Audio Playback
    
    /// Sets up the audio playback engine for playing assistant's responses.
    private func setupPlayback() {
        playbackEngine = AVAudioEngine()
        playbackPlayerNode = AVAudioPlayerNode()
        
        guard let playbackEngine = playbackEngine,
              let playbackPlayerNode = playbackPlayerNode else { return }
        
        playbackEngine.attach(playbackPlayerNode)
        
        // Use the hardware's preferred sample rate and format.
        let outputFormat = playbackEngine.outputNode.inputFormat(forBus: 0)
        playbackFormat = outputFormat
        
        // Connect the player node to the main mixer node with the output format.
        playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        
        do {
            try playbackEngine.start()
        } catch {
            print("Failed to start playback engine: \(error)")
        }
        
        playbackPlayerNode.play()
    }
    
    /// Stops the audio playback and releases resources.
    private func stopPlayback() {
        playbackPlayerNode?.stop()
        playbackEngine?.stop()
        playbackEngine = nil
        playbackPlayerNode = nil
        playbackFormat = nil
    }
    
    /// Plays the audio data received from the assistant.
    /// - Parameter data: The audio data to play.
    private func playAudioData(_ data: Data) {
        guard let playbackPlayerNode = playbackPlayerNode,
              let playbackFormat = playbackFormat else { return }
        
        // Define the input format matching the server's audio data (PCM 16-bit, 24 kHz, mono).
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000.0, channels: 1, interleaved: true)!
        
        // Convert the data to an audio buffer.
        guard let inputBuffer = dataToPCMBuffer(data: data, format: inputFormat) else { return }
        
        // Convert the buffer to the playback format.
        guard let bufferToPlay = convertBuffer(inputBuffer, to: playbackFormat) else { return }
        
        // Increment the pending buffers counter
        DispatchQueue.main.async {
            self.audioBuffersPending += 1
        }
        
        // Schedule the buffer for playback with a completion handler
        playbackPlayerNode.scheduleBuffer(bufferToPlay, completionHandler: {
            DispatchQueue.main.async {
                self.audioBuffersPending -= 1
                print("Buffer played, pending buffers: \(self.audioBuffersPending)")
                
                // Check if all buffers have played and the assistant has finished responding
                if self.audioBuffersPending == 0 && self.isAssistantResponseDone {
                    print("All audio buffers played, starting recording.")
                    self.isAssistantSpeaking = false
                    self.startRecording()
                }
            }
        })
        
        // Ensure the player node is playing
        if !playbackPlayerNode.isPlaying {
            playbackPlayerNode.play()
        }
    }
    
    /// Converts raw Data into an AVAudioPCMBuffer with the specified format.
    /// - Parameters:
    ///   - data: The raw audio data.
    ///   - format: The audio format to use.
    /// - Returns: An optional AVAudioPCMBuffer containing the audio data.
    private func dataToPCMBuffer(data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { rawBufferPointer in
            guard let rawPointer = rawBufferPointer.baseAddress else { return }
            let audioBufferPointer = buffer.int16ChannelData![0]
            audioBufferPointer.update(from: rawPointer.assumingMemoryBound(to: Int16.self), count: Int(buffer.frameLength))
        }
        
        return buffer
    }
    
    /// Converts an audio buffer to the specified output format.
    /// - Parameters:
    ///   - inputBuffer: The input audio buffer.
    ///   - outputFormat: The desired output audio format.
    /// - Returns: An optional AVAudioPCMBuffer in the output format.
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
        
        // Perform the conversion.
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Audio conversion error: \(error)")
            return nil
        }
        
        return outputBuffer
    }
}

// Note: The extension for AVAudioRecorderDelegate is included if needed.
extension RealtimeSpeechViewModel: AVAudioRecorderDelegate {
    // Implement AVAudioRecorder delegate methods if necessary.
}

