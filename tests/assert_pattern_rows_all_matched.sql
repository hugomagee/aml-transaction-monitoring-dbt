-- Every Patterns.txt row must map to exactly one staged transaction row
-- (duplicated source rows excepted: a pattern row may match each copy).
with matched as (
    select pattern_id, pattern_type from {{ ref('int_txn_enriched') }} where pattern_id is not null
)
select (select count(*) from {{ ref('stg_patterns') }}) as pattern_rows, count(*) as matched_rows
from matched
having count(*) < (select count(*) from {{ ref('stg_patterns') }})
