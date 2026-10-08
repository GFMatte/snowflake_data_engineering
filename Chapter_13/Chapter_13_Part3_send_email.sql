-- create a notification integration using the ACCOUNTADMIN role
use role ACCOUNTADMIN;
create notification integration PIPELINE_EMAIL_INT
  type = email
  enabled = true;

-- grant usage on the integration to the DATA_ENGINEER role
grant usage on integration PIPELINE_EMAIL_INT to role DATA_ENGINEER;

-- use the DATA_ENGINEER role to send an email to yourself
use role DATA_ENGINEER;
call SYSTEM$SEND_EMAIL(
    'PIPELINE_EMAIL_INT',
    'guilherme.matte@notitia.com.au', -- substitute you email address
    'Send email from Snowflake using the PIPELINE_EMAIL_INT integration',
    'This is a test email sent from Snowflake using the PIPELINE_EMAIL_INT integration. Please ignore this email.'
);
