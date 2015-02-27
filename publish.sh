#!/bin/zsh

# Clean out old files
rm -rf CPAN.docset/Contents/Resources/Documents/*(/)
rm CPAN.docset/Contents/Resources/docSet.dsidx

# Move new files into place
mv HTMLDocs/* CPAN.docset/Contents/Resources/Documents
mv poddb.sqlite CPAN.docset/Contents/Resources/docSet.dsidx
