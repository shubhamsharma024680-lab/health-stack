-- Appointment transactions, as run by backend/transactions/appointment.py.
-- Reference only: the backend sends these with %s parameters; this file is not sourced.

-- BOOK APPOINTMENT (patient)
-- Slot rules (one of six times, today to 3 days ahead, not in the past) are checked in Python first.
START TRANSACTION;
SELECT e.Is_active FROM Doctor d JOIN Employee e ON e.Employee_id = d.Employee_id WHERE d.Employee_id = %s;
-- no doctor or inactive: ROLLBACK, 404
INSERT INTO Appointment (Patient_id, Doctor_id, App_date, App_time) VALUES (%s, %s, %s, %s);
-- No "is the slot free?" query: the UNIQUE slot indexes decide (error 1062, then ROLLBACK).
--   UNIQUE (Doctor_id, ...)  -> 409 "This appointment slot is already occupied"
--   UNIQUE (Patient_id, ...) -> 409 "You already have an appointment at this time"
COMMIT;


-- VIEW APPOINTMENTS (patient, read-only: no transaction)
SELECT a.Appointment_id, a.Doctor_id, a.App_date, TIME_FORMAT(a.App_time, '%H:%i') AS App_time, a.App_status,
       e.First_name, e.Last_name, dep.Dept_name
FROM Appointment a
JOIN Employee e ON e.Employee_id = a.Doctor_id
LEFT JOIN Doctor d ON d.Employee_id = a.Doctor_id
LEFT JOIN Department dep ON dep.Dept_id = d.Dept_id
WHERE a.Patient_id = %s ORDER BY a.App_date DESC, a.App_time DESC;
-- then the prescriptions, medicines and bills of those appointments with IN (...)


-- CANCEL APPOINTMENT (patient)
START TRANSACTION;
UPDATE Appointment SET App_status = 'Cancelled'
WHERE Appointment_id = %s AND Patient_id = %s AND App_status = 'Scheduled' AND App_date > %s;  -- %s = today
-- 0 rows changed: ROLLBACK, 409 "Appointment cannot be cancelled"
COMMIT;


-- RESCHEDULE APPOINTMENT (patient)
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
-- a taken slot fails on the UNIQUE slot indexes exactly as in booking
COMMIT;


-- COMPLETE APPOINTMENT (doctor)
START TRANSACTION;
SELECT a.App_status, a.App_date FROM Appointment a JOIN Employee e ON a.Doctor_id = e.Employee_id
WHERE a.Appointment_id = %s AND a.Doctor_id = %s AND e.Is_active = TRUE FOR UPDATE;
-- not found: ROLLBACK, 404. Not Scheduled, or a future date: ROLLBACK, 409
INSERT INTO Prescription (Appointment_id, Pres_date, Notes, Valid_until) VALUES (%s, %s, %s, %s);
-- for each medicine, in ascending Med_id order (a fixed lock order, so two doctors cannot deadlock):
SELECT Price FROM Medicine WHERE Med_id = %s FOR UPDATE;   -- not found: ROLLBACK, 422
INSERT INTO Pres_Details (Pres_id, Med_id, Quantity, Dosage, Frequency, Unit_price) VALUES (%s, %s, %s, %s, %s, %s);
-- then:
INSERT INTO Bill (Appointment_id, Consultation_fee, Bill_amount, Bill_date) VALUES (%s, %s, %s, %s);
-- trg_bill_bi recomputes Bill_amount from the stored prices
UPDATE Appointment SET App_status = 'Completed' WHERE Appointment_id = %s;
UPDATE Doctor SET Current_appointment_id = NULL WHERE Employee_id = %s AND Current_appointment_id = %s;
COMMIT;
