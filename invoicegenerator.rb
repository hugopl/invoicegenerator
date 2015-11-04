#!/usr/bin/env ruby

require 'pdfkit'
require 'yaml'
require 'trollop'
require 'date'
require 'money'
I18n.enforce_available_locales = false

def show_yml_example_and_exit
  puts <<eot
from: |
  My multiline name
  Here's a second line
client: |
  My multiline client
  Hey ho, second line here
notes: |
  If all your data are always the same, just the invoice number changes,
  save the the static data in a yml and pass the invoice number on command line
  by using (--number).

  Note that the date is always default to today, and the due-date to today + 15
items:
  -
    - Nice item for %past_month% %year%
    - 1
    - 12334
  -
    - Other item, for %month%
    - 0.5
    - 100000
currency: GBP
eot
  exit
end

def map_date_fields(opts)
  [:date, 'due-date'].each do |i|
    opts[i] = yield(opts[i])
  end
end

def read_params
  Trollop.options do
    opt :client,            'Contents of client field.', type: :string
    opt :currency,          'Currency used.', type: :string, default: 'USD'
    opt :date,              'Invoice date.', type: :date, default: Date.today
    opt 'due-date',         'Due date.', type: :date, default: (Date.today + 15)
    opt :from,              'Contents of from field.', type: :string
    opt :header,            'Contents of the header.', type: :string, default: 'Invoice'
    opt :notes,             'Contents of notes field.', type: :string
    opt :number,            'Invoice number.', type: :string
    opt 'show-yml-example', 'Show a example of a YML file that can be used by this script.'
    opt :yml,               'YML file with values for parameters not given into command line.', default: 'invoice.yml'
  end
end

def read_yml(opts)
  yaml = YAML.load(File.read(opts[:yml]))
  yaml.inject(opts) do |memo, item|
    memo[item[0].to_sym] = item[1]
    memo
  end
  fail('Items not in the right format, something is missing.') unless opts[:items].is_a?(Array)
  opts
rescue Errno::ENOENT
  raise "YML file #{opts[:yml]} not found or can't be read."
end

def fix_date_options(opts)
  map_date_fields(opts) do |value|
    value.is_a?(Date) ? value : Date.parse(value)
  end
end

def add_extra_options(opts)
  today = Date.today
  opts[:month] = today.strftime('%B')
  opts[:past_month] = (today << 1).strftime('%B')
  opts[:year] = today.strftime('%Y')

  raw_balance = opts[:items].inject(0) do |balance, item|
    balance + (item[2] * item[1])
  end
  opts[:balance] = Money.new(raw_balance, opts[:currency]).format
end

def format_items(opts)
  opts[:items].map! do |i|
    fail 'Items must have 3 values' if i.size != 3

    i[3] = Money.new(i[2] * i[1], opts[:currency]).format
    i[2] = Money.new(i[2], opts[:currency]).format
    "<tr><td>#{i.join('</td><td>')}</td></tr>"
  end
  opts[:items] = opts[:items].join
end

def generate_html(opts)
  map_date_fields(opts) do |value|
    value.strftime('%B %-d, %Y')
  end

  html = File.read('invoicegenerator.html')

  opts.each do |opt, value|
    html.gsub!("%#{opt}%", value.to_s)
  end
  html
end

def main
  opts = read_params
  show_yml_example_and_exit if opts[:'show-yml-example_given']

  read_yml(opts)
  fix_date_options(opts)
  add_extra_options(opts)
  format_items(opts)
  html = generate_html(opts)

  kit = PDFKit.new(html.encode('iso-8859-1'))
  name = "invoice-#{opts[:number]}.pdf"
  puts "Generating #{name}..."
  kit.to_file(name)
rescue
  abort $!.message
end

main
