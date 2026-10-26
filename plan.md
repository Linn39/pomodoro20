# promodoro20 project plan

## Goal and scope

Create a separate iPhone and Apple Watch app called **promodoro20**, beside Blink. Users create plans with selected weekdays and a daily time window; the watch reminds them every 20 minutes during active windows to take a 20-second break. A reminder offers **Start Break** and **Snooze**. Starting a break runs a 20-second countdown and gives an end haptic if it completes within the active window; the next 20-minute work interval starts automatically. Snooze postpones the reminder by a configurable duration, initially one hour.

The initial implementation now lives in this repository. Its two-target SwiftUI Xcode layout uses Blink as a reference, with independent app identifiers and only the code this simpler app needs. Blink's motion detection, calibration, session logging, and extended-runtime design are not included.

## Implementation status

- The iPhone plan editor, shared schedule and reminder engine, watch interface, settings sync, and watch-scheduled notifications are implemented. The schedule and reminder engine tests pass in an iPhone simulator, and both app targets build for simulator and device SDKs.
- Reminder and break-end notifications are projected into a finite pending queue. The watch requests background refresh to replenish that queue, but watchOS may defer the refresh. If the queue runs out before the app runs again, break reminders may pause until the next refresh or launch. Recurring window start/end notifications remain scheduled separately.
- Validate notification timing, actions, haptics, syncing, and unattended multi-day delivery on a physical Apple Watch before treating watch delivery as complete. Device signing must be configured in Xcode.

## Proposed project structure

```text
promodoro20/
├── plan.md
├── promodoro20.xcodeproj/           # iOS app and companion watchOS app targets
├── Shared/
│   ├── Schedule.swift               # plans with weekdays and local start/end times
│   ├── ReminderState.swift            # idle, working, prompted, breaking, snoozed
│   ├── ReminderEngine.swift           # date-based transitions and next due time
│   └── SettingsStore.swift            # local persistence and versioned settings
├── iOS/
│   ├── App.swift
│   ├── SettingsView.swift             # schedule editor and permission/status help
│   └── WatchSync.swift                # transfer settings to the watch
├── watchOS/
│   ├── App.swift
│   ├── ReminderView.swift             # status, countdown, Start Break, Snooze
│   ├── ReminderDelivery.swift         # notifications, actions, haptics
│   └── WatchSync.swift                # receive settings; keep a local copy
└── Tests/
    ├── ScheduleTests.swift
    └── ReminderEngineTests.swift
```

SwiftUI provides the two interfaces. A small shared, platform-independent engine computes transitions from absolute dates; neither device relies on a continuously running 20-minute timer. The watch owns reminder state and delivery, so it can work when the iPhone is unavailable. The phone edits the schedule and sends it via WatchConnectivity; the watch stores the last received settings. If on-watch schedule editing is later required, add it after the basic flow works.

## Behavior to specify before coding

- Store enabled plans, each with selected weekdays and start/end times as local wall-clock values. Prevent overlapping active windows. Re-evaluate using the current timezone and calendar after timezone or daylight-saving changes.
- Send a watch notification when an active window starts or ends. Entering an active window starts a new 20-minute interval. When it ends, cancel pending reminders and stop the cycle. The first break reminder occurs 20 minutes after the window opens, subject to the decisions below.
- At the due time, deliver a watch reminder with **Start Break** and **Snooze** actions. The watch screen exposes the same actions when a prompt is pending. Persist due times and state so relaunches recover correctly.
- **Start Break** records an absolute end time 20 seconds later. Show a countdown when the watch app is visible, give an end haptic or watch notification as the platform permits, then automatically set the next reminder for 20 minutes after break completion. If the active window ends during the break, stop the countdown immediately, send only the window-end notification, and start fresh at the next active window.
- **Snooze** is a one-tap watch action using one global duration selected in iPhone settings; do not ask for a duration on each tap. Offer 15, 30, 60, and 120 minutes, defaulting to 60, and show the selected duration in the watch action label. Record the next reminder due that long after the tap; it does not start the break countdown. An active window ending during snooze cancels that pending prompt.
- Treat notification permission denial and unavailable background delivery as visible status in the app. Do not claim that an arbitrary repeating app timer can reliably wake a backgrounded watch app or produce a haptic at an exact second; validate notification and action behavior on a physical watch.

