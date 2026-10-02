# Interview prep: aml-transaction-monitoring-dbt

How to use this. Read each walkthrough, then open the file and trace it yourself. Every claim below is
checkable in the repo; the numbers come from `docs/eda_notes.md`, `docs/rule_results.md` and
`docs/ml_results.md` (regenerate with `python scripts/eda.py`, `make results`, `make ml`).

**Be straight about authorship.** The SQL, models, tests and scripts were written by Claude Code. You
specified the project, designed the evaluation, made the design decisions and reviewed the results. In an
interview, claim exactly that, and only defend what you can explain. If asked "did you write the cycles
rule?", the honest answer is "I specified it and reviewed the results; an AI assistant wrote the SQL, and
here is how it works and where it falls short." This document exists so that second half is true.

**The 30-second version.** I built a dbt + DuckDB pipeline over IBM's synthetic AMLworld transaction data:
raw load, staging, intermediate and mart layers, five SQL detection rules, and an evaluation harness that
scores them per account with time-split labels. The best rule (fan-in/out) lifts precision about 10x over the
base rate; a gradient-boosted model beats every rule at equal alert volume; and because the data is
synthetic and generated from the patterns the rules look for, none of this is evidence about real
detection.

---

## 1. Numbers to know cold

| Fact | Value | Where it comes from |
|---|---|---|
| HI-Small transactions | 5,078,345 | `docs/eda_notes.md` |
| HI-Small laundering transactions | 5,177 (0.10%) | same |
| HI-Small window | 18 days (2022-09-01 to 09-18) | same |
| HI-Small accounts-table rows / active accounts | 518,581 / 515,088 | EDA; harness population |
| Labelled accounts, whole window | 6,357 (1.23% of active accounts) | `dim_account` |
| Self-transfers (HI) | 591,212 (11.6%), almost all `Reinvestment` | EDA |
| Exact duplicate transaction rows (HI) | 9 (kept) | EDA |
| Cross-currency rows (HI) | 72,170; 15 payment currencies | EDA |
| Patterns.txt (HI) | 370 groups, 8 types, 3,209 rows = 62% of laundering rows | EDA |
| Volume shape | 0.2M-1.1M txns/day for days 1-10, then under 400/day | EDA daily table |
| LI-Small | 6,924,049 txns, 3,565 laundering (0.05%), 17 days, 117 groups = 29% coverage | EDA |
| Split | tune = days 1-7, validate = days 8-18 | `dbt_project.yml` |
| Tune population / labelled | 513,512 accounts / 4,064 (0.79%); 3,027 laundering txns | `fct_rule_performance` |
| Validate population / labelled | 361,568 accounts / 2,652 (0.73%); 2,150 laundering txns | same |
| Discarded split | "last 3 days": 60 accounts, all labelled | `scripts/split_counts.py` |
| LI base rate (whole window) | 0.75% (5,304 / 705,907) | `docs/rule_results.md` |
| dbt build | 29 models, 2 seeds, 93 data tests + 9 unit tests = 133 nodes | `dbt build` |
| CI sample | 100,000 txns, all 5,177 laundering rows, 102,174 accounts, seed `aml-ci-sample-v1` | `ci/sample/MANIFEST.json` |

**Rule results** (account level; precision / recall / alerts per 1,000 accounts):

| Rule | HI validate | LI whole window (frozen defaults) |
|---|---|---|
| fan_in_out | 7.1% / 4.9% / 5.0 (about 10x the 0.73% base rate) | 6.9% / 9.4% / 10.2 (about 9x) |
| cycles | 25.0% / 2.9% / 0.8 (about 34x, tiny volume) | 13.2% / 1.2% / 0.7 (about 18x) |
| structuring | 1.3% / 4.4% / 24.8 (about 2x) | 1.8% / 4.3% / 18.2 |
| pass_through | 2.9% / 1.6% / 4.1 (about 4x) | 1.8% / 2.7% / 11.1 |
| baseline_anomaly | 2.5% / 28.7% / 84.4 (tune was 8.2 per 1,000: does not transfer) | 2.2% / 19.5% / 65.4 |

**ML** (HI validate, account-disjoint test accounts, PR-AUC): ML base 0.230, ML base+rules 0.183, best
rule 0.035 (cycles), fan-in/out 0.012. At 5 alerts per 1,000: ML base 34.5% precision (22.9% recall) versus
fan-in/out 5.9%. On LI-Small (model applied once) ML base is 10.4% at 5 per 1,000 versus 6.6%.

