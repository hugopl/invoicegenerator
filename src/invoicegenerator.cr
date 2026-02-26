# UTF-8 support and memory font loading — not yet wrapped by hpdf.cr
@[Link("png")]
@[Link("z")]
lib LibHaru
  fun use_utf_encodings = HPDF_UseUTFEncodings(doc : Doc) : UInt32
  fun load_tt_font_from_memory = HPDF_LoadTTFontFromMemory(doc : Doc, buffer : UInt8*, size : UInt32, embedding : Int32) : UInt8*
end

require "option_parser"
require "yaml"
require "hpdf"

# YAML file schema

struct InvoiceFile
  include YAML::Serializable

  getter from : String
  getter client : String
  getter invoice_number : String = "0000001"

  @[YAML::Field(key: "date")]
  getter invoice_date : String = Time.local.to_s("%Y-%m-%d")

  getter due_date : String = (Time.local + 14.days).to_s("%Y-%m-%d")
  getter currency : String = "$"
  getter tax_rate : Float64? = nil
  getter notes : String? = nil
  getter output : String = "invoice.pdf"
  getter items : Array(InvoiceItem)
end

# InvoiceItem

struct InvoiceItem
  include YAML::Serializable

  getter description : String
  getter quantity : Int32

  getter price : Int32 = 0 # cents

  # Total in cents
  def total : Int32
    @quantity * @price
  end
end

# Colors

alias Color = {Float32, Float32, Float32}

COLOR_ACCENT   = {0.0_f32, 0.0_f32, 0.0_f32}
COLOR_BLACK    = {0.13_f32, 0.13_f32, 0.13_f32}
COLOR_DARK     = {0.2_f32, 0.2_f32, 0.2_f32}
COLOR_MID_DARK = {0.25_f32, 0.25_f32, 0.25_f32}
COLOR_GREY     = {0.35_f32, 0.35_f32, 0.35_f32}
COLOR_LIGHT    = {0.65_f32, 0.65_f32, 0.65_f32}
COLOR_RULE     = {0.88_f32, 0.88_f32, 0.88_f32}
COLOR_WHITE    = {1.0_f32, 1.0_f32, 1.0_f32}

PAGE_W = 595.0_f32 # A4 page width in points
PAGE_H = 842.0_f32 # A4 page height in points
MARGIN =  48.0_f32 # Page margin on all sides

COL_R = PAGE_W - MARGIN # X coordinate of the right content boundary

# Vertical layout offsets from the top of the page
HEADING_OFFSET = 90.0_f32 # Distance from top_y down to the "INVOICE" heading
BILL_TO_OFFSET = 55.0_f32 # Distance from the heading down to the bill-to block
TABLE_GAP      = 20.0_f32 # Gap between the address blocks and the items table

# Row and cell geometry
ROW_HEIGHT      = 22.0_f32 # Height of each item row (and the table header)
META_ROW_HEIGHT = 18.0_f32 # Height of each invoice-meta row (number, date, due date)
SUM_ROW_HEIGHT  = 20.0_f32 # Height of each totals row (subtotal, tax, total)
HEADER_PADDING  =  6.0_f32 # Vertical padding inside the table header rectangle
CELL_PADDING    =  4.0_f32 # Horizontal padding inside table cells and at column edges
RULE_THICKNESS  =  0.5_f32 # Stroke width of horizontal rule lines

# Column X positions (right-aligned values are measured from these as a right edge)
META_LABEL_X  = 340.0_f32 # Left edge of the invoice-meta label column
SUM_LABEL_X   = 380.0_f32 # Left edge of the subtotal/tax/total label column
PRICE_RIGHT_X = 440.0_f32 # Right edge of the unit-price column
DESC_INDENT   =  50.0_f32 # Indent of the description column from MARGIN

# Font sizes
FONT_SIZE_HEADING      = 36 # "INVOICE" title
FONT_SIZE_COMPANY_NAME = 16 # Issuer company name
FONT_SIZE_CLIENT_NAME  = 20 # Client name in bill-to block
FONT_SIZE_TOTAL        = 11 # Total row label and amount
FONT_SIZE_BODY         = 10 # All regular body text

# Line spacing
LINE_HEIGHT       = 16.0_f32 # Vertical gap between address lines in the from block
LINE_HEIGHT_SMALL = 14.0_f32 # Vertical gap between lines in bill-to and notes blocks

# Miscellaneous spacing
NOTES_GAP  = 30.0_f32 # Vertical gap between the totals block and the notes block
TOTALS_GAP = 10.0_f32 # Vertical gap between the last item row and the subtotal line

YAML_EXAMPLE = <<-YAML
from: |
  Your Company Inc.
  1234 Company St,
  Company Town, ST 12345
client: |
  Customer Name
  1234 Customer St,
  Customer Town, ST 12345
