#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/liferecord-sync-checks.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
# Append a bridge in a temporary copy to exercise the actual private implementation.
cp "${LIFERECORD_SYNC_TEST_SOURCE:-LifeRecord/Services/SyncService.swift}" "$test_directory/SyncService.swift"
cat >> "$test_directory/SyncService.swift" <<'SWIFT'
@MainActor extension SyncCoordinator {
    func testSnapshot(context: ModelContext, settings: AppSettings) throws -> SyncSnapshot {
        try makeSnapshot(context: context, settings: settings)
    }
    func testApply(_ data: Data, context: ModelContext, settings: AppSettings, failCommit: Bool = false) throws {
        try apply(JSONDecoder().decode(SyncSnapshot.self, from: data), context: context, settings: settings, persist: { transaction in
            if failCommit { throw NSError(domain: "InjectedDiskFull", code: 28) }
            try transaction.save()
        })
    }
}
SWIFT
xcrun swiftc -module-cache-path "$test_directory/cache" \
  LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift \
  LifeRecord/Services/GoalHistory.swift LifeRecord/Services/AppSettings.swift LifeRecord/Services/RecordInput.swift \
  LifeRecord/Services/AIAuthentication.swift LifeRecord/Services/MealPhotoStore.swift \
  LifeRecord/Services/SyncFailureDescription.swift LifeRecord/Services/SyncModels.swift \
  LifeRecord/Services/SyncCompatibility.swift "$test_directory/SyncService.swift" \
  Tests/sync-atomicity.swift -o "$test_directory/check"
"$test_directory/check"