---

## 2. Layer walkthroughs

Plain-English: what it computes, why, edge cases, performance.

### Raw load (`scripts/load_raw.py`)
**What:** reads the CSVs into DuckDB schema `raw` with every column as VARCHAR, renaming the duplicate
`Account` header to `from_account` / `to_account` via explicit `names=[...]`. Parses `Patterns.txt` (blocks
between `BEGIN LAUNDERING ATTEMPT - TYPE` and `END ...`) into one row per transaction line tagged with
`pattern_id` and `pattern_type`.
**Why VARCHAR:** keep bank ids and account ids exactly as given; cast in staging where it is tested.
**Edge case that bit:** I first used `skip=1` with `header=true`, which silently dropped the first data row
(5,078,344 vs 5,078,345). The count check against the known row count caught it.
**Performance:** DuckDB's CSV reader does the work; no tuning was needed.

### Seeds
`fx_rates_approx.csv`: static, rounded early-Sep-2022 USD rates for the 15 currencies. An assumption, not
data. `payment_format_risk.csv`: generic AML priors per format (cash and bitcoin 3, wire and cheque 2, ...),
fixed before looking at labels. Both have relationship tests from staging, so a new currency or format
fails the build instead of silently becoming null.

### Staging
- **`stg_transactions`** (table, not view, because the surrogate key is an expensive window function):
  typed timestamp (`strptime`), `txn_id` = `row_number()` over a total ordering of the row's columns
  (deterministic), `from_account_id` / `to_account_id` = `<bank as integer>|<account>`, `is_self_transfer`.
  The bank-id normalisation is a macro (`bank_id`): `cast(cast(bank as bigint) as varchar)`.
  *Edge cases:* exact duplicate rows are kept (9) because dropping them would break label reconciliation
  with the raw file; the singular test `assert_stg_row_and_label_counts_match_raw` enforces no rows or labels
  are dropped or invented.
- **`stg_accounts`**: `account_id = bank_id|account_number`, plus parsed `bank_country` and `entity_type`
  from the name strings. Unique on the composite key; the account number alone is not unique (4 numbers
  appear at two banks).
- **`stg_patterns`**: Patterns.txt rows, typed, same id normalisation. For diagnosis only. Never the label.

### Intermediate
- **`int_txn_enriched`**: adds `amount_usd` (paid amount x FX), received USD, the format risk weight,
  `day_index` (1 = first day, via `min(txn_date) over ()`), `is_cross_currency`, and the pattern tag. The
  pattern join is a 9-column equality; the pattern key is unique so the left join cannot fan out (singular
  test `assert_int_txn_enriched_preserves_rows_and_labels`).
- **`int_edges`**: directed money movements between two different accounts (self-transfers removed), the
  input to fan, pass-through and cycles. Self-transfers would be trivial one-hop cycles and are not movement.
- **`int_account_daily`**: per account and day, counts, USD and distinct counterparties for sent and received,
  built as two aggregates and a full outer join (an account may only send or only receive on a day). About
  2.3M rows.
- **`int_account_activity_days`**: one row per account and day with any activity, self-transfers included
  (counted once). This is the evaluation population: an account is "in" a split if it was active in it. About
  2.48M rows.
- **`int_account_profile`**: one row per account in the accounts table, including accounts with no
  transactions (95,847 have no non-self flows). Includes whole-window degrees and the label
  `is_laundering_account`. *Edge case:* the whole-window degrees are look-ahead; only the cycles rule's hub
  cap uses them (disclosed in the README).

### Marts
- **`dim_account`** (profile + names) and **`fct_transactions`** (the enriched table).
- **`fct_account_split_label`**: for `all`, `tune`, `validate`, sums transaction counts and laundering
  counts over only the activity days in that split's window. An account is labelled in a split only if a
  laundering transaction falls inside the window. This is the leakage guard: the unit test builds an account
  that launders only on day 5 and requires it to be unlabelled in the tune split; an independent re-derivation
  from staging must match exactly. I also broke the model on purpose to confirm both tests fail.
- **`fct_alerts`**: union of the wired rules, contract `rule_id, account_id, alert_ts, score, reason`.
  Tests: reason non-empty, account exists in `dim_account`.
