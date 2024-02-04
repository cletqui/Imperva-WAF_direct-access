"""Checks if Imperva WAF protected websites are directly accessible.

Returns:
    _type_: TODO
"""


import os
import sys
import argparse
from dotenv import load_dotenv
import requests


def load_env():
    """
    Loads environment variables using `load_dotenv()` and retrieves specific variables.

    Args:
        None

    Returns:
        list: A list containing the values of the following environment variables:
            - API_ENDPOINT: The API endpoint.
            - API_KEY: The API key.
            - API_ID: The API ID.
            - ACCOUNT_ID: The account ID.
    """
    load_dotenv()
    return {
        "API_ENDPOINT": os.getenv("API_ENDPOINT"),
        "API_KEY": os.getenv("API_KEY"),
        "API_ID": os.getenv("API_ID"),
        "ACCOUNT_ID": os.getenv("ACCOUNT_ID")}


def create_parser():
    """
    Creates and configures the argument parser.

    Returns:
        argparse.ArgumentParser: The configured argument parser.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="enable verbose mode")
    parser.add_argument(
        "-o", "--output", help="specify the output file with a .txt extension", default="")
    parser.add_argument("-t", "--timeout", type=int,
                        help="specify the timeout in seconds (positive integer)", default=10)
    parser.add_argument("-l", "--list-only", action="store_true",
                        help="list only websites, no check is performed")
    parser.add_argument(
        "--env", help="specify the path to a .env file for environment variables", default=".env")
    return parser


def load_args():
    """
    Loads and parses command line arguments.

    Returns:
        argparse.Namespace: An object containing the parsed command line arguments.
    """
    parser = create_parser()
    return parser.parse_args()


def get_sites(env):
    """
    Retrieves sites from the API endpoint.

    Args:
        env (dict): A dictionary containing environment variables.

    Returns:
        requests.Response: The response object json.

    Raises:
        requests.HTTPError: If the response is not ok.
    """
    params = {'account_id': env["ACCOUNT_ID"]}
    response = requests.post(env["API_ENDPOINT"],
                             headers={'Accept': 'application/json'}, params=params, timeout=10)

    if response.ok:
        return response.json()

    response.raise_for_status()


def main():
    """
    Parses command line arguments and executes the main logic of the script.

    Args:
        None

    Returns:
        None
    """
    env = load_env()
    options = load_args()
    print("Env: ", env, "\nOptions: ", options)
    sites = get_sites(env)
    print("Sites: ", sites)


if __name__ == "__main__":
    main()
    sys.exit(0)
