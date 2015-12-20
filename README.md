python-library-populator
========================

Creates a Document Collection file for the Python standard library

This project serves an example of how to create a Document Collection in Solve for All.
It is the source of the Python Library Documentation Semantic Data Collection.

Usage:
  ruby main.rb DOC_DIR

where DOC_DIR is the path to the uncompressed Python documentation in HTML format, like ~/docs/python-3.5.1-docs-html.
You can download the documentation here: https://docs.python.org/3/download.html

In your current directory, python-doc.json.bz2 will be created and you can upload it to a Semantic Collection in solveforall.com
See https://solveforall.com/docs/developer/semantic_data_collection for more info.

License

This project is licensed with the Apache License, Version 2.0. See LICENSE.
  
