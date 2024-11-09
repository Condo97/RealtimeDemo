//
//  ContentView.swift
//  RealtimeDemo
//
//  Created by Alex Coundouriotis on 11/8/24.
//

import SwiftUI
import AVFoundation
import Network

struct ContentView: View {
    @StateObject private var viewModel = RealtimeSpeechViewModel()
    
    var body: some View {
        VStack {
            Text("Realtime Speech Demo")
                .font(.largeTitle)
                .padding()
            Button(action: {
//                viewModel.copyMessagesToClipboard()
            }) {
                Text("Copy Messages")
                    .foregroundColor(.blue)
            }
            .padding()
            ScrollView {
                ForEach(viewModel.messages, id: \.id) { message in
                    HStack(alignment: .top) {
                        if message.isUser {
                            Spacer()
                            Text(message.text)
                                .padding()
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        } else {
                            Text(message.text)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            Spacer()
                        }
                    }
                }
            }
            
            HStack {
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    Image(systemName: viewModel.isRecording ? "mic.circle.fill" : "mic.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 50)
                        .padding()
                }
                
                TextField("Type a message...", text: $viewModel.textInput, onCommit: {
                    viewModel.sendTextMessage()
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                
                Button(action: {
                    viewModel.sendTextMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 30)
                        .padding()
                }
            }
        }
        .onAppear {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }
}
