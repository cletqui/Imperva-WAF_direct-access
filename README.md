# Imperva-WAF_direct-access

## Description

Imperva-WAF_direct-access is a project designed to help you check whether the backend of your websites behind an Imperva Web Application Firewall ([WAF](https://www.imperva.com/products/web-application-firewall-waf/)) is directly accessible without going through the WAF. This can be a valuable security measure to ensure that traffic is routed through your WAF as recommended (c.f. [Imperva Documentation](https://www.imperva.com/blog/how-to-maximize-your-waf/)).

## Table of Contents

- [Imperva-WAF\_direct-access](#imperva-waf_direct-access)
  - [Description](#description)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Installation](#installation)
  - [Imperva API Setup](#imperva-api-setup)
  - [Usage](#usage)
    - [Options](#options)
    - [Examples](#examples)
  - [Acknowledgments](#acknowledgments)
  - [Roadmap](#roadmap)
  - [Support](#support)
  - [Contributing](#contributing)
  - [License](#license)
  - [Project Status](#project-status)

## Features

- Check if backend servers are directly accessible without the WAF.
- Option to list only the websites names (to see exactly what sites are secured by your WAF).
- User-friendly and easy to run.

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/cletqui/Imperva-WAF_direct-access.git
   ```

2. Navigate to the project directory:

   ```bash
   cd Imperva-WAF_direct-access
   ```

3. Make the script executable:

   ```bash
   chmod +x check_direct_access.sh
   ```

## Imperva API Setup

To use this repository with Imperva API, you need to create a `.env` file in the project directory with the following credentials:

1. **API Endpoint**:
   Set the API endpoint URL as follows:

   ```plaintext
   API_ENDPOINT="https://my.imperva.com/api/prov/v1/sites/list"
   ```

2. **API Credentials**:
   Provide your Imperva API credentials:

   - API_ID: Your API ID
   - API_KEY: Your API Key

   ```plaintext
   API_ID=00000
   API_KEY="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   ```

3. **Account ID**:
   Specify your Imperva Account ID:

   ```plaintext
   ACCOUNT_ID=0000000
   ```

Ensure that you replace the placeholder values with your actual Imperva API information. Keep this `.env` file secure and do not share it publicly. It is explicitely excluded in `.gitignore`.

## Usage

To use this script, you can run it from the command line with the following options:

```bash
./check_direct_access.sh check.py [OPTIONS]
```

Remember to replace the option values with your specific choices and ensure that you have created a `.env` file with your Imperva API credentials as explained in the previous section.

### Options

- `-v, --verbose`: Enable verbose mode (log it into logs.txt).
- `-a, --all`: Include all websites (only unsafe websites by default).
- `-o, --output <file>`: Specify the output file (with a .json extension).
- `-t, --timeout <timeout>`: Specify the timeout in seconds (positive integer).
- `-l, --list-only`: List only websites (no check is performed).
- `-e, --env <file>`: Specify the path to a .env file for environment variables.
- `-h, --help`: Display this help message.

### Examples

1. **Basic Usage**:

   ```bash
   ./check_direct_access.sh -v -a -o output.json -t 10 -e .env
   ```

2. **Minimum Usage**:

   ```bash
   ./check_direct_access.sh
   ```

3. **Display Help**:

   ```bash
   ./check_direct_access.sh -h
   ```

## Acknowledgments

- [Imperva](https://www.imperva.com/) for their Web Application Firewall technology.
- Contributors: List any contributors here.

## Roadmap

- [x] Return data in JSON.
- [ ] Add option to test only selected websites
- [ ] Improve user interface and error handling.
- [ ] Add additional security checks.
- [ ] Adapt shell scritp to Python.

## Support

If you have any questions or encounter issues, please open an [issue](https://github.com/cletqui/Imperva-WAF_direct-access/issues).

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Project Status

This project is actively maintained and open to contributions.
