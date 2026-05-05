import SwiftUI
import SwiftData

struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var page: Int = 0
    @State private var appeared = false

    // Page 1 — Basics
    @State private var name: String = ""
    @State private var bodyweight: String = ""
    @State private var useMetric: Bool = false

    // Page 2 — Program selection (inline)
    @State private var showProgramSelection = false

    // App Tour
    @State private var showTour = false

    var body: some View {
        if showProgramSelection {
            ProgramSelectionView(recommendedId: 1, onComplete: { showTour = true })
                .fullScreenCover(isPresented: $showTour) {
                    AppTourView()
                }
        } else {
            ZStack {
                Color.appBG.ignoresSafeArea()

                Circle()
                    .fill(Color.appRed.opacity(0.08))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: 100, y: -200)

                VStack(spacing: 0) {
                    // Progress bar
                    HStack(spacing: 6) {
                        ForEach(0..<2) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i <= page ? Color.appRed : Color.appSurface2)
                                .frame(height: 3)
                                .animation(.easeInOut(duration: 0.3), value: page)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

                    if page == 0 {
                        welcomePage
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    } else {
                        profilePage
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { appeared = true }
                if !profiles.isEmpty { showProgramSelection = true }
            }
        }
    }

    // ─── Page 0 — Welcome ───
    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.appRed)
                    .opacity(appeared ? 1 : 0)

                Text("POWERFORGE")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text("Intelligent training that adapts to you")
                    .font(.system(size: 15))
                    .foregroundColor(.appTextSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "brain.head.profile", text: "Algorithm learns your strength over time")
                featureRow(icon: "chart.line.uptrend.xyaxis", text: "Auto-periodized programs that progress with you")
                featureRow(icon: "figure.strengthtraining.traditional", text: "160+ exercises with smart swap suggestions")
                featureRow(icon: "trophy.fill", text: "Track PRs, volume, and muscle balance")
            }
            .padding(20)
            .background(Color.appSurface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))

            Spacer()

            PrimaryButton(title: "GET STARTED", icon: "arrow.right") {
                withAnimation(.easeInOut(duration: 0.3)) { page = 1 }
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundColor(.appRed)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14, weight: .medium)).foregroundColor(.appTextPrimary)
        }
    }

    // ─── Page 1 — Quick Profile ───
    private var profilePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Setup")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Text("Just the basics — you can customize everything later in Settings")
                        .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)

                VStack(spacing: 12) {
                    AppTextField(placeholder: "Your name (optional)", text: $name, icon: "person.fill")
                    AppTextField(
                        placeholder: useMetric ? "Bodyweight (kg)" : "Bodyweight (lbs)",
                        text: $bodyweight,
                        keyboardType: .decimalPad,
                        icon: "scalemass.fill"
                    )

                    HStack {
                        Image(systemName: "globe").font(.system(size: 14)).foregroundColor(.appTextDim)
                        Text("Use Metric (kg)").font(.system(size: 15, weight: .medium)).foregroundColor(.appTextSecondary)
                        Spacer()
                        Toggle("", isOn: $useMetric).tint(.appRed)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.appSurface2).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(20).appCard()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundColor(.appBlue)
                        Text("Everything else is in Settings").font(.system(size: 12, weight: .medium)).foregroundColor(.appBlue)
                    }
                    Text("Experience level, muscle priorities, algorithm mode, and more — all adjustable anytime.")
                        .font(.system(size: 12)).foregroundColor(.appTextDim)
                }
                .padding(14).background(Color.appBlue.opacity(0.04)).cornerRadius(10)

                PrimaryButton(title: "CHOOSE A PROGRAM", icon: "list.bullet.clipboard.fill") {
                    saveProfile()
                }
                .disabled(bodyweight.isEmpty)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func saveProfile() {
        let profile = UserProfile(
            name: name,
            bodyweight: Double(bodyweight) ?? 0,
            age: 0,
            useMetric: useMetric,
            goal: GoalType.hypertrophy.rawValue,
            experience: "Intermediate",
            daysPerWeek: 4,
            priorityMuscles: []
        )
        modelContext.insert(profile)
        try? modelContext.save()
        showProgramSelection = true
    }
}

// ═══════════════════════════════════════════
// APP TOUR — shown once after first program selection
// ═══════════════════════════════════════════

struct AppTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tourPage = 0

    private let slides: [(icon: String, title: String, subtitle: String, detail: String, color: Color)] = [
        ("house.fill", "HOME", "Your weekly dashboard",
         "See your schedule, track volume per muscle, swap exercises, and configure your week. Tap any session to see what's planned.",
         .appRed),
        ("dumbbell.fill", "TRAIN", "Start your workout",
         "Pick a session and go. The algorithm suggests weights and reps based on your history. Log sets, adjust mid-workout, add exercises anytime.",
         .appBlue),
        ("trophy.fill", "PROGRESS", "Track everything",
         "PRs, e1RM trends, volume charts, strength balance ratios. You can also log PRs here from workouts done outside the app.",
         .appGold),
        ("gearshape.fill", "SETTINGS", "Make it yours",
         "Change your experience level, muscle priorities, toggle RPE/rest timer/rep ranges, adjust algorithm intensity, and more. Everything is customizable.",
         .appGreen),
    ]

    var body: some View {
        ZStack {
            Color.appBG.ignoresSafeArea()
            VStack(spacing: 0) {
                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Circle()
                            .fill(i == tourPage ? slides[tourPage].color : Color.appSurface2)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 24)

                TabView(selection: $tourPage) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        tourSlide(slide: slide)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Button
                if tourPage == slides.count - 1 {
                    PrimaryButton(title: "LET'S GO", icon: "bolt.fill") {
                        UserDefaults.standard.set(true, forKey: "hasSeenTour")
                        dismiss()
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                } else {
                    HStack {
                        Button("Skip") {
                            UserDefaults.standard.set(true, forKey: "hasSeenTour")
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.appTextDim)

                        Spacer()

                        Button {
                            withAnimation { tourPage += 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Next").font(.system(size: 14, weight: .bold))
                                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.appRed)
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 40)
                }
            }
        }
    }

    private func tourSlide(slide: (icon: String, title: String, subtitle: String, detail: String, color: Color)) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(slide.color.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: slide.icon)
                    .font(.system(size: 36))
                    .foregroundColor(slide.color)
            }

            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.system(size: 12, weight: .black)).foregroundColor(slide.color).kerning(3)
                Text(slide.subtitle)
                    .font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.appTextPrimary)
            }

            Text(slide.detail)
                .font(.system(size: 15)).foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
