-- Installs all 25 triggers and two procedures: check_employee_role (used by the
-- triggers) and onboard_employee (the employee onboarding transaction).
-- Run from the project root, after backend/schema/table.sql and before backend/seed/seed.sql.
-- Safe to run again at any time: each file drops its triggers before recreating them,
-- and no table data is touched.
use Healthstack;

source backend/triggers/employee.sql;
source backend/triggers/date_validation.sql;
source backend/triggers/prescription.sql;
source backend/triggers/billing.sql;
source backend/triggers/appointment.sql;

