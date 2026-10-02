-- Proves the harness before any real rule exists:
--   alert-everyone: recall 1 on every split, precision == base rate of labelled accounts
--   alert-nobody:   recall 0 and no alerts on every split
select rule_id, split, account_recall, precision, n_alerted_accounts, n_labelled_accounts, n_population
from {{ ref('fct_rule_performance') }}
where (rule_id = 'rule_dummy_all' and (
          account_recall <> 1 or txn_recall <> 1
          or abs(precision - n_labelled_accounts::double / n_population) > 1e-12
          or n_alerted_accounts <> n_population))
   or (rule_id = 'rule_dummy_none' and (
          account_recall <> 0 or txn_recall <> 0 or n_alerted_accounts <> 0))
