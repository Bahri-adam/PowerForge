import SwiftUI

struct SplashScreen: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 14
    @State private var ruleWidth: CGFloat = 0
    @State private var ruleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var loaderOpacity: Double = 0
    @State private var loaderProgress: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var particleOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.031, green: 0.031, blue: 0.031)
                .ignoresSafeArea()

            // Red radial glow
            RadialGradient(
                colors: [Color.red.opacity(0.15), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 250
            )
            .ignoresSafeArea()
            .opacity(glowOpacity)

            // Floating particles
            ParticleView()
                .ignoresSafeArea()
                .opacity(particleOpacity)

            // Main content
            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    // Glow behind logo
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 200, height: 200)
                        .blur(radius: 40)
                        .opacity(logoOpacity)

                    // App icon from assets
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 36))
                        .shadow(color: .red.opacity(0.4), radius: 30)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // App name
                HStack(spacing: 0) {
                    Text("Advanced")
                        .foregroundColor(Color(red: 0.8, green: 0, blue: 0))
                    Text("Lifter")
                        .foregroundColor(.white)
                }
                .font(.system(size: 42, weight: .black, design: .rounded))
                .kerning(3)
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                .padding(.top, 24)
                .shadow(color: .red.opacity(0.3), radius: 30)

                // Rule lines
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(red: 0.8, green: 0, blue: 0), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: ruleWidth, height: 1)

                    Circle()
                        .fill(Color(red: 0.8, green: 0, blue: 0))
                        .frame(width: 4, height: 4)
                        .shadow(color: .red, radius: 4)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(red: 0.8, green: 0, blue: 0), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: ruleWidth, height: 1)
                }
                .opacity(ruleOpacity)
                .padding(.top, 20)

                // Tagline
                Text("TRAIN WITHOUT LIMITS")
                    .font(.system(size: 11, weight: .medium))
                    .kerning(5)
                    .foregroundColor(Color(white: 0.33))
                    .opacity(taglineOpacity)
                    .padding(.top, 14)

                Spacer()

                // Loading bar
                VStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(white: 0.1))
                            .frame(width: 120, height: 2)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.6, green: 0, blue: 0), Color(red: 1, green: 0.2, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120 * loaderProgress, height: 2)
                            .shadow(color: .red.opacity(0.6), radius: 6)
                    }

                    Text("LOADING")
                        .font(.system(size: 9, weight: .medium))
                        .kerning(4)
                        .foregroundColor(Color(white: 0.2))
                }
                .opacity(loaderOpacity)
                .padding(.bottom, 60)
            }

            // Scanlines overlay
            ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            runAnimations()
        }
    }

    private func runAnimations() {
        // Particles fade in
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
            particleOpacity = 1
        }

        // Glow
        withAnimation(.easeOut(duration: 1.8).delay(0.5)) {
            glowOpacity = 1
        }

        // Logo scale + fade
        withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.4)) {
            logoScale = 1.0
            logoOpacity = 1
        }

        // Title
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.95)) {
            titleOpacity = 1
            titleOffset = 0
        }

        // Rule lines
        withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(1.1)) {
            ruleWidth = 90
            ruleOpacity = 1
        }

        // Tagline
        withAnimation(.easeOut(duration: 0.7).delay(1.35)) {
            taglineOpacity = 1
        }

        // Loader
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            loaderOpacity = 1
        }

        // Loader fill
        withAnimation(.easeInOut(duration: 1.8).delay(1.8)) {
            loaderProgress = 1.0
        }
    }
}

// MARK: - Particle System

private struct ParticleView: View {
    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        let radius: CGFloat
        let alpha: Double
        let speed: CGFloat
        let drift: CGFloat
        let isRed: Bool
    }

    var body: some View {
        Canvas { context, size in
            for p in particles {
                let rect = CGRect(
                    x: p.x - p.radius,
                    y: p.y - p.radius,
                    width: p.radius * 2,
                    height: p.radius * 2
                )
                context.opacity = p.alpha
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(p.isRed ? Color(red: 0.8, green: 0, blue: 0) : Color(red: 1, green: 0.27, blue: 0.27))
                )
            }
        }
        .onAppear {
            let screen = UIScreen.main.bounds
            particles = (0..<55).map { _ in
                Particle(
                    x: CGFloat.random(in: 0...screen.width),
                    y: CGFloat.random(in: 0...screen.height),
                    radius: CGFloat.random(in: 0.3...1.8),
                    alpha: Double.random(in: 0.05...0.4),
                    speed: CGFloat.random(in: 0.05...0.3),
                    drift: CGFloat.random(in: -0.2...0.2),
                    isRed: Double.random(in: 0...1) > 0.7
                )
            }
            let displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                let h = UIScreen.main.bounds.height
                let w = UIScreen.main.bounds.width
                for i in particles.indices {
                    particles[i].y -= particles[i].speed
                    particles[i].x += particles[i].drift
                    if particles[i].y < -5 {
                        particles[i].y = h + 5
                        particles[i].x = CGFloat.random(in: 0...w)
                    }
                }
            }
            timer = displayLink
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - Scanline Overlay

private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 0, to: size.height, by: 4) {
                context.fill(
                    Path(CGRect(x: 0, y: y + 3, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.04))
                )
            }
        }
    }
}