- **`fct_alerts_combined_headline` / `_all`**: one row per account-day any rule in the set fired; score = number
  of distinct rules that fired (rule scores are on different scales). The headline set excludes baseline
  anomaly.
- **Evaluation marts** (`fct_rule_performance`, `_pattern_recall`, `_threshold_sensitivity`, `_overlap`) are
  thin unions over one macro file (`macros/rule_eval.sql`) so the marts and `make eval` share one definition.
- **`fct_alert_features`**: per split and account, point-in-time features computed only from that split's
  window (7 days for tune, 11 for validate), counts also as per-day rates; separate `rf_*` columns for the
  rules' alert counts and max scores. Two singular tests: no label-derived columns exist, and three features
  are re-derived from staging for the tune split and must match (I leaked on purpose to confirm the test
  fails: 359,992 mismatches).

### The evaluation macro
Unit: the account. For a split (day range): *population* = accounts active in it; *labelled* = population
accounts with a laundering endpoint inside it; *alerted* = population accounts with an alert dated inside it.
Metrics: precision, account recall, alerts per 1,000 accounts, precision@100/1000 (top accounts by max score),
and transaction-level recall (share of laundering transactions touching at least one alerted account), also by
pattern type. **Proof before real rules:** "alert everyone" must give recall 1 and precision equal to the base
rate (6,357 / 515,088 = 0.01234); "alert nobody" must give recall 0. A singular test asserts both.

---

## 3. The rules

All five emit one alert per account per calendar day on which the condition holds (a persistent offender
keeps alerting, so every time split sees it). Defaults were chosen on the tune split only: highest account
recall with at most 10 alerts per 1,000 accounts.

### `rule_fan_in_out`
**What:** an account receiving from, or paying, at least 6 distinct counterparties within 6 hours.
**How:** a trailing `RANGE` window per account and side over its time-ordered edges: `count(distinct
counterparty)` and `sum(amount)` in `(ts - 6h, ts]`. Alert when the distinct count reaches 6; score is the
day's peak count; the reason quotes it. A prefilter keeps only accounts whose lifetime distinct counterparties
reach the threshold (they are the only ones that can alert).
**Edge cases:** distinct counts, not transaction counts (one counterparty paying six times does not alert);
rows with identical timestamps are all inside each other's window; both sides can alert on one account.
**Performance:** about 10 seconds on HI-Small thanks to the prefilter.
**Result:** the most useful rule: about 10x the base rate at 5 alerts per 1,000 (HI validate), about 9x on LI.
**Weakness:** recall is only 5-9% of labelled accounts; it finds the hub patterns only.

### `rule_structuring`
**What:** at least 4 payments of 7,000-10,000 USD (a 30% band under a 10,000 threshold) from one sender within
72 hours.
**How:** filter to in-band, non-self payments, then a trailing window count and sum per sender.
**Edge cases:** the minimum is enforced at 3 or more in the SQL (a 2-payment pattern is not structuring;
the model refuses to compile otherwise); amounts are in approximate USD, so the band is only as good as the
FX seed; a 30% band is "below the threshold", not "just below" it.
**Result:** weak, about 2x the base rate. **Honest note:** the first tuning chose a 2-payment minimum; I
overruled it.

### `rule_pass_through`
**What:** at least 80% of an incoming payment of 5,000 USD or more is forwarded to other accounts within 1
hour.
**How:** for each large incoming edge, join the account's later outgoing edges (to someone other than the
sender) in the window, accumulate them in time order, alert at the payment where the running total reaches the
ratio. Collapsed to the strongest per account-day.
**Edge cases:** several outgoing payments add up; money sent straight back to the sender does not count;
payments inside the window but before the receipt do not count.
**Performance:** a time-bounded self-join per account, a few seconds.
**Result:** weak, about 2-4x. Precision stays near 1.5-3% across almost the whole parameter grid: ordinary
accounts forward money too, so this signal does not separate laundering here.

