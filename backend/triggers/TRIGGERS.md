# trigger notes

All triggers live in this folder, one file per topic, and `install.sql` installs them.
`backend/schema/table.sql` only creates the tables. Source the three files from the
project root, in this order:

```sql
SOURCE backend/schema/table.sql;     -- tables
SOURCE backend/triggers/install.sql; -- 25 triggers + 2 procedures
SOURCE backend/seed/seed.sql;        -- demo data
```

`table.sql` rebuilds the application tables (including login accounts and sessions).
`install.sql` sources the five trigger files below; each one drops its triggers before
recreating them, so it can be re-run at any time without touching data. Install the
triggers before seeding, so the demo data is checked and priced by them.
`seed.sql` inserts the fictional demo records. Re-sourcing all three resets the demo.
All seeded login passwords are `demo123`.

| file                  | triggers                                                                |
| --------------------- | ----------------------------------------------------------------------- |
| `employee.sql`        | `check_employee_role` procedure, 10 subclass role checks, role lock, `onboard_employee` procedure |
| `date_validation.sql` | employee dates, patient DOB, prescription dates                         |
| `prescription.sql`    | prescription-detail price and freeze rules, billed prescription delete  |
| `billing.sql`         | bill calculation and freeze                                             |
| `appointment.sql`     | active-doctor and no-cancel-after-billing rules                         |

Technician and Admission triggers were removed because those tables are no longer in the schema.

## rules

| area                      | trigger(s)                                                          | what they do                                                                                                                                                                                                              |
| ------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| employee role             | `check_employee_role`, `trg_*_role_bi`, `trg_*_role_bu`             | Check that an employee's `Role` matches the subclass table they are inserted into or updated in.                                                                                                                          |
| employee role changes     | `trg_employee_role_lock`                                            | Stops a role change while the employee still has a row in any subclass table. Remove the old subclass row before changing the role.                                                                                       |
| employee dates            | `trg_employee_dates_bi`, `trg_employee_dates_bu`                    | Reject a DOB that is today or later, a joining date in the future, or a joining age below 18.                                                                                                                             |
| prescription details      | `trg_pres_details_bi`, `trg_pres_details_bu`, `trg_pres_details_bd` | Save the current medicine price in `Unit_price` and block adding, editing, or deleting details once the prescription has been billed.                                                                                     |
| prescription dates        | `trg_prescription_bi`, `trg_prescription_bu`                        | Reject a prescription date earlier than its appointment date.                                                                                                                                                             |
| prescription deletion     | `trg_prescription_bd`                                               | Prevent deleting a prescription that has a bill. This also protects its detail rows from being removed through the foreign-key cascade.                                                                                   |
| bill creation and updates | `trg_bill_bi`, `trg_bill_bu`                                        | Calculate the bill from the consultation fee and stored medicine prices. Later edits cannot change the fee or total, and the bill cannot be moved to another appointment. The bill date must not precede the appointment. |
| patient DOB               | `trg_patient_dob_bi`, `trg_patient_dob_bu`                          | Reject a patient DOB in the future. A DOB equal to today is allowed.                                                                                                                                                      |

Together the files define 25 triggers and two procedures: the helper `check_employee_role`, and `onboard_employee`, the employee onboarding transaction. The five subclass role checks each have an insert and update trigger.

## bill calculation

The bill total is:

```text
Bill_amount = Consultation_fee + SUM(Quantity * Unit_price)
```

`Unit_price` is captured when a prescription line is added. Later changes to `Medicine.Price` do not change that stored price or the amount on an issued bill. Appointments without a prescription can still be billed for the consultation fee.

## notes

- Appointment double-booking is handled by the unique constraints in `schema/table.sql`; this file does not duplicate those checks with triggers.
- The triggers do not guarantee that every employee has a subclass row. Add staff with the employee onboarding transaction, `CALL onboard_employee(...)` (defined in `employee.sql`), which inserts the `Employee` row and its subclass row together or neither. See `backend/transactions/README.md` for its arguments.
- Multi-table workflows should use transactions and roll back when a statement or trigger fails.
- Tested on a disposable MariaDB database: a fresh `table.sql` + `install.sql` + `seed.sql` installs all 25 triggers and both procedures, each trigger rejects (or, for `trg_bill_bu`, silently ignores) the bad change it guards against, and re-running `install.sql` leaves existing data untouched. Test changes the same way before merging them.
