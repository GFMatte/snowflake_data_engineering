-- create the root task
create or replace task BAKERY_DB.ORCHESTRATION.PIPELINE_START_TASK
  warehouse = BAKERY_WH
  schedule = '10 M'
as
  call SYSTEM$SEND_EMAIL(
    'PIPELINE_EMAIL_INT',
    'guilherme.matte@notitia.com.au', -- substitute you email address
    'Daily pipeline start',
    'The daily pipeline started at ' || current_timestamp || '.'
);