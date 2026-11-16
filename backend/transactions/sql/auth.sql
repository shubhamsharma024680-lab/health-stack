-- Authentication transactions, as run by backend/transactions/auth.py.
-- Reference only: the backend sends these with %s parameters; this file is not sourced.

-- LOGIN
START TRANSACTION;
SELECT Account_id, Password_hash, Role, User_id FROM AuthAccount WHERE Email = %s AND Role = %s;
-- no row: ROLLBACK, 401. Wrong password (checked in Python against the scrypt hash): ROLLBACK, 401.
INSERT INTO AuthSession (Token_hash, Account_id, Expires_at)
VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY));   -- SHA-256 of the token, never the token
COMMIT;


-- REGISTER (patient)
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


-- LOGOUT (a single statement, so no explicit transaction)
DELETE FROM AuthSession WHERE Token_hash = %s;
COMMIT;
