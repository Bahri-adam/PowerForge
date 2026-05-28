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

    // Page 2 — Density preference (defaults to standard so a Skip
    // lands somewhere sensible without exposing the full firehose).
    @State private var selectedDensity: UIDensity = .standard

    // Page 3 — Program selection (inline)
    @State private var showProgramSelection = false

    // App Tour
    @State private var showTour = false

    var body: some View {
        if showProgramSelection {
            ProgramSelectionView(recommendedId: 1, onComplete: { showTour = true })
                .fullScreenCover(isPresented: $showTour) {
                    AppWalkthroughView()
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
                    // Progress bar — 3 pages now (welcome → profile → density)
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
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
                    } else if page == 1 {
                        profilePage
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    } else {
                        densityPage
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

                PrimaryButton(title: "NEXT", icon: "arrow.right") {
                    withAnimation(.easeInOut(duration: 0.3)) { page = 2 }
                }
                .disabled(bodyweight.isEmpty)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ─── Page 2 — Interface density ───
    private var densityPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How much detail?")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Text("Pick a starting density — you can change this anytime in Settings.")
                        .font(.system(size: 13)).foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)

                VStack(spacing: 10) {
                    densityChoice(level: .minimal,
                                  title: "Just track my workouts",
                                  subtitle: "Log sets, see history. No jargon, no extra cards. Algorithm runs quietly.")
                    densityChoice(level: .standard,
                                  title: "Show me the basics",
                                  subtitle: "Volume tracking, PRs, recovery hints — all in plain language.",
                                  recommended: true)
                    densityChoice(level: .advanced,
                                  title: "Show me everything",
                                  subtitle: "IFI, PML, MRV signals, balance ratios, predictive 1RM — the full coaching layer.")
                }

                PrimaryButton(title: "CHOOSE A PROGRAM", icon: "list.bullet.clipboard.fill") {
                    saveProfile()
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
    }

    private func densityChoice(level: UIDensity, title: String, subtitle: String, recommended: Bool = false) -> some View {
        let selected = selectedDensity == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedDensity = level
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color.appRed : Color.appBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(Color.appRed).frame(width: 12, height: 12)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold)).foregroundColor(.appTextPrimary)
                        if recommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .black)).foregroundColor(.appRed).kerning(0.8)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.appRed.opacity(0.12)).cornerRadius(4)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11)).foregroundColor(.appTextDim)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.appSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.appRed.opacity(0.4) : Color.appBorder, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
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
        // Setter also forces algorithmMode = .full for minimal/standard.
        profile.density = selectedDensity
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
    @Query private var profiles: [UserProfile]
    @State private var tourPage = 0

    /// User's UI density. Advanced users get extra slides explaining the
    /// algorithm concepts (IFI, MRV, PML, block phases, "ⓘ" icons).
    private var density: UIDensity { profiles.first?.density ?? .standard }

    /// Base 4-slide tour shown to everyone.
    private let baseSlides: [(icon: String, title: String, subtitle: String, detail: String, color: Color)] = [
        ("house.fill", "HOME", "Your weekly dashboard",
         "See your schedule, track volume per muscle, swap exercises, and configure your week. Tap any session to see what's planned.",
         .appRed),
        ("dumbbell.fill", "TRAIN", "Start your workout",
         "Pick a session and go. The algorithm suggests weights and reps based on your history. Log sets, adjust mid-workout, add exercises anytime.",
         .appBlue),
        ("trophy.fill", "PROGRESS", "Track everything",
         "PRs, e1RM trends, volume charts, history. Log a PR anytime from workouts done outside the app.",
         .appGold),
        ("gearshape.fill", "SETTINGS", "Make it yours",
         "Change your goal, muscle priorities, interface density, and more. Everything is adjustable later.",
         .appGreen),
    ]

    /// Extra slides shown only to advanced users — introduce the algorithmic
    /// metrics they'll see throughout the app so they're not surprised by jargon.
    private let advancedSlides: [(icon: String, title: String, subtitle: String, detail: String, color: Color)] = [
        ("waveform.path.ecg", "IFI",
         "Watches how hard you're working",
         "After all sets are logged, you'll see an IFI badge. It measures rep drop-off across the exercise. Green = optimal effort. Yellow/orange = fatigue building. The algorithm uses it to decide next session's load.",
         .appYellow),
        ("exclamationmark.triangle.fill", "MRV signals",
         "Knows when to back you off",
         "Five fatigue signals per muscle — e1RM decline, IFI trend, stuck loads, dropping volume, missed reps. When they accumulate, you'll see a 'fatigue building' banner. Take the deload when offered.",
         .appOrange),
        ("arrow.right.circle", "Adaptive recommendations",
         "Weight reduces when you're pre-fatigued",
         "If you bench heavy first, the algorithm reduces tricep weight later (PML — Prior Muscle Load). The amount adapts to your personal recovery profile over time. You'll see 'Adjusted for prior X work' as a note.",
         .appBlue),
        ("info.circle.fill", "Tap ⓘ for any term",
         "In-app explanations everywhere",
         "Look for the small 'ⓘ' icons next to IFI, MRV warnings, stall cards, balance ratios, and more. Tap any one for a clear explanation. The full glossary lives in Settings → Learn → Glossary.",
         .appRed),
    ]

    private var slides: [(icon: String, title: String, subtitle: String, detail: String, color: Color)] {
        density == .advanced ? baseSlides + advancedSlides : baseSlides
    }

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
