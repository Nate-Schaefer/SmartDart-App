//
//  SmartDart.swift
//  SmartDart
//
//  Created by Nathan Schaefer on 1/22/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Charts


struct SmartDart: View {
    var name: String

        var body: some View {
            TabView {
                PlayScreen()
                    .tabItem {
                        Label("Play", systemImage: "gamecontroller")
                    }
                
                DashboardScreen()
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar")
                    }
                
                FriendsScreen()
                    .tabItem {
                        Label("Friends", systemImage: "person.2")
                    }

                AccountScreen(name: name)
                    .tabItem {
                        Label("Account", systemImage: "person")
                    }
            }
            .navigationBarBackButtonHidden(true)
        }
}

struct FriendsScreen: View {
    var body: some View {
        VStack {
            Text("Friends Screen")
                .font(.largeTitle)
                .padding()

            Spacer()
        }
    }
}

struct DashboardScreen: View {
    @State private var elo: Int = 0
    @State private var wins: Int = 0
    @State private var losses: Int = 0
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var eloHistory: [EloHistoryItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading Data...")
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.headline)
                } else {
                    Text("Dashboard Screen")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding()

                    HStack(spacing: 20) {
                        // Section 1: ELO Rating Display
                        DashboardCard(title: "ELO Rating", content: {
                            Text("\(elo)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(eloColor)
                            Text(eloCategory)
                                .font(.footnote)
                                .foregroundColor(eloColor)
                        })

                        DashboardCard(title: "Performance", content: {
                            VStack {
                                HStack(alignment: .bottom, spacing: 10) {
                                    VStack {
                                        Text("\(wins)") // Display the number of wins
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        Rectangle()
                                            .fill(Color.green)
                                            .frame(width: 30, height: CGFloat(wins) * 10)
                                    }
                                    VStack {
                                        Text("\(losses)") // Display the number of losses
                                            .font(.caption)
                                            .foregroundColor(.red)
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(width: 30, height: CGFloat(losses) * 10)
                                    }
                                }
                                .padding(.vertical, 10)
                                Text("Wins vs Losses")
                                    .font(.footnote)
                            }
                        })
                    }
                    HStack(spacing: 20) {
                        DashboardCard(title: "Elo History", content: {
                            EloHistoryChart(eloHistory: eloHistory)
                        })
                        DashboardCard(title: "Elo History", content: {
                            EloHistoryChart(eloHistory: eloHistory)
                        })
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadUserData()
        }
    }

    // Computed property for ELO category
    var eloCategory: String {
        switch elo {
        case 0..<1000: return "Beginner"
        case 1000..<1400: return "Intermediate"
        case 1400..<1800: return "Advanced"
        case 1800..<2200: return "Expert"
        default: return "Champion"
        }
    }

    // Computed property for ELO color
    var eloColor: Color {
        switch elo {
        case 0..<1000: return .gray
        case 1000..<1400: return .blue
        case 1400..<1800: return .green
        case 1800..<2200: return .orange
        default: return .yellow // Use yellow for gold
        }
    }

    func loadUserData() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            isLoading = false
            return
        }

        let db = Firestore.firestore()
        let userDoc = db.collection("users").document(currentUser.uid)

        // Fetch user document data
        userDoc.getDocument { snapshot, error in
            if let error = error {
                errorMessage = "Error loading data: \(error.localizedDescription)"
                isLoading = false
                return
            }

            guard let data = snapshot?.data() else {
                errorMessage = "No data found for this user."
                isLoading = false
                return
            }

            elo = data["elo"] as? Int ?? 0
            wins = data["wins"] as? Int ?? 0
            losses = data["losses"] as? Int ?? 0

            // Fetch eloHistory subcollection
            userDoc.collection("eloHistory").getDocuments { querySnapshot, error in
                if let error = error {
                    errorMessage = "Error loading Elo history: \(error.localizedDescription)"
                    isLoading = false
                    return
                }

                eloHistory = querySnapshot?.documents.compactMap { document in
                    let data = document.data()
                    guard let eloValue = data["elo"] as? Int,
                          let timestamp = data["timestamp"] as? Timestamp else { return nil }
                    return EloHistoryItem(id: document.documentID, elo: eloValue, timestamp: timestamp.dateValue())
                } ?? []

                print("Elo History Loaded: \(eloHistory)") // Debug print
                isLoading = false
            }
        }
    }
}

struct EloHistoryChart: View {
    var eloHistory: [EloHistoryItem]

    var body: some View {
        Chart {
            ForEach(eloHistory) { item in
                LineMark(
                    x: .value("Date", item.timestamp, unit: .day),
                    y: .value("Elo", item.elo)
                )
                .interpolationMethod(.catmullRom) // Smooths the line
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) // Show Y-axis on the left
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) // Customize X-axis tick spacing
        }
        .frame(height: 200) // Set the height for the chart
        .padding()
    }
}


struct EloHistoryItem: Identifiable {
    var id: String
    var elo: Int
    var timestamp: Date
}


struct DashboardCard<Content: View>: View {
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 200)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
    }
}

struct PlayScreen: View {
    @State private var showGameScreen = false

    var body: some View {
        VStack {
            Text("Play Screen")
                .font(.largeTitle)
                .padding()

            Spacer()

            Button(action: {
                showGameScreen = true
            }) {
                Text("Start New Game")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .fullScreenCover(isPresented: $showGameScreen) {
            GameScreen()
        }
    }
}

struct AccountScreen: View {
    var name: String
    @Environment(\.presentationMode) var presentationMode // Used to navigate back to the starting screen
    @State private var errorMessage = "" // To display any errors
    @State private var showAlert = false // To confirm account deletion

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome, \(name)")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            Button(action: {
                logout()
            }) {
                Text("Log Out")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

            Button(action: {
                showAlert = true
            }) {
                Text("Delete Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .alert("Are you sure?", isPresented: $showAlert) {
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
        .navigationBarBackButtonHidden(true)
    }

    func logout() {
        do {
            try Auth.auth().signOut()
            presentationMode.wrappedValue.dismiss()
        } catch let signOutError as NSError {
            errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
    }

    func deleteAccount() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No user logged in."
            return
        }

        // Delete the user from Firebase Authentication
        user.delete { error in
            if let error = error {
                errorMessage = "Error deleting account: \(error.localizedDescription)"
            } else {
                // Remove the user's data from Firestore
                let db = Firestore.firestore()
                db.collection("users").document(user.uid).delete { error in
                    if let error = error {
                        errorMessage = "Error deleting user data: \(error.localizedDescription)"
                    } else {
                        // Successfully deleted user
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}



struct SmartDart_Previews: PreviewProvider {
    static var previews: some View {
        SmartDart(name: "Preview User")
    }
}
