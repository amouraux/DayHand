# DayHand App Store creative

`dayhand-universal.png`: 5244 × 2950 PNG, English artwork, for the 16:9 row of Apple's Product page header and Search results placements (opaque, no alpha). Generated with the built-in image generation tool, then resampled to that size. Check both placements using App Store Connect Preview before submission; this is conceptual brand artwork, not an app screenshot.

Apple specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications

## Generation prompt

Use case: ads-marketing.
Create polished App Store universal creative artwork for DayHand, a personal task manager. Landscape 16:9 composition, highest available resolution. Reference image is the app icon: use its soft sculptural white cards, blue, warm gold and indigo palette, rounded edges and delicate shadows as visual style inspiration; do not simply enlarge the square icon.
Design a beautiful restrained editorial product illustration on a luminous very pale blue-white backdrop. Central composition: to the left a clear large dark navy typographic headline on two lines, exactly "Tasks beyond" and "the calendar". A small "DayHand" wordmark above. To the right a beautifully arranged fan of three dimensional rounded task cards, white foreground card with a vivid blue circular checkmark and two subtle blue-gray lines, warm golden card behind, indigo card behind that. Subtle sun and crescent details echo the original icon. This symbolizes work that continues across days. No calendar grids, dates, urgency badges, fake screenshots, phones, extra logos or tiny text.
All important typography and artwork must fit within central 70% width and central 48% height of canvas so a very wide horizontal header crop and a narrower search crop both retain entire message and focal artwork. Outside this central band only soft atmospheric pale gradients and gentle shadows; no objects near edges. Strong readable typography at thumbnail size, generous spacing, sophisticated luminous materials, calm clarity rather than toy-like plastic. No borders, no transparency, no watermark, no prices. Output a single finished image, not a mockup sheet.

## Review notes

Checked against Apple's creative asset specification (opaque PNG or JPEG, no alpha):

- `dayhand-universal.png` is 5244 × 2950, the 16:9 row for the product page
  header and for search results. It is brand artwork with no interface in it, so
  nothing in it can misdescribe the app. Check it in App Store Connect's preview:
  the header crops it wide.
- `dayhand-search-results.png` is 1920 × 1280, the 3:2 minimum for search
  results, but **do not submit it as it is**. It is an image-generation
  composition of an old screenshot, not a screenshot: the tasks and the October
  dates are from the demo data of the time, the task panel runs off the bottom
  edge with its last row cut, and the text was redrawn rather than copied, so
  nothing guarantees it matches the shipping interface. A search result must
  show the app as it is. Rebuild it from a current simulator screenshot (one
  task in each of Now, Next, Later and Waiting fits on one phone screen), set
  by script rather than generated, and keep the headline "A place for every
  task." beside it.
