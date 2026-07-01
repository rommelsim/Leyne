# WhereSia — data: LTA DataMall mapping

Every number in WhereSia comes from **LTA DataMall** (Singapore's official open transport API). This maps each screen to its endpoint and fields.

> **Authoritative source:** the full API guide the design was built against is at
> `/Users/rommel/Downloads/LTA_DataMall_API_User_Guide.md`.
> Field names/values below are from that guide, but **verify against it before coding** — treat it as the contract, not this summary.

## Access
- **Base:** `http://datamall2.mytransport.sg/ltaodataservice/`
- **Auth:** every request needs an `AccountKey` header (register free at DataMall). 
- **⚠️ The key is secret and DataMall has no CORS** → the client must **not** call DataMall directly. Stand up a small **backend proxy** that holds the key, adds caching, and serves the app. Plan for rate limits.
- **Responses:** JSON, most under a `value` array. Large static datasets are **paginated** via `$skip` in 500-row pages.

## Data shapes that matter
- **Bus Load** (per bus): `SEA` = Seats Available → **"Seats"** · `SDA` = Standing Available → **"Standing"** · `LSD` = Limited Standing → **"Limited/Full"**. Maps to gauge 34 / 67 / 100%.
- **Bus Type:** `SD` single-deck · `DD` double-deck · `BD` bendy. Pick the bus-type icon from this.
- **Feature:** `WAB` = wheelchair-accessible → show wheelchair icon.
- **Monitored:** `1` = live estimate (show live ")))" glyph) · `0` = scheduled (dim the pill, empty gauge, label "sched").
- **Station CrowdLevel:** `l` / `m` / `h` → **Low / Moderate / High**, gauge 34 / 67 / 100%.

## Endpoint → screen map

| Screen | Endpoint(s) | Key fields |
|---|---|---|
| **Home · Nearby** | `BusStops` (static, cached) + `v3/BusArrival` per nearby stop + `PCDRealTime` for nearby stations | nearest stops by lat/long; soonest `EstimatedArrival` + `Load`; station `CrowdLevel` |
| **Search** | `BusStops`, `BusServices` (both static/cached); station list | `Description`, `RoadName`, `BusStopCode`, `ServiceNo` |
| **Bus stop** | `v3/BusArrival?BusStopCode=` | per service: `NextBus/NextBus2/NextBus3` → `EstimatedArrival`, `Load`, `Type`, `Feature`, `Monitored`, `DestinationCode`, `Operator` |
| **MRT station** | `PCDRealTime?TrainLine=` + `PCDForecast?TrainLine=` + `TrainServiceAlerts` | `CrowdLevel` now (per station/platform); 30-min forecast for the day; service `Status` |
| **Service info** | `BusServices` + `BusRoutes` | `AM_Peak_Freq` etc. (frequency bands); `WD/SAT/SUN_FirstBus/LastBus` per stop; `StopSequence` |
| **Track bus** | `v3/BusArrival` (bus coords + downstream ETAs) + `BusRoutes` (stop sequence) | `Latitude`/`Longitude` of next bus, per-stop `EstimatedArrival`, ordered `BusStopCode` list |
| **Alerts** | `TrainServiceAlerts` + `FacilitiesMaintenance` | disruption `Message`, affected line/stations, bridging buses; lift/facility outages. User reminders are **local** (not an API). |

## Refresh cadence
- **Bus arrivals:** real-time; poll ~every 20s while a stop is open (the UI states "refreshes every 20s").
- **Station crowd real-time:** updates ~every 10 min; forecast is per-day.
- **Static sets** (`BusStops`, `BusServices`, `BusRoutes`): change rarely — fetch fully once, cache locally, refresh on a schedule (e.g. daily). These power search and the route timeline; the app should feel instant offline for lookups.

## Honest limitations (design already accounts for these)
- **No minute-level bus timetable exists.** "Service info" shows first/last bus + frequency *bands* only — never invent scheduled minute times.
- **No full live-vehicle GPS stream.** `BusArrival` gives coordinates + ETAs for the next 1–3 buses only. "Track bus" approximates position from those + the route's stop sequence and per-stop ETAs; don't imply second-by-second GPS.
- **Crowd granularity:** buses report a 3-level `Load`; stations a 3-level `CrowdLevel`. That's the ceiling — the 3-step gauge matches the data exactly (don't fake finer resolution).
