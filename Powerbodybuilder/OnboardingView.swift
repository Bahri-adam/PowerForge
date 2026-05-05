import SwiftUI
import SwiftData

struct OnboardingView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var page: Int = 0
    @State private var appeared = false
    
    // Page 1
    @State private var name: String = ""
    @State private var bodyweight: String = ""
    @State private var age: String = ""
    @State private var useMetric: Bool = false
    
    // Page 2
    @State private var goal: String = ""
    @State private var experience: String = ""
    @State private var daysPerWeek: Int = 4
    
    // Page 3
    @State private var priorityMuscles: Set<String> = []

    // Page 4 — program selection
    @State private var showProgramPage = false
    @State private var recommendedProgramId: Int = 1

    let goals = GoalType.allCases
    let experiences = ["Beginner", "Intermediate", "Advanced"]
    let muscles = ExerciseDictionary.trackingMuscles
    
    var body: some View {
        if showProgramPage {
            ProgramSelectionView(recommendedId: recommendedProgramId)
        } else {
            ZStack {
                Color.appBG
                    .ignoresSafeArea()

                Circle()
                    .fill(Color.appRed.opacity(0.08))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: 100, y: -200)

                VStack(spacing: 0) {

                    // PROGRESS BAR + BACK
                    HStack(spacing: 12) {
                        if page > 0 {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    page -= 1
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.appTextSecondary)
                                    .padding(10)
                                    .background(Color.appSurface2)
                                    .clipShape(Circle())
                            }
                        } else {
                            // Placeholder to keep progress bar aligned
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 34, height: 34)
                        }

                        HStack(spacing: 6) {
                            ForEach(0..<3) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i <= page ? Color.appRed : Color.appSurface2)
                                    .frame(height: 3)
                                    .animation(.easeInOut(duration: 0.3), value: page)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                    // PAGES
                    if page == 0 {
                        page1
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .leading)
                            ))
                    } else if page == 1 {
                        page2
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .leading)
                            ))
                    } else {
                        page3
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .leading)
                            ))
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    appeared = true
                }
                // If profile already exists but no program, skip to program selection
                if !profiles.isEmpty {
                    let p = profiles.first!
                    recommendedProgramId = recommendProgram(
                        goal: p.goal.rawValue,
                        experience: p.experience.rawValue,
                        daysPerWeek: p.daysPerWeek
                    )
                    showProgramPage = true
                }
            }
        }
    }
    
    // ─── PAGE 1 — Profile ───
    var page1: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                
                VStack(spacing: 8) {
                    Text("ADAM")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Text("POWERBUILDING TRACKER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTextDim)
                        .kerning(3)
                    Rectangle()
                        .frame(width: 36, height: 3)
                        .foregroundColor(.appRed)
                        .cornerRadius(2)
                }
                .padding(.top, 32)
                .opacity(appeared ? 1 : 0)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "YOUR PROFILE")
                        Text("Let's personalize your experience")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.appTextPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 10) {
                        AppTextField(placeholder: "Your name", text: $name, icon: "person.fill")
                        AppTextField(
                            placeholder: useMetric ? "Bodyweight (kg)" : "Bodyweight (lbs)",
                            text: $bodyweight,
                            keyboardType: .decimalPad,
                            icon: "scalemass.fill"
                        )
                        AppTextField(placeholder: "Age", text: $age, keyboardType: .numberPad, icon: "calendar")
                        
                        HStack {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundColor(.appTextDim)
                            Text("Use Metric (kg/cm)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                            Toggle("", isOn: $useMetric)
                                .tint(.appRed)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.appSurface2)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                    }
                }
                .padding(20)
                .appCard()
                
                PrimaryButton(title: "CONTINUE", icon: "arrow.right") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        page = 1
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // ─── PAGE 2 — Goals ───
    var page2: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "STEP 2 OF 3")
                    Text("What's your main goal?")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                
                // GOALS
                VStack(spacing: 8) {
                    ForEach(goals, id: \.self) { g in
                        Button(action: { goal = g.rawValue }) {
                            HStack {
                                Text(g.displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(goal == g.rawValue ? .white : .appTextSecondary)
                                Spacer()
                                if goal == g.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(16)
                            .background(goal == g.rawValue ? Color.appRed : Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(goal == g.rawValue ? Color.appRed : Color.appBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // EXPERIENCE
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "EXPERIENCE LEVEL")
                        Text("Be honest — this determines your program")
                            .font(.system(size: 12))
                            .foregroundColor(.appTextDim)
                    }
                    
                    HStack(spacing: 8) {
                        ForEach(experiences, id: \.self) { exp in
                            Button(action: { experience = exp }) {
                                VStack(spacing: 4) {
                                    Text(exp)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(experience == exp ? .white : .appTextSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(experience == exp ? Color.appRed : Color.appSurface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(experience == exp ? Color.appRed : Color.appBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // DAYS PER WEEK
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "DAYS PER WEEK")
                    
                    HStack(spacing: 8) {
                        ForEach([3, 4, 5, 6], id: \.self) { d in
                            Button(action: { daysPerWeek = d }) {
                                VStack(spacing: 2) {
                                    Text("\(d)")
                                        .font(.system(size: 22, weight: .black, design: .rounded))
                                        .foregroundColor(daysPerWeek == d ? .white : .appTextSecondary)
                                    Text("days")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(daysPerWeek == d ? .white.opacity(0.8) : .appTextDim)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(daysPerWeek == d ? Color.appRed : Color.appSurface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(daysPerWeek == d ? Color.appRed : Color.appBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                PrimaryButton(title: "CONTINUE", icon: "arrow.right") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        page = 2
                    }
                }
                .disabled(goal.isEmpty || experience.isEmpty)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // ─── PAGE 3 — Priority Muscles ───
    var page3: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "STEP 3 OF 3")
                    Text("Priority muscle groups")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Text("Pick up to 3 — we'll emphasize these in your program")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(muscles, id: \.self) { muscle in
                        let isSelected = priorityMuscles.contains(muscle)
                        let isDisabled = !isSelected && priorityMuscles.count >= 3
                        
                        Button(action: {
                            if isSelected {
                                priorityMuscles.remove(muscle)
                            } else if priorityMuscles.count < 3 {
                                priorityMuscles.insert(muscle)
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .white : .appTextDim)
                                Text(muscle)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isSelected ? .white : isDisabled ? .appTextDim : .appTextSecondary)
                                Spacer()
                            }
                            .padding(16)
                            .background(isSelected ? Color.appRed : Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.appRed : Color.appBorder, lineWidth: 1)
                            )
                            .opacity(isDisabled ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                    }
                }
                
                // SUMMARY CARD
                if !goal.isEmpty && !experience.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "YOUR SETUP", accent: .appGold)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(goal, systemImage: "target")
                                Label(experience, systemImage: "chart.bar.fill")
                                Label("\(daysPerWeek) days/week", systemImage: "calendar")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                    }
                    .padding(16)
                    .background(Color.appGold.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appGold.opacity(0.2), lineWidth: 1)
                    )
                }
                
                PrimaryButton(title: "FIND MY PROGRAM", icon: "sparkles") {
                    saveAndRecommend()
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
    }
    
    func saveAndRecommend() {
        let profile = UserProfile(
            name: name,
            bodyweight: Double(bodyweight) ?? 0,
            age: Int(age) ?? 0,
            useMetric: useMetric,
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            priorityMuscles: Array(priorityMuscles)
        )
        modelContext.insert(profile)
        try? modelContext.save()

        recommendedProgramId = recommendProgram(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek
        )
        showProgramPage = true
    }
}
