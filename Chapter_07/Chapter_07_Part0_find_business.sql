use role SYSADMIN;

-- Find the business ID for the "Coffee Branch" business in Adelaide, South Australia
create or replace function SEARCH_YELP_BUSINESSES(term varchar, location varchar)
returns variant
language python
runtime_version = 3.10
handler = 'search_businesses'
external_access_integrations = (YELP_API_INTEGRATION)
secrets = ('yelp_api_token' = YELP_API_TOKEN)
packages = ('requests')
as
$$
import _snowflake
import requests

def search_businesses(term, location):
    api_key = _snowflake.get_generic_secret_string('yelp_api_token')

    url = 'https://api.yelp.com/v3/businesses/search'

    response = requests.get(
        url=url,
        headers={'Authorization': 'Bearer ' + api_key},
        params={
            'term': term,
            'location': location,
            'limit': 5
        }
    )

    return response.json()
$$;


select SEARCH_YELP_BUSINESSES('Coffee Branch', 'Adelaide, SA');


-- Search for business information using the business ID
create or replace function GET_YELP_BUSINESS(business_id varchar)
returns variant
language python
runtime_version = 3.10
handler = 'get_business'
external_access_integrations = (YELP_API_INTEGRATION)
secrets = ('yelp_api_token' = YELP_API_TOKEN)
packages = ('requests')
as
$$
import _snowflake
import requests

def get_business(business_id):
    api_key = _snowflake.get_generic_secret_string('yelp_api_token')

    response = requests.get(
        url=f'https://api.yelp.com/v3/businesses/{business_id}',
        headers={'Authorization': 'Bearer ' + api_key}
    )

    return response.json()
$$;



select GET_YELP_BUSINESS('IWc6D0H6FRAd6kMOVthPXg');