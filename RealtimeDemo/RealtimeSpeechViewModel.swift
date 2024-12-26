//
// RealtimeSpeechViewModel.swift
//

import SwiftUI
import AVFoundation
import Network
import Speech
import Accelerate

/// ViewModel for handling real-time speech interactions.
/// Manages audio recording, playback, and WebSocket communication with the server.
/// Processes and sends user speech to the server and handles the assistant's text and audio responses.
class RealtimeSpeechViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// The message currently being written by the assistant.
    @Published var currentlyWritingMessage: ChatMessage?
    
    /// An array of completed chat messages displayed in the UI.
    @Published var finishedMessages: [ChatMessage] = []
    
    /// The text input from the user (for typed messages).
    @Published var textInput = ""
    
    /// The current state of the interaction: speaking, listening, or idle.
    @Published var currentState: State = .idle
    
    /// Published property for recording volume (used for waveform visualization).
    @Published var recordingVolume: Float = 0.0
    
    /// Published property for playback volume (used for waveform visualization).
    @Published var playbackVolume: Float = 0.0
    
    /// Enum representing the possible states of the interaction.
    enum State {
        case speaking
        case listening
        case idle
    }
    
    // MARK: - Private Properties
    
    /// The audio engine for recording audio from the microphone.
    private var audioEngine: AVAudioEngine?
    
    /// The WebSocket task for communicating with the server.
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// The authentication token used for authenticating with the server.
    private var authToken: String = "YOUR_AUTH_TOKEN"
    
    /// A flag indicating whether the WebSocket connection is active.
    private var isConnected = false
    
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
    
    /// Tracks the number of audio buffers pending playback.
    private var audioBuffersPending: Int = 0
    
    /// Indicates whether the assistant's response is fully received.
    private var isAssistantResponseDone: Bool = false
    
    /// Variables to keep track of the current response and item IDs
    private var currentResponseID: String?
    private var currentItemID: String?
    private var currentContentIndex: Int?
    
    /// Tracks the audio playback position for potential truncation.
    private var audioPlaybackPositionMs: Int = 0
    
    // MARK: - Speech Recognition Properties
    
    /// Speech recognizer for transcribing user's speech.
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    /// Recognition request for speech recognition.
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    /// Recognition task for handling recognition callbacks.
    private var recognitionTask: SFSpeechRecognitionTask?
    
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
            case "conversation.item.input_audio_transcription.completed":
                print("HERE")
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
            case "conversation.item.truncated":
                let event = try decoder.decode(ConversationItemTruncatedEvent.self, from: data)
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
                print("Rate limits updated: \(rateLimitsUpdatedEvent.rate_limits)")
            }
        case "response.output_item.added":
            if let outputItemAddedEvent = event as? ResponseOutputItemAddedEvent {
                handleResponseOutputItemAddedEvent(outputItemAddedEvent)
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
        case "conversation.item.truncated":
            if let truncatedEvent = event as? ConversationItemTruncatedEvent {
                handleConversationItemTruncatedEvent(truncatedEvent)
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
        if currentState != .speaking {
            DispatchQueue.main.async {
                self.currentState = .speaking
                self.stopRecording()
                self.resumePlayback()
            }
            isAssistantResponseDone = false
        }
        
        // Update current response and item IDs
        currentResponseID = event.response_id
        currentItemID = event.item_id
        currentContentIndex = event.content_index
        
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
            if let currentMessage = self.currentlyWritingMessage {
                self.currentlyWritingMessage?.text += deltaText
            } else {
                let message = ChatMessage(id: UUID(), text: deltaText, isUser: false)
                self.currentlyWritingMessage = message
            }
        }
    }
    
    /// Handles the completion of the assistant's transcript.
    /// - Parameter event: The transcript done event from the server.
    private func handleTranscriptDoneEvent(_ event: ResponseAudioTranscriptDoneEvent) {
        let transcript = event.transcript
        DispatchQueue.main.async {
            if let currentMessage = self.currentlyWritingMessage {
                self.currentlyWritingMessage?.text = transcript
                self.finishedMessages.append(currentMessage)
                self.currentlyWritingMessage = nil
            } else {
                let message = ChatMessage(id: UUID(), text: transcript, isUser: false)
                self.finishedMessages.append(message)
            }
        }
    }
    
    /// Handles the conversation item truncated event by pausing playback and updating state.
    private func handleConversationItemTruncatedEvent(_ event: ConversationItemTruncatedEvent) {
        print("Received conversation.item.truncated event. Item ID: \(event.item_id)")
        DispatchQueue.main.async {
            self.pausePlayback()
            self.currentState = .idle
            // Optionally, update the UI to reflect the truncation
        }
    }
    
    /// Handles the creation of a new conversation item.
    /// - Parameter event: The conversation item created event from the server.
    private func handleConversationItemCreatedEvent(_ event: ConversationItemCreatedEvent) {
        print("Conversation item created: \(event.item)")
    }
    
    /// Handles the response creation event.
    /// - Parameter event: The response created event from the server.
    private func handleResponseCreatedEvent(_ event: ResponseCreatedEvent) {
        print("Response created with ID: \(event.response.id)")
        currentResponseID = event.response.id
    }
    
    /// Handles when an output item is added to the response.
    private func handleResponseOutputItemAddedEvent(_ event: ResponseOutputItemAddedEvent) {
        currentItemID = event.item.id
    }
    
    /// Handles when the assistant's response is fully done.
    private func handleResponseDoneEvent(_ event: ResponseDoneEvent) {
        print("Assistant response fully done.")
        DispatchQueue.main.async {
            self.isAssistantResponseDone = true
            // Move currentlyWritingMessage to finishedMessages if it's not already done
            if let currentMessage = self.currentlyWritingMessage {
                self.finishedMessages.append(currentMessage)
                self.currentlyWritingMessage = nil
            }
        }
    }
    
    /// Handles when a response content part is added.
    private func handleContentPartAddedEvent(_ event: ResponseContentPartAddedEvent) {
        currentContentIndex = event.content_index
        print("Response content part added.")
    }
    
    /// Handles the speech started event, indicating the user has started speaking.
    private func handleSpeechStartedEvent(_ event: InputAudioBufferSpeechStartedEvent) {
        print("User speech started, pausing playback.")
        DispatchQueue.main.async {
            self.pausePlayback()
            self.currentState = .listening
        }
    }
    
    /// Handles the speech stopped event, indicating the user has stopped speaking.
    private func handleSpeechStoppedEvent(_ event: InputAudioBufferSpeechStoppedEvent) {
        // Handle if needed.
    }
    
    /// Handles the input audio buffer committed event.
    private func handleInputAudioBufferCommittedEvent(_ event: InputAudioBufferCommittedEvent) {
        print("Input audio buffer committed, item ID: \(event.item_id)")
    }
    
    /// Handles when the assistant's audio is done playing.
    private func handleResponseAudioDoneEvent(_ event: ResponseAudioDoneEvent) {
        print("Assistant audio segment done.")
    }
    
    // MARK: - Sending Messages
    
    /// Sends a text message to the assistant and requests a response.
    func sendTextMessage() {
        guard !textInput.isEmpty else { return }
        
        let message = textInput
        textInput = ""
        
        let newMessage = ChatMessage(id: UUID(), text: message, isUser: true)
        DispatchQueue.main.async {
            self.finishedMessages.append(newMessage)
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
    
    // MARK: - State Control Methods
    
    /// Interrupts the speaking state, cancels the response, and moves to idle state.
    func interruptSpeaking() {
        guard currentState == .speaking else { return }
        pausePlayback()
        // Send response cancel event
        sendResponseCancelEvent()
        if let itemID = currentItemID, let contentIndex = currentContentIndex {
            let audioEndMs = audioPlaybackPositionMs
            sendConversationItemTruncateEvent(itemID: itemID, contentIndex: contentIndex, audioEndMs: audioEndMs)
        }
        currentState = .idle
    }
    
    /// Sends a response.cancel event to the server to cancel the current response.
    private func sendResponseCancelEvent() {
        let event: [String: Any] = [
            "type": "response.cancel"
        ]
        sendJSON(event)
    }
    
    /// Sends a conversation.item.truncate event to the server to truncate the assistant's response.
    private func sendConversationItemTruncateEvent(itemID: String, contentIndex: Int, audioEndMs: Int) {
        let event: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": contentIndex,
            "audio_end_ms": audioEndMs
        ]
        sendJSON(event)
    }
    
    /// Interrupts the listening state, stops recording, clears the input audio buffer, and moves to idle state.
    func interruptListening() {
        guard currentState == .listening else { return }
        stopRecording()
        sendInputAudioBufferClearEvent()
        currentState = .idle
    }
    
    private func stopAndClearPlayback() {
        playbackPlayerNode?.stop()
        audioPlaybackPositionMs = 0
        isAssistantResponseDone = true
        print("Playback stopped and buffers cleared.")
    }
    
    /// Sends an input_audio_buffer.clear event to the server.
    private func sendInputAudioBufferClearEvent() {
        let event: [String: Any] = [
            "type": "input_audio_buffer.clear"
        ]
        sendJSON(event)
    }
    
    /// Starts speaking any leftover buffers and moves to speaking state.
    func startSpeakingLeftoverBuffers() {
        guard currentState != .speaking else { return }
        if audioBuffersPending > 0 {
            currentState = .speaking
            resumePlayback()
        } else {
            print("No leftover buffers to play.")
        }
    }
    
    /// Starts listening by initiating audio recording and moves to listening state.
    func startListening() {
        if currentState == .speaking {
            print("Cannot start listening while assistant is speaking")
            return
        }
        if currentState != .listening {
            // Clear audio buffer on the server
            sendInputAudioBufferClearEvent()
            // Stop and clear playback
            stopAndClearPlayback()
            
            // Start recording
            startRecording()
        }
    }
    
    // MARK: - Audio Control Methods
    
    /// Pauses the audio playback.
    private func pausePlayback() {
        playbackPlayerNode?.pause()
        print("Playback paused.")
    }
    
    /// Resumes the audio playback.
    private func resumePlayback() {
        playbackPlayerNode?.play()
        print("Playback resumed.")
    }
    
    // MARK: - Audio Recording
    
    /// Toggles the audio recording state.
    func toggleRecording() {
        if currentState == .speaking {
            print("Cannot start recording while assistant is speaking")
            return
        }
        
        if currentState == .listening {
            stopRecording()
        } else {
            startListening()
        }
    }
    
    /// Starts recording audio from the microphone.
    private func startRecording() {
        DispatchQueue.main.async {
            let audioSession = AVAudioSession.sharedInstance()
            audioSession.requestRecordPermission { [weak self] granted in
                if granted {
                    do {
                        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
                        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                        self?.setupAudioEngine()
                        // Request speech recognition authorization
                        SFSpeechRecognizer.requestAuthorization { authStatus in
                            switch authStatus {
                            case .authorized:
                                DispatchQueue.main.async {
                                    self?.startSpeechRecognition()
                                    self?.currentState = .listening
                                }
                            default:
                                print("Speech recognition authorization was declined.")
                            }
                        }
                    } catch {
                        print("Failed to set up audio session: \(error)")
                    }
                } else {
                    print("Microphone access denied.")
                }
            }
        }
    }
    
    /// Starts speech recognition for transcribing user's speech.
    private func startSpeechRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer is not available.")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            var isFinal = false
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print("Transcription: \(transcription)")
                // Update the UI
                DispatchQueue.main.async {
                    // Update the finishedMessages with user's transcription if it's a complete message
                    if result.isFinal {
                        let message = ChatMessage(id: UUID(), text: transcription, isUser: true)
                        self.finishedMessages.append(message)
                    } else {
                        // Optionally handle intermediate transcriptions
                        if let lastUserMessageIndex = self.finishedMessages.lastIndex(where: { $0.isUser }) {
                            self.finishedMessages[lastUserMessageIndex].text = transcription
                        } else {
                            let message = ChatMessage(id: UUID(), text: transcription, isUser: true)
                            self.finishedMessages.append(message)
                        }
                    }
                }
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self.audioEngine?.stop()
                self.audioEngine?.inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                DispatchQueue.main.async {
                    self.currentState = .idle
                }
            }
        }
    }
    
    /// Stops recording audio.
    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    /// Sets up the audio engine for recording.
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let bus = 0
        
        let inputFormat = inputNode.inputFormat(forBus: bus)
        
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, _) in
            guard let self = self else { return }
            if let recognitionRequest = self.recognitionRequest {
                recognitionRequest.append(buffer)
            }
            self.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Processes the captured audio buffer, converts it to the desired format, and sends it to the server.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard currentState != .speaking else {
            return
        }
        
        let desiredSampleRate: Double = 24000.0
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: desiredSampleRate, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: buffer.format, to: desiredFormat) else {
            print("Failed to create AVAudioConverter")
            return
        }
        
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
        
        if status != .haveData {
            print("Conversion ended with status: \(status)")
            return
        }
        
        guard let channelData = convertedBuffer.int16ChannelData else { return }
        let channelDataPointer = channelData.pointee
        let dataSize = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
        
        let data = Data(bytes: channelDataPointer, count: dataSize)
        
        let audioMessage: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        
        sendJSON(audioMessage)
        
        // Compute recording volume
        DispatchQueue.main.async {
            self.recordingVolume = self.computeVolumeFromInt16Data(buffer: convertedBuffer)
        }
    }
    
    /// Computes the volume level from Int16 audio data.
    private func computeVolumeFromInt16Data(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.int16ChannelData else {
            return 0.0
        }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        var volume: Float = 0.0
        
        // Convert Int16 data to Float
        let floatData = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
        for i in 0..<frameLength {
            floatData[i] = Float(channelDataValue[i]) / Float(Int16.max)
        }
        
        vDSP_maxmgv(floatData, 1, &volume, vDSP_Length(buffer.frameLength))
        
        floatData.deallocate()
        
        return volume
    }
    
    // MARK: - Audio Playback
    
    /// Sets up the audio playback engine for playing assistant's responses.
    private func setupPlayback() {
        playbackEngine = AVAudioEngine()
        playbackPlayerNode = AVAudioPlayerNode()
        
        guard let playbackEngine = playbackEngine,
              let playbackPlayerNode = playbackPlayerNode else { return }
        
        playbackEngine.attach(playbackPlayerNode)
        
        let outputFormat = playbackEngine.outputNode.inputFormat(forBus: 0)
        playbackFormat = outputFormat
        
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
    private func playAudioData(_ data: Data) {
        guard let playbackPlayerNode = playbackPlayerNode,
              let playbackFormat = playbackFormat else { return }
        
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000.0, channels: 1, interleaved: true)!
        
        guard let inputBuffer = dataToPCMBuffer(data: data, format: inputFormat) else { return }
        
        guard let bufferToPlay = convertBuffer(inputBuffer, to: playbackFormat) else { return }
        
        // Compute playback volume
        DispatchQueue.main.async {
            self.playbackVolume = self.computeVolumeFromBuffer(buffer: bufferToPlay)
        }
        
        let durationInSeconds = Double(bufferToPlay.frameLength) / playbackFormat.sampleRate
        let durationInMs = Int(durationInSeconds * 1000)
        audioPlaybackPositionMs += durationInMs
        
        audioBuffersPending += 1
        
        playbackPlayerNode.scheduleBuffer(bufferToPlay, completionHandler: {
            DispatchQueue.main.async {
                self.audioBuffersPending -= 1
                print("Buffer played, pending buffers: \(self.audioBuffersPending)")
                
                if self.audioBuffersPending == 0 && self.isAssistantResponseDone {
                    print("All audio buffers played, starting listening.")
                    self.currentState = .idle
                    self.startListening()
                }
            }
        })
        
        if !playbackPlayerNode.isPlaying {
            playbackPlayerNode.play()
        }
    }
    
    /// Converts raw Data into an AVAudioPCMBuffer with the specified format.
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
    
    /// Converts an audio buffer to the specified output format.
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
    
    /// Computes the volume level from a Float32 audio buffer.
    private func computeVolumeFromBuffer(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0.0
        }
        let channelDataValue = channelData.pointee
        let channelDataArray = Array(UnsafeBufferPointer(start: channelDataValue, count: Int(buffer.frameLength)))
        var rms: Float = 0.0
        vDSP_rmsqv(channelDataArray, 1, &rms, vDSP_Length(buffer.frameLength))
        return rms
    }
    
}

// Note: The extension for AVAudioRecorderDelegate is included if needed.
extension RealtimeSpeechViewModel: AVAudioRecorderDelegate {
    // Implement AVAudioRecorder delegate methods if necessary.
}
