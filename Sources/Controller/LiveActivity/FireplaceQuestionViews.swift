//
//  FireplaceQuestionViews.swift
//  ControllerFeatures
//
//  The fireplace question "Ist der Kamin noch an?" on the Lock Screen and in the Dynamic Island.
//

#if os(iOS)
import AppIntents
import HAModels
import SwiftUI

/// The question with its answers, for the Lock Screen and the banner.
public struct FireplaceQuestionLiveActivityView: View {
    let contentState: FireplaceContentState
    let isStale: Bool

    /// - Parameter isStale: Past `endsAt` the server switches the fireplace off; the answers stay until the end arrives.
    public init(contentState: FireplaceContentState, isStale: Bool = false) {
        self.contentState = contentState
        self.isStale = isStale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ist der Kamin noch an?")
                        .font(.headline)
                    FireplaceQuestionDeadlineText(contentState: contentState, isStale: isStale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            FireplaceQuestionButtons()
        }
        .padding(14)
    }
}

/// "Nein" and "Ja", each answers through ``AnswerFireplaceQuestionIntent`` without opening the app.
public struct FireplaceQuestionButtons: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Button(intent: AnswerFireplaceQuestionIntent(stillOn: false)) {
                Text("Nein, aus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(intent: AnswerFireplaceQuestionIntent(stillOn: true)) {
                Text("Ja, noch an")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .font(.subheadline.weight(.semibold))
    }
}

/// "Ohne Antwort aus in 29:41": a timer text, which runs on without a new content state.
public struct FireplaceQuestionDeadlineText: View {
    let contentState: FireplaceContentState
    let isStale: Bool

    public init(contentState: FireplaceContentState, isStale: Bool) {
        self.contentState = contentState
        self.isStale = isStale
    }

    public var body: some View {
        if isStale {
            Text("Wird ausgeschaltet")
        } else {
            Text("Ohne Antwort aus in \(Text(contentState.endsAt, style: .timer))")
                .monospacedDigit()
        }
    }
}

/// The countdown alone, for the compact and the expanded Dynamic Island.
public struct FireplaceQuestionCountdown: View {
    let contentState: FireplaceContentState

    public init(contentState: FireplaceContentState) {
        self.contentState = contentState
    }

    public var body: some View {
        Text(contentState.endsAt, style: .timer)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 48)
            .foregroundStyle(.orange)
    }
}

#Preview("Kamin-Frage") {
    FireplaceQuestionLiveActivityView(contentState: FireplaceContentState(since: .now.addingTimeInterval(-7_200),
                                                                          endsAt: .now.addingTimeInterval(1_800)))
}
#endif
