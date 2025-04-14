//
//  GameScreen.swift
//  SmartDart
//
//  Created by Nathan Schaefer on 1/24/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

struct GameScreen: View {
    let gameCode: String

    // Global turn indicator (stored in Firebase under "turn")
    @State private var turnOwner: String = ""
    
    // Overall (running) totals for each player (starting at 501)
    @State private var player1Total: Int = 501
    @State private var player2Total: Int = 501
    
    // For entering the active turn's scores (used only on the active turn)
    @State private var currentInputScores: [String] = ["", "", ""]
    
    // Last completed turn's scores (for display when the player is inactive)
    @State private var lastTurnScorePlayer1: [Int]? = nil
    @State private var lastTurnScorePlayer2: [Int]? = nil
    
    // Current turn index for each player (number of completed turns)
    @State private var currentTurnIndexPlayer1: Int = 0
    @State private var currentTurnIndexPlayer2: Int = 0
    
    @State private var errorMessage: String? = nil
    
    // Listener handles
    @State private var turnListenerHandle: DatabaseHandle?
    @State private var player1ListenerHandle: DatabaseHandle?
    @State private var player2ListenerHandle: DatabaseHandle?

    var body: some View {
        VStack(spacing: 20) {
            // Header and global turn indicator
            Text("Game Code: \(gameCode)")
                .font(.largeTitle)
            Text("Current Turn: \(turnOwner)")
                .font(.headline)
            
            // Overall scores for each player
            HStack {
                VStack {
                    Text("Player 1")
                        .font(.headline)
                    Text("Score: \(player1Total)")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                VStack {
                    Text("Player 2")
                        .font(.headline)
                    Text("Score: \(player2Total)")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Two-column layout for each player's section
            HStack(alignment: .top, spacing: 20) {
                // Player 1 Column
                VStack(spacing: 10) {
                    Text("Player 1")
                        .font(.headline)
                    
                    if turnOwner == "player1" {
                        // Active turn: show editable TextFields bound to currentInputScores,
                        // but disable them if Firebase has not returned data yet.
                        ForEach(0..<3, id: \.self) { index in
                            TextField("Dart \(index + 1)", text: $currentInputScores[index])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .disabled(!activeScoresLoaded(for: "player1"))
                        }
                        Button(action: {
                            endTurn(for: "player1")
                        }) {
                            Text("End Turn")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        // Inactive: if there is a last turn, show "Last Turn:" with values;
                        // otherwise, show "No turn recorded"
                        if let last = lastTurnScorePlayer1 {
                            Text("Last Turn: \(last.map { String($0) }.joined(separator: ", "))")
                                .padding()
                        } else {
                            Text("No turn recorded")
                                .padding()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray))
                .frame(maxWidth: .infinity)
                
                // Player 2 Column
                VStack(spacing: 10) {
                    Text("Player 2")
                        .font(.headline)
                    
                    if turnOwner == "player2" {
                        ForEach(0..<3, id: \.self) { index in
                            TextField("Dart \(index + 1)", text: $currentInputScores[index])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .disabled(!activeScoresLoaded(for: "player2"))
                        }
                        Button(action: {
                            endTurn(for: "player2")
                        }) {
                            Text("End Turn")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        if let last = lastTurnScorePlayer2 {
                            Text("Last Turn: \(last.map { String($0) }.joined(separator: ", "))")
                                .padding()
                        } else {
                            Text("No turn recorded")
                                .padding()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            listenForTurnIndicator()
            listenForPlayerHistory(for: "player1")
            listenForPlayerHistory(for: "player2")
        }
        .onDisappear {
            removeAllListeners()
        }
    }
    
    // MARK: - Firebase Listeners
    
    /// Listen to the global "turn" node to determine which player's turn is active.
    func listenForTurnIndicator() {
        let turnRef = Database.database().reference()
            .child("games")
            .child(gameCode)
            .child("turn")
        turnListenerHandle = turnRef.observe(.value) { snapshot in
            if let t = snapshot.value as? String {
                self.turnOwner = t
                print("DEBUG: Turn indicator updated to \(t)")
                // Clear current input scores when turn changes.
                self.currentInputScores = ["", "", ""]
            } else {
                self.errorMessage = "No turn information available."
            }
        }
    }
    
    /// Listen for the player's history. This listener updates the last completed turn's scores
    /// and the current turn index. (Note: The overall totals are updated manually on End Turn.)
    func listenForPlayerHistory(for player: String) {
        let ref = Database.database().reference()
            .child("games")
            .child(gameCode)
            .child(player)
        let handle = ref.observe(.value) { snapshot in
            print("DEBUG: \(player) history snapshot: \(snapshot.value ?? "nil")")
            var lastTurn: [Int]? = nil
            var count = 0
            for child in snapshot.children {
                if let snap = child as? DataSnapshot,
                   let arr = snap.value as? [Int],
                   arr.count == 3 { // Only count complete turns
                    count += 1
                    lastTurn = arr
                }
            }
            if let lastTurn = lastTurn {
                count = 0
                print("scores::::")
                for x in lastTurn {
                    print(x)
                    self.currentInputScores[count] = String(x)
                    count += 1
                }
            }
            if player == "player1" {
                self.currentTurnIndexPlayer1 = count
                self.lastTurnScorePlayer1 = lastTurn
                print("DEBUG: Player1 current turn index: \(self.currentTurnIndexPlayer1)")
            } else {
                self.currentTurnIndexPlayer2 = count
                self.lastTurnScorePlayer2 = lastTurn
                print("DEBUG: Player2 current turn index: \(self.currentTurnIndexPlayer2)")
            }
        }
        if player == "player1" {
            self.player1ListenerHandle = handle
        } else {
            self.player2ListenerHandle = handle
        }
    }
    
    // MARK: - Ending a Turn
    /// Called when the active player taps "End Turn." This writes the complete 3-dart turn
    /// to Firebase, then updates the overall score (only after End Turn is pressed),
    /// saves the last turn's scores, increments the player's turn index, and toggles the global turn.
    func endTurn(for player: String) {
        let scores = currentInputScores.compactMap { Int($0) }
        guard scores.count == 3 else {
            errorMessage = "Please enter valid scores for all three darts."
            return
        }
        errorMessage = nil
        
        // Read turnNum from the database
        let turnNumRef = Database.database().reference()
            .child("games")
            .child(gameCode)
            .child("turnNum")
        
        turnNumRef.observeSingleEvent(of: .value) { snapshot in
            let currentTurnNum = snapshot.value as? Int ?? 0
            let turnKey = "\(currentTurnNum)"  // We'll store this player's darts under this turnKey
            
            // Write the complete turn's scores for the active player at 'games/<gameCode>/<player>/<turnKey>'
            let playerRef = Database.database().reference()
                .child("games")
                .child(gameCode)
                .child(player)
            
            playerRef.child(turnKey).setValue(scores) { error, _ in
                if let error = error {
                    self.errorMessage = "Error writing scores: \(error.localizedDescription)"
                } else {
                    self.errorMessage = nil
                    print("DEBUG: Successfully wrote scores for \(player) at turn \(turnKey).")
                    
                    // Update local total and store the last turn's scores
                    let turnSum = scores.reduce(0, +)
                    if player == "player1" {
                        self.player1Total -= turnSum
                        self.lastTurnScorePlayer1 = scores
                        // No turnNum increment for player1
                    } else {
                        self.player2Total -= turnSum
                        self.lastTurnScorePlayer2 = scores
                        // Increment turnNum ONLY after player2 ends turn
                        turnNumRef.setValue(currentTurnNum + 1)
                        print("DEBUG: turnNum incremented to \(currentTurnNum + 1)")
                    }
                    
                    // Toggle the global turn indicator in Firebase
                    let newTurn = (player == "player1") ? "player2" : "player1"
                    let turnRef = Database.database().reference()
                        .child("games")
                        .child(gameCode)
                        .child("turn")
                    turnRef.setValue(newTurn) { error, _ in
                        if let error = error {
                            self.errorMessage = "Error updating turn: \(error.localizedDescription)"
                        } else {
                            print("DEBUG: Turn updated to \(newTurn)")
                        }
                    }
                }
            }
        }
    }
    
    func activeScoresLoaded(for player: String) -> Bool {
        // Returns true if a last turn’s scores exist for the active player.
        if player == "player1" {
            return lastTurnScorePlayer1 != nil
        } else {
            return lastTurnScorePlayer2 != nil
        }
    }

    
    // MARK: - Cleanup
    func removeAllListeners() {
        let gameRef = Database.database().reference().child("games").child(gameCode)
        if let handle = turnListenerHandle {
            gameRef.child("turn").removeObserver(withHandle: handle)
        }
        if let handle = player1ListenerHandle {
            gameRef.child("player1").removeObserver(withHandle: handle)
        }
        if let handle = player2ListenerHandle {
            gameRef.child("player2").removeObserver(withHandle: handle)
        }
    }
}

struct GameScreen_Previews: PreviewProvider {
    static var previews: some View {
        GameScreen(gameCode: "b")
    }
}
