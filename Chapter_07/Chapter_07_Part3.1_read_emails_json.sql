--python -m pip install snowflake-ml-python
use role SYSADMIN;
use database BAKERY_DB;
use schema REVIEWS;

-- create a stored procedure that calls the Snowflake Cortex Complete model
-- it then converts the resulting CSV output into a data frame and saves it to a table
CREATE OR REPLACE PROCEDURE READ_EMAIL_PROC_JSON(email_content VARCHAR)
RETURNS TABLE()
LANGUAGE PYTHON
RUNTIME_VERSION = 3.10
HANDLER = 'get_order_info_from_email'
PACKAGES = (
    'snowflake-snowpark-python',
    'snowflake-ml-python'
)
AS
$$
import json

import snowflake.snowpark as snowpark
from snowflake.snowpark.types import (
    StructType,
    StructField,
    DateType,
    StringType,
    IntegerType
)
from snowflake.cortex import Complete


def get_order_info_from_email(
    session: snowpark.Session,
    email_content: str
):

    prompt = f"""
You are a bakery employee reading customer delivery emails.

Extract all ordered items from the email.

Return only valid JSON.
Do not include markdown, explanations, or code fences.

Return a JSON array in this exact structure:

[
  {{
    "customer": "customer name",
    "order_date": "YYYY-MM-DD",
    "delivery_date": "YYYY-MM-DD",
    "item": "item name",
    "quantity": 1
  }}
]

Rules:

- Use the current date for order_date.
- If no year is provided, assume the current year.
- quantity must be an integer.
- item must be one of:
  white loaf,
  rye loaf,
  baguette,
  bagel,
  croissant,
  chocolate muffin,
  blueberry muffin.

Email content:

{email_content}
"""

    json_output = Complete(
        'llama3.1-8b',
        prompt
    )

    orders = json.loads(json_output)

    rows = [
        (
            order["customer"],
            order["order_date"],
            order["delivery_date"],
            order["item"],
            int(order["quantity"])
        )
        for order in orders
    ]

    schema = StructType([
        StructField("CUSTOMER", StringType(), False),
        StructField("ORDER_DATE", DateType(), False),
        StructField("DELIVERY_DATE", DateType(), False),
        StructField("ITEM", StringType(), False),
        StructField("QUANTITY", IntegerType(), False)
    ])

    orders_df = session.create_dataframe(
        rows,
        schema
    )

    orders_df.write.mode("append").save_as_table(
        "COLLECTED_ORDERS_FROM_EMAIL"
    )

    return orders_df
$$;

-- execute the stored procedure and provide a sample of an email content
call READ_EMAIL_PROC_JSON('Hello, please deliver 6 loaves of white bread on Tuesday, September 5. On Wednesday, September 6, we need 16 bagels. Thanks, Lilys Coffee');

-- select from the table to verify that the csv was written to the table
select * from COLLECTED_ORDERS_FROM_EMAIL;

-- a few more sample email contents to test the stored procedure
call READ_EMAIL_PROC_JSON('Hi again. At Metro Fine Foods, we are renewing our order for Thursday, September 7. We need 20 baguettes, 16 croissants, and a dozen blueberry muffins. Have a nice day!');

call READ_EMAIL_PROC_JSON('Greetings! We loved your French bread last week. Please deliver 10 more tomorrow. Cheers from your friends at Page One Fast Food');

call READ_EMAIL_PROC_JSON('Do you deliver pizza? If so, send two this afternoon. If not, then some bagels should do. Best, Jimmys Diner');