invoice_number: "0000007"
date: "2023-10-02"
due_date: "2023-10-16"
currency: "$"
tax_rate: 0.05
output: "invoice-2023-0000007.pdf"
notes: |
  Wire Transfer Details:
    Bank: First National Bank
items:
  - description: "Replacement of spark plugs"
    quantity: 1
    price: 4000
  - description: "Brake pad replacement (front)"
    quantity: 2
    price: 4000
YAML

# Format cents as a US-format currency string: 10050 → "$100.50"
def money(cents : Int32, currency : String = "$") : String
  "#{currency}#{plain_money(cents)}"
end

# Format cents as a US-format plain decimal: 10050 → "100.50"
def plain_money(cents : Int32) : String
  (cents / 100.0).format(separator: '.', delimiter: ',', decimal_places: 2, group: 3)
end

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

# expand_variables: replace $month, $past_month and $year in any string value
# with the current month name, the previous month name, and the current year.

def expand_variables(text : String) : String
  now = Time.local
  past = now - 1.month

  text
    .gsub("$past_month", past.to_s("%B"))
    .gsub("$month", now.to_s("%B"))
    .gsub("$year", now.year.to_s)
end

# load_invoice_data

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

  # Notes: split block-scalar string into individual lines
  notes = invoice_file.notes.try(&.lines.map(&.rstrip)) || [] of String

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
    notes:          notes,
    items:          invoice_file.items,
  }
end

# Font bytes embedded at compile time from the source tree — no files needed at runtime.
FONT_REGULAR_DATA = {{ read_file("fonts/DejaVuSans.ttf") }}.bytes
FONT_BOLD_DATA    = {{ read_file("fonts/DejaVuSans-Bold.ttf") }}.bytes

# Font pair (regular + bold) as LibHaru::Font handles loaded with UTF-8 encoding
record Fonts, regular : LibHaru::Font, bold : LibHaru::Font

# Render text at (x, y) using the given font and size, with full UTF-8 support.
# Bypasses page.text which re-fetches the font without the UTF-8 encoder.
def utf8_text(page, font : LibHaru::Font, size : Int32, x : Float32, y : Float32, str : String)
  LibHaru.page_set_font_and_size(page, font, size.to_f32)
  LibHaru.page_begin_text(page)
  LibHaru.page_text_out(page, x, y, str)
  LibHaru.page_end_text(page)
end

def utf8_text_width(page, font : LibHaru::Font, size : Int32, str : String) : Float32
  LibHaru.page_set_font_and_size(page, font, size.to_f32)
  LibHaru.page_text_width(page, str)
end

# render helpers

def fill_with_background_color(page, accent : Color)
  page.set_rgb_fill(*accent)
end

# render_top_section: company info (left) + logo box (right)
# Returns the bottom Y of the from-address block so callers can avoid overlap.
def render_top_section(page, fonts : Fonts, from : Array(String), top_y : Float32, accent : Color) : Float32
  name = from[0]? || ""
  address_lines = from[1..]? || [] of String

  page.set_rgb_fill(*COLOR_BLACK)
  utf8_text(page, fonts.bold, FONT_SIZE_COMPANY_NAME, MARGIN, top_y, name)
  page.set_rgb_fill(*COLOR_GREY)
  address_lines.each_with_index do |line, i|
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, MARGIN, top_y - ROW_HEIGHT - i * LINE_HEIGHT, line)
  end

  # Bottom of the from block: baseline of last address line minus one line-height clearance
  from_bottom = top_y - ROW_HEIGHT - address_lines.size * LINE_HEIGHT

  # Logo placeholder box
  # logo_x = 360.0_f32
  # logo_y = top_y - 44.0_f32
  # logo_w = 175.0_f32
  # logo_h = 58.0_f32
  #
  # page.set_rgb_stroke(*COLOR_ACCENT)
  # page.set_rgb_fill(*COLOR_WHITE)
  # page.rectangle logo_x, logo_y, logo_w, logo_h
  # page.fill_stroke
  #
  # fill_with_background_color(page)
  # utf8_text(page, fonts.bold, 14, logo_x + logo_w / 2 - 18.0_f32, logo_y + logo_h / 2 - 5.0_f32, "LOGO")

  from_bottom
end

# render_invoice_heading: large "INVOICE" title
def render_invoice_heading(page, fonts : Fonts, inv_y : Float32, accent : Color)
  fill_with_background_color(page, accent)
  utf8_text(page, fonts.bold, FONT_SIZE_HEADING, COL_R - 165.0_f32, inv_y, "INVOICE")
end

