# Dropzones Scraper

This is a web scraper written in node.js that uses puppeteer to gather data on USPA dropzones.

You should never need to run this since all the data is contained in the parent directory's `dropzones.geojson` file.

To get started, run `yarn` and then `yarn scrape`. This will create (or overwrite) a `dropzones.geojson` file in the parent directory.

This may break ion the future based on changes to the USPA website.