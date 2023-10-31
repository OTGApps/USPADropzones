import puppeteer from "puppeteer";
import fs from "fs";
import DropzonesJSONSource from "./dz_list.json" assert { type: "json" };
import DropzonesGeoJSON from "../dropzones.geojson" assert { type: "json" };

const DELAY_BETWEEN_REQUESTS = 1000;

const browser = await puppeteer.launch({
  headless: false,
  defaultViewport: null,
});
const page = await browser.newPage();
await page.setUserAgent(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
);

const getDZDetails = async (dzId) => {
  await page.goto(`https://www.uspa.org/DZdetails?accountnumber=${dzId}`, {
    waitUntil: "networkidle0",
  });

  const dzNameHandle = await page.$(".ng-scope h2");
  const dzName = await page.evaluate((selector) => selector.innerHTML, dzNameHandle);

  const planesHandle = await page.$("i.fa-plane");
  const planes = await page.evaluate(
    (selector) => selector.parentElement.textContent.trim(),
    planesHandle
  );

  const websiteHandle = await page.$("i.fa-external-link");
  const website = await page.evaluate(
    (selector) => selector.parentElement.textContent.trim(),
    websiteHandle
  );

  const descriptionHandle = await page.$("hr");
  let description = "";
  try {
    description = await page.evaluate(
      (selector) => selector.nextElementSibling.textContent.trim(),
      descriptionHandle
    );
    if (description === "") {
      description = await page.evaluate(
        (selector) => selector.nextElementSibling.nextElementSibling.textContent.trim(),
        descriptionHandle
      );
    }
  } catch (error) {
    console.log("WARNING: Could not get description");
  }

  // Get Amenities
  const checkedAmenities = await page.$$eval(
    "checkbox-tree-view[name='p_Amenities'] input[type='checkbox']",
    (checks) =>
      checks.map((check) => {
        if (check.checked) {
          return check.getAttribute("value");
        }
      })
  );
  const amenities = checkedAmenities.filter(function (el) {
    return el != null;
  });

  // Get Training Programs
  const checkedTrainingPrograms = await page.$$eval(
    "checkbox-tree-view[name='p_TrainingPrograms'] input[type='checkbox']",
    (checks) =>
      checks.map((check) => {
        if (check.checked) {
          return check.getAttribute("value");
        }
      })
  );
  const trainingPrograms = checkedTrainingPrograms.filter(function (el) {
    return el != null;
  });

  console.log({ dzName, planes, description, amenities, trainingPrograms, website });
  return { dzName, planes, description, amenities, trainingPrograms, website };
};

// const dzGeoJSON = {
//   type: "FeatureCollection",
//   features: [],
// };

// await getDZDetails(101662);
// exit(1);

const alreadyScrapedIds = DropzonesGeoJSON.features.map((dz) => dz.properties.anchor);

// Read in the dropzones json object and loop over it to get all the data
for await (const dzJSON of DropzonesJSONSource) {
  if (alreadyScrapedIds.includes(dzJSON.Id)) {
    console.log(`Skipping ${dzJSON.Id}: ${dzJSON.AccountName} because it has already been scraped`);
    continue;
  }

  console.log(`Scraping data for: ${dzJSON.Id}: ${dzJSON.AccountName}`);
  await delay(DELAY_BETWEEN_REQUESTS);
  const dzDetails = await getDZDetails(dzJSON.Id);

  const dzDataToAdd = {
    type: "Feature",
    properties: {
      aircraft: dzDetails.planes,
      anchor: dzJSON.Id,
      description: dzDetails.description,
      email: dzJSON.Email,
      location: [dzJSON.PhysicalCity, dzJSON.PhysicalState, dzJSON.PhysicalCountry]
        .filter((loc) => loc !== "")
        .map((loc) => toTitleCase(loc.trim()))
        .join(", "),
      name: dzJSON.AccountName,
      phone: dzJSON.PhoneDZ,
      training: dzDetails.trainingPrograms,
      services: dzDetails.amenities,
      website: dzDetails.website,
      airportName: dzJSON.AirportName,
    },
    geometry: {
      type: "Point",
      coordinates: [dzJSON.Longitude, dzJSON.Latitude],
    },
  };

  DropzonesGeoJSON.features.push(dzDataToAdd);

  // Write to the geojson file within the loop:
  fs.writeFile("../dropzones.geojson", JSON.stringify(DropzonesGeoJSON, null, 2), function (err) {
    if (err) {
      console.log(err);
    }
  });
}

// Close the browser
await browser.close();

// Once we have all the data in the object, write out the geojson file:
fs.writeFile("../dropzones.geojson", JSON.stringify(DropzonesGeoJSON, null, 2), function (err) {
  console.log(err);
});

function delay(time) {
  return new Promise(function (resolve) {
    setTimeout(resolve, time);
  });
}

function toTitleCase(str) {
  return str.replace(/\w\S*/g, function (txt) {
    return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();
  });
}
