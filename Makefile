# make setup data load build test eval
SHELL := /bin/bash
VENV  := .venv
PY    := $(VENV)/bin/python
DBT   := DBT_PROFILES_DIR=. $(VENV)/bin/dbt

.PHONY: setup data load build test test-rule eval ci-sample ci clean

setup:
	/opt/homebrew/bin/python3.12 -m venv $(VENV) || python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -U pip
	$(VENV)/bin/pip install -q -r requirements.txt

data:
	$(PY) scripts/download_data.py

load:
	$(PY) scripts/load_raw.py

# Rule fixtures (tag hugo_rule) are excluded until a rule is implemented; run them
# with `make test-rule RULE=<name>`.
build:
	$(DBT) seed
	$(DBT) build --exclude tag:hugo_rule

test:
	$(DBT) test --exclude tag:hugo_rule

# make test-rule RULE=rule_fan_in_out   (runs the hand-built fixture only)
test-rule:
	$(DBT) test --select "$(RULE),test_type:unit"

# make eval RULE=rule_fan_in_out   (rules in models/rules must pass their fixture first)
eval:
	$(PY) scripts/eval_rule.py $(RULE)

clean:
	rm -rf target logs

# Regenerate the committed CI sample from the full HI-Small files (needs `make data`).
ci-sample:
	$(PY) scripts/make_ci_sample.py

# Reproduce CI locally: load the committed sample into data/ci.duckdb and build on it.
ci:
	AML_RAW_DIR=ci/sample AML_DB=data/ci.duckdb $(PY) scripts/load_raw.py hi
	AML_DB=data/ci.duckdb $(DBT) build --exclude tag:hugo_rule
