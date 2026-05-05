import SwiftUI

struct AnalyticsView: View {
    var body: some View {
        ZStack {
            Color.appBG
                .ignoresSafeArea()
            Text("ANALYTICS")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(.appTextPrimary)
        }
    }
}
