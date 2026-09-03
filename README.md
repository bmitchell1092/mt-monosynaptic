# Katniss MT — Neuropixels units

Spiking data from area MT in a common marmoset (Callithrix jacchus), recorded with a
Neuropixels 1.0 probe. One session, 100 minutes, 702 units.

Everything is in a single file. There is no pipeline to run and no sorting to clean up —
the spike sorter's clusters have already been resolved into units.

---

## Getting the data

The code is in this repo. The data file is **not** — at 235 MB it exceeds GitHub's 100 MB
per-file limit, so it is hosted separately.

1. Download **`katniss_251120_units.mat`**:
   `<PASTE DROPBOX LINK HERE>`
2. Put it in the `data/` folder of your clone:

```
mt-monosynaptic/
└── data/
    └── katniss_251120_units.mat
```

That is the entire setup. `loadUnits` looks there by default; pass `'File'` to point it
somewhere else.

---

## Quickstart

```matlab
[units, session, events] = loadUnits('Epoch', 'task');

% the most active unit, aligned to stimulus onset
[~, ord] = sort([units.firingRate], 'descend');
plotEvokedSpikes(units, events, ord(1));
```

Needs MATLAB. No toolboxes, no dependencies.

---

## The recording

| | |
|---|---|
| Subject | `katniss`, common marmoset |
| Area | MT |
| Probe | Neuropixels 1.0, acute, 384 sites |
| Sampling rate | 30 kHz |
| Duration | 6012.7 s (100.2 min), continuous |
| Units | 702 |
| Spikes | 56,188,186 |

### Two epochs

The recording has a task block followed by a task-free block, and they are worth analysing
separately. `session.epochs` carries both windows.

| Epoch | Window (s) | Duration | What happened |
|---|---|---|---|
| `task` | 0 – 4211.4 | 70.2 min | visual stimuli: bistable motion, bistable control, screen flashes |
| `spontaneous` | 4211.4 – 6012.7 | **30.0 min** | screen off, no task, animal simply sitting |

Same units in both — the unit set was determined once over the whole recording, so anything
you compute in one epoch is directly comparable to the other.

```matlab
uTask  = loadUnits('Epoch', 'task');
uSpont = loadUnits('Epoch', 'spontaneous');
```

---

## Data structures

### `units` — 1 × 702 struct array

| Field | Type | Meaning |
|---|---|---|
| `id` | scalar | unit identifier |
| `spikes` | `[n × 1]` | **spike times in SECONDS**, from the start of the recording |
| `nSpikes` | scalar | number of spikes |
| `firingRate` | scalar | spikes/s over the epoch |
| `channel` | scalar | probe channel where the unit's waveform is largest (0-based) |
| `depth_um` | scalar | depth along the probe, µm |
| `x_um`, `y_um` | scalar | position of that channel on the probe, µm |
| `pctRefr` | scalar | % of inter-spike intervals shorter than 1.5 ms — a contamination measure. A clean single unit is under ~1%. |
| `ksLabel` | char | the sorter's own call: `'good'` or `'mua'` |
| `contamPct` | scalar | the sorter's contamination estimate |
| `mergedFrom` | `[k × 1]` | original cluster ids combined into this unit. One entry = never merged. |
| `waveform` | `[52 × 1]` | mean spike waveform on the peak channel |

Spike times are **absolute** and stay absolute when you restrict to an epoch, so they always
line up with `events.times_s`.

### `session`

`id`, `subject`, `date`, `area`, `probe`, `fs`, `duration_s`, `nUnits`, `epochs`,
`epochNotes`, `curation` (what was done to the clusters), `exported`, and:

`session.laminar` — where cortex is along the probe:

| Field | Value | Meaning |
|---|---|---|
| `botChan` | 117 | channels strictly between these two are inside cortex |
| `topChan` | 292 | |
| `sink_ch` | 212 | CSD-estimated input layer |

```matlab
inCortex = [units.channel] > session.laminar.botChan ...
         & [units.channel] < session.laminar.topChan;
```

The granular layer was placed by hand on a CSD from Nick Dotson, so treat layer assignment as approximate here.

### `events` — behavioural events

| Field | Meaning |
|---|---|
| `times_s` | `[5190 × 1]` event times, in seconds |
| `codes` | `[5190 × 1]` matching event codes |
| `codeMeaning` | lookup table for the codes below |

| Code | Count | Meaning |
|---|---|---|
| 9 | 1341 | trial start |
| 10 | 1341 | fixation acquired |
| **11** | **487** | **stimulus on** — align to this one |
| 12 | 275 | stimulus off |
| 18 | 1342 | trial end / inter-trial interval |

