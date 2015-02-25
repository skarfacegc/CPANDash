# CPANDash
Code to create a CPAN docset for Dash.app

Downloads all available (as far as I can tell) CPAN documentation and creates the appropriate database for Dash.app

usage:
- run getPods.pl
   - Generates the database
   - Downloads the pod documentation
- run publish.sh
   - Moves the database and pod documentation into place uder CPAN.docset

- First full run done  (2105-02-24)
   - Seems to work fine.
   - Not really possible to check every possible doc  :)
- Docset size is 1.2G
- 140086 total stored docs
   - Skipped 51210 packages because the API didn't return any PODs
