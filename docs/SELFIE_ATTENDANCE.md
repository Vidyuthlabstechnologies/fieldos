# Selfie and geofence attendance

Two kinds of attendance, both stamped with a photo and a GPS fix.

## Labour punches (site supervisor marks workers)

- Punch in and Mark many take an optional photo: the worker, or one photo
  of the whole morning roll call that stands for everyone punched in
  together (`site_attendance.photo_id`).
- Each punch keeps how far from the site's centre it was (`distance_m`).
  The "Punches away from site" report shows the distance and whether a
  photo was taken.

## Staff check-in (each person marks their own day)

- Home menu, **My attendance**: the nearest site with a location is chosen
  from the GPS fix, then **Check in with selfie** opens the front camera
  (camera only, no gallery) and stamps time, site and GPS on the photo.
- Inside the site's geofence the day counts at once (`ok`). Outside it,
  with no GPS fix, or at a site with no location set, the person must say
  where they are and why, and the day waits (`pending`).
- **Check out with selfie** closes the day; one check-in per person per
  site per day.
- Home menu, **Staff attendance** (owners and project managers): Today,
  Waiting (approve or turn down, with a note they see), and Month (days at
  work per person). Nobody approves their own day.
- **Staff salaries**: link a salary to the person's FieldOS login. The
  payslip then offers "From attendance: N days at work + S Sundays off"
  with a one-tap **Use** for the paid days. Nothing is changed without
  that tap.
- Reports: **Staff check-ins** and **Staff days at work** (managers only).

## Server rules (`20261110430000_selfie_attendance.sql`)

- `attendance_photos`: read and added by the site's team, never edited;
  files in the documents bucket at `{project_id}/attendance/{id}.jpg`,
  under the existing site storage policies.
- `staff_attendance`: the server sets `user_id` to the signed-in person and
  works out the distance and "inside" again from the coordinates and the
  site's location, so a changed app cannot mark itself inside or approved.
  Check-in fields are kept as made; only the person checks themselves out;
  only an owner or project manager decides, never on their own day.
  People read their own days; owners and project managers read everyone's.
- `staff_members.user_id`: one salary per login in a company.
- New fields on existing payloads (`photo_id`, `distance_m`, `accuracy_m`,
  `user_id` on staff) are only sent when set, so punches keep syncing to a
  server that has not had this migration yet.

## Tests

`test/staff_attendance_test.dart`, `test/attendance_screens_test.dart`,
`test/schema_v24_upgrade_test.dart`, `test/staff_attendance_cloud_test.dart`
(against the local Supabase stack).
