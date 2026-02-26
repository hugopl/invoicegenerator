# Stupid invoice generator

Put the data you usually use to create your invoices into a YAML file, run this
tool and done, you have a nice PDF invoice.

> **Note:** This project has been rewritten in [Crystal](https://crystal-lang.org/)
> and now uses [libharu](http://libharu.org/) for PDF generation instead of
> wkhtmltopdf/WebKit. It no longer depends on X11, WebKit, or any browser engine.

A pre-built static binary with no external dependencies can be downloaded from
the [releases page](https://github.com/hugopl/invoicegenerator/releases).

To see an example the fastest possible way, run:

```
$ invoicegenerator --show-yml-example | invoicegenerator --stdin
```

To have a starting point to write your YAML describing your invoice, type:

```
$ invoicegenerator --show-yml-example > invoice.yml
```

Then edit the generated `invoice.yml` to match your data.

You can find an example of the generated PDF at [`examples/invoice.pdf`](examples/invoice.pdf).

## Invoice template

The invoice layout is built directly into the program. **Changing the template
is not currently supported.**

## What to write in the YAML file?

Run `invoicegenerator --show-yml-example` and you will see an example. The
supported fields are:

| Field            | Description                                      |
|------------------|--------------------------------------------------|
| `from`           | Your company name and address (block scalar)     |
| `client`         | Client name and address (block scalar)           |
| `invoice_number` | Invoice number string                            |
| `date`           | Invoice date (`YYYY-MM-DD`)                      |
| `due_date`       | Payment due date (`YYYY-MM-DD`)                  |
| `currency`       | Currency symbol (default: `$`)                   |
| `tax_rate`       | Tax rate as a decimal, e.g. `0.05` for 5%        |
| `output`         | Output PDF filename (default: `invoice.pdf`)     |
| `notes`          | Optional payment or bank transfer notes          |
| `items`          | List of line items (see below)                   |

The **first line** of `from` and `client` is treated as the entity name and
rendered more prominently; all subsequent lines are used as the address.

Each item under `items` has:

| Field         | Description                        |
|---------------|------------------------------------|
| `description` | Description of the service/product |
| `quantity`    | Quantity (integer)                 |
| `price`       | Unit price **in cents** (integer)  |

### Dynamic variables

Any field in the YAML file can include the following variables, which are
automatically substituted at generation time:

| Variable      | Replaced with                          |
|---------------|----------------------------------------|
| `$month`      | Current month (e.g. `October`)         |
| `$past_month` | Previous month (e.g. `September`)      |
| `$year`       | Current year (e.g. `2024`)             |

Example usage in your YAML:

```yaml
invoice_number: "INV-$year-007"
notes: |
  Services rendered for $past_month $year.
  Thank you for your business!
```

## Command-line options

All YAML fields can also be overridden via command-line flags. Run
`invoicegenerator --help` for the full list. CLI flags take precedence over YAML
values.

```
--from=TEXT            Issuing company (name + address, newline-separated)
--client=TEXT          Client info (name + address, newline-separated)
--invoice-number=TEXT  Invoice number
--date=YYYY-MM-DD      Invoice date
--due-date=YYYY-MM-DD  Due date
--currency=SYM         Currency symbol (default: $)
--tax-rate=RATE        Tax rate as decimal (e.g. 0.05)
--output=FILE          Output PDF path (overrides 'output' in YAML, default: invoice.pdf)
--file=FILE            YAML invoice data file (default: invoice.yml)
--stdin                Read YAML from STDIN instead of a file
--show-yml-example     Print an example YAML file and exit
```

## Building from source

You will need the [Crystal compiler](https://crystal-lang.org/install/) and
[shards](https://github.com/crystal-lang/shards) (bundled with Crystal).

### Install libharu

libharu is required at compile time when building from source.

| Distro                      | Command                              |
|-----------------------------|--------------------------------------|
| Debian / Ubuntu             | `sudo apt install libharu-dev`       |
| Fedora / RHEL               | `sudo dnf install libharu-devel`     |
| Arch Linux                  | `sudo pacman -S libharu`             |
| openSUSE                    | `sudo zypper install libharu-devel`  |

### Install DejaVu fonts

The generator uses DejaVu Sans to render text with broad Unicode support.

| Distro                      | Command                                    |
|-----------------------------|--------------------------------------------|
| Debian / Ubuntu             | `sudo apt install fonts-dejavu`            |
| Fedora / RHEL               | `sudo dnf install dejavu-sans-fonts`       |
| Arch Linux                  | `sudo pacman -S ttf-dejavu`                |
| openSUSE                    | `sudo zypper install dejavu-fonts`         |

### Compile

```
$ shards build --release
$ ./bin/invoicegenerator --help
```

## Third-party licenses

This binary embeds the [DejaVu Sans](https://dejavu-fonts.github.io/) fonts.
DejaVu fonts are derived from Bitstream Vera fonts, copyright © 2003 Bitstream, Inc.
DejaVu changes are in the public domain. The full license text is available at
<https://dejavu-fonts.github.io/License.html>.

## Contributing

1. Fork it (<https://github.com/hugopl/invoicegenerator/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Hugo Parente Lima](https://github.com/hugopl) - creator and maintainer
