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

check settings-privacy LifeRecord/Services/AppSettings.swift LifeRecord/Services/AIAuthentication.swift
check ai-authentication LifeRecord/Services/AIAuthentication.swift
check body-trend LifeRecord/Services/BodyTrend.swift
check favorite-food-storage LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check meal-photo-cache LifeRecord/Services/MealPhotoStore.swift
check coach-meal-actions LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift LifeRecord/Services/CoachActions.swift
check meal-provenance LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check record-insights LifeRecord/Services/BodyTrend.swift LifeRecord/Services/RecordWeek.swift LifeRecord/Services/RecordQuality.swift LifeRecord/Services/GoalFeedback.swift
check reminder-plan LifeRecord/Services/ReminderPlan.swift
check sync-failure-description LifeRecord/Services/SyncFailureDescription.swift
check workout-details LifeRecord/Services/WorkoutDetails.swift
check workout-part-review LifeRecord/Services/WorkoutDetails.swift LifeRecord/Services/WorkoutPartReview.swift
check workout-storage LifeRecord/Services/WorkoutDetails.swift LifeRecord/Models/HealthModels.swift
check workout-summary LifeRecord/Services/WorkoutSummary.swift
