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

struct Friend: Identifiable {
    var id: String
    var username: String
    var email: String
    var elo: Int
}

struct FriendRequest: Identifiable {
    var id: String
    var username: String
    var email: String
    var timestamp: Date
}

// MARK: - Enhanced Friends Screen
struct FriendsScreen: View {
    @State private var friends: [Friend] = []
    @State private var incomingRequests: [FriendRequest] = []
    @State private var outgoingRequests: [FriendRequest] = []
    @State private var searchText: String = ""
    @State private var searchResults: [Friend] = []
    @State private var isSearching: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedTab: Int = 0
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    // Search bar
                    SearchBar(text: $searchText, isSearching: $isSearching, onSearch: performSearch)
                        .padding(.horizontal)
                    
                    // Tab selector
                    Picker("Friends", selection: $selectedTab) {
                        Text("Friends").tag(0)
                        Text("Requests").tag(1)
                        if !outgoingRequests.isEmpty {
                            Text("Pending").tag(2)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Content based on selected tab
                    TabView(selection: $selectedTab) {
                        // Friends List Tab
                        FriendsListView(friends: friends)
                            .tag(0)
                        
                        // Friend Requests Tab
                        FriendRequestsView(requests: incomingRequests, onAccept: acceptFriendRequest, onDecline: declineFriendRequest)
                            .tag(1)
                        
                        // Pending Requests Tab
                        if !outgoingRequests.isEmpty {
                            PendingRequestsView(requests: outgoingRequests, onCancel: cancelFriendRequest)
                                .tag(2)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    
                    // Search Results Overlay
                    if isSearching {
                        SearchResultsView(
                            results: searchResults,
                            searchText: searchText,
                            onSendRequest: sendFriendRequest
                        )
                    }
                }
            }
            .navigationTitle("Friends")
            .onAppear {
                loadFriendsData()
            }
        }
    }
    
    // MARK: - Data Loading Functions
    
