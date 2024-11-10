//
// ContentView.swift
// RealtimeDemo
//
// Created by Alex Coundouriotis on 11/8/24.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var viewModel = RealtimeSpeechViewModel()
    @State private var showPauseButton = false
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    handleTapGesture()
                }
            
            VStack {
                // Top circle: Speaking indicator
                Circle()
                    .fill(Color.blue)
                    .frame(width: viewModel.currentState == .speaking ? 200 : 50,
                           height: viewModel.currentState == .speaking ? 200 : 50)
                    .animation(.spring(), value: viewModel.currentState)
                    .padding()
                
                Spacer()
                
                // Bottom circle: Listening indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: viewModel.currentState == .listening ? 200 : 50,
                           height: viewModel.currentState == .listening ? 200 : 50)
                    .animation(.spring(), value: viewModel.currentState)
                    .padding()
                
                ScrollView {
                    ForEach(viewModel.messages) { message in
                        Text(message.text)
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 500.0)
            }
            
            if showPauseButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            // Resume speaking leftover buffers
                            viewModel.startSpeakingLeftoverBuffers()
                            showPauseButton = false
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.gray.opacity(0.7))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            viewModel.connect()
        }
    }
    
    private func handleTapGesture() {
        switch viewModel.currentState {
        case .speaking:
            // Interrupt speaking, display pause button
            viewModel.interruptSpeaking()
            showPauseButton = true
        case .listening:
            // Interrupt listening, notify server, discard recording
            viewModel.interruptListening()
        case .idle:
            // Start listening
            viewModel.startListening()
        }
    }
    
}