# render_bill_to: client info + invoice meta — returns bottom Y of the client block
def render_bill_to(page, fonts : Fonts, client : Array(String), invoice_number : String, invoice_date : String, due_date : String, bill_y : Float32, accent : Color) : Float32
  client_name = client[0]? || ""
  client_address_lines = client[1..]? || [] of String

  fill_with_background_color(page, accent)
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, MARGIN, bill_y, "Bill To")

  page.set_rgb_fill(*COLOR_BLACK)
  utf8_text(page, fonts.bold, FONT_SIZE_CLIENT_NAME, MARGIN, bill_y - ROW_HEIGHT, client_name)

  page.set_rgb_fill(*COLOR_GREY)
  client_address_lines.each_with_index do |line, i|
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, MARGIN, bill_y - 42.0_f32 - i * LINE_HEIGHT_SMALL, line)
  end

  # Bottom of the client address block
  bill_bottom = bill_y - 42.0_f32 - client_address_lines.size * LINE_HEIGHT_SMALL

  meta_label_x = META_LABEL_X
  meta_value_x = COL_R - 20.0_f32
  meta_row_h = META_ROW_HEIGHT
  meta_y = bill_y - LINE_HEIGHT

  {
    {"Invoice #", invoice_number},
    {"Invoice date", invoice_date},
    {"Due date", due_date},
  }.each_with_index do |(label, value), i|
    row = meta_y - i * meta_row_h

    fill_with_background_color(page, accent)
    utf8_text(page, fonts.bold, FONT_SIZE_BODY, meta_label_x, row, label)

    page.set_rgb_fill(*COLOR_BLACK)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, meta_value_x - utf8_text_width(page, fonts.regular, FONT_SIZE_BODY, value), row, value)
  end

  # Meta block ends after 3 rows; return whichever block is lower
  meta_bottom = meta_y - 2 * meta_row_h
  {bill_bottom, meta_bottom}.min
end

# render_table: items table with header and rows
def render_table(page, fonts : Fonts, items : Array(InvoiceItem), currency : String, tbl_top : Float32, accent : Color) : Float32
  # Header background
  fill_with_background_color(page, accent)
  page.rectangle MARGIN, tbl_top - HEADER_PADDING, PAGE_W - MARGIN * 2, ROW_HEIGHT
  page.fill

  price_right_x = PRICE_RIGHT_X
  amount_right_x = COL_R - CELL_PADDING

  # Header labels
  page.set_rgb_fill(*COLOR_WHITE)
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, MARGIN + CELL_PADDING, tbl_top, "QTY")
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, MARGIN + DESC_INDENT, tbl_top, "Description")
  # Right-align "Price" header
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, price_right_x - utf8_text_width(page, fonts.bold, FONT_SIZE_BODY, "Price"), tbl_top, "Price")
  # Right-align "Amount" header
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, amount_right_x - utf8_text_width(page, fonts.bold, FONT_SIZE_BODY, "Amount"), tbl_top, "Amount")

  row_y = tbl_top - ROW_HEIGHT
  row_h = ROW_HEIGHT

  items.each do |item|
    # Row separator
    page.set_rgb_fill(*COLOR_RULE)
    page.rectangle MARGIN, row_y - 2.0_f32, PAGE_W - MARGIN * 2, RULE_THICKNESS
    page.fill

    page.set_rgb_fill(*COLOR_DARK)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, MARGIN + CELL_PADDING, row_y, item.quantity.to_s)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, MARGIN + DESC_INDENT, row_y, item.description)
    # Right-align price value
    s = plain_money(item.price)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, price_right_x - utf8_text_width(page, fonts.regular, FONT_SIZE_BODY, s), row_y, s)
    # Right-align amount value
    s = money(item.total, currency)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, amount_right_x - utf8_text_width(page, fonts.regular, FONT_SIZE_BODY, s), row_y, s)

    row_y -= row_h
  end

  row_y
end

