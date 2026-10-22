"""Civil-day targets with stable-ID corrections, independent of profile LWW."""
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
        if "revisionAt" in entry:
            revision = entry["revisionAt"]
            if isinstance(revision, bool) or not isinstance(revision, (int, float)) or not math.isfinite(revision) or not 0 <= revision <= 4_102_444_800:
                raise ValueError("invalid goal revision timestamp")
        if "revisionID" in entry and (not isinstance(entry["revisionID"],str) or not entry["revisionID"]):
            raise ValueError("invalid goal revision id")
        if not 0 <= entry["updatedAt"] <= 4_102_444_800:
            raise ValueError("invalid goal history timestamp")
    return result


def rank(entry):
    return (max(entry["updatedAt"],entry.get("revisionAt",0)),entry.get("revisionID",entry["id"]),entry["id"])


def winner(items):
    if all(item["effectiveDate"] == BASELINE for item in items):
        revisions = [item for item in items if "revisionAt" in item]
        if revisions:
            return max(revisions,key=rank)
        return min(items,key=lambda item:(item["updatedAt"],item["id"]))
    return max(items,key=rank)


def merged_history(*profiles):
    by_id = {}
    for profile in profiles:
        for entry in versions(profile):
            by_id.setdefault(entry["id"],[]).append(entry)
    return sorted((dict(winner(items)) for items in by_id.values()),key=lambda item:(item["effectiveDate"],rank(item)))


def active(history):
    days = {}
    for entry in merged_history({"goalHistory":history}):
        days.setdefault(entry["effectiveDate"],[]).append(entry)
    return [winner(days[day]) for day in sorted(days)]


def merge_profile(previous, incoming, stamp):
    """Keep offline history even when its enclosing profile loses an LWW race."""
    history = merged_history(previous, incoming)
    previous_stamp = previous.get("updatedAt", 0)
    candidate = {**previous, **incoming}
    current = candidate if stamp >= previous_stamp else dict(previous)
    if previous and all(key in previous and key in candidate for key in FIELDS) and stamp >= previous_stamp and values(previous) != values(candidate):
        zone_name = incoming.get("goalTimeZone", previous.get("goalTimeZone", "UTC"))
        try:
            zone = ZoneInfo(zone_name)
        except (ValueError, TypeError, KeyError):
            raise ValueError("invalid goal timezone") from None
        day = datetime.datetime.fromtimestamp(stamp, zone).date().isoformat()
        if not history:
            history.append(dict(values(previous), id="baseline", effectiveDate=BASELINE, updatedAt=previous_stamp))
        effective = next((v for v in reversed(active(history)) if v["effectiveDate"] <= day), None)
        if effective is None or values(effective) != values(candidate):
            identity = hashlib.sha256(json.dumps([day, stamp, values(candidate)], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            history.append(dict(values(candidate), id="legacy-" + identity, effectiveDate=day, updatedAt=stamp))
        current["goalTimeZone"] = zone_name
    if history:
        current["goalHistory"] = merged_history({"goalHistory": history})
    if any("revisionAt" in entry for entry in history):
        try:
            zone = ZoneInfo(current.get("goalTimeZone","UTC"))
        except (ValueError,TypeError,KeyError):
            raise ValueError("invalid goal timezone") from None
        day = datetime.datetime.now(zone).date().isoformat()
        applicable = active(history)
        selected = next((v for v in reversed(applicable) if v["effectiveDate"]<=day),applicable[0])
        current.update(values(selected))
    current["updatedAt"] = max(stamp, previous_stamp)
    return current
