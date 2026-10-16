# Experimental Health Age input layer

This is a local, read-only research input API. It computes no Health Age,
fitness age, age difference, risk score or proprietary WHOOP result. It has no
UI, sensor subscriptions, new permission requests, uploads or persisted scores.

## Calling it

Construct `LocalHealthAgeInputRepository(getProfileMap: ...)` with the existing
stored profile getter, then call `HealthAgeInputService(repository).load(asOf: ...)`.
Nothing is wired into AppState or automatic derivation. The default clock is
`DateTime.now`; tests can inject it. Input assembly, including existing SRI,
runs in an isolate.

## Window

180 **completed local calendar days**, from local midnight 180 calendar dates
before today, inclusive, to today's local midnight, exclusive. Today and future
records are excluded. DST days are not assumed to last 86,400 seconds.

## Observations and summaries

Every metric returns value, unit, dated observations, daysAvailable,
samplesAvailable, coveragePercentage, coverageBasis, low/medium/high confidence,
source, summaryMethod, missingReason, notes and details.

Daily observations have one entry per calendar date (180), with null values and
a missing reason for gaps. The summary never substitutes a zero for those gaps.
Daily dates describe the producer's day assignment, not a fabricated exact
measurement timestamp. Dated observations preserve individual values, quality,
algorithm versions, methods, device family and available producer evidence.
All returned observations and nested evidence are immutable.

| Input | Summary | Underlying observations |
| --- | --- | --- |
| Chronological age | Stored reported/imported integer age | One undated profile observation when present; DOB, source origin and freshness remain unknown |
| Sleep duration | Mean available main-sleep minutes | Per-night TST and original accounting envelope, with sleep source; naps are not added |
| Sleep consistency | Existing Phillips SRI, including its original confidence gate | Dated hypnograms, original hypnogram evidence and emitted adjacent-night comparisons |
| Daily steps | Mean available stored daily count | Per-date counts and step-source evidence; explicit recorded zero is preserved |
| Zone 1–3 minutes | Mean available daily sum of Z1, Z2, Z3 | Per-date group value, original five bins, zone anchors and available HR coverage |
| Zone 4–5 minutes | Mean available daily sum of Z4, Z5 | Same evidence; any missing required bin leaves that group missing |
| Resting heart rate | Mean available stored nocturnal RHR | Per-night value and clinical envelope; absent envelope is never rescued by another scalar |
| VO2 max | Latest existing stored session estimate in the window | Every positive finite stored estimate, session ID/type/bounds and explicit estimate label |
| Strength activity | Recorded sessions, sets, minutes and known-duration counts | Every eligible completed strength session, recorded duration and individual sets (including null load/reps) |
| Lean mass percentage | Unavailable | No observations; weight, BMI, impedance and body fat are not converted |

VO2 timestamps name **session start**, not the exact instant the estimate was
measured: that instant was never stored. The metric is an existing submaximal
estimate, not a laboratory measurement, and is never recomputed here.

SRI reuses the original gap-aware calculation. Its former 90-row caller is
unchanged; this input layer supplies only the requested 180 calendar dates.
All contributing night hypnograms are retained, including thin comparisons
that affect the headline but do not clear the existing pair-reporting floor.
No asleep/wake states are invented outside recorded segments.

Strength minutes remain null if any included session lacks a recorded duration;
knownMinutes separately reports only recorded minutes (null if none). Sets do
not imply minutes. No logged strength session means unknown activity, not zero.
Unfinished, invalid, orphaned and boundary-crossing sessions are excluded.
Paused durations are not prorated across boundaries. Private sessions remain
local inputs and retain their flag; this API has no sharing or export operation.

## Counts, coverage and confidence

- Daily samplesAvailable counts non-null daily observations. daysAvailable is
  the number of distinct dates with valid observations.
- SRI counts dated nights with usable hypnograms, not emitted pair rows. A
  single night can be available while the SRI summary remains missing.
- VO2 samples count eligible sessions; strength samples count eligible sessions
  with explicit strength type or linked recorded sets. Sets remain separately
  inspectable. These sparse observations are never carried forward.
- Calendar coverage is `daysAvailable / 180 * 100`, never days since first wear.
  This is availability, not a claim of complete all-day sensor coverage.
  Strength uses the explicit `recorded_activity_days` basis.
- Profile age uses `profile_field`: 100% if the field is present, 0% if missing,
  one sample and zero observed calendar days. Its freshness remains unknown.
- Initial availability bands: below 50% low, 50–79% medium, at least 80% high.
  Missing summaries are low. Existing source confidence below 0.5 caps at low,
  below 0.8 caps at medium; unknown origin/quality or partial results cap at low.
  Mixed algorithm versions/source families cap at medium. Estimates never
  exceed medium. Existing SRI confidence also caps its result.
- These are conservative **input availability/quality** labels, not validated
  probabilities of measurement correctness or confidence in an age model.
  In particular, sensor coverage cannot prove a detected sleep was real.

## Storage and eligibility

Bounded projected reads use LocalDb's existing served-version join. One latest
served result per day is selected; newer unserved rows are not used. Per-day
method/source stamps are attached only when their version matches the served
result. Existing unavailable/unsupported estimated daily method gates and
session sensor-off score masking are respected. Null provenance stays unknown.

The input layer needs no raw BLE retention, database migration, dependency
change, scoring update or kAlgoVersion bump. Malformed payloads and invalid
numeric values stay missing. Stored values from older algorithm versions remain
labelled; this module does not claim that their methods are interchangeable.

## Focused validation

Only the three new health_age input test files and directly affected
crossday_pipeline_test are required. Tests exercise calendar/DST boundaries,
version/source eligibility, immutable dated observations, missing and zero
semantics, no database writes, existing VO2 labels, strength sets, and exact
reuse of the existing SRI envelope. No full test suite is requested.
