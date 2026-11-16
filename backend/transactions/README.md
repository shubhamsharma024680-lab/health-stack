# Application transactions

The SQL each backend transaction runs, in the order the code runs it. Every one goes through `mysql-connector` with `%s` parameters, then `COMMIT`; a failed check or database error calls `ROLLBACK`. The same SQL is grouped by file in [`sql/`](sql/).

| Transaction | Endpoint | Code |
| --- | --- | --- |
| [Login](#login) | `POST /auth/login` | `auth.py` |
| [Register](#register) | `POST /auth/register` | `auth.py` |
| [Logout](#logout) | `DELETE /auth/session` | `auth.py` |
| [Book appointment](#book-appointment) | `POST /appointments` | `appointment.py` |
| [View appointments](#view-appointments) | `GET /patients/me/appointments` | `appointment.py` |
| [Cancel appointment](#cancel-appointment) | `PATCH /appointments/{id}/cancel` | `appointment.py` |
| [Reschedule appointment](#reschedule-appointment) | `PATCH /appointments/{id}/reschedule` | `appointment.py` |
| [Complete appointment](#complete-appointment) | `POST /appointments/{id}/complete` | `appointment.py` |
| [Complete bill](#complete-bill) | `POST /bills/{id}/payments` | `reception.py` |
| [Employee onboarding](#employee-onboarding) | none: stored procedure `onboard_employee` | `backend/triggers/employee.sql` |

## Login

Checks the account and password, then creates a session token.

```sql
START TRANSACTION;
SELECT Account_id, Password_hash, Role, User_id FROM AuthAccount WHERE Email = %s AND Role = %s;
-- no row: ROLLBACK, 401. Wrong password (checked in Python against the scrypt hash): ROLLBACK, 401.
INSERT INTO AuthSession (Token_hash, Account_id, Expires_at)
VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY));   -- SHA-256 of the token, never the token
COMMIT;
```

## Register

Checks for an existing email, then creates the patient, login account and session together.

```sql
START TRANSACTION;
SELECT Patient_id FROM Patient WHERE Mail = %s;
-- found: ROLLBACK, 403 "Already Registered"
INSERT INTO Patient (First_name, Last_name, Mail, Contact, DOB, Gender) VALUES (%s, %s, %s, %s, %s, %s);
INSERT INTO AuthAccount (Email, Password_hash, Role, User_id) VALUES (%s, %s, 'patient', %s);
INSERT INTO AuthSession (Token_hash, Account_id, Expires_at)
VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY));
COMMIT;
-- any database error: ROLLBACK, so no patient is left without a login.
--   duplicate email (1062, AuthAccount.Email is UNIQUE): 403 "Already Registered"
--   trigger SIGNAL (45000), e.g. a future date of birth: 409 with the trigger's message
```

## Logout

Deletes the session matching the token. A single statement, so it needs no explicit transaction.

```sql
DELETE FROM AuthSession WHERE Token_hash = %s;
COMMIT;
```

## Book appointment

Checks the doctor is active, then inserts the appointment. The slot rules (one of the six times, today to 3 days ahead, not in the past) are checked in Python first.

```sql
START TRANSACTION;
SELECT e.Is_active FROM Doctor d JOIN Employee e ON e.Employee_id = d.Employee_id WHERE d.Employee_id = %s;
-- no doctor or inactive: ROLLBACK, 404
INSERT INTO Appointment (Patient_id, Doctor_id, App_date, App_time) VALUES (%s, %s, %s, %s);
COMMIT;
```

There is no "is the slot free?" query. Two `UNIQUE` indexes on `Appointment` decide, so two requests at the same moment cannot both succeed:

- `UNIQUE (Doctor_id, App_date, App_time, Active_slot)`: the doctor is taken. Error 1062, `ROLLBACK`, 409 "This appointment slot is already occupied".
- `UNIQUE (Patient_id, App_date, App_time, Active_slot)`: the patient already has a visit then. Error 1062, `ROLLBACK`, 409 "You already have an appointment at this time".

`Active_slot` is `NULL` for cancelled appointments, so a cancelled slot can be booked again.

## View appointments

Read-only, so no transaction. The prescription and bill for each visit are fetched afterwards with `IN (...)`.

```sql
SELECT a.Appointment_id, a.Doctor_id, a.App_date, TIME_FORMAT(a.App_time, '%H:%i') AS App_time, a.App_status,
       e.First_name, e.Last_name, dep.Dept_name
FROM Appointment a
JOIN Employee e ON e.Employee_id = a.Doctor_id
LEFT JOIN Doctor d ON d.Employee_id = a.Doctor_id
LEFT JOIN Department dep ON dep.Dept_id = d.Dept_id
WHERE a.Patient_id = %s ORDER BY a.App_date DESC, a.App_time DESC;
```

## Cancel appointment

One guarded `UPDATE`. The row lock it takes makes the status check and the change one step, so a visit completed at the same moment cannot also be cancelled.

```sql
START TRANSACTION;
UPDATE Appointment SET App_status = 'Cancelled'
WHERE Appointment_id = %s AND Patient_id = %s AND App_status = 'Scheduled' AND App_date > %s;  -- %s = today
-- 0 rows changed: ROLLBACK, 409 "Appointment cannot be cancelled"
COMMIT;
```

## Reschedule appointment

Locks the appointment, checks it can still move, then moves it. The slot rules are checked in Python first, and the slot indexes reject a taken slot exactly as in booking.

```sql
START TRANSACTION;
SELECT Doctor_id, App_status, App_date FROM Appointment
WHERE Appointment_id = %s AND Patient_id = %s FOR UPDATE;
-- not found: ROLLBACK, 404. Not Scheduled, or today or earlier: ROLLBACK, 409
SELECT Is_active FROM Employee WHERE Employee_id = %s;
-- doctor inactive: ROLLBACK, 409
SELECT 1 FROM Prescription WHERE Appointment_id = %s
UNION SELECT 1 FROM Bill WHERE Appointment_id = %s;
-- any row: ROLLBACK, 409 "Appointment already has medical or billing records"
UPDATE Appointment SET App_date = %s, App_time = %s WHERE Appointment_id = %s;
COMMIT;
```

## Complete appointment

Locks the appointment, creates its prescription, medicine details and bill, then marks the appointment completed. Five tables change together or not at all.

```sql
START TRANSACTION;
SELECT a.App_status, a.App_date FROM Appointment a JOIN Employee e ON a.Doctor_id = e.Employee_id
WHERE a.Appointment_id = %s AND a.Doctor_id = %s AND e.Is_active = TRUE FOR UPDATE;
-- not found: ROLLBACK, 404. Not Scheduled, or a future date: ROLLBACK, 409
INSERT INTO Prescription (Appointment_id, Pres_date, Notes, Valid_until) VALUES (%s, %s, %s, %s);
-- for each medicine, in ascending Med_id order:
SELECT Price FROM Medicine WHERE Med_id = %s FOR UPDATE;   -- not found: ROLLBACK, 422
INSERT INTO Pres_Details (Pres_id, Med_id, Quantity, Dosage, Frequency, Unit_price) VALUES (%s, %s, %s, %s, %s, %s);
-- then:
INSERT INTO Bill (Appointment_id, Consultation_fee, Bill_amount, Bill_date) VALUES (%s, %s, %s, %s);
-- trg_bill_bi recomputes Bill_amount from the stored prices
UPDATE Appointment SET App_status = 'Completed' WHERE Appointment_id = %s;
UPDATE Doctor SET Current_appointment_id = NULL WHERE Employee_id = %s AND Current_appointment_id = %s;
COMMIT;
```

Medicines are locked in ascending `Med_id` order whatever order the doctor added them in. Two doctors prescribing the same medicines then always lock them in the same order, so they cannot deadlock waiting for each other.

## Complete bill

Locks the bill, checks it is still pending, and marks it paid by cash. The lock means two pharmacists cannot record the same payment.

```sql
START TRANSACTION;
SELECT Payment_status FROM Bill WHERE Bill_id = %s FOR UPDATE;
-- not found: ROLLBACK, 404. Not Pending: ROLLBACK, 409 "Bill is already paid."
UPDATE Bill SET Payment_status = 'Paid', Payment_mode = 'Cash', Paid_date = %s WHERE Bill_id = %s;
COMMIT;
```

## Employee onboarding

Adds an `Employee` row and its subclass row (Doctor, Nurse, Ward_boy, Receptionist or Pharmacist) together. There is no API endpoint or staff screen for this, so it is a stored procedure, `onboard_employee`, defined in [`backend/triggers/employee.sql`](../triggers/employee.sql) and installed by `backend/triggers/install.sql`. Run it from the MySQL client:

```sql
CALL onboard_employee(106, 'Asha', 'Menon', 'Female', '1990-02-14', CURDATE(),
                      'asha@demo.com', 118000, 'Doctor', 'DEMO-CARD-106', 2, 200, NULL, NULL);
-- arguments: id, first name, last name, gender, DOB, joining date, email, salary, role,
--            licence no. and department (doctors), fee (doctors, default 200),
--            ward (ward boys), desk (receptionists); NULL for the ones a role does not use
```

Inside, it runs:

```sql
START TRANSACTION;
INSERT INTO Employee (Employee_id, First_name, Last_name, Gender, DOB, Date_join, Mail, Salary, Role) VALUES (...);
INSERT INTO Doctor | Nurse | Ward_boy | Receptionist | Pharmacist (...) VALUES (...);  -- chosen by Role
COMMIT;
-- any error (a CHECK or NOT NULL, a foreign key, a duplicate email, a trigger such as
-- "at least 18 when joining", or a role with no subclass table): ROLLBACK, then the error is re-raised
```

The triggers check each row on its own; this transaction makes sure no employee is left without a subclass row. It does not create a login: staff logins are `AuthAccount` rows.
