"""Download the six IBM AMLworld files we use (HI-Small and LI-Small only).

Uses kagglehub (no Kaggle token needed for this public dataset). Each file is
fetched separately so the Medium and Large files are never downloaded. Files
are symlinked into data/raw/ (gitignored); the kagglehub cache holds the bytes.
"""
from pathlib import Path

import kagglehub

HANDLE = "ealtman2019/ibm-transactions-for-anti-money-laundering-aml"
FILES = [
    "HI-Small_Trans.csv",
    "HI-Small_accounts.csv",
    "HI-Small_Patterns.txt",
    "LI-Small_Trans.csv",
    "LI-Small_accounts.csv",
    "LI-Small_Patterns.txt",
]
RAW = Path(__file__).resolve().parent.parent / "data" / "raw"


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        cached = Path(kagglehub.dataset_download(HANDLE, path=name))
        link = RAW / name
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(cached)
        print(f"{name}: {cached.stat().st_size / 1e6:,.1f} MB -> {link}")


if __name__ == "__main__":
    main()
