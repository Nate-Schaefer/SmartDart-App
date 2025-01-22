//
//  ContentView.swift
//  SmartDart
//
//  Created by Nathan Schaefer on 1/21/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Image(systemName: "target") // SF Symbol for the dartboard
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)

                Text("Welcome to SmartDart")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("Revolutionize your dart game with intelligent scoring and tracking.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 15) {
                    NavigationLink(destination: LoginScreen()) {
                        Text("Log In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }

                    NavigationLink(destination: SignUpScreen()) {
                        Text("Sign Up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
            .edgesIgnoringSafeArea(.all)
        }
    }
}

struct LoginScreen: View {
    @State private var usernameOrEmail = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoggedIn = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Log In")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            TextField("Username or Email", text: $usernameOrEmail)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.top)
            }

            Button(action: {
                loginUser()
            }) {
                Text("Log In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .padding(.top)

            NavigationLink(destination: WelcomeScreen(name: usernameOrEmail), isActive: $isLoggedIn) {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
        .frame(alignment: .center)
    }

    func loginUser() {
        // Check if the input is an email or username
        if isValidEmail(usernameOrEmail) {
            // Login with email and password
            Auth.auth().signIn(withEmail: usernameOrEmail, password: password) { result, error in
                if let error = error {
                    errorMessage = "Error logging in: \(error.localizedDescription)"
                } else {
                    isLoggedIn = true
                }
            }
        } else {
            // Fetch the user's email from Firestore using their username
            let db = Firestore.firestore()
            let usersRef = db.collection("users").whereField("username", isEqualTo: usernameOrEmail)
            usersRef.getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = "Error fetching user: \(error.localizedDescription)"
                } else if let document = snapshot?.documents.first, let email = document["email"] as? String {
                    // Login using the email
                    Auth.auth().signIn(withEmail: email, password: password) { result, error in
                        if let error = error {
                            errorMessage = "Error logging in: \(error.localizedDescription)"
                        } else {
                            isLoggedIn = true
                        }
                    }
                } else {
                    errorMessage = "No user found with that username."
                }
            }
        }
    }

    // Helper function to check if the input is a valid email
    func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailTest.evaluate(with: email)
    }
}

struct SignUpScreen: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showWelcome = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            Button(action: {
                signUp()
            }) {
                Text("Sign Up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
        .frame(alignment: .center)
        .navigationDestination(isPresented: $showWelcome) {
            WelcomeScreen(name: username)
        }
    }

    func signUp() {
        // Create the user with Firebase Authentication
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                // Store the user's data in Firestore
                saveUserData()
            }
        }
    }

    func saveUserData() {
        let db = Firestore.firestore()

        // Add user data to Firestore
        db.collection("users").document(Auth.auth().currentUser!.uid).setData([
            "username": username,
            "email": email
        ]) { error in
            if let error = error {
                errorMessage = "Error saving user data: \(error.localizedDescription)"
            } else {
                showWelcome = true
            }
        }
    }
}


struct WelcomeScreen: View {
    var name: String
    @Environment(\.presentationMode) var presentationMode // Used to navigate back to the starting screen

    var body: some View {
        VStack {
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
            .padding()

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
        .frame(alignment: .center)
        .navigationBarBackButtonHidden(true)
    }

    func logout() {
        // Sign out the user using Firebase Authentication
        do {
            try Auth.auth().signOut()

            // Navigate back to the starting screen (ContentView)
            presentationMode.wrappedValue.dismiss()

        } catch let signOutError as NSError {
            print("Error signing out: %@", signOutError)
        }
    }
}

struct StartingScreen_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
