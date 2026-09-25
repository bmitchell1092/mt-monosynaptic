# Katniss MT — Neuropixels units

Spiking data from area MT in a common marmoset (*Callithrix jacchus*), Neuropixels 1.0, acute,
384 sites, 30 kHz. One `.mat` file per session, ~100 min each. Every file has identical fields.

This page defines the terms and the datasets. Nothing here needs installing.

---

## The sessions

| | 251120 | 251121 |
|---|---|---|
| units (base set) | 301 | 217 |
| **`passQC`** | **176** | **112** |
| duration | 100.2 min | 95.8 min |
| `restPre` (screen ON) | 0.6 min | 10.1 min |
| `task` | 69.6 min | 55.2 min |
| `restPost` (screen OFF) | 30.0 min | 30.6 min |
| task blocks | bistable, flash, bistable control | **+ RF mapping** |
| laminar `botChan`–`topChan` (`sink_ch`) | 117–292 (212) | 111–280 (208) |

Separate probe insertions, so **unit `id`s are not comparable across sessions** — `id` 191 in one
file is a different neuron from `id` 191 in the other. Take laminar bounds from each session's
own `session.laminar`.

```matlab
units = loadUnits('Session', '251121', 'OnlyQC', true, 'Epoch', 'task');
```

`loadUnits` options: `'Session'`, `'OnlyQC'`, `'Epoch'` (`'all'` | `'restPre'` | `'task'` |
`'restPost'` | `[t0 t1]`), `'MinSpikes'`, `'MaxPctRefr'`, `'File'`. With one file in `data/` it
loads with no arguments; with several, `'Session'` is required and the error lists them.

---

## `units` — 1 × nUnits struct array

| Field | Meaning |
|---|---|
| `id` | cluster id as Kilosort numbered it, 0-based. Not comparable across sessions |
| `spikes` | `[n × 1]` spike times in **seconds**, absolute from the start of the recording |
| `nSpikes`, `firingRate` | count and spikes/s **in the epoch you loaded** |
| `channel` | probe channel with the largest waveform, 0-based |
| `depth_um` | depth along the probe, µm |
| `x_um`, `y_um` | position of that channel on the probe, µm |
| `pctRefr` | measured % of ISIs under 1.5 ms, **for the epoch you loaded**. See below |
| `ksLabel` | Kilosort's **automatic** call, `'good'` or `'mua'`. Not a human judgement |
| `contamPct` | Kilosort's model contamination estimate. **Not bounded at 100**. See below |
| `passQC` | **the recommended unit selection.** Same in every epoch. See below |
| `waveform` | `[52 × 1]` mean waveform on the peak channel |

Spike times stay **absolute** when you restrict to an epoch, so they always line up with
`events.times_s` — no conversion, ever.

## `session`

`id`, `subject`, `date`, `area`, `probe`, `fs`, `duration_s`, `nUnits`, `nClustersSorted`,
`epochs`, `epochNotes`, `curation`, `exported`, plus:

- **`session.laminar`** — `botChan`, `topChan` (channels strictly between the two are inside
  cortex), `sink_ch` (CSD-estimated input layer). Every unit in the file is already inside the
  bounds. The granular layer was placed by hand, so layer assignment is approximate.
- **`session.qcCriteria`** — the definition behind `passQC`: `expression`, `maxPctRefr` (2),
  `minSpikes` (1000), `requireInCortex`, `excludeDuplicates`, `epochInvariant`, `computedOver`,
  `nPass`, `note`.
- **`session.epochs`** — `restPre`, `task`, `restPost`, each `[t0 t1]` in seconds.

## `events`

`times_s` and `codes` (matched vectors), `codeMeaning`, `codeCounts`, `note`. Event times are on
the **same clock as the spikes**.

| Code | Meaning | 251120 | 251121 |
|---|---|---|---|
| 9 | trial start | 1341 | 993 |
| 10 | fixation acquired | 1341 | 993 |
| **11** | **stimulus on** — the alignment event | **487** | **1324** |
| 12 | stimulus off | 275 | 1078 |
| 18 | trial end / ITI | 1342 | 994 |

Other codes occur and are not established here (3/20/21/25 on 251120; also 22/26/27 on 251121).
**`events.codeCounts` gives `[code, count]` for every code in the file you loaded.**

---

## The three terms worth defining

### `passQC` — the recommended unit selection

`pctRefr < 2` **and** `nSpikes > 1000` **and** not a sorting duplicate **and** inside the
laminar bounds, i.e. the standard connectivity criteria. **176 units on 251120, 112 on 251121.**
`'OnlyQC', true` applies it.

The base set behind it (301 / 217) is the clusters a manual waveform screen accepted. That
screen looked at waveform shape and depth, **not** at refractory periods — which is why 91 of
251120's 301 still violate 2%, and why `passQC` exists.

