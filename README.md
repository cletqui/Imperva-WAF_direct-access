# Imperva-WAF_direct-access

## Description

Imperva-WAF_direct-access is a project designed to help you check whether the backend of your websites behind an Imperva Web Application Firewall (WAF) is directly accessible without going through the WAF. This can be a valuable security measure to ensure that traffic is routed through your WAF as intended.

## Features

- Check if backend servers are accessible without the WAF.
- Support for multiple URLs.
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

## Usage

To check whether the backend is accessible without the WAF for a single URL:

```bash
./check_direct_access.sh https://example.com
```

To check multiple URLs, create a text file with one URL per line (e.g., `urls.txt`), and then run:

```bash
./check_direct_access.sh -f urls.txt
```

## Example

```bash
$ ./check_direct_access.sh https://example.com

Checking direct access for URL: https://example.com
Direct access is not allowed. WAF protection is active.

```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Imperva](https://www.imperva.com/) for their Web Application Firewall technology.
- Contributors: List any contributors here.

## Support

If you have any questions or encounter issues, please open an [issue](https://github.com/cletqui/Imperva-WAF_direct-access/issues).

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## Roadmap

- [ ] Add support for custom WAF IP addresses.
- [ ] Improve user interface and error handling.
- [ ] Add additional security checks.

## Project Status

This project is actively maintained and open to contributions.