# render_totals: subtotal, optional tax, total
def render_totals(page, fonts : Fonts, items : Array(InvoiceItem), tax_rate : Float64?, currency : String, row_y : Float32, accent : Color) : Float32
  subtotal_cents = items.sum(&.total)
  tax_cents = tax_rate ? (subtotal_cents * tax_rate).round.to_i : 0
  total_cents = subtotal_cents + tax_cents

  sum_label_x = SUM_LABEL_X
  sum_value_x = COL_R - CELL_PADDING
  sum_y = row_y - TOTALS_GAP
  sum_row_h = SUM_ROW_HEIGHT

  page.set_rgb_fill(*COLOR_MID_DARK)
  utf8_text(page, fonts.regular, FONT_SIZE_BODY, sum_label_x, sum_y, "Subtotal")
  s = money(subtotal_cents, currency)
  utf8_text(page, fonts.regular, FONT_SIZE_BODY, sum_value_x - utf8_text_width(page, fonts.regular, FONT_SIZE_BODY, s), sum_y, s)

  next_y = sum_y

  # Only render sales tax row if tax_rate is set
  if tax_rate
    tax_pct = "#{(tax_rate * 100).to_i}%"
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, sum_label_x, sum_y - sum_row_h, "Sales Tax (#{tax_pct})")
    s = money(tax_cents, currency)
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, sum_value_x - utf8_text_width(page, fonts.regular, FONT_SIZE_BODY, s), sum_y - sum_row_h, s)
    next_y = sum_y - sum_row_h
  end

  div_y = next_y - sum_row_h + HEADER_PADDING
  page.set_rgb_fill(*COLOR_LIGHT)
  page.rectangle sum_label_x - 10.0_f32, div_y, COL_R - sum_label_x + 10.0_f32, RULE_THICKNESS
  page.fill

  total_y = div_y - LINE_HEIGHT
  fill_with_background_color(page, accent)
  utf8_text(page, fonts.bold, FONT_SIZE_TOTAL, sum_label_x, total_y, "Total (#{currency})")
  s = money(total_cents, currency)
  utf8_text(page, fonts.bold, FONT_SIZE_TOTAL, sum_value_x - utf8_text_width(page, fonts.bold, FONT_SIZE_TOTAL, s), total_y, s)

  page.set_rgb_fill(*COLOR_LIGHT)
  page.rectangle sum_label_x - 10.0_f32, total_y - HEADER_PADDING, COL_R - sum_label_x + 10.0_f32, RULE_THICKNESS
  page.fill

  total_y
end

# render_notes: optional notes block
def render_notes(page, fonts : Fonts, notes : Array(String), total_y : Float32, accent : Color)
  return if notes.empty?

  notes_y = total_y - NOTES_GAP

  fill_with_background_color(page, accent)
  utf8_text(page, fonts.bold, FONT_SIZE_BODY, MARGIN, notes_y, "Notes")

  page.set_rgb_fill(*COLOR_MID_DARK)
  notes.each_with_index do |line, i|
    utf8_text(page, fonts.regular, FONT_SIZE_BODY, MARGIN, notes_y - LINE_HEIGHT - i * LINE_HEIGHT_SMALL, line)
  end
end

# render_pdf

def render_pdf(data, output : String, accent : Color) : Nil
  from = data[:from]
  client = data[:client]
  invoice_number = data[:invoice_number]
  invoice_date = data[:invoice_date]
  due_date = data[:due_date]
  currency = data[:currency]
  tax_rate = data[:tax_rate]
  notes = data[:notes]
  items = data[:items]

  pdf = Hpdf::Doc.build do |doc|
    # Enable UTF-8 text support (must be called before loading TTF fonts)
    LibHaru.use_utf_encodings(doc)
    LibHaru.set_current_encoder(doc, "UTF-8")

    # Load DejaVu Sans fonts from the bytes embedded at compile time.
    # Covers full Latin, Latin Extended, Greek, Cyrillic and many other scripts.
    regular_name = LibHaru.load_tt_font_from_memory(doc, FONT_REGULAR_DATA, FONT_REGULAR_DATA.size.to_u32, 1)
    bold_name = LibHaru.load_tt_font_from_memory(doc, FONT_BOLD_DATA, FONT_BOLD_DATA.size.to_u32, 1)

    # Fetch font handles explicitly with "UTF-8" encoding so libharu renders
    # multi-byte characters correctly instead of treating them as Latin-1 bytes.
    regular_font = LibHaru.get_font(doc, regular_name, "UTF-8")
    bold_font = LibHaru.get_font(doc, bold_name, "UTF-8")
    fonts = Fonts.new(regular: regular_font, bold: bold_font)

    page do |pg|
      top_y = PAGE_H - MARGIN

      from_bottom = render_top_section(pg, fonts, from, top_y, accent)

      inv_y = top_y - HEADING_OFFSET
      render_invoice_heading(pg, fonts, inv_y, accent)

      bill_y = inv_y - BILL_TO_OFFSET
      bill_bottom = render_bill_to(pg, fonts, client, invoice_number, invoice_date, due_date, bill_y, accent)

      # Start the table below whichever block (from-address or bill-to) reaches lower,
      # plus a small gap. Lower on the page = smaller Y in PDF coordinates.
      tbl_top = {from_bottom, bill_bottom}.min - TABLE_GAP
      row_y = render_table(pg, fonts, items, currency, tbl_top, accent)

      total_y = render_totals(pg, fonts, items, tax_rate, currency, row_y, accent)

      render_notes(pg, fonts, notes, total_y, accent)
    end
  end

  pdf.save_to_file output
  puts "Invoice saved to #{output}"
end

# main

def main
  opts = parse_options
  data = load_invoice_data(opts)
  output = opts[:output] || data[:output]
  accent = opts[:color_accent] || COLOR_ACCENT
  render_pdf(data, output, accent)
end

main
