//
//  GameScreen.swift
//  SmartDart
//
//  Created by Nathan Schaefer on 1/24/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GameScreen: View {
    @State private var playerScore: Int = 501
    @State private var guestScore: Int = 501
    @State private var currentTurnScore: String = ""
    @State private var isUserTurn: Bool = true
    @State private var errorMessage: String?
    @State private var turnDarts: [Int] = []
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Steel Darts")
                .font(.largeTitle)
                .padding()
            
            Text(isUserTurn ? "Your Turn" : "Guest's Turn")
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
            
            Text("Your Score: \(playerScore)")
                .font(.headline)
                .foregroundColor(.green)
                .padding()
            
            Text("Guest Score: \(guestScore)")
                .font(.headline)
                .foregroundColor(.red)
                .padding()
            
            TextField("Enter dart score", text: $currentTurnScore)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .padding()
            
            Button(action: {
                registerDart()
            }) {
                Text("Throw Dart")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            Button(action: {
                endTurn()
            }) {
                Text("End Turn")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
    }
    
    func registerDart() {
        guard let dartScore = Int(currentTurnScore), dartScore >= 0 && dartScore <= 60 else {
            errorMessage = "Invalid score. Enter a value between 0 and 60."
            return
        }
        
        turnDarts.append(dartScore)
        currentTurnScore = ""
        errorMessage = nil
        
        if turnDarts.count == 3 {
            endTurn()
        }
    }
    
    func endTurn() {
        let turnTotal = turnDarts.reduce(0, +)
        
        if isUserTurn {
            let newScore = playerScore - turnTotal
            if newScore == 0 {
                handleWin(isUser: true)
            } else if newScore < 0 {
                errorMessage = "Bust! Turn ignored."
            } else {
                playerScore = newScore
            }
        } else {
            let newScore = guestScore - turnTotal
            if newScore == 0 {
                handleWin(isUser: false)
            } else if newScore < 0 {
                errorMessage = "Guest bust! Turn ignored."
            } else {
                guestScore = newScore
            }
        }
        
        turnDarts.removeAll()
        isUserTurn.toggle()
    }
    
    func handleWin(isUser: Bool) {
        guard let currentUser = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        let userDoc = db.collection("users").document(currentUser.uid)
        
        userDoc.getDocument { document, error in
            if let document = document, document.exists {
                let currentElo = document.data()? ["elo"] as? Int ?? 1000
                let currentWins = document.data()? ["wins"] as? Int ?? 0
                let currentLosses = document.data()? ["losses"] as? Int ?? 0
                
                let newElo = isUser ? currentElo + 50 : currentElo - 50
                let newWins = isUser ? currentWins + 1 : currentWins
                let newLosses = isUser ? currentLosses : currentLosses + 1
                
                userDoc.updateData(["elo": newElo, "wins": newWins, "losses": newLosses]) { error in
                    if error == nil {
                        updateEloHistory(newElo: newElo, elo: currentElo)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    func updateEloHistory(newElo: Int, elo: Int) {
        guard let currentUser = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        let historyRef = db.collection("users").document(currentUser.uid).collection("eloHistory")
        
        historyRef.addDocument(data: ["elo": newElo, "timestamp": Timestamp(), "change": newElo - elo])
    }
}

struct GameScreen_Previews: PreviewProvider {
    static var previews: some View {
        GameScreen()
    }
}
