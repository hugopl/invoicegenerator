# Stupid invoice generator

Put the data you usualy uses to create your invoices into a YML file, run this script and done, you have a nice pdf invoice

## Install

It's not a gem because I'm too lazy to create a gem just for that. so to use this script you should.

  1. Clone this repository.
  2. Execute `bundle`, so all dependencies will be installed (pdfkit, trollop, money).
  3. run `./invoicegenerator.rb --help`, from now on you should know what to do.

## How to change the invoice template?

Just edit the html file.

## What to write in the YAML file?

Run `./invoicegenerator.rb --help` and you will see an example, basically you cna use all keys you find as a command line option.
