-- A supplier's opening balance (app schema v13): what the company owed
-- them, or the advance they held, when it started using FieldOS, so the
-- party balance is right from day one. Onsite's reviews ask for "opening
-- balance of party" and "advance given to supplier". Nullable, so older
-- app versions keep inserting as before; changing it follows the existing
-- owner/PM update policy on vendors.

alter table vendors
  add column if not exists opening_balance numeric(14, 2)
    check (opening_balance between -99999999999 and 99999999999);