**`passQC` is identical in every epoch, on purpose.** It is computed once over the whole
recording and never recomputed on a sub-window, because isolation is a property of the unit
rather than of the window you analyse: the 100-minute `pctRefr` uses every spike and is the best
estimate available, while a 30-minute estimate of the same quantity is *noisier*, not stricter.
It also means `uTask(k)` and `uRest(k)` are guaranteed to be the same neuron, so task-versus-rest
is a clean within-neuron comparison. If you need *enough spikes in one window* to compute
something, that is a power criterion — use `'MinSpikes'` after choosing the epoch.

### `pctRefr` — measured refractory violations

```
pctRefr = 100 × (ISIs shorter than 1.5 ms) / (all ISIs)
```

A plain count, no model. A neuron is absolutely refractory for ~1–2 ms, so a shorter interval
cannot have come from one neuron: either two neurons are in the cluster, or one spike was counted
twice. Both are what manufacture a fake short-latency CCG peak, which is why this is the metric
to threshold on. **0% ideal, under 1% clean, 2% and above suspect.** Recomputed per epoch.

⚠️ **Not chance-corrected, so it is biased against fast units.** A Poisson train at rate *r*
shows `1 − exp(−r × 0.0015)` even when perfectly isolated — 1.49% at 10 Hz, **2.96% at 20 Hz**,
5.82% at 40 Hz. A flawless 20 Hz neuron fails a 2% cut on rate alone. If a result turns on the
fastest units, compare each unit against its own chance level rather than a fixed threshold.

### `contamPct` — Kilosort's model estimate

Kilosort's own number, passed through. Estimates the fraction of spikes in the cluster that do
not belong to it, from the autocorrelogram's density at short lags against its long-lag
asymptote. ⚠️ **Not a bounded percentage** — it ranges 0 to 1786 here; above 100 means no
refractory dip at all. Correlates with `pctRefr` (Spearman ρ = 0.83) but is not interchangeable.
`ksLabel` is roughly `contamPct < 20`.

**Use `pctRefr` for connectivity work** — it is a measurement, not a model output, so a threshold
on it means something statable. Keep `contamPct` as a second opinion.

---

## Four things that will produce wrong answers

**1. No cluster has ever been merged or split.** The boundaries are Kilosort 4's exactly as the
sorter drew them — `cluster_group.tsv` marks everything "good" and the one manual Phy pass was
fully reverted. So one neuron split across two clusters is still split, and such a pair shows an
enormous peak at **~0 ms lag**. A chemical synapse cannot act at 0 ms: read a strong near-zero
peak as a **merge candidate, not a connection**. (`passQC` removes only the most blatant cases,
where two clusters were near-copies.)

**2. Code 11 is not one per trial, and the ratio differs by session.** 251120 has 487 stimulus
events for 1341 trial starts (0.36 per trial — fixation breaks). **251121 has 1324 for 993 —
more stimuli than trials**, because its RF-mapping block fires code 11 once per stimulus. Never
assume one stimulus per trial, and never pool code-11 events across blocks: on 251121 they mix RF
probes with bistable motion, so a PSTH over all of them is not comparable to 251120's.

**3. `restPre` and `restPost` are different conditions** — screen ON versus screen OFF. Do not
pool them. Durations vary a lot by session; 251120 has effectively no `restPre` (0.6 min). Asking
for an empty window raises an error rather than returning nothing.

**4. `unitIdx` is not `id`.** `plotEvokedSpikes(units, events, k)` takes an **index into
`units`**, and filtering changes indices. Use `k = find([units.id] == 191)`.

---

## Getting the data

The `.mat` files are not in version control. Download them from
[Dropbox](https://www.dropbox.com/scl/fo/xhiozlkeaml3a1p8uwaqu/AEP9oIbPFCQ5XFAoxmJzUUM?rlkey=ei9s6i03sidmtl6a7qfvk9u7d&st=wlg7rj1w&dl=0)
into `data/`:

```
mt-monosynaptic/
└── data/
    ├── katniss_251120_units.mat
    └── katniss_251121_units.mat
```

**`plotEvokedSpikes(units, events, unitIdx)`** is the only other function here — raster and PSTH
for one unit, aligned to `'AlignCode'` (default 11) over `'Window'` (default `[-200 500]` ms).
Returns `[psth, t_ms, raster]`, and takes `'Plot', false` to run headless. Needs the `task`
epoch; the rest blocks have no stimuli to align to.

## Provenance

Kilosort 4 on the raw Neuropixels recording, then a manual waveform screen. The full pipeline,
and the ECoG recorded simultaneously with these spikes, live in the **`mt-ecog-npx`** repository
(`ingest/kilosort/exportUnits.m` wrote these files). Ask if you need any of it.