### `rule_cycles`
**What:** money that leaves an account and returns to it through 2 to 5 others (3-6 hops), each leg at least
500 USD, strictly time-ordered, all within 168 hours, skipping accounts with more than 50 counterparties.
**How:** a recursive CTE that starts a walk at every qualifying edge and extends it with edges that leave the
current node, are strictly later, start within the window of the first edge and do not revisit a node; it
closes when an edge returns to the start. Because time must strictly increase around the loop, each cycle is
found exactly once (from its earliest edge). Every account on a closed cycle alerts at the closing edge's
time. Edges are pre-pruned to accounts that have both an in-edge and an out-edge.
**Why each bound:** hops (depth), amount floor (kills dust, and is what keeps the search tractable), window
(stale loops are not laundering), degree cap (hubs explode the search).
**What went wrong:** a 100 USD floor filled the disk with DuckDB spill files and a 250 USD floor ran out of
memory. The 500 USD floor is a compute constraint, not a tuned optimum. I added `max_temp_directory_size: 3GB`
in `profiles.yml` so a runaway query fails fast. Window beyond 168 hours and the degree cap changed almost
nothing.
**Result:** high precision (25% on HI validate, 13% on LI) at under 1 alert per 1,000, so recall is under 3%.
**Caveat:** the hub cap uses whole-window degrees (look-ahead on hub status, not labels).

### `rule_baseline_anomaly`
**What:** a day's activity (sent + received USD) at least 3x the median of the account's earlier active days,
at least 5,000 USD, with at least 2 earlier days.
**How:** window median (`quantile_cont`) over the account's rows strictly before the day.
**Why it fails to transfer:** it needs earlier active days, and accounts accumulate history over time, so more
accounts qualify later: 8.2 alerts per 1,000 on tune versus 84 on validate. A cold-start problem. It stays in
the per-rule tables, labelled, and is excluded from the headline combined set.

### Dummy rules (`models/harness`)
`rule_dummy_all` (every account-day) and `rule_dummy_none` exist to prove the harness before any real rule.

### ML (`scripts/ml_compare.py`)
Features: `fct_alert_features` base columns; trained on tune-window rows of 70% of accounts (hash of the
account id), tested on validate-window rows of the other 30%, so no account is on both sides and the test
window is later. One fixed gradient-boosting configuration, no tuning. Rules are scored on the same accounts;
ties at the alert cut are resolved pro rata (expected value under random tie-breaking).
Why scikit-learn rather than LightGBM: LightGBM needs a system `libomp` that was not installed, and I did not
install system software for this.

---

## 4. Fifteen likely questions (Input and Transformation)

**1. Why is the alert unit the account, not the transaction?**
Investigators work cases per customer/account, and the labels are on transactions but a single laundering
transaction implicates two accounts. So an account is labelled if it is an endpoint of at least one laundering
transaction, and I also report transaction-level recall (laundering transactions touching an alerted account)
so the account choice cannot hide behind a single metric. The cost is that the account label is a derived
choice (1.2% of accounts are labelled versus 0.10% of transactions).

**2. The transactions file has two columns called `Account`. What did you do?**
Rename them at ingestion with explicit column names (`from_account`, `to_account`) instead of letting the
reader auto-rename to `Account` and `Account_1`. Doing it at the boundary means nothing downstream ever sees
the ambiguity.

