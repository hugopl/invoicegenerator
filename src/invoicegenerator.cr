# UTF-8 support and memory font loading — not yet wrapped by hpdf.cr
# Need to add png and zlib link annotations to support static linking.
@[Link("png")]
@[Link("z")]
lib LibHaru
  fun use_utf_encodings = HPDF_UseUTFEncodings(doc : Doc) : UInt32
  fun load_tt_font_from_memory = HPDF_LoadTTFontFromMemory(doc : Doc, buffer : UInt8*, size : UInt32, embedding : Int32) : UInt8*
end

require "option_parser"
require "yaml"
require "hpdf"
require "./renderer"

# YAML file schema
struct InvoiceFile
  include YAML::Serializable

  getter from : String
  getter client : String
  getter invoice_number : String = Time.local.to_s("%Y%m01")

  @[YAML::Field(key: "date")]
  getter invoice_date : String = Time.local.to_s("%Y-%m-%d")

  getter due_date : String = (Time.local + 14.days).to_s("%Y-%m-%d")
  getter currency : String = "$"
  getter tax_rate : Float64? = nil
  getter notes : String = ""
  getter output : String = "invoice.pdf"
  getter items : Array(InvoiceItem)
end

# InvoiceItem
struct InvoiceItem
  include YAML::Serializable

  getter description : String
  getter quantity : Int32 = 1

  getter price : Int32 = 0 # cents

  # Total in cents
  def total : Int32
    @quantity * @price
  end
end

YAML_EXAMPLE = <<-YAML
from: | # First line is the company name, remaining lines are the address
  Your Company Inc.
  1234 Company St,
  Company Town, ST 12345
client: | # First line is the client name, remaining lines are the address
  Customer Name
  1234 Customer St,
  Customer Town, ST 12345
invoice_number: "0000007"
date: "2026-10-02"     # Default to now
due_date: "2023-10-16" # Default to 2 weeks from now
currency: "$"
tax_rate: 0.05         # 5% sales tax; omit or set to null for no tax
output: "invoice-$year-0000007.pdf" # Output PDF file path
notes: |
  Wire Transfer Details:
    Bank: First National Bank
items:
  - description: "Replacement of spark plugs"
    quantity: 1 # Default to 1 if omitted
    price: 4000
  - description: "Brake pad replacement (front)"
    quantity: 2
    price: 4000
YAML

# Parse a #RRGGBB hex string into a Float32 RGB tuple, or abort with an error.
def parse_hex_color(hex : String) : Color
  unless hex =~ /\A#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})\z/
    STDERR.puts "Error: invalid color '#{hex}', expected format #RRGGBB."
    exit 1
  end
  {$1.to_i(16) / 255.0_f32, $2.to_i(16) / 255.0_f32, $3.to_i(16) / 255.0_f32}
end

# parse_options

def parse_options
  from = "Your Company Inc.\n1234 Company St,\nCompany Town, ST 12345"
  client = "Customer Name\n1234 Customer St,\nCustomer Town, ST 12345"
  invoice_number = nil
  invoice_date = nil
  due_date = nil
  currency = nil
  tax_rate = nil
  output = nil
  color_accent = nil
  yaml_file = "invoice.yml"
  read_stdin = false

  OptionParser.parse do |p|
    p.banner = "Usage: invoicegenerator [options]"

    p.on("--from=TEXT", "Issuing company (name + address, newline-separated)") { |v| from = v }
    p.on("--client=TEXT", "Client info (name + address, newline-separated)") { |v| client = v }
    p.on("--invoice-number=TEXT", "Invoice number") { |v| invoice_number = v }
    p.on("--date=YYYY-MM-DD", "Invoice date (YYYY-MM-DD)") { |v| invoice_date = v }
    p.on("--due-date=YYYY-MM-DD", "Due date (YYYY-MM-DD)") { |v| due_date = v }
    p.on("--currency=SYM", "Currency symbol (default: $)") { |v| currency = v }
    p.on("--tax-rate=RATE", "Tax rate as decimal (e.g. 0.05); omit for no tax") { |v| tax_rate = v.to_f64 }
    p.on("--output=FILE", "Output PDF path (overrides 'output' in YAML, default: invoice.pdf)") { |v| output = v }
    p.on("--color-accent=#RRGGBB", "Accent color in #RRGGBB format (default: #BE6340)") { |v| color_accent = parse_hex_color(v) }
    p.on("--file=FILE", "YAML invoice data file (default: invoice.yml)") { |v| yaml_file = v }
    p.on("--stdin", "Read YAML from STDIN instead of a file") { read_stdin = true }
    p.on("--show-yml-example", "Print an example YAML invoice file and exit") { puts YAML_EXAMPLE; exit 0 }
    p.on("-h", "--help", "Show this help") { puts p; exit 0 }
  end

  {
    from:           from,
    client:         client,
    invoice_number: invoice_number,
    invoice_date:   invoice_date,
    due_date:       due_date,
    currency:       currency,
    tax_rate:       tax_rate,
    output:         output,
    color_accent:   color_accent,
    yaml_file:      yaml_file,
    read_stdin:     read_stdin,
  }
end

def expand_variables(text : String) : String
  now = Time.local
  past = now - 1.month

  text
    .gsub("$past_month", past.to_s("%B"))
    .gsub("$month", now.to_s("%B"))
    .gsub("$year", now.year.to_s)
end

def load_invoice_data(opts)
  yaml_source = if opts[:read_stdin]
                  STDIN.gets_to_end
                else
                  yaml_file = opts[:yaml_file]
                  unless File.exists?(yaml_file)
                    STDERR.puts "Error: YAML file '#{yaml_file}' not found."
                    exit 1
                  end
                  File.read(yaml_file)
                end

  yaml_source = expand_variables(yaml_source)

  invoice_file = InvoiceFile.from_yaml(yaml_source)

  # First line of from/client is the name, remaining lines are the address
  from_lines = invoice_file.from.lines.map(&.rstrip)
  client_lines = invoice_file.client.lines.map(&.rstrip)

  # CLI flags override YAML values when explicitly provided
  {
    from:           from_lines,
    client:         client_lines,
    invoice_number: opts[:invoice_number] || invoice_file.invoice_number,
    invoice_date:   opts[:invoice_date] || invoice_file.invoice_date,
    due_date:       opts[:due_date] || invoice_file.due_date,
    currency:       opts[:currency] || invoice_file.currency,
    tax_rate:       opts[:tax_rate] || invoice_file.tax_rate,
    output:         invoice_file.output,
    notes:          invoice_file.notes,
    items:          invoice_file.items,
  }
end

def main
  opts = parse_options
  data = load_invoice_data(opts)
  output = opts[:output] || data[:output]
  accent = opts[:color_accent] || COLOR_ACCENT
  render_pdf(data, output, accent)
  puts "Invoice saved to #{output}"
end

main