    func loadFriendsData() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            isLoading = false
            return
        }
        
        let db = Firestore.firestore()
        let currentUserID = currentUser.uid
        isLoading = true
        
        // Load friends list
        db.collection("users").document(currentUserID).collection("friends")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error loading friends: \(error.localizedDescription)"
                    isLoading = false
                    return
                }
                
                var loadedFriends: [Friend] = []
                let group = DispatchGroup()
                
                for document in snapshot?.documents ?? [] {
                    let friendID = document.documentID
                    
                    group.enter()
                    db.collection("users").document(friendID).getDocument { snapshot, error in
                        defer { group.leave() }
                        
                        if let data = snapshot?.data(),
                           let username = data["username"] as? String,
                           let email = data["email"] as? String,
                           let elo = data["elo"] as? Int {
                            let friend = Friend(id: friendID, username: username, email: email, elo: elo)
                            loadedFriends.append(friend)
                        }
                    }
                }
                
                // Load incoming friend requests
                group.enter()
                db.collection("users").document(currentUserID).collection("friendRequests")
                    .whereField("status", isEqualTo: "pending")
                    .getDocuments { snapshot, error in
                        defer { group.leave() }
                        
                        if let error = error {
                            errorMessage = "Error loading friend requests: \(error.localizedDescription)"
                            return
                        }
                        
                        var loadedRequests: [FriendRequest] = []
                        let requestGroup = DispatchGroup()
                        
                        for document in snapshot?.documents ?? [] {
                            let requestID = document.documentID
                            let data = document.data()
                            let senderID = data["senderID"] as? String ?? ""
                            
                            requestGroup.enter()
                            db.collection("users").document(senderID).getDocument { snapshot, error in
                                defer { requestGroup.leave() }
                                
                                if let data = snapshot?.data(),
                                   let username = data["username"] as? String,
                                   let email = data["email"] as? String,
                                   let timestamp = document.data()["timestamp"] as? Timestamp {
                                    let request = FriendRequest(
                                        id: requestID,
                                        username: username,
                                        email: email,
                                        timestamp: timestamp.dateValue()
                                    )
                                    loadedRequests.append(request)
                                }
                            }
                        }
                        
                        requestGroup.notify(queue: .main) {
                            incomingRequests = loadedRequests
                        }
                    }
                
                // Load outgoing friend requests
                group.enter()
                db.collection("friendRequests")
                    .whereField("senderID", isEqualTo: currentUserID)
                    .whereField("status", isEqualTo: "pending")
                    .getDocuments { snapshot, error in
                        defer { group.leave() }
                        
                        if let error = error {
                            errorMessage = "Error loading outgoing requests: \(error.localizedDescription)"
                            return
                        }
                        
                        var loadedRequests: [FriendRequest] = []
                        let requestGroup = DispatchGroup()
                        
                        for document in snapshot?.documents ?? [] {
                            let requestID = document.documentID
                            let data = document.data()
                            let receiverID = data["receiverID"] as? String ?? ""
                            
                            requestGroup.enter()
                            db.collection("users").document(receiverID).getDocument { snapshot, error in
                                defer { requestGroup.leave() }
                                
                                if let data = snapshot?.data(),
                                   let username = data["username"] as? String,
                                   let email = data["email"] as? String,
                                   let timestamp = document.data()["timestamp"] as? Timestamp {
                                    let request = FriendRequest(
                                        id: requestID,
                                        username: username,
                                        email: email,
                                        timestamp: timestamp.dateValue()
                                    )
                                    loadedRequests.append(request)
                                }
                            }
                        }
                        
                        requestGroup.notify(queue: .main) {
                            outgoingRequests = loadedRequests
                        }
                    }
                
                group.notify(queue: .main) {
                    friends = loadedFriends
                    isLoading = false
                }
            }
    }
    
    // MARK: - Friend Request Functions
    
    func performSearch() {
        guard !searchText.isEmpty, let currentUser = Auth.auth().currentUser else {
            searchResults = []
            return
        }
        
        let db = Firestore.firestore()
        isSearching = true
        
        // Search for users by username
        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: searchText)
            .whereField("username", isLessThanOrEqualTo: searchText + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error searching: \(error.localizedDescription)"
                    return
                }
                
                let friendIDs = Set(friends.map { friend in friend.id })
                let incomingRequestIDs = Set(incomingRequests.map { request in request.id })
                let outgoingRequestIDs = Set(outgoingRequests.map { request in request.id })
                
                searchResults = snapshot?.documents.compactMap { document in
                    let userID = document.documentID
                    let data = document.data()
                    
                    // Skip current user and existing friends/requests
                    guard userID != currentUser.uid,
                          !friendIDs.contains(userID),
                          !incomingRequestIDs.contains(userID),
                          !outgoingRequestIDs.contains(userID),
                          let username = data["username"] as? String,
                          let email = data["email"] as? String,
                          let elo = data["elo"] as? Int else {
                        return nil
                    }
                    
                    return Friend(id: userID, username: username, email: email, elo: elo)
                } ?? []
            }
    }
    
    func sendFriendRequest(to friend: Friend) {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            return
        }
        
        let db = Firestore.firestore()
        let currentUserID = currentUser.uid
        
        // Create a new friend request document
        let requestData: [String: Any] = [
            "senderID": currentUserID,
            "receiverID": friend.id,
            "status": "pending",
            "timestamp": Timestamp()
        ]
        
        // Save to general friendRequests collection and to the user's friendRequests subcollection
        db.collection("friendRequests").addDocument(data: requestData) { error in
            if let error = error {
                errorMessage = "Error sending request: \(error.localizedDescription)"
                return
            }
            
            // Add to the receiver's friendRequests subcollection
            db.collection("users").document(friend.id).collection("friendRequests")
                .addDocument(data: requestData) { error in
                    if let error = error {
                        errorMessage = "Error completing request: \(error.localizedDescription)"
                        return
                    }
                    
                    // Add to outgoing requests and clear search
                    let newRequest = FriendRequest(
                        id: friend.id,
                        username: friend.username,
                        email: friend.email,
                        timestamp: Date()
                    )
                    outgoingRequests.append(newRequest)
                    searchText = ""
                    isSearching = false
                    
                    // Update UI to show pending requests tab
                    if selectedTab != 2 && !outgoingRequests.isEmpty {
                        selectedTab = 2
                    }
                }
        }
    }
    
    func acceptFriendRequest(request: FriendRequest) {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            return
        }
        
        let db = Firestore.firestore()
        let currentUserID = currentUser.uid
        
        // First, find the sender ID from this request
        db.collection("users").document(currentUserID).collection("friendRequests")
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error accepting request: \(error.localizedDescription)"
                    return
                }
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    if let senderID = data["senderID"] as? String {
                        // Mark the request as accepted in the user's friendRequests collection
                        document.reference.updateData(["status": "accepted"]) { error in
                            if let error = error {
                                errorMessage = "Error updating request: \(error.localizedDescription)"
                                return
                            }
                            
                            // Add to current user's friends collection
                            db.collection("users").document(currentUserID).collection("friends")
                                .document(senderID).setData([:]) { error in
                                    if let error = error {
                                        errorMessage = "Error adding friend: \(error.localizedDescription)"
                                        return
                                    }
                                    
                                    // Add current user to sender's friends collection
                                    db.collection("users").document(senderID).collection("friends")
                                        .document(currentUserID).setData([:]) { error in
                                            if let error = error {
                                                errorMessage = "Error completing friend connection: \(error.localizedDescription)"
                                                return
                                            }
                                            
                                            // Update UI: remove from requests and add to friends
                                            if let index = incomingRequests.firstIndex(where: { $0.id == request.id }) {
                                                incomingRequests.remove(at: index)
                                            }
                                            
                                            let newFriend = Friend(
                                                id: senderID,
                                                username: request.username,
                                                email: request.email,
                                                elo: 0 // Will be updated on next refresh
                                            )
                                            friends.append(newFriend)
                                            selectedTab = 0 // Switch to friends tab
                                        }
                                }
                        }
                    }
                }
            }
    }
    
    func declineFriendRequest(request: FriendRequest) {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            return
        }
        
        let db = Firestore.firestore()
        let currentUserID = currentUser.uid
        
        // Find and delete the request from user's friendRequests collection
        db.collection("users").document(currentUserID).collection("friendRequests")
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error declining request: \(error.localizedDescription)"
                    return
                }
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    if let senderID = data["senderID"] as? String {
                        // Delete the request document
                        document.reference.delete { error in
                            if let error = error {
                                errorMessage = "Error removing request: \(error.localizedDescription)"
                                return
                            }
                            
                            // Also delete from main friendRequests collection if possible
                            db.collection("friendRequests")
                                .whereField("senderID", isEqualTo: senderID)
                                .whereField("receiverID", isEqualTo: currentUserID)
                                .getDocuments { snapshot, error in
                                    if let document = snapshot?.documents.first {
                                        document.reference.delete()
                                    }
                                    
                                    // Update UI to remove from requests list
                                    if let index = incomingRequests.firstIndex(where: { $0.id == request.id }) {
                                        incomingRequests.remove(at: index)
                                    }
                                }
                        }
                    }
                }
            }
    }
    
    func cancelFriendRequest(request: FriendRequest) {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No authenticated user found."
            return
        }
        
        let db = Firestore.firestore()
        let currentUserID = currentUser.uid
        
        // Find and delete the outgoing request
        db.collection("friendRequests")
            .whereField("senderID", isEqualTo: currentUserID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error canceling request: \(error.localizedDescription)"
                    return
                }
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    if let receiverID = data["receiverID"] as? String {
                        // Delete from main collection
                        document.reference.delete { error in
                            if let error = error {
                                errorMessage = "Error removing request: \(error.localizedDescription)"
                                return
                            }
                            
                            // Also delete from receiver's friendRequests subcollection
                            db.collection("users").document(receiverID).collection("friendRequests")
                                .whereField("senderID", isEqualTo: currentUserID)
                                .getDocuments { snapshot, error in
                                    if let document = snapshot?.documents.first {
                                        document.reference.delete()
                                    }
                                    
                                    // Update UI to remove from outgoing requests
                                    if let index = outgoingRequests.firstIndex(where: { $0.id == request.id }) {
                                        outgoingRequests.remove(at: index)
                                    }
                                    
                                    // If no more outgoing requests, switch to friends tab
                                    if outgoingRequests.isEmpty && selectedTab == 2 {
                                        selectedTab = 0
                                    }
                                }
                        }
                    }
                }
            }
    }
}

