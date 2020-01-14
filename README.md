# Stupid invoice generator

Put the data you usualy uses to create your invoices into a YML file, run this
gem and done, you have a nice pdf invoice

To see an example the fast possible way run:

```
$ gem install invoicegenerator
$ invoicegenerator --show-yml-example | invoicegenerator --stdin
```

To have a starting point to write your YAML describing your invoice, type:

```
$ invoicegenerator --show-yml-example > invoice.yml
```

Then change the generated invoice.yml

## How to change the invoice template?

Use the --template command line switch to specify an HTML template, to have a look in a example, type:

```
$ invoicegenerator --show-template-example
```

## What to write in the YAML file?

Run `invoicegenerator.rb --show-yml-example` and you will see an example, basically you can use all keys you find as a command line option.

## I got an error while running the example!

```
Generating invoice-2019-123.pdf...
No such file or directory @ rb_file_s_size - invoice-2019-123.pdf
```

This is a [PDFKit issue](https://github.com/pdfkit/pdfkit/issues/380#issuecomment-421269690), install libXrender package on your distro and the issue should be fixed.
