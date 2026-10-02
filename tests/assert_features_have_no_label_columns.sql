-- Feature columns must not be derived from labels or pattern tags. Only `label` itself may
-- carry label information, and only the allow-listed column names may exist.
select column_name
from information_schema.columns
where table_schema = 'marts' and table_name = 'fct_alert_features'
  and column_name not in ('split', 'account_id', 'label', 'entity_type', 'bank_country')
  and column_name not like 'f\_%' escape '\'
  and column_name not like 'rf\_%' escape '\'
union all
select column_name
from information_schema.columns
where table_schema = 'marts' and table_name = 'fct_alert_features'
  and (column_name like '%launder%' or column_name like '%pattern%' or column_name like '%profile%')
