# pre-requisites for executing the python code:
# - install a supported Python version
# - create and activate a Python virtual environment
# - install the snowflake-snowpark-python package (using pip or conda, depending on your Python environment)

#Listing 6.3
# import Session from the snowflake.snowpark package
from snowflake.snowpark import Session

# create a dictionary with the connection parameters
connection_parameters_dict = {
    "account": "KVAIEAM-GS58625", # replace with your Snowflake account
    "user": "GUILHERME MATTE", # replace with your username
    "password": "pass", # replace with your password
    "role": "SYSADMIN",
    "warehouse": "COMPUTE_WH",
    "database": "BAKERY_DB",
    "schema": "SNOWPARK"
}  

# create the session
my_session = Session.builder.configs(connection_parameters_dict).create()

# close the session
my_session.close()