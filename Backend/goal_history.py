"""Append-only, civil-day goal versions; current profile still uses its LWW stamp."""
import datetime
import hashlib
import json
import math
from zoneinfo import ZoneInfo

FIELDS = ("fitnessGoal", "baselineWeight", "targetWeight", "weeklyWeightTarget", "calorieGoal", "proteinGoal", "carbsGoal", "fatGoal")
BASELINE = "1970-01-01"


def values(profile):
    return {key: profile[key] for key in FIELDS}


def versions(profile):
    result = profile.get("goalHistory", [])
    if not isinstance(result, list):
        raise ValueError("goalHistory must be an array")
    for entry in result:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or not entry["id"]:
            raise ValueError("invalid goal history id")
        day = entry.get("effectiveDate")
        if not isinstance(day, str) or len(day) != 10 or datetime.date.fromisoformat(day).isoformat() != day or day < BASELINE:
            raise ValueError("invalid goal effective date")
        if not isinstance(entry.get("fitnessGoal"), str):
            raise ValueError("invalid historical fitness goal")
        for key in ("updatedAt", *FIELDS[1:]):
            number = entry.get(key)
            if isinstance(number, bool) or not isinstance(number, (int, float)) or not math.isfinite(number):
                raise ValueError("invalid goal history number")
        if not 0 <= entry["updatedAt"] <= 4_102_444_800:
            raise ValueError("invalid goal history timestamp")
    return result


def merged_history(*profiles):
    result = {}
    for profile in profiles:
        for entry in versions(profile):
            day = entry["effectiveDate"]
            previous = result.get(day)
            candidate = (entry["updatedAt"], entry["id"])
            old = (previous["updatedAt"], previous["id"]) if previous else None
            if old is None or (candidate < old if day == BASELINE else candidate > old):
                result[day] = dict(entry)
    return [result[day] for day in sorted(result)]


def merge_profile(previous, incoming, stamp):
    """Keep offline history even when its enclosing profile loses an LWW race."""
    history = merged_history(previous, incoming)
    previous_stamp = previous.get("updatedAt", 0)
    candidate = {**previous, **incoming}
    winner = candidate if stamp >= previous_stamp else dict(previous)
    if previous and all(key in previous and key in candidate for key in FIELDS) and stamp >= previous_stamp and values(previous) != values(candidate):
        zone_name = incoming.get("goalTimeZone", previous.get("goalTimeZone", "UTC"))
        try:
            zone = ZoneInfo(zone_name)
        except (ValueError, TypeError, KeyError):
            raise ValueError("invalid goal timezone") from None
        day = datetime.datetime.fromtimestamp(stamp, zone).date().isoformat()
        if not history:
            history.append(dict(values(previous), id="baseline", effectiveDate=BASELINE, updatedAt=previous_stamp))
        effective = next((v for v in reversed(history) if v["effectiveDate"] <= day), None)
        if effective is None or values(effective) != values(candidate):
            identity = hashlib.sha256(json.dumps([day, stamp, values(candidate)], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            history.append(dict(values(candidate), id="legacy-" + identity, effectiveDate=day, updatedAt=stamp))
        winner["goalTimeZone"] = zone_name
    if history:
        winner["goalHistory"] = merged_history({"goalHistory": history})
    winner["updatedAt"] = max(stamp, previous_stamp)
    return winner
