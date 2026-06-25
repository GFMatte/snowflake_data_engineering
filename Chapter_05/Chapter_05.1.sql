/*============================================================================
  Chapter 5 — Continuous data loading from Azure Blob Storage with Snowpipe
  Version: 5.1 (refactored)

  What this script builds, end to end:
    1. A storage integration / external stage over an Azure container
    2. A raw staging table for the "Speedy" delivery-order JSON files
    3. A notification integration + auto-ingest Snowpipe (Event Grid driven)
    4. A dynamic table that flattens the JSON into a queryable model

  Conventions used below:
    - Lowercase SQL keywords, UPPERCASE object identifiers
    - Idempotent DDL (create or replace / if not exists) so the script can
      be re-run safely
    - Secrets are NEVER hardcoded. Replace the <PLACEHOLDER> values, or set
      SnowSQL variables, before running. See the "Parameters" block below.

  SECURITY NOTE: The original v5 hardcoded a live Azure SAS token and tenant
  IDs. Those have been replaced with placeholders. Rotate any credential that
  was previously committed to source control.
============================================================================*/

/*----------------------------------------------------------------------------
  Parameters — set these once (SnowSQL: pass with -D NAME=value, or edit here)
----------------------------------------------------------------------------*/
-- Azure tenant that owns the storage account:
--   &AZURE_TENANT_ID            e.g. 71a3136a-xxxx-xxxx-xxxx-xxxxxxxxxxxx
-- Blob container holding the order files:
--   &AZURE_BLOB_URL             azure://<account>.blob.core.windows.net/<container>
-- Storage queue receiving "Blob Created" events:
--   &AZURE_QUEUE_URL            https://<account>.queue.core.windows.net/<queue>
-- Short-lived SAS token (account or container scoped):
--   &AZURE_SAS_TOKEN            ?sv=...&sig=...


/*============================================================================
  1. STORAGE INTEGRATION  (ACCOUNTADMIN)
  ----------------------------------------------------------------------------
  Preferred over SAS tokens: uses an Azure AD app consent instead of a static
  secret. After creating it, run DESCRIBE and complete the consent flow using
  AZURE_CONSENT_URL / AZURE_MULTI_TENANT_APP_NAME.
============================================================================*/
use role ACCOUNTADMIN;

create storage integration if not exists SPEEDY_INTEGRATION
  type = external_stage
  storage_provider = 'AZURE'
  enabled = true
  azure_tenant_id = '&AZURE_TENANT_ID'
  storage_allowed_locations = ('&AZURE_BLOB_URL');

-- Note AZURE_CONSENT_URL and AZURE_MULTI_TENANT_APP_NAME from the output,
-- then grant Azure consent before the integration can be used.
describe integration SPEEDY_INTEGRATION;

-- Let SYSADMIN (the workload role) use the integration.
grant usage on integration SPEEDY_INTEGRATION to role SYSADMIN;


/*============================================================================
  2. DATABASE OBJECTS  (SYSADMIN)
============================================================================*/
use role SYSADMIN;

create warehouse if not exists BAKERY_WH
  with warehouse_size = 'XSMALL'
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;

create database if not exists BAKERY_DB;
create schema if not exists BAKERY_DB.DELIVERY_ORDERS;

use database BAKERY_DB;
use schema DELIVERY_ORDERS;
use warehouse BAKERY_WH;


/*============================================================================
  3. EXTERNAL STAGE
  ----------------------------------------------------------------------------
  Option A (recommended): reuse the storage integration above.
  Option B: a SAS token, for quick tests only. Tokens are short-lived secrets
  and should be passed via the &AZURE_SAS_TOKEN variable, never committed.
============================================================================*/

-- Option A — storage integration based stage
create or replace stage SPEEDY_STAGE
  storage_integration = SPEEDY_INTEGRATION
  url = '&AZURE_BLOB_URL'
  file_format = (type = json);

/* Option B — SAS-token based stage (uncomment to use instead of Option A)
create or replace stage SPEEDY_STAGE
  url = '&AZURE_BLOB_URL'
  credentials = (azure_sas_token = '&AZURE_SAS_TOKEN')
  file_format = (type = json);
*/

