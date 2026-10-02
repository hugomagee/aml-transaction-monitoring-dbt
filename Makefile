# make setup data load build test eval
SHELL := /bin/bash
VENV  := .venv
PY    := $(VENV)/bin/python
DBT   := DBT_PROFILES_DIR=. $(VENV)/bin/dbt

.PHONY: setup data load build test eval clean

setup:
	/opt/homebrew/bin/python3.12 -m venv $(VENV) || python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -U pip
	$(VENV)/bin/pip install -q -r requirements.txt

data:
	$(PY) scripts/download_data.py

load:
	$(PY) scripts/load_raw.py

build:
	$(DBT) build

test:
	$(DBT) test

# make eval RULE=rule_fan_in_out
eval:
	$(PY) scripts/eval_rule.py $(RULE)

clean:
	rm -rf target logs
