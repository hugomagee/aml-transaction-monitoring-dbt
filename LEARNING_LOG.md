# Learning log

One entry per rule review or surprise. Short and specific: what was wrong, why, how it was fixed.

## Template

### <date> - <rule or topic>
- **What I wrote / assumed:**
- **What review or the data showed:** (edge case, bug, performance issue, leakage)
- **Why it happens:**
- **Change made:**
- **Number before -> after (command that reproduces it):**

## Entries

### 2026-10-02 - Autopilot rules: alert only the first time (Claude Code)
- **What I wrote:** structuring and fan-in/out emitted one alert per account, at the first qualifying time.
- **What the data showed:** validate (days 8-18) held 1 structuring alert against 3,380 in tune, though ~11k in-band payments fell in days 8-10. Persistent offenders alerted on day 1 and were invisible to every later split.
- **Why:** a first-alert-only design is a function of the account's whole history, not of the window being scored.
- **Change made:** every rule alerts once per account per calendar day the condition holds. Tune results were unchanged (same distinct accounts); validate became a fair test. Fixtures unchanged.
- **Caveat:** I saw validate at untuned defaults before making this change (see docs/rule_results.md).

### 2026-10-02 - Autopilot rules: recursion blows up below an amount floor (Claude Code)
- **What I assumed:** loosening the cycle amount floor to 100-250 USD would raise recall.
- **What happened:** 100 USD filled the disk with DuckDB spill files; 250 USD hit the memory limit. The floor (500 USD) is the bound that keeps the search tractable. Window and degree cap changed almost nothing.
- **Change made:** `max_temp_directory_size: 3GB` in profiles.yml so a runaway query fails fast; cycles recall stays under 3%.

### 2026-10-02 - Autopilot rules: baseline anomaly alert volume is not stationary (Claude Code)
- **What the data showed:** tune alert rate 8.2 per 1,000 accounts, validate 84 per 1,000.
- **Why:** the baseline needs earlier active days, and accounts accumulate history over time, so more accounts qualify later. A rate tuned on days 1-7 does not carry over.
- **Reproduce:** `python scripts/rule_results.py`.