## Implementation steps and dependencies

| Step | Work and completion check | Depends on |
| --- | --- | --- |
| 1. Resolve product rules | Confirm the open decisions below and write concrete acceptance cases for schedule boundaries, snooze, and break completion. | None |
| 2. Create Xcode project | Create separate iOS/watchOS targets, unique bundle IDs, signing placeholders, shared source group, test target, and minimum OS versions (initial proposal: iOS 17/watchOS 10, matching Blink). Both starter apps build. | 1 |
| 3. Build the schedule model | Persist enabled plans and wall-clock start/end; reject overlapping windows; compute whether a date is active and the next opening/closing across week, midnight, timezone, and DST changes. Unit tests pass. | 1, 2 |
| 4. Build the reminder engine | Model work, prompt, break, snooze, and inactive states with absolute deadlines; persist and restore transitions; define behavior when deadlines pass while the app is closed. Unit tests cover actions and schedule edges. | 3 |
| 5. Prove watch delivery | Prototype scheduled watch notifications, action handling, permission flow, and foreground haptics on a real watch. Document actual timing limits and adjust the UX or delivery strategy if needed. | 2, 4 |
| 6. Build watch UI | Show current status and remaining time; implement Start Break and Snooze through the engine; show the 20-second countdown and automatic restart. | 4, 5 |
| 7. Build iPhone settings and sync | Edit plans and the global snooze duration on iPhone; send complete settings snapshots to watch; persist on both devices and reschedule when settings change. Show sync/permission state. | 3, 5 |
| 8. Integrate and verify | Build both targets; test selected/unselected days, window start/end notifications, snooze durations and closing time, break completion and interruption at window end, app termination/relaunch, phone disconnected, permissions denied, timezone/DST changes, and actual watch haptics/actions. | 6, 7 |

The critical path is **1 → 2 → 3 → 4 → 5 → 6 → 8**. Step 7 can run alongside step 6 after steps 3 and 5. Step 5 is an early feasibility gate: the final delivery implementation should follow what watchOS actually allows on target hardware.

## More detailed design decisions

### Plans and active windows

Users can create multiple plans and enable or disable each one. Each plan selects one or more weekdays and applies the same start and end time to every selected day. A window may cross midnight and belongs to its starting weekday. Active windows cannot overlap.

### Ignored reminders and snooze

A reminder expires if neither **Start Break** nor **Snooze** is selected within one minute of its scheduled time. The watch retries once, five minutes after the first reminder was scheduled. If the retry also expires after one minute, a new 20-minute work interval starts at that expiration time. For example, a reminder at 10:00 expires at 10:01, retries at 10:05, expires at 10:06, and is followed by another reminder at 10:26.

**Snooze** is a one-tap watch action. Its duration is a global iPhone setting with choices of 15, 30, 60, or 120 minutes and a default of 60 minutes. The watch action shows the selected duration. The next reminder is due exactly that long after the tap, even if several normal 20-minute intervals are skipped. The reminder is canceled if the active window ends first.

Actions on expired notifications cannot start a break or snooze an old prompt. The app shows the current state and next reminder instead.

### Window boundaries and breaks

The watch sends a general notification when an active window starts or ends. If a window ends during a 20-second break, the countdown stops at the window end and only the window-end notification is sent. No break-end alert is sent. The next active window starts a fresh 20-minute cycle.

### Setup and watch operation

Schedules are created and edited only on iPhone. The watch stores the last synced schedule and works without a phone connection after setup. Watch-only installation and a default schedule are out of scope.

### Notification delivery

The watch schedules reminders directly. Notifications may arrive late or be silenced by system settings; an alert at the exact second is not required.

