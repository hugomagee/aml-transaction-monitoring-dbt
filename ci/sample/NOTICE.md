# Notice: CI sample data

The `*.gz` files in this directory are **a modified subset of the IBM AMLworld dataset**:

- **Dataset:** "IBM Transactions for Anti Money Laundering (AML)", files `HI-Small_Trans.csv`,
  `HI-Small_accounts.csv` and `HI-Small_Patterns.txt`.
- **Data Provider:** Erik Altman (IBM), published on Kaggle:
  <https://www.kaggle.com/datasets/ealtman2019/ibm-transactions-for-anti-money-laundering-aml>
- **Licence of this data:** Community Data License Agreement – Sharing – Version 1.0
  (CDLA-Sharing-1.0), <https://cdla.dev/sharing-1-0/>. The data in this directory is Published under that
  unmodified agreement. Nothing in this repository adds any restriction on its use, and any licence
  applied to the repository's own code does not apply to these data files.
- **The data is provided "AS IS"** (CDLA-Sharing-1.0, Section 6).

## What was changed (CDLA-Sharing-1.0, Section 3.1(b))

These files differ from the originals:

- `HI-Small_Trans.csv.gz`: a **subset** of the transactions (rows removed), selected by
  `scripts/make_ci_sample.py` (fixed seed; every laundering row kept; other rows hash-sampled). Values are
  unchanged; rows are ordered by timestamp. Compressed with gzip.
- `HI-Small_accounts.csv.gz`: only the account rows that appear in the sampled transactions (rows removed).
  Compressed with gzip.
- `HI-Small_Patterns.txt.gz`: all pattern blocks (every row is a laundering row and is present in the
  sample); only gzip compression and trailing-newline normalisation differ.

`MANIFEST.json` records the seed, the quotas, the row counts and a SHA-256 of each file. The full,
unmodified data is not committed (`data/` is gitignored); fetch it with `make data`.

This notice is the repository owner's good-faith reading of the licence text, not legal advice.
