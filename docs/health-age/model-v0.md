# Health Age Estimate: proposed v0 calculation model

**Experimental design only — not implemented, clinically validated, or ready for a public age claim.** Reviewed 2026-10-16. Model identifier proposed: `health_age_v0_research_1`.

This is an original, bounded lifestyle/fitness index expressed in provisional age units. It is not a biological-age measurement, life-expectancy prediction, diagnosis, or reproduction of WHOOP Age. The exact WHOOP formula is proprietary and is not available as a complete public implementation specification.

Read with the [implemented input contract](input-layer.md) and [existing research notes](https://github.com/namahsea/edge/blob/a8cd7bff611fc07803acf1535e1ded6ed367d332/docs/health-age/research.md). The research notes currently live on `feature/health-age-docs`, so this link pins their source rather than assuming that file exists on the input branch. Their earlier recommendation to defer an age formula remains the release boundary; this document proposes a research model for evaluation, not permission to ship one.

**Evidence supports associations and directions. It does not establish the proposed year coefficients, normalisation anchors, confidence weights, or caps.** Every such number below is an explicitly tunable design parameter. No mortality risk ratio is converted into years, and independent study risk ratios are never multiplied together.

## 1. Formula structure

Use the same 180 completed **local calendar dates ending yesterday**. Retain the dated observations, nulls, genuine zeroes, original source evidence and algorithm versions. Evaluate transformations from those observations; do not replace the input API or discard its time series.

For each eligible factor, calculate a dimensionless burden `s_i`, ordinarily in `[-1, 1]`: positive increases estimated age; negative decreases it. An evidence attenuation `q_i` lies in `[0, 1]`. It is a policy weight, not a probability. The provisional contributions in years are:

```text
c_duration = 1.50 * q_duration * s_duration
c_sri      = 1.50 * q_sri      * s_sri

c_steps    = 1.25 * q_steps    * s_steps
c_zones    = 0.75 * q_zones    * s_zones
c_strength = 0.50 * q_strength * s_strength

c_fitness  = 2.50 * q_selected_fitness * s_selected_fitness
             selected_fitness is eligible VO2 estimate OR eligible nocturnal RHR

D_raw = sum of eligible contributions only

lower = -min(8 years, 0.20 * reported_age, reported_age - 18 years)
upper =  min(8 years, 0.20 * reported_age)
D     = clamp(D_raw, lower, upper)

estimated_health_age = reported_age + D
age_difference       = D
```

A negative difference means a lower experimental estimate than reported chronological age. The proposed population scope is reported ages **20–79**, a conservative design scope, not a claim that all cited studies cover every age in it. Outside scope, or without age, return no numerical Health Age or difference.

The model has a sleep budget of 3 years and a combined activity/fitness budget of 5 years. Contributions are weighted, bounded proxies, **not separate causal years gained or lost**. With current quality caps, actual effects will generally be smaller.

When the final cap applies, multiply every included contribution by `D / D_raw` so the reported contributions sum exactly to the difference. If `D_raw = 0`, leave contributions unchanged. Keep both pre-cap and final contributions for audit; defer rounding until presentation. No UI is proposed here.

For an explicitly synthetic arithmetic example, take reported age 40, eligible 8-hour nights, SRI 80, 9,000 mean steps/day, eligible nocturnal RHR 65, and `q = 0.4` for each included factor. VO2 and strength are missing; zones are unsupported. Contributions are -0.60, -0.30, -0.50 and 0 years respectively: `D_raw = -1.40`, so the unrounded research estimate is 38.60, difference -1.40, status partial and overall confidence low. Missing factors retain null contributions. These are invented example inputs for checking arithmetic, not user data or validated precision; any eventual presentation should favour whole years and expose the missing-factor envelope.

Output contract proposed:

- Reported chronological age, with `freshness: unknown`.
- Nullable estimated Health Age and age difference; `status: insufficient_data | partial | research_estimate`.
- For every factor: observed value/aggregation, dated evidence, inclusion status, exclusion reason, input coverage/counts/confidence, `s_i`, `q_i`, and nullable pre-cap/final contribution.
- Explicit selection/overlap decisions, model/parameter version, window boundaries and overall confidence with reasons.
- A missing-factor sensitivity envelope, described in section 4; never label it a clinical confidence interval.

### Correlation and overlap rules

1. **VO2 and RHR are alternatives in one fitness slot.** The existing submaximal VO2 estimate already uses HR anchors, including RHR. If its evidence gate passes, use it and retain RHR as context with an explicit zero model contribution, `excluded_correlated`. Otherwise an independently observed, eligible RHR may occupy that slot. Never generate either missing measurement from the other.
2. **Steps and zones share one 2-year activity budget.** Their fixed coefficients are a convex blend: `2 * (0.625*q_steps*s_steps + 0.375*q_zones*s_zones)`. Extra activity channels cannot each claim a full activity benefit. Missing channels do not transfer their budget to the remaining channel.
3. **Strength and zone exposure must not both credit the same exercise.** Current daily zone totals cannot reliably subtract strength minutes, especially paused sessions. If zones contribute, strength is context only (`excluded_overlap`). If zones are unavailable/ineligible, independently recorded strength can use its separate small slot. Do not subtract elapsed session bounds from zone totals or invent an overlap allocation.
4. Never add workout zone totals to daily zone totals; workouts are already represented there. Do not add a second workout-count, strain, calories, steps-derived fitness or historical fitness-age factor.
5. All activity, strength and fitness slots together remain within the shared 5-year budget. This controls amplification and direct reuse, **but does not prove statistical independence** between exercise behaviour and fitness. Residual correlation must be evaluated by joint fitting and ablation before release; the proposed weights are not an empirically established overlap correction.

## 2. Factor-by-factor calculation

Definitions: `clip(x) = clamp(x, -1, 1)`; `clip01(x) = clamp(x, 0, 1)`. All aggregations below use eligible observations only. An excluded observation remains visible with its original value and reason.

### Sleep duration

**Evidence:** Prospective studies show a nonlinear association between sleep duration and mortality, with elevated risk at short and long durations. This does not prove that changing a person's sleep duration changes lifespan. [Yin et al., 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5634263/).

For each available main-sleep night, convert recorded TST minutes to hours `h`:

```text
p(h)       = min(1, max(0, (7-h)/2, (h-9)/2))
s_duration = mean(2*p(h) - 1 over eligible nights)
```

A recorded night of 7–9 hours scores -1; 6 or 10 hours scores 0; 5 or fewer, or 11 or more, scores +1. Average the **nightly transformed values**, so alternating short/long nights cannot masquerade as consistently adequate sleep by averaging to 8 hours. Missing nights are omitted; an explicitly measured zero remains zero and reaches the short-sleep cap.

The 7–9-hour band and two-hour ramps are provisional normalisation choices, not fitted thresholds from Yin. Main-night TST excludes naps and is not identical to research measures of total daily or self-reported sleep. False sleep detection remains a material risk: a high coverage percentage cannot establish that the user slept.

Before attenuation, one extra hour in either ramp changes the nightly contribution by at most 1.5 years, divided by the number of eligible nights in the 180-day aggregate. Outside the ramps the marginal effect is zero.

### Sleep consistency

**Evidence:** Higher sleep regularity was associated with lower mortality in a prospective UK Biobank analysis. SRI measures agreement of sleep/wake state across adjacent days; it is not the same construct as bedtime variance. [Windred et al., 2024](https://doi.org/10.1093/sleep/zsad253); original SRI definition: [Phillips et al., 2017](https://www.nature.com/articles/s41598-017-03171-4).

```text
s_sri = clip((70 - existing_180_day_SRI) / 20)
```

SRI 50 or lower scores +1; 70 scores 0; 90 or higher scores -1. Within the ramp, ten extra SRI points lower the pre-cap contribution by `0.75*q_sri` years.

**Reuse the existing SRI result unchanged.** It can validly be negative; do not truncate the input to 0 or rescale it into another index. The anchor 70 and span 20 are policy parameters, not published clinical cutoffs.

OpenStrap's masked, often night-only hypnograms are not continuous 24-hour research actigraphy. Require the existing validity/confidence gate plus adequate supporting comparisons; cap `q_sri` at 0.5 until measurement comparability is demonstrated. Emitted comparisons are support evidence, not a replacement calculation: thin comparisons may still affect the existing headline.

### Daily steps

**Evidence:** The 15-cohort meta-analysis supports lower mortality with higher daily step volume, with diminishing associations and different plateau ranges in older and younger adults. It does not prescribe a universal 10,000-step target. [Paluch et al., 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9289978/).

Let `x` be mean recorded daily steps over eligible days:

```text
P(age)  = 9000 - 2000 * clip01((age - 55) / 10)
R       = P / 2
s_steps = clip( ln((R + 1000)/(x + 1000))
                / ln((P + 1000)/(R + 1000)) )
```

The curve decreases smoothly as steps increase, is neutral at `P/2`, and reaches its lower cap at `P`. The proposed plateau is 9,000 for ages up to 55, smoothly transitioning to 7,000 at 65 and older. The interpolation ages, halfway neutral point and logarithmic offset are tunable engineering choices; the cited research supports only the broad shape and age variation.

For a 40-year-old, 4,500 steps/day is neutral and 9,000 reaches -1. Before clipping, increasing steps from `x1` to `x2` changes age by:

```text
-1.25*q_steps * ln((x2+1000)/(x1+1000))
              / ln((P+1000)/(R+1000))
```

Preserve phone/strap/mixed/counter provenance and actual coverage evidence. A producer labelled `band` alone does not prove native WHOOP 4.0 steps. Genuine observed zero is valid; absent counts or evidence that a count is only partial must not be interpreted as a sedentary whole day.

### Zone 1–3 and Zone 4–5 activity

**Evidence:** Device-measured activity studies support beneficial associations across activity intensities; separate pooled research supports diminishing associations for moderate-to-vigorous activity. Neither validates OpenStrap's HR-zone bins as MET categories. [Ekelund et al., 2019](https://www.bmj.com/content/366/bmj.l4570); [Arem et al., 2015](https://pmc.ncbi.nlm.nih.gov/articles/pmid/25844730/). The moderate/vigorous minute framework below follows [WHO physical-activity guidance](https://www.who.int/news-room/fact-sheets/detail/physical-activity).

**Default v0: both zone contributions are withheld (`unsupported_intensity_mapping`).** Stored Zone 1–3 includes potentially light activity, and observed/Tanaka/Karvonen zone anchors are not interchangeable. Do not label all Zone 1–3 minutes moderate or all Zone 4–5 minutes vigorous merely from their names. Preserve both series and show why neither currently changes age.

The precise reserved calculation, enabled only in a later version after validating a source-specific mapping, is:

```text
M = 7 * mean(validated moderate minutes per adequately observed day)
V = 7 * mean(validated vigorous minutes per the SAME days)
E = M + 2*V
b = clip01(ln(1 + E/75) / ln(1 + 300/75))
s_zones = -b

if E > 0:
  c_zone_1_3 = -0.75*q_zones*b * M/E
  c_zone_4_5 = -0.75*q_zones*b * (2*V)/E
else:
  both contributions = 0, provided both are genuinely observed zero
```

Thus this slot provides a bounded activity credit, not an inactivity penalty: more mapped exposure lowers age until the combined credit saturates at 300 moderate-equivalent minutes/week. The two contributions sum to the single zone contribution. The 75-minute curve offset, 300-minute saturation and credit-only treatment are policy choices, not a fitted longevity model.

A versioned mapping would need disjoint per-bin assignments using the retained original bins, known zone anchors and activity validation. Unmapped light minutes remain context; they are not reclassified or estimated. Without that mapping or adequate HR observation coverage, **none of this reserved calculation runs**. Do not add a mapping or change the BLE parser/input layer in this task.

### Resting heart rate

**Evidence:** Higher resting HR was associated with greater mortality in a prospective-study meta-analysis; protocols varied and substantial heterogeneity was present. This is not evidence that every low pulse is healthy. [Zhang et al., 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC4754196/).

```text
r     = mean(eligible recorded nocturnal RHR in bpm)
s_rhr = clip((r - 65) / 20)
```

45 bpm reaches -1, 65 is neutral, and 85 reaches +1. Within the ramp, ten extra bpm increase the selected fitness contribution by `1.25*q_rhr` years. The anchors are provisional, not diagnostic ranges.

Use only the existing nocturnal RHR measurement; do not substitute daytime HR or a profile default. Nocturnal RHR differs from many published resting-pulse protocols, so `q_rhr <= 0.5`. A mean outside 40–110 bpm is out of scope for this simple mapping and is retained as context, not extrapolated; these are review bounds, not a medical assessment. Medication, rhythm abnormalities, illness and sleep errors can invalidate interpretation. RHR contributes only when the VO2 slot is ineligible.

### VO2 max — existing estimate

**Evidence:** Greater objectively assessed cardiorespiratory fitness is associated with lower mortality. That evidence does not validate this app's submaximal estimator. Reference data show that interpretation varies with age, sex and test modality. [Laukkanen et al., 2022](https://pubmed.ncbi.nlm.nih.gov/35562197/); [Kaminsky et al., 2015, FRIEND](https://pmc.ncbi.nlm.nih.gov/articles/PMC4919021/).

```text
v     = median(eligible stored estimates within the 180-day window)
s_vo2 = clip((35 - v) / 15)    // units: mL/kg/min
```

20 reaches +1, 35 is neutral, and 50 reaches -1. Within the ramp, five extra mL/kg/min lower the selected fitness contribution by `(2.5/3)*q_vo2` years.

This deliberately differs from the input summary's latest value: the model reads all dated observations, retains that latest value for audit, and explicitly labels its own median aggregation. Require at least three distinct session dates across at least two of the six 30-date blocks, with the latest session within the final 30 dates. Use session-start dates, not an invented estimate timestamp. Do not recompute VO2 or carry an old estimate forward into missing dates. Values outside 10–90 are out of scope for this mapping, not automatically invalid measurements.

**35 and 15 are uncalibrated centring/scaling parameters, not a normal VO2 value or biological-age equation.** The present input contract lacks sex-specific reference selection, and this common anchor can introduce substantial bias. Retain it only for research simulation; before a public estimate, validate/replace it with appropriate reference modelling or disable this factor. Do not infer missing sex, body size, laboratory fitness or demographic norms from the available data. Cap `q_vo2` at 0.5; label it `existing_submaximal_estimate` in every result.

### Strength activity

**Evidence:** Muscle-strengthening activity was associated with lower mortality in cohort studies, with the clearest reductions around modest weekly volumes and uncertainty at higher doses. This does not measure an individual's functional strength or justify unlimited credit. [Momma et al., 2022](https://pubmed.ncbi.nlm.nih.gov/35228201/).

```text
T_recorded = sum(actual known, eligible, non-overlapping session minutes)
L          = 7*T_recorded / 180
s_strength = -clip01(L / 60)
```

Here `L` is **recorded exposure per calendar week over the window**, a lower bound on total performed activity, not an estimated habitual weekly volume. It is not the mean over logged days. No logged sessions means unknown, not zero exercise.

Each additional ten recorded minutes/week lowers age by `q_strength/12` years until the 60-minute cap; no high-volume penalty or extra credit is proposed. Unknown durations remain null: timed observations can support a clearly labelled lower-bound contribution without claiming that the input's total `minutes` is known. Sets/reps do not imply time.

Require at least three sessions with known duration on distinct dates across two blocks, latest within 60 dates. Deduplicate session IDs; conservatively exclude sessions with ambiguous overlapping bounds rather than allocating paused time. Keep excluded sets/sessions as evidence. Without enough timed records, return missing contribution. Cap `q_strength` at 0.5 because logging completeness is unknown. If zones contribute, suppress strength under the overlap rule.

### Lean mass percentage

**Evidence:** Lean mass is not interchangeable with functional strength; a Health ABC cohort found strength more informative than muscle size for mortality in its older population. This cannot establish a universal healthy lean-mass percentage. [Newman et al., 2006](https://pubmed.ncbi.nlm.nih.gov/16456196/).

Current input is **unavailable**, so its contribution is null and it has no model weight. Never derive it from BMI, weight, impedance, body fat or strength records.

Even if a directly sourced lean-mass percentage becomes available, initial v0 retains it as context with `excluded_unvalidated_relationship` and no age effect. A nonzero coefficient needs a separate, method/demographic-appropriate evidence review and versioned model change. Do not assume that a larger percentage always means better health or add another muscle benefit alongside strength.

## 3. Bounds, eligibility and attenuation

These are proposed safeguards for research, not evidence-derived statistical thresholds.

| Rule | Proposed default |
| --- | --- |
| Daily factor support | At least 90 eligible dates; at least 10 in each of five of the six consecutive 30-date blocks; at least 14 in the final block |
| SRI extra support | Existing SRI non-null/valid; daily support above; at least 30 emitted adjacent-night comparisons meeting the existing reporting floor |
| Daily evidence attenuation | `q_i = min(eligible_dates/180, input_label_weight, method_cap)` |
| Input label weights | Low 0.4; medium 0.7; high 1.0; not calibrated probabilities |
| SRI / nocturnal RHR / VO2 / strength / future mapped zones | Method cap 0.5 |
| VO2 attenuation | `min(distinct_dates/6, input_label_weight, 0.5)`, after its sample/recency gate |
| Strength attenuation | `min(distinct_known_duration_dates/12, input_label_weight, 0.5)`, after its gate |
| Absolute sleep contribution | At most 3 years total; duration and SRI at most 1.5 each before attenuation |
| Absolute activity/fitness contribution | At most 5 years total; steps 1.25, zones 0.75, strength 0.5, selected fitness 2.5 before attenuation |
| Overall difference | At most 8 years and 20% of reported age; estimated age floor 18 |

Use actual source evidence to exclude known invalid/partial observations; never turn rejected observations into zero. Unknown measurement quality stays unknown and retains the conservative low-label weight. An input's low label alone is not a missing-value gate: source quality may be unknown even with many real observations. The separate upstream labels remain unchanged.

For daily summaries, recalculate eligible counts after exclusions. Zone eligibility would additionally require a validated source/method mapping and known observed HR coverage of at least 80% of that actual local day's elapsed duration. Unknown coverage cannot pass. Daily availability alone cannot certify all-day observation. SRI uses its existing computation and confidence; do not recompute it on a model-selected subset.

No generic percentile winsorisation is proposed. Preserve genuine extremes and cap their model effect; retain unusable/out-of-scope values as context. Chronological age is the stored integer read now, with unknown freshness: do not fabricate DOB, observation date or birthdays.

## 4. Missing-data behavior

A missing measurement or insufficient evidence produces a **null contribution with an explicit reason**. A measured neutral score produces a real numeric zero. An available metric deliberately excluded by correlation/overlap has numeric zero with its exclusion status. These three states must remain distinguishable.

Sum eligible contributions without filling missing factor values and **without renormalising weights**. Omitting a slot from the arithmetic is not a claim that its true physiological effect is zero. A partial model estimates only the supported portion of this index; it cannot be compared as a full-profile age.

Require reported age in scope, eligible sleep duration, and at least one eligible steps/zone/selected-fitness factor for a numerical research result. Otherwise return `insufficient_data`, null age/difference, and available factor evidence. Strength alone cannot supply the activity/fitness requirement. This gate is tunable.

- `partial`: numerical gate passes, but one or more non-optional required slots are unsupported: duration, SRI, steps, zones, or the selected fitness slot.
- `research_estimate`: those slots pass. Optional strength/lean-mass absence does not block it; this status still means experimental.
- With current intensity-mapping constraints, a numerical v0 result will normally be **partial**.

Alongside a partial result, calculate a **sensitivity envelope** by allowing unsupported daily/fitness slots to range across their full reserved budgets, then applying the same total/age bounds. Respect mutually exclusive VO2/RHR and zone/strength branches; evaluate feasible branch choices rather than adding incompatible effects. Missing strength spans only `[-0.5, 0]`; disabled lean mass spans `[0,0]`.

For a structurally disabled factor, distinguish its current deterministic effect (none) from a hypothetical contribution if appropriately validated measurements/mapping became available. Label that latter range as a missing-evidence scenario; enabling it would require a new mapping/model version. This is a range of possible outputs under those stated assumptions, not imputed observations, a prediction interval, or a promise that biological age lies inside it. Switching source/gate eligibility can change the model even if physiology has not changed; report the changed evidence mask and compare trends only with matching masks/versions.

## 5. Confidence calculation

Separate data support, measurement validity, age-anchor freshness and model validation.

```text
Q_data = (
  1.5*q_duration + 1.5*q_sri
  + 1.25*q_steps + 0.75*q_zones
  + 0.5*q_strength + 2.5*q_selected_fitness
) / 8

data_support_label:
  low    if Q_data < 0.50
  medium if 0.50 <= Q_data < 0.80
  high   otherwise

overall_confidence = minimum(
  data_support_label,
  age_anchor_confidence,
  model_validation_confidence
)
```

An absent, ineligible or excluded slot supplies no supported weight to this **support calculation**, while retaining its null/exclusion status in the output. The denominator is fixed; optional lean mass is not included. Two fitness measurements do not earn two confidence credits. Strength suppressed by overlap does not transfer its confidence weight elsewhere. This intentionally conservative index is not a coverage percentage.

Proposed `age_anchor_confidence = low` when an in-scope age is present but freshness is unknown, matching the input's low profile confidence. Missing age makes the numerical result unavailable. Do not upgrade that input label or treat the read time as the age's observation date.

**For the entire unvalidated v0, `model_validation_confidence = low`, so overall confidence is always low.** More dates can improve data support but cannot certify the model. Any future medium/high model-validation label requires a documented independent validation protocol, not just agreement with WHOOP Age. Do not report a calibrated confidence percentage or statistical age interval.

## 6. Fixed assumptions versus tunable parameters

“Fixed” here means explicit constraints for this model family, revisable only with a documented evidence/design review.

| Fixed research-informed or integrity assumption | Basis |
| --- | --- |
| Sleep duration is nonlinear; more sleep is not always assigned more benefit | Yin; observational, not causal |
| Greater regularity is directionally favourable when the measurement is valid | Windred; Phillips |
| Step-volume benefits saturate and vary with age | Paluch |
| Activity/fitness benefits cannot be extrapolated indefinitely | Ekelund; Arem; Laukkanen |
| Higher RHR is directionally adverse within an applicable protocol/range | Zhang |
| Recorded strengthening can support bounded credit; time is not functional strength | Momma; Newman |
| A wearable VO2 estimate is not a measured laboratory value | Existing method; FRIEND applicability limit |
| Unknown is not zero; preserve sources and dates; no inferred lean mass | Input contract |
| Shared source signals and overlapping exercise cannot receive independent full credits | Input provenance and correlation rules |

**All numerical settings are tunable**, including the example defaults:

| Parameter family | Initial proposal |
| --- | --- |
| Year budgets | Sleep 3; activity/fitness 5; slot coefficients 1.5/1.5/1.25/0.75/0.5/2.5 |
| Sleep mapping | Band 7–9 hours; two-hour ramps |
| SRI mapping | Anchor 70; span 20 |
| Step mapping | Plateau 9,000 to 7,000; transition ages 55–65; neutral half plateau; log offset 1,000 |
| Zone mapping | Disabled by default; no assumed bin conversion; conditional vigorous multiplier 2; curve offset 75; saturation 300 |
| RHR mapping | Anchor 65 bpm; span 20; mapping scope 40–110 |
| VO2 mapping | Research anchor 35; span 15; mapping scope 10–90; median aggregation |
| Strength mapping | Recorded exposure credit saturates at 60 minutes/week |
| Quality and eligibility | All date/sample/block/recency thresholds, label weights and method caps in section 3 |
| Output gates/caps | Ages 20–79; numerical evidence gate; 8 years; 20% of age; floor 18 |
| Confidence | Fixed denominator 8; support bands 0.50/0.80; model label low until validation |

Version the formula, input algorithm provenance, parameter set and mapping registry independently. Keep an immutable evaluation manifest, including observations used/excluded and selected channels. Tune a small set of budgets/scales first; do not fit dozens of knobs to a handful of screenshots. Never tune caps solely to make a particular participant's age match.

Future computation belongs in the analytics sibling under repository architecture rules; Edge should remain an input adapter/orchestrator. This document requests no analytics dependency change or implementation.

## 7. Known limitations

- This is an uncalibrated age-shaped index. No cited study establishes the combined model, proposed year units, neutral anchors or independent contribution years.
- Observational associations can reflect confounding, reverse causation, disease and selection effects. Cohort mortality, remaining lifespan, biological age and “Health Age” are different outcomes.
- Masked SRI, detected main sleep, phone steps, relative HR zones and submaximal VO2 estimates differ from research instruments. A consistently wrong sleep detector can create a consistently wrong input.
- The VO2 research anchor lacks demographic normalisation. Age scope and smooth age-dependent step targets do not correct sex, disability, medication, socioeconomic, ethnicity or body-size bias.
- Caps and shared budgets limit amplification; they do not estimate conditional causal effects or eliminate residual statistical dependence. Source switching, algorithm-version changes and changed missingness can mimic improvement.
- Sparse VO2 and incomplete strength logs are subject to selection bias. Their calendar coverage is not interchangeable with daily sleep/step coverage.
- Strength benefits are one-sided, zones are disabled, lean mass is absent, and some normalisation anchors reward values relative to engineering references rather than population norms. The estimate is not centred to match any population's actual age.
- 180 dates are an observation window, not proof of habitual long-term health. No smoothing, carry-forward or invented “pace of ageing” is proposed.
- Unknown chronological-age freshness remains unresolved. Low confidence does not make an unreliable numerical result clinically meaningful.

## 8. Validation strategy

### Measurement and model checks before any public output

1. Verify input sources with consenting real users: sleep diaries (including awake nights), step counter/phone carry coverage, training logs, HR-zone definitions and where possible resting-HR protocol checks and supervised/laboratory fitness assessment. Investigate false sleep detection independently.
2. Specify future focused tests for null versus zero, date/DST boundaries, exact unchanged SRI reuse, sample gates, monotonic curves, clipping, contribution sums, mutually exclusive channels and parameter-version reproducibility. **No tests are run for this documentation task.**
3. Use retained time series for participant-level missingness stress tests: drop contiguous periods and activity-heavy days, vary phone wear, remove sparse VO2 sessions and perturb source algorithms. Measure shifts, status changes, saturation and abstention rates.
4. Examine step/zone/strength/VO2/RHR correlations, shared inputs and residual associations. Compare one-channel and grouped models; verify that duplicated exercise exposure does not expand a budget. Include ablations and source-switch checks. Revise/disable factors if the overlap design remains unstable.
5. Assess robustness to threshold crossings, age transitions, a single extreme night/session, and adding one new day. Proposed engineering target: no isolated observation creates a >1-year change in an otherwise stable supported profile. Gate/selection switches are separately tested; withhold trend comparisons if they breach that target. This target is tunable, not a published medical criterion.

### Paired comparisons with real WHOOP users

Recruit a consented pilot for feasibility, then size an evaluation cohort for the desired precision rather than claiming that a small convenience sample validates the model. Include different ages, sexes, fitness levels, phone-carry patterns and missing-data profiles. User exports/comparison records must stay local unless a separate, explicitly consented study authorises sharing; private workouts require the same consent.

Record paired dates, reported age, OpenStrap evidence/method versions and input mask, and the user's voluntarily supplied WHOOP Age with device/app version where available. Align observation windows as far as documented; record unknown differences. Compare the **same participants over time**, but split training/validation/test sets by participant, not by overlapping daily snapshots.

WHOOP Age is an external product reference, **not physiological ground truth or an algorithm specification**. Report mean error/bias, MAE, agreement plots/limits, rank/trend agreement, abstention/coverage, saturation and subgroup errors. Keep uncertainty clustered by participant. An age-only baseline and simple one-factor baselines help detect age leakage and needless complexity.

For exploratory compatibility tuning, fit constrained monotone scales/group budgets on training participants only, regularise toward the documented defaults and lock parameters before evaluating held-out users. Preserve the evidence directions, caps, missingness and overlap rules; report any trade-off against independent measurement validity. Do not fit hidden WHOOP coefficients, copy its factor-impact values or claim reproduction.

A comparison study can establish usability and product agreement. Higher model-validation confidence or a public age interpretation needs independent reference assessments and longitudinal outcome validation, an appropriate demographic reference model, prespecified error/robustness criteria, and external evaluation. If these fail, retain transparent factor summaries and no numerical age output.