**3. What was the zero-padded bank id problem?**
Bank ids are padded in the transactions and patterns files (`010`) but not in the accounts file (`10`). My
first `relationships` test (every transaction's account exists in the accounts table) failed for all 5.08M
rows. The fix is a `bank_id` macro that casts to integer in staging. The lesson: a relationships test on day
one caught a silent total join failure that row counts would not.

**4. Why a composite account key?**
Four account numbers appear at two different banks in the accounts table. Keyed on the number alone, those
accounts would merge and their transactions and labels would be mixed. The key is `bank|account`, tested
unique.

**5. Why keep the 9 exact duplicate transactions?**
Dropping them would break reconciliation with the raw file and could drop a labelled row. Each gets its own
surrogate id, and a test requires staging to preserve row and label counts. Nine rows in five million cannot
move any metric.

**6. How do you handle multiple currencies with no FX table?**
A seed of static, rounded approximate USD rates, normalising to `amount_usd`. I say plainly in the README that
this is an assumption, not data. It matters most for the structuring rule, whose band is in USD; with static
rates the band is only approximate (I did not measure by how much). A relationships test fails the build if a currency has no rate.

**7. How do you stop the labels from leaking across time?**
Labels are per split: within a window an account is labelled only if a laundering transaction falls inside it
(`fct_account_split_label`). A unit test constructs an account that launders only after the cut and requires it
to be unlabelled in tune; a singular test re-derives every split's labels from staging; and I deliberately
broke the model to check both fail. The whole-window label is kept only for transaction-level recall.

**8. You changed the validation split. Why, and how did you choose day 7?**
The original plan (last 3 days) turned out to hold 60 accounts, every one labelled, so precision there tells
you nothing. I printed per-day counts and the number of labelled accounts if validation starts at each day
(`scripts/split_counts.py`), required at least about 300 labelled accounts in validation, and kept day 7: days
8-18 hold 2,652 labelled accounts.

**9. The window is 18 days and volume collapses after day 10. What does that do to the work?**
Days 11-18 have under 400 transactions a day but laundering keeps trickling in, so the validate split is
mostly days 8-10 by volume and later days are almost entirely laundering rows. It means validate precision is
about the high-volume days, and it is one reason I treat results as exploratory and say so. It also makes
history-hungry rules like the baseline anomaly behave differently across the cut.

**10. Why is `Patterns.txt` not the label?**
It covers only 62% of the laundering rows in HI-Small (29% in LI-Small), so using it as the label would
silently relabel a third to two thirds of the positives as clean. The label is `Is Laundering` on the
transaction; the patterns file only tags a pattern type for diagnosis (recall by pattern type).

**11. How do you know the evaluation code is right before there are any rules?**
I wrote two dummy rules: alert everyone (recall must be 1 and precision must equal the base rate) and alert
nobody (recall 0). A dbt singular test asserts both on every build, for every split. It caught nothing
because it passed the first time, but it is what lets me trust the numbers for the real rules.

**12. Walk me through the cycle search and what went wrong.**
A recursive CTE walks time-ordered edges and closes when an edge returns to the start; bounded by hop count,
a minimum amount, a time window and a degree cap, with edges pre-pruned to nodes that have an in- and an
out-edge. I tried to raise recall by lowering the amount floor: 100 USD filled the disk with spill files and
250 USD ran out of memory. So the 500 USD floor is a compute constraint and the README says so. I also capped
DuckDB's temp spill so a runaway query fails fast instead of eating the disk.

**13. You changed all the rules to alert once per day instead of once. Why?**
My first version alerted only the first time an account qualified. On validate, structuring had one alert
against 3,380 on tune, even though thousands of in-band payments happened in days 8-10: persistent offenders
alerted on day 1 and were invisible later. A monitoring system re-alerts while behaviour continues, so each
rule now alerts once per account per day. Tune results did not change (same distinct accounts), but validate
became a fair test.

**14. How did you tune without overfitting, and what is the catch?**
Parameter grids were scored on the tune split only (a script that never queries validate), with a fixed
criterion chosen in advance: highest recall within 10 alerts per 1,000 accounts. The catch, which I disclose:
`make eval` prints every split, so I had seen validate at the untuned defaults, and that view prompted the
once-per-day change. So validate is not a pristine holdout; the LI-Small run, with frozen defaults run once, is
the clean check.

**15. Why dbt + DuckDB, and what does your CI actually prove?**
dbt gives tested, documented, lineage-tracked SQL; DuckDB runs 5M-row joins and recursive CTEs locally for
free, which suits a portfolio project. CI cannot download the full dataset, so it loads a committed
100,000-row hash sample (every laundering row kept) and runs `dbt build`, including all rule fixtures. That
proves the pipeline builds and its tests hold. It does not prove the rules perform: sampling breaks the graph
structure, and the README says so.

---

## 5. Follow-ups worth rehearsing

- **"Is the ML result real?"** On this data yes, but the top features are the number of currencies, self-transfers and the
  share of risky formats. Those look like how the generator makes laundering accounts, not like real laundering,
  so it is a statement about this dataset. The rules-as-features model was not better than base features (the
  rules were tuned on the same labels the model trains on).
- **"Where is the look-ahead?"** The cycles hub cap uses whole-window degrees (hub status, not labels). ML features are
  strictly per-window; two tests enforce no label-derived columns and point-in-time values.
- **"What would you do with real data?"** Re-run, expect everything to drop, replace the whole-window degree with an
  as-of degree, use rolling-origin evaluation, and get real FX and a justified format-risk table.
- **"What did you personally decide?"** The alert unit and labelling, the tune/validate design and the
  selection criterion, overruling the 2-payment structuring result, excluding baseline anomaly from the
  headline, and requiring that results be reported even when ML wins.
