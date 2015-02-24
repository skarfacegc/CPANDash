# CPANDash
Code to create a CPAN docset for Dash.app

Downloads all available (as far as I can tell) CPAN documentation and creates the appropriate database for Dash.app

usage:
- run getPods.pl
   - Generates the database
   - Downloads the pod documentation
- run publish.sh
   - Moves the database and pod documentation into place uder CPAN.docset


