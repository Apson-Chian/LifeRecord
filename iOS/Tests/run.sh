#!/bin/bash
# Run the existing Swift regression programs from any working directory.
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/liferecord-ios-checks.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT

check() {
  local name=$1
  shift
  xcrun swiftc -module-cache-path "$test_directory/ModuleCache" "$@" "Tests/$name.swift" -o "$test_directory/$name"
  "$test_directory/$name"
  echo "PASS: $name"
}

check settings-privacy LifeRecord/Services/RecordInput.swift LifeRecord/Services/AppSettings.swift LifeRecord/Services/AIAuthentication.swift
check ai-authentication LifeRecord/Services/AIAuthentication.swift
check account-connection LifeRecord/Services/AccountConnection.swift
check body-trend LifeRecord/Services/BodyTrend.swift
check daily-chart-scale LifeRecord/Services/DailyChartScale.swift
check favorite-food-storage LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check coach-task-center LifeRecord/Services/CoachBackgroundExecution.swift LifeRecord/Services/CoachTaskCenter.swift
check coach-failure-description LifeRecord/Services/CoachFailureDescription.swift
check coach-photo-storage LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check meal-photo-cache LifeRecord/Services/MealPhotoStore.swift
check coach-meal-actions LifeRecord/Services/RecordInput.swift LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift LifeRecord/Services/CoachActions.swift
check meal-provenance LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check record-insights LifeRecord/Services/BodyTrend.swift LifeRecord/Services/RecordWeek.swift LifeRecord/Services/RecordQuality.swift LifeRecord/Services/GoalFeedback.swift
check reminder-plan LifeRecord/Services/ReminderPlan.swift
check sync-failure-description LifeRecord/Services/SyncFailureDescription.swift
check workout-details LifeRecord/Services/WorkoutDetails.swift
check workout-part-review LifeRecord/Services/WorkoutDetails.swift LifeRecord/Services/WorkoutPartReview.swift
check workout-storage LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check workout-summary LifeRecord/Services/WorkoutSummary.swift
check workout-calendar LifeRecord/Services/WorkoutDetails.swift LifeRecord/Services/WorkoutCalendar.swift

check demo-data LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift LifeRecord/Services/DemoDataService.swift LifeRecord/Services/RecordQuality.swift LifeRecord/Services/GoalFeedback.swift LifeRecord/Services/BodyTrend.swift LifeRecord/Services/RecordWeek.swift

check data-contract LifeRecord/Services/SyncCompatibility.swift LifeRecord/Services/RecordInput.swift LifeRecord/Services/SyncModels.swift LifeRecord/Services/WorkoutDetails.swift

# These exercise the actual synchronization and AI writer with isolated stores.
./Tests/sync-atomicity.sh
python3 Tests/coach-atomicity.py
