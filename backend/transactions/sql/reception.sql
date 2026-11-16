-- Billing transaction, as run by backend/transactions/reception.py.
-- Reference only: the backend sends these with %s parameters; this file is not sourced.

-- COMPLETE BILL (pharmacist records a cash payment)
START TRANSACTION;
SELECT Payment_status FROM Bill WHERE Bill_id = %s FOR UPDATE;
-- not found: ROLLBACK, 404. Not Pending: ROLLBACK, 409 "Bill is already paid."
UPDATE Bill SET Payment_status = 'Paid', Payment_mode = 'Cash', Paid_date = %s WHERE Bill_id = %s;
COMMIT;