// MARK: - Supporting Views

struct SearchBar: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    var onSearch: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search for friends", text: $text, onCommit: onSearch)
                .padding(8)
                .padding(.horizontal, 24)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                        
                        if !text.isEmpty {
                            Button(action: {
                                text = ""
                                isSearching = false
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .onTapGesture {
                    isSearching = true
                }
            
            if isSearching {
                Button("Cancel") {
                    text = ""
                    isSearching = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .transition(.move(edge: .trailing))
                .animation(.default)
            }
        }
    }
}

struct FriendsListView: View {
    var friends: [Friend]
    
    var body: some View {
        if friends.isEmpty {
            VStack {
                Spacer()
                Text("No friends yet")
                    .font(.title2)
                    .foregroundColor(.gray)
                Text("Search for players to add them as friends")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                Spacer()
            }
        } else {
            List {
                ForEach(friends) { friend in
                    NavigationLink(destination: FriendDetailView(friend: friend)) {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(friend.username)
                                    .font(.headline)
                                Text(friend.email)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text("ELO: \(friend.elo)")
                                .foregroundColor(.orange)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

struct FriendRequestsView: View {
    var requests: [FriendRequest]
    var onAccept: (FriendRequest) -> Void
    var onDecline: (FriendRequest) -> Void
    
    var body: some View {
        if requests.isEmpty {
            VStack {
                Spacer()
                Text("No friend requests")
                    .font(.title2)
                    .foregroundColor(.gray)
                Spacer()
            }
        } else {
            List {
                ForEach(requests) { request in
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(request.username)
                                .font(.headline)
                            Text(request.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text("Sent \(timeAgo(request.timestamp))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Button(action: {
                                onAccept(request)
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                            }
                            
                            Button(action: {
                                onDecline(request)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PendingRequestsView: View {
    var requests: [FriendRequest]
    var onCancel: (FriendRequest) -> Void
    
    var body: some View {
        List {
            ForEach(requests) { request in
                HStack {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading) {
                        Text(request.username)
                            .font(.headline)
                        Text(request.email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("Sent \(timeAgo(request.timestamp))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        onCancel(request)
                    }) {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct SearchResultsView: View {
    var results: [Friend]
    var searchText: String
    var onSendRequest: (Friend) -> Void
    
    var body: some View {
        VStack {
            if results.isEmpty {
                VStack {
                    Spacer()
                    
                    if searchText.isEmpty {
                        Text("Enter a username to search")
                    } else {
                        Text("No users found")
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.9))
            } else {
                List {
                    ForEach(results) { result in
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(result.username)
                                    .font(.headline)
                                Text(result.email)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                onSendRequest(result)
                            }) {
                                Text("Add Friend")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .background(Color.white)
            }
        }
    }
}

struct FriendDetailView: View {
    var friend: Friend
    @State private var showChallengeOptions: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile header
            VStack {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                
                Text(friend.username)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("ELO Rating: \(friend.elo)")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .padding()
            
            // Action buttons
            VStack(spacing: 15) {
                Button(action: {
                    showChallengeOptions = true
                }) {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                        Text("Challenge to Game")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    // Would implement message functionality
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Send Message")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    // Would implement unfriend functionality
                }) {
                    HStack {
                        Image(systemName: "person.badge.minus")
                        Text("Remove Friend")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Friend Profile")
        .actionSheet(isPresented: $showChallengeOptions) {
            ActionSheet(
                title: Text("Challenge \(friend.username)"),
                message: Text("Select a game mode"),
                buttons: [
                    .default(Text("Standard Game")) {
                        // Would implement game invitation functionality
                    },
                    .default(Text("Practice Mode")) {
                        // Would implement practice game invitation functionality
                    },
                    .cancel()
                ]
            )
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

                        // Replace the old performance card with the new one
                        PerformanceCard(wins: wins, losses: losses)
                    }
                    
                    // Second row: ELO History (full width)
                    DashboardCard(title: "Elo History", content: {
                        EloHistoryChart(eloHistory: eloHistory)
                    })
                    
                    // Third row: Leaderboard (full width)
                    LeaderboardCard()
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

struct PerformanceCard: View {
    var wins: Int
    var losses: Int
    
    // Fixed maximum height for the bars
    private let maxBarHeight: CGFloat = 70
    
    var body: some View {
        VStack {
            Text("Performance")
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack {
                HStack(alignment: .bottom, spacing: 20) {
                    // Wins bar
                    VStack {
                        Text("\(wins)")
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                        
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 30, height: calculateBarHeight(value: wins))
                    }
                    
                    // Losses bar
                    VStack {
                        Text("\(losses)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fontWeight(.bold)
                        
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 30, height: calculateBarHeight(value: losses))
                    }
                }
                .padding(.vertical, 10)
                
                // Win rate calculation
                if wins + losses > 0 {
                    Text("Win Rate: \(calculateWinRate())%")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.top, 5)
                }
                
                Text("Wins vs Losses")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 200)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
    }
    
    // Calculate bar heights with correct handling for zero values
    private func calculateBarHeight(value: Int) -> CGFloat {
        let total = wins + losses
        
        // If there are no games at all, show minimal height
        if total == 0 {
            return 10
        }
        
        // If this specific value is zero, return minimal height
        if value == 0 {
            return 2  // Minimal height to show empty bar
        }
        
        // Calculate proportional height based on the maximum value
        let maxValue = max(wins, losses)
        let proportion = CGFloat(value) / CGFloat(maxValue)
        return maxBarHeight * proportion
    }
    
    // Calculate win rate percentage
    private func calculateWinRate() -> String {
        let total = wins + losses
        if total == 0 {
            return "0"
        }
        
        let winRate = Double(wins) / Double(total) * 100
        return String(format: "%.1f", winRate)
    }
}

struct LeaderboardCard: View {
    @State private var topPlayers: [UserRanking] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Leaderboard")
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isLoading {
                ProgressView("Loading leaderboard...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            } else if topPlayers.isEmpty {
                Text("No players found")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    // Header
                    HStack {
                        Text("Rank")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 40, alignment: .leading)
                        
                        Text("Player")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("ELO")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.bottom, 5)
                    
                    // Player list
                    ForEach(Array(topPlayers.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .foregroundColor(index < 3 ? .orange : .gray)
                                .fontWeight(index < 3 ? .bold : .regular)
                                .frame(width: 40, alignment: .leading)
                            
                            Text(player.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(player.elo)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(getEloColor(elo: player.elo))
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        
                        if index < topPlayers.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 300)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
        .onAppear {
            fetchTopPlayers()
        }
    }
    
    private func fetchTopPlayers() {
        let db = Firestore.firestore()
        
        // Query the top 5 users by ELO
        db.collection("users")
            .order(by: "elo", descending: true)
            .limit(to: 5)
            .getDocuments { snapshot, error in
                isLoading = false
                
                if let error = error {
                    errorMessage = "Failed to load leaderboard"
                    print("Error fetching leaderboard: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    errorMessage = "No leaderboard data"
                    return
                }
                
                self.topPlayers = documents.compactMap { document in
                    let data = document.data()
                    let id = document.documentID
                    guard let elo = data["elo"] as? Int else { return nil }
                    let displayName = data["displayName"] as? String ?? "Player"
                    
                    return UserRanking(id: id, displayName: displayName, elo: elo)
                }
            }
    }
    
    private func getEloColor(elo: Int) -> Color {
        switch elo {
        case 0..<1000: return .gray
        case 1000..<1400: return .blue
        case 1400..<1800: return .green
        case 1800..<2200: return .orange
        default: return .yellow
        }
    }
}

struct UserRanking: Identifiable {
    var id: String
    var displayName: String
    var elo: Int
}

struct EloHistoryChart: View {
    var eloHistory: [EloHistoryItem]
    
    // Computed properties to get min, max, and starting values
    private var sortedHistory: [EloHistoryItem] {
        return eloHistory.sorted { $0.timestamp < $1.timestamp }
    }
    
    private var minElo: Int {
        return eloHistory.min { $0.elo < $1.elo }?.elo ?? 0
    }
    
    private var maxElo: Int {
        return eloHistory.max { $0.elo < $1.elo }?.elo ?? 0
    }
    
    private var startingElo: Int {
        return sortedHistory.first?.elo ?? 0
    }
    
    private var latestElo: Int {
        return sortedHistory.last?.elo ?? 0
    }
    
    private var eloChange: Int {
        return latestElo - startingElo
    }
    
    private var isPositiveChange: Bool {
        return eloChange >= 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Current vs Starting ELO display with smaller text
            if !eloHistory.isEmpty {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("\(latestElo)")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    // ELO Change
                    HStack(spacing: 1) {
                        Image(systemName: isPositiveChange ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(isPositiveChange ? .green : .red)
                        
                        Text("\(abs(eloChange))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(isPositiveChange ? .green : .red)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Starting")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("\(startingElo)")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // ELO Chart
            if eloHistory.isEmpty {
                Text("No ELO history available")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                Chart {
                    ForEach(sortedHistory) { item in
                        LineMark(
                            x: .value("Date", item.timestamp, unit: .day),
                            y: .value("Elo", item.elo)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.blue.gradient)
                        
                        // Add points at each data point
                        PointMark(
                            x: .value("Date", item.timestamp, unit: .day),
                            y: .value("Elo", item.elo)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(20) // Smaller point size
                    }
                    
                    // Add a rule mark for the starting ELO
                    RuleMark(y: .value("Starting ELO", startingElo))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .trailing) {
                            Text("St")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                }
                .chartYScale(domain: (minElo - 30)...(maxElo + 30))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        if let intValue = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(intValue)")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisGridLine()
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month().day())
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .frame(height: 110) // Reduced chart height
                .padding(.top, 4)
            }
        }
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
        .frame(maxWidth: .infinity, maxHeight: 300)
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