-- Inspect the stage and the raw JSON before loading.
list @SPEEDY_STAGE;
select $1 from @SPEEDY_STAGE;

-- Preview the projection we will load: pull scalar fields, keep ITEMS as a
-- variant for later flattening, and capture file/load lineage.
select
    $1:"Order id"        as order_id,
    $1:"Order datetime"  as order_datetime,
    $1:"Items"           as items,
    metadata$filename    as source_file_name,
    current_timestamp()  as load_ts
from @SPEEDY_STAGE;


/*============================================================================
  4. RAW STAGING TABLE
============================================================================*/
create table if not exists SPEEDY_ORDERS_RAW_STG (
    order_id          varchar,
    order_datetime    timestamp,
    items             variant,
    source_file_name  varchar,
    load_ts           timestamp
);


/*============================================================================
  5. NOTIFICATION INTEGRATION  (ACCOUNTADMIN)
  ----------------------------------------------------------------------------
  Prerequisites in Azure:
    - Enable the Event Grid resource provider
    - Create a storage queue (note its URL -> &AZURE_QUEUE_URL)
    - Create an Event Grid subscription on the "Blob Created" event that
      delivers to that queue
============================================================================*/
use role ACCOUNTADMIN;

create notification integration if not exists SPEEDY_QUEUE_INTEGRATION
  enabled = true
  type = queue
  notification_provider = azure_storage_queue
  azure_storage_queue_primary_uri = '&AZURE_QUEUE_URL'
  azure_tenant_id = '&AZURE_TENANT_ID';

-- Note AZURE_CONSENT_URL / AZURE_MULTI_TENANT_APP_NAME and grant consent.
describe notification integration SPEEDY_QUEUE_INTEGRATION;
show integrations;

grant usage on integration SPEEDY_QUEUE_INTEGRATION to role SYSADMIN;


/*============================================================================
  6. SNOWPIPE (auto-ingest)  (SYSADMIN)
============================================================================*/
use role SYSADMIN;
use database BAKERY_DB;
use schema DELIVERY_ORDERS;

create or replace pipe SPEEDY_PIPE
  auto_ingest = true
  integration = 'SPEEDY_QUEUE_INTEGRATION'
  as
  copy into SPEEDY_ORDERS_RAW_STG
  from (
    select
        $1:"Order id",
        $1:"Order datetime",
        $1:"Items",
        metadata$filename,
        current_timestamp()
    from @SPEEDY_STAGE
  );

-- Backfill: load files that already existed before Event Grid was wired up.
alter pipe SPEEDY_PIPE refresh;


/*============================================================================
  7. VERIFY THE LOAD
============================================================================*/
select * from SPEEDY_ORDERS_RAW_STG;

-- Pipe health (executionState, pendingFileCount, lastError, ...).
select system$pipe_status('SPEEDY_PIPE');

-- Copy activity in the last hour.
select *
from table(information_schema.copy_history(
    table_name => 'SPEEDY_ORDERS_RAW_STG',
    start_time => dateadd(hours, -1, current_timestamp())));


/*============================================================================
  8. MODELED DYNAMIC TABLE
  ----------------------------------------------------------------------------
  Flatten the ITEMS array (one row per line item) and let Snowflake keep it
  fresh within the target lag.
============================================================================*/

-- Ad hoc check of the flatten logic before materializing it.
select
    order_id,
    order_datetime,
    value:"Item"::varchar     as baked_good_type,
    value:"Quantity"::number  as quantity
from SPEEDY_ORDERS_RAW_STG,
     lateral flatten(input => items);

create or replace dynamic table SPEEDY_ORDERS
  target_lag = '1 minute'
  warehouse = BAKERY_WH
  as
  select
      order_id,
      order_datetime,
      value:"Item"::varchar     as baked_good_type,
      value:"Quantity"::number  as quantity,
      source_file_name,
      load_ts
  from SPEEDY_ORDERS_RAW_STG,
       lateral flatten(input => items);

-- Query the modeled data.
select *
from SPEEDY_ORDERS
order by order_datetime desc;

-- Dynamic table refresh history.
select *
from table(information_schema.dynamic_table_refresh_history())
order by refresh_start_time desc;
