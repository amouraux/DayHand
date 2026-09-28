import SwiftUI
import UserNotifications

/// The one place that talks to the notification centre.
///
/// Reminders live on the cards; this only mirrors them into pending
/// notifications. Nothing here decides anything — `Reminders` does that, in the
/// model layer, where it can be tested — so a schedule that has drifted from
/// the cards is fixed by handing it the cards again.
extension Notification.Name {
    /// Posted when a reminder notification is opened, so the app can show the
    /// review rather than just coming to the front.
    static let reminderOpened = Notification.Name("DayHandReminderOpened")
}

final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private let centre = UNUserNotificationCenter.current()
    /// Asked for the first time a reminder is actually set, not at launch: a
    /// permission sheet in front of an empty list is a question about nothing.
    private var askedForPermission = false

    private override init() {
        super.init()
        centre.delegate = self
    }

    /// Opening a notification asks for the review. Swiping one away does not:
    /// that is how a notification is got rid of, not how a decision is made,
    /// so the reminder is still waiting afterwards.
    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            NotificationCenter.default.post(name: .reminderOpened, object: nil)
        }
        done()
    }

    /// Show it even with the app in front: the review is the only place it can
    /// be answered, and a reminder that fired invisibly is one that was missed.
    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /// Replace every pending reminder with one per armed card.
    ///
    /// Rewriting the lot is deliberate. The set is a handful of notifications,
    /// and patching them one at a time is how a reminder ends up firing for a
    /// card finished last week.
    /// - Parameter cards: every card, not just the ones with reminders to
    ///   come. The badge each notification carries is the flag's count at the
    ///   moment that notification fires, and working that out needs the lot.
    func sync(to cards: [TodoItem], now: Date = Date()) {
        let wanted = Reminders.scheduled(in: cards, now: now)
            .compactMap { card -> (TodoItem, Date)? in
                guard let at = card.remindAt else { return nil }
                return (card, at)
            }
            .sorted { $0.1 < $1.1 }

        setBadge(Attention.count(in: cards, now: now))
        centre.removeAllPendingNotificationRequests()
        guard !wanted.isEmpty else { return }

        requestPermissionIfNeeded { [weak self] granted in
            guard granted, let self else { return }
            // Again: the first attempt above ran before there was permission
            // to show a badge at all. Belt and braces rather than a proven
            // fix — a brand-new install still shows no badge until its second
            // launch, which looks like the system not accepting one in the
            // same session the permission was granted. It corrects itself,
            // and nothing is wrong by the time a reminder matters.
            self.setBadge(Attention.count(in: cards, now: now))

            for (card, at) in wanted {
                let content = UNMutableNotificationContent()
                content.title = card.title
                content.body = String(localized: "Move it, or keep it where it is.",
                                      comment: "Notification body for a reminder")
                content.sound = .default
                // What the flag will read once this has fired. Not a running
                // total: a card whose reminder arrives while it already sits
                // in Today adds nothing, and one that turns red at midnight
                // adds itself without any notification to announce it.
                content.badge = NSNumber(value: Attention.count(in: cards, now: at))
                // Carries the card so opening the notification can go straight
                // to the review rather than to the top of the list.
                content.userInfo = ["card": card.id.uuidString]

                let parts = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: at)
                let request = UNNotificationRequest(
                    identifier: card.id.uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                self.centre.add(request)
            }
        }
    }

    /// The one number on the icon, and the same one the flag shows: cards
    /// whose reminder has arrived that are still sitting in Inbox or Later.
    /// Two numbers meaning nearly the same thing is how you end up with an
    /// icon saying 1 and a button saying 0.
    func setBadge(_ count: Int) {
        // On the main queue always: the permission callback arrives on one of
        // the notification centre's own queues, and anything touching the icon
        // belongs on the main one.
        DispatchQueue.main.async { [weak self] in
            self?.centre.setBadgeCount(count)
        }
    }

    private func requestPermissionIfNeeded(_ done: @escaping (Bool) -> Void) {
        centre.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                done(true)
            case .denied:
                // Reminders still show in the review; only the notification is
                // lost. Nothing is worth nagging about here.
                done(false)
            default:
                guard let self, !self.askedForPermission else { return done(false) }
                self.askedForPermission = true
                self.centre.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    done(granted)
                }
            }
        }
    }
}

extension Urgency {
    /// Orange while it is coming, red once it is here or past. Red stays
    /// reserved for exactly that.
    var tint: Color? {
        switch self {
        case .none:        return nil
        case .approaching: return .orange
        case .due, .overdue: return .red
        }
    }
}
