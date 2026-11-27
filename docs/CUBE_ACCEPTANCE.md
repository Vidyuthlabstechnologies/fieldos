# Concrete cube acceptance (IS 456:2000)

How the Quality tab decides whether concrete complies. Read from the standard
itself (the scan at law.resource.org: clauses 15.4 and 16.1, Table 8 and
Table 11), not from memory. Code: `fieldos_mobile/lib/features/execution/cube_acceptance.dart`,
tests `cube_acceptance_test.dart` (worked by hand from the formulas) and
`cube_acceptance_screen_test.dart`.

## The rules

1. **A sample is three cubes** (clause 15.4). Its test result is their average.
   If a cube is more than **15%** from that average, the sample is **invalid**
   and must be cast again. The app asks for the three cubes when a 28-day
   result is recorded and refuses to save an invalid sample. (Typing only the
   average is still possible when the three values are not to hand.)
2. **Every sample** must reach **fck - 4 N/mm2** (M20 and above) or **fck - 3**
   (M15) (Table 11, column 3). This is the "Required" shown on a new 28-day
   cube, so the server's own pass/fail check enforces it.
3. **Every group of four consecutive samples** (not overlapping, in the order
   sampled, one grade at a time, clause 16.5) must have a mean of at least
   **fck + 0.825 x s, or fck + 4 (fck + 3 for M15), whichever is greater**
   (Table 11, column 2). *s* is the site's established standard deviation
   rounded to the nearest 0.5 N/mm2; until the site has 30 results, the value
   of **Table 8** is used: **3.5** (M10, M15), **4.0** (M20, M25), **5.0**
   (M30 and above).
4. The concrete complies when **both** 2 and 3 hold (clause 16.1). A group that
   is not yet four samples is not judged; the card says how many are in.

| Grade | One sample at least | Group of four, mean at least (s from Table 8) |
|---|---|---|
| M15 | 12 | 18 |
| M20 | 16 | 24 |
| M25 | 21 | 29 |
| M30 | 26 | 34.125 |
| M40 | 36 | 44.125 |

The 7 and 14 day cubes are **not** part of acceptance; the standard accepts
concrete on the 28-day result. A miss there shows as an amber *Below early
target*, a warning to watch.

## Limits to know

- Cubes made before this change keep the old 28-day requirement (the grade
  itself) on their row. The group check still uses their recorded result.
- The M15 individual limit (fck - 3) is faint in the scan; it follows the +3 /
  +4 split of column 2. Nobody on a G+12 tower is pouring M15.
- The site's own standard deviation is not entered anywhere yet; Table 8 is
  always used. Table 8's note adds 1 N/mm2 where site control is poor; that is
  not modelled either.
- Not built: the real crushing date, the lab and certificate number, a photo on
  the cube record, grades above M40, pour cards.
- Check the figures with the project's quality engineer before relying on them
  for an audit, and tell us if the standard or the client's specification
  differs (some clients specify stricter limits).
