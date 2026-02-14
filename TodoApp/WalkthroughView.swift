import SwiftUI

struct WalkthroughStep {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    let codeSnippet: String?
}

struct WalkthroughView: View {
    @Binding var isPresented: Bool

    @State private var currentStep = 0

    private let steps: [WalkthroughStep] = [
        WalkthroughStep(
            icon: "hand.wave.fill",
            iconColor: .orange,
            title: "Welcome to Big Rocks First",
            body: "Plan your week with clarity. Set goals, pick your top priorities, and organize todos by urgency and context — all stored in a simple markdown file you own.",
            codeSnippet: nil
        ),
        WalkthroughStep(
            icon: "target",
            iconColor: .blue,
            title: "Start with your Goals",
            body: "The left sidebar holds your goals organized by theme. Each goal can have a #tag that links it to related todos, so you always see the big picture.",
            codeSnippet: nil
        ),
        WalkthroughStep(
            icon: "star.fill",
            iconColor: .yellow,
            title: "Pick your Top 5",
            body: "Pin your most important tasks for the week in the Top 5 section. Click + to add a task, and use the reset arrow to start fresh each week.",
            codeSnippet: nil
        ),
        WalkthroughStep(
            icon: "checklist",
            iconColor: .green,
            title: "Organize by Priority & Context",
            body: "Todos are grouped by urgency (Today / This Week / Urgent / Normal) and context tags (prep / reply / deep / waiting). Right-click any todo for actions like edit, move, or delete.",
            codeSnippet: nil
        ),
        WalkthroughStep(
            icon: "doc.text",
            iconColor: .purple,
            title: "Your data is a simple .md file",
            body: "Everything is stored as a plain markdown file — no database, no lock-in. You can edit it in any text editor.",
            codeSnippet: """
            ## 🎯 Goals
            **Q1 Launch** #launch
            - Ship v2.0 by end of March

            ### 🔴 Top 5 of the week
            - [ ] Finalize v2.0 feature spec #launch

            ### 🟠 This Week
            - [ ] Review user research #growth #deep
            """
        ),
        WalkthroughStep(
            icon: "sparkles",
            iconColor: .pink,
            title: "Auto-tag with AI",
            body: "Right-click any todo → \"Auto-tag with AI\" to automatically add context tags. Works out of the box in demo mode (enter demo as API key) or with your own Anthropic API key.",
            codeSnippet: nil
        ),
    ]

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Card
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Theme.secondaryBackground)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                // Step content
                let step = steps[currentStep]

                VStack(spacing: 16) {
                    Image(systemName: step.icon)
                        .font(.system(size: 40))
                        .foregroundColor(step.iconColor)
                        .frame(height: 48)

                    Text(step.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)

                    Text(step.body)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let snippet = step.codeSnippet {
                        Text(snippet)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.text.opacity(0.85))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .fill(Theme.secondaryBackground)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .padding(.bottom, 20)

                // Step dots
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Theme.accent : Theme.secondaryText.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 20)

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button(action: {
                            withAnimation(Theme.Animation.quickFade) {
                                currentStep -= 1
                            }
                        }) {
                            Text("Back")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .fill(Theme.secondaryBackground)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()

                    if currentStep < steps.count - 1 {
                        Button(action: {
                            withAnimation(Theme.Animation.quickFade) {
                                currentStep += 1
                            }
                        }) {
                            Text("Next")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .fill(Theme.accent)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: dismiss) {
                            Text("Get Started")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .fill(Theme.accent)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusLg)
                    .fill(Theme.cardBackground)
                    .shadow(color: Theme.Shadow.hoverColor, radius: Theme.Shadow.hoverRadius, y: Theme.Shadow.hoverY)
            )
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: "hasSeenWalkthrough")
        withAnimation(Theme.Animation.quickFade) {
            isPresented = false
        }
    }
}
