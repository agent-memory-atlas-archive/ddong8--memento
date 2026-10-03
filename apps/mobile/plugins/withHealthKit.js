const { withAppDelegate, withInfoPlist, withEntitlementsPlist, createRunOncePlugin } = require("@expo/config-plugins");

const PKG_NAME = "memento-healthkit-plugin";
const PKG_VERSION = "1.0.0";

function modifyAppDelegate(contents) {
  if (contents.includes("HealthKitSleepManager")) {
    return contents;
  }

  // 1. Ensure HealthKit is imported
  let newContents = contents;
  if (!newContents.includes("import HealthKit")) {
    newContents = newContents.replace("import React", "import React\nimport HealthKit");
  }

  // 2. Insert HealthKitSleepManager class before @main class AppDelegate
  const managerCode = `
@objc public class HealthKitSleepManager: NSObject {
  @objc public static let shared = HealthKitSleepManager()
  private let healthStore = HKHealthStore()
  private var lastSyncTime: Date?

  public override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onDefaultsChanged),
      name: UserDefaults.didChangeNotification,
      object: nil
    )
  }

  @objc private func onDefaultsChanged() {
    syncSleepIfAuthorized()
  }

  @objc public func syncSleepIfAuthorized() {
    guard HKHealthStore.isHealthDataAvailable(),
          let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      return
    }

    let defaults = UserDefaults.standard
    guard let server = defaults.string(forKey: "memento_server"),
          let token = defaults.string(forKey: "memento_token"),
          !server.isEmpty, !token.isEmpty else {
      return
    }

    if let last = lastSyncTime, Date().timeIntervalSince(last) < 10 {
      return
    }
    lastSyncTime = Date()

    healthStore.requestAuthorization(toShare: nil, read: [sleepType]) { [weak self] success, _ in
      guard success, let self = self else { return }
      self.fetchAndUploadSleep(server: server, token: token)
    }
  }

  @objc public func fetchAndUploadSleep(server: String, token: String) {
    guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
    let now = Date()
    let calendar = Calendar.current
    guard let startDate = calendar.date(byAdding: .day, value: -2, to: now) else { return }

    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

    let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, results, _ in
      guard let samples = results as? [HKCategorySample], !samples.isEmpty else { return }

      var sessions: [[HKCategorySample]] = []
      var currentSession: [HKCategorySample] = []

      for s in samples {
        if let last = currentSession.last {
          if s.startDate.timeIntervalSince(last.endDate) > 4 * 3600 {
            if !currentSession.isEmpty {
              sessions.append(currentSession)
            }
            currentSession = [s]
          } else {
            currentSession.append(s)
          }
        } else {
          currentSession.append(s)
        }
      }
      if !currentSession.isEmpty {
        sessions.append(currentSession)
      }

      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "yyyy-MM-dd"

      let timeFormatter = DateFormatter()
      timeFormatter.dateFormat = "HH:mm"

      for session in sessions {
        guard let firstSample = session.first, let lastSample = session.last else { continue }

        let minStart = firstSample.startDate
        let maxEnd = lastSample.endDate

        let stageSamples = session.filter { $0.value == 1 || $0.value == 3 || $0.value == 4 || $0.value == 5 }
        let validSamples = !stageSamples.isEmpty ? stageSamples : session.filter { $0.value == 0 }

        var mergedIntervals: [(start: Date, end: Date)] = []
        for s in validSamples {
          if let last = mergedIntervals.last, s.startDate <= last.end {
            mergedIntervals[mergedIntervals.count - 1].end = max(last.end, s.endDate)
          } else {
            mergedIntervals.append((start: s.startDate, end: s.endDate))
          }
        }

        let totalDuration = mergedIntervals.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        let sleepHours = round((totalDuration / 3600.0) * 10) / 10.0

        if sleepHours < 0.5 {
          continue
        }

        let payload: [String: Any] = [
          "log_date": dateFormatter.string(from: maxEnd),
          "wakeup_time": timeFormatter.string(from: maxEnd),
          "bedtime": timeFormatter.string(from: minStart),
          "sleep_hours": sleepHours
        ]

        guard let cleanUrl = URL(string: "\\(server.trimmingCharacters(in: CharacterSet(charactersIn: \\"/\\")))/api/life/rhythm") else { continue }
        var request = URLRequest(url: cleanUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")

        do {
          request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
          URLSession.shared.dataTask(with: request).resume()
        } catch {}
      }
    }
    healthStore.execute(query)
  }
}
`;

  if (newContents.includes("@main\nclass AppDelegate")) {
    newContents = newContents.replace("@main\nclass AppDelegate", `${managerCode}\n@main\nclass AppDelegate`);
  } else if (newContents.includes("class AppDelegate")) {
    newContents = newContents.replace("class AppDelegate", `${managerCode}\nclass AppDelegate`);
  }

  // 3. Insert call in applicationDidBecomeActive
  if (!newContents.includes("HealthKitSleepManager.shared.syncSleepIfAuthorized()")) {
    const becomeActiveBlock = `
  public override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    HealthKitSleepManager.shared.syncSleepIfAuthorized()
  }
`;
    // Insert before end of AppDelegate class or before `// Linking API`
    if (newContents.includes("// Linking API")) {
      newContents = newContents.replace("// Linking API", `${becomeActiveBlock}\n  // Linking API`);
    } else {
      // Find the closing brace of AppDelegate
      const lastBraceIndex = newContents.lastIndexOf("}");
      if (lastBraceIndex !== -1) {
        newContents = newContents.slice(0, lastBraceIndex) + becomeActiveBlock + "\n" + newContents.slice(lastBraceIndex);
      }
    }
  }

  return newContents;
}

function withHealthKitPlugin(config) {
  config = withInfoPlist(config, (config) => {
    config.modResults.NSHealthShareUsageDescription =
      "Memento 需要读取您的健康睡眠与作息数据，以便全自动同步精力与生活节律分析。";
    config.modResults.NSHealthUpdateUsageDescription =
      "Memento 需要访问您的健康数据以保持作息同步。";
    return config;
  });

  config = withEntitlementsPlist(config, (config) => {
    config.modResults["com.apple.developer.healthkit"] = true;
    config.modResults["com.apple.developer.healthkit.access"] = [];
    return config;
  });

  config = withAppDelegate(config, (config) => {
    config.modResults.contents = modifyAppDelegate(config.modResults.contents);
    return config;
  });

  return config;
}

module.exports = createRunOncePlugin(withHealthKitPlugin, PKG_NAME, PKG_VERSION);