Codes 3, 20, 21 and 25 also appear; their meanings are not established here.

Event times are on the **same clock as the spikes**, so no conversion is needed:

```matlab
stimOn = events.times_s(events.codes == 11);
n = sum(units(1).spikes > stimOn(1) & units(1).spikes < stimOn(1) + 0.2);
```

---

## Functions

**`loadUnits`** — options: `'Epoch'` (`'all'` | `'task'` | `'spontaneous'` | `[t0 t1]`),
`'MinSpikes'`, `'MaxPctRefr'`, `'File'`.

```matlab
units = loadUnits('Epoch', 'task', 'MinSpikes', 1000, 'MaxPctRefr', 2);
```

**`plotEvokedSpikes(units, events, unitIdx)`** — raster and PSTH for one unit. Options:
`'AlignCode'` (default 11), `'Window'` (default `[-200 500]` ms), `'BinMs'` (default 10),
`'Plot'`. Returns `[psth, t_ms, raster]`, so it also works headless with `'Plot', false`.

 **Needs the `task` epoch.** The `spontaneous` block is screen-off — it contains no
stimuli, so there is nothing to align to and every raster comes out empty. The function
raises a clear error if you try. All 487 stimulus events fall between 38.8 s and 4206.0 s.

`unitIdx` is an **index into `units`**, not a cluster id. They are different numbers, and
filtering changes the indices. To go from an id:

```matlab
k = find([units.id] == 191);
plotEvokedSpikes(units, events, k);
```

If a plot comes up empty, check that first — then run with `'Plot', false` and inspect the
returned `psth`. Numbers there but a blank figure means a graphics problem, not a data one.

---

## About this NeuroPixel dataset (1 session)

**Only 487 of 1341 trials reached stimulus onset.** The animal broke fixation on most
trials. Align to code 11 and you automatically get only the trials that happened; count
trials from code 9 and you will overcount by roughly 3×.

**Firing rates differ a lot between the two epochs.** Units are less active in the 30-minute
screen-off block, so anything spike-count-dependent has less statistical power there. Check
`[units.nSpikes]` for the epoch you are actually using rather than assuming.

---

## Analysing monosynaptic pairs

The goal: find pairs where one neuron drives the other, from a short-latency peak in their
cross-correlogram. The method and code are in **`CCG Connectivity Code`** (P. Jendritza) —
a separate repo. 

**Probably step 1. Write the adapter.** The pipeline wants a `clu` struct. Everything it needs is here:

| It wants | You give it |
|---|---|
| `spkTU` | `{units.spikes}` |
| `cluster_id`, `ch`, `n_spikes`, `pctRefr` | `units.id`, `.channel`, `.nSpikes`, `.pctRefr` |
| `spike_position_median_X` / `_Y` | `units.x_um`, `units.y_um` |
| `isDoublCountedUnit` | all `false` — already resolved |
| `sink_ch`, `botChanM`, `topChanM` | `session.laminar` |

Plus a `cfg` with `sessionID`, `sessionDate`, `datapath`, `codeDir`. About 20 lines.

**2. Two code hang-ups from patrick's code** `getConnectivitySTA.m:112` calls `toc` with its
only `tic` commented out, and line 294 saves into a folder it never creates. Call `tic` and
`mkdir` first.

**3. Run the main functions.** `getConnectivitySTA` then `getSignifPeaks_CCG`. On the task epoch with
`pctRefr < 2` inside the cortex bounds that should give you **~200 units, ~43,000 ordered pairs** — a few
minutes, under a gigabyte.

**4. On my dry-run, I noticed most of the output is throwaway** A comparable run (183
units) returned **928 "significant" pairs — 62.5% of them at exactly 0 ms lag.** A chemical
synapse cannot act at 0 ms as you know, so you can exclude those as candidates.

**5. Interesting to do** 
Compare `task` against `spontaneous` on the same units. 
Layer connectivity via `session.laminar`. 
Efficacy versus distance via `x_um` / `y_um`.

---

## Where the data came from

Kilosort 4 → Phy, from the raw Neuropixels recording. The full processing pipeline, the
curation that produced these units, and the ECoG recorded simultaneously with them all live
in the `mt-ecog-npx` repository. Ask if you need any of it — none of it is required to work
with this file.

`data/katniss_251120_units.mat` is 235 MB and is not in version control — see **Getting the
data** at the top.
