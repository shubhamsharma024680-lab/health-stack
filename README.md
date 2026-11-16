# HealthStack

HealthStack is a hospital management system built around a MySQL database. It covers the part of a hospital's day that a patient actually sees: finding a doctor, booking a time slot, the consultation, the prescription and the bill. The web interface is branded **Careflow**.

There are three kinds of users, and each gets their own screens:

- **Patients** register and log in, browse departments and doctors, see a doctor's free slots, and book, cancel or reschedule appointments. They can see every past visit with its prescription and bill, and a dashboard of upcoming visits, running prescriptions and unpaid bills.
- **Doctors** see today's queue. Opening an appointment shows the patient's details and their full visit history across all doctors. Completing a visit records the prescription, and the system creates the bill automatically.
- **Pharmacists** see every unpaid bill with the medicines to dispense, and record payments.

The database is the core of the project. It does more than store rows: constraints and triggers enforce the hospital's rules, such as no double-booking, no prescription for a cancelled visit, and no change to an issued bill's calculated amount. These rules hold no matter which program writes the data. Every multi-step action, like completing a visit, runs as one transaction, so it either completes fully or leaves nothing behind.

| Layer    | Technology                                                            | Folder                                               |
| -------- | --------------------------------------------------------------------- | ---------------------------------------------------- |
| Database | MySQL 8.0.16+ (16 tables, 25 triggers, 1 stored procedure)            | `backend/schema`, `backend/seed`, `backend/triggers` |
| Backend  | Python 3, FastAPI, `mysql-connector-python` (21 endpoints)            | `backend/transactions`                               |
| Frontend | React 19, Vite, Tailwind CSS, React Router                            | `frontend/`                                          |

**Scope.** Hospital staff structure (employees, doctors, nurses, ward boys, receptionists, pharmacists, wards, departments) is fully modelled in the database. The application workflows cover outpatient care: appointments, prescriptions and billing. Ward admissions and technicians appear in the ER diagram as planned extensions.

This README is the project report for the DBIS course project (November 2026). **Demo videos:** [`docs/demo/`](docs/demo/), a walkthrough of all three roles and a recording of transactions, triggers and locks in the running app.

## Team

| Name            | Roll no.  | Main contributions                                                                          |
| --------------- | --------- | ------------------------------------------------------------------------------------------- |
| Darshik Ladhe   | 250001025 | FastAPI backend and its APIs (authentication, appointments, billing), triggers, seed data   |
| Deepak Chahar   | 250001026 | Schema design and fixes, ER diagram, frontend and its tests, documentation                  |
| Shubham Sharma  | 250051017 | Transactions, grouping the triggers and aligning them with the schema                       |
| Kedar Hadnurkar | 250001038 | Repository configuration                                                                    |

## Contents

1. [Getting started](#1-getting-started)
2. [ER model](#2-er-model)
3. [Schema and normal forms](#3-schema-and-normal-forms)
4. [Triggers](#4-triggers)
5. [Transactions](#5-transactions)
6. [Locking protocols](#6-locking-protocols)
7. [Backend](#7-backend)
8. [Frontend](#8-frontend)
9. [Concepts from class used here](#9-concepts-from-class-used-here)
10. [Limitations and future work](#10-limitations-and-future-work)

## 1. Getting started

### 1.1 Prerequisites

- Git
- MySQL 8.0.16 or newer. Older versions silently ignore `CHECK` constraints. MariaDB also works; the schema was tested on MariaDB 13.
- Python 3.10 or newer
- Node.js 20.19 or newer (needed by Vite)

### 1.2 Clone the repository

```bash
git clone https://github.com/shubhamsharma024680-lab/health-stack.git
cd health-stack
```

### 1.3 Create the database

Run both scripts from the project root, inside the MySQL client. `table.sql` drops and recreates every table and installs all triggers; `seed.sql` loads the demo data. Running both again resets the demo.

```bash
mysql -u root -p
mysql> SOURCE backend/schema/table.sql;
mysql> SOURCE backend/seed/seed.sql;
```

The last statement prints `Demo ready` and the number of accounts per role (10 patients, 4 doctors, 2 pharmacists).

### 1.4 Start the backend

The backend code lives in `backend/transactions/` and imports itself as the package `backend.transactions`, so the server is started **from the project root**. It reads its settings from `backend/transactions/.env`.

```bash
python -m venv backend/.venv
source backend/.venv/bin/activate                     # Windows: backend\.venv\Scripts\activate
pip install -r backend/requirements.txt
cp backend/.env.example backend/transactions/.env     # then set My_SQL_USER and My_SQL_PASSWORD
uvicorn backend.transactions.server:app --reload      # serves http://127.0.0.1:8000
```

Open <http://127.0.0.1:8000/health/db>; it should return `{"database": "connected"}`. If it returns `Database unavailable`, the user or password in `backend/transactions/.env` is wrong. Interactive API documentation is at <http://127.0.0.1:8000/docs>.

### 1.5 Start the frontend

In a second terminal:

```bash
cd frontend
cp .env.example .env          # VITE_API_URL=http://127.0.0.1:8000
npm install
npm run dev                   # serves http://localhost:5173
```

Keep the frontend on port 5173: the backend only accepts requests from `localhost:5173` and `127.0.0.1:5173` unless `FRONTEND_ORIGINS` in the backend `.env` is changed.

### 1.6 Log in

Open <http://localhost:5173>, pick a role and sign in. Every demo account uses the password `demo123`.

| Role       | Email                 | Who                               |
| ---------- | --------------------- | --------------------------------- |
| Patient    | `patient@demo.com`    | Aarav Mehta                       |
| Doctor     | `doctor@demo.com`     | Dr. Meera Iyer (General Medicine) |
| Pharmacist | `pharmacist@demo.com` | Riya Shah                         |

## 2. ER model

![HealthStack ER diagram](docs/diagrams/HealthStack_ER_updated.jpg)

### 2.1 Entities and specialisation

- **Employee** is the superclass of all staff. It is specialised into Doctor, Nurse, Ward_boy, Receptionist, Technician and Pharmacist. The specialisation is **disjoint** (the `d` in the triangle: one employee is in at most one subclass), **total** (double line: every employee is in some subclass) and attribute-defined by `Role`.
- `Name` (`First_name`, `Last_name`) and `Address` (`Street`, `City`, `State`) are composite attributes.
- `Active_slot` on Appointment is a derived attribute (dashed ellipse).
- **AuthAccount** and **AuthSession** hold logins and signed-in sessions. `User_id` is a `Patient_id` when `Role` = patient and an `Employee_id` otherwise.

### 2.2 Relationships

| Relationship                  | Between                          | Cardinality | Notes                                                    |
| ----------------------------- | -------------------------------- | ----------- | -------------------------------------------------------- |
| Books                         | Patient – Appointment            | 1:N         | Every appointment has a patient (total)                  |
| Attends                       | Doctor – Appointment             | 1:N         | Every appointment has a doctor (total)                   |
| Currently_attending           | Doctor – Appointment             | 1:1         | The visit a doctor is in right now (partial)             |
| Belongs_to                    | Department – Doctor              | 1:N         | Every doctor is in a department (total)                  |
| Issues                        | Appointment – Prescription       | 1:1         | At most one prescription per visit                       |
| Invoice                       | Appointment – Bill               | 1:1         | At most one bill per visit                               |
| Pres_Details                  | Prescription – Medicine          | M:N         | Attributes: Dosage, Quantity, Frequency, Unit_price      |
| Assigned_to                   | Ward – Ward_boy                  | 1:N         | Every ward boy has a ward (total)                        |
| Has                           | AuthAccount – AuthSession        | 1:N         | One account, many sessions                               |
| Admitted, Houses, Cares_for   | Patient, Ward, Nurse – Admission | 1:N         | Planned; not yet tables                                  |

### 2.3 Mapping the ER model to tables

- Composite attributes are split into one column per part.
- Each subclass becomes its own table whose primary key is also a foreign key to `Employee` (`ON DELETE CASCADE`). Triggers enforce that the subclass matches `Employee.Role`.
- 1:N relationships become a foreign key on the N side, `NOT NULL` where participation is total.
- 1:1 relationships (Issues, Invoice) become a `UNIQUE NOT NULL` foreign key.
- The M:N relationship Pres_Details becomes a junction table with the composite key `(Pres_id, Med_id)` and its four attributes.
- The derived `Active_slot` becomes a `STORED` generated column in Appointment.

## 3. Schema and normal forms

All tables are created by [`backend/schema/table.sql`](backend/schema/table.sql). **Bold** marks the primary key, → marks a foreign key, and (U) marks a `UNIQUE NOT NULL` column.

| Table          | Columns                                                                                                                          |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `Department`   | **Dept_id**, Dept_name (U), Description                                                                                          |
| `Employee`     | **Employee_id**, First_name, Last_name, Gender, DOB, Date_join, Mail (U), Salary, Role, Is_active                                |
| `Doctor`       | **Employee_id** → Employee, License_no (U), Current_appointment_id, Dept_id → Department, Consultation_fee                       |
| `Nurse`        | **Employee_id** → Employee                                                                                                       |
| `Ward`         | **Ward_id**, Ward_name (U), Capacity                                                                                             |
| `Ward_boy`     | **Employee_id** → Employee, Ward_id → Ward                                                                                       |
| `Receptionist` | **Employee_id** → Employee, Desk_no                                                                                              |
| `Pharmacist`   | **Employee_id** → Employee                                                                                                       |
| `Patient`      | **Patient_id**, First_name, Last_name, Gender, DOB, Mail, Contact, Street, City, State, History                                  |
| `Appointment`  | **Appointment_id**, Patient_id → Patient, Doctor_id → Doctor, App_date, App_time, App_status, Active_slot (generated)            |
| `Prescription` | **Pres_id**, Appointment_id → Appointment (U), Pres_date, Notes, Valid_until                                                     |
| `Medicine`     | **Med_id**, Med_name, Price                                                                                                      |
| `Pres_Details` | **(Pres_id → Prescription, Med_id → Medicine)**, Dosage, Quantity, Frequency, Unit_price                                         |
| `Bill`         | **Bill_id**, Appointment_id → Appointment (U), Consultation_fee, Bill_amount, Bill_date, Paid_date, Payment_status, Payment_mode |
| `AuthAccount`  | **Account_id**, Email (U), Password_hash, Role, User_id; `UNIQUE (Role, User_id)`                                                |
| `AuthSession`  | **Token_hash**, Account_id → AuthAccount, Expires_at                                                                             |

`CHECK` constraints cover values such as gender, status, `Salary >= 0` and `Date_join > DOB`.

<details>
<summary><b>Full column types and constraints</b> (PK = primary key, FK = foreign key, NN = <code>NOT NULL</code>, AI = <code>AUTO_INCREMENT</code>)</summary>

| Table                  | Column                     | Type          | Constraints                                                                                     |
| ---------------------- | -------------------------- | ------------- | ----------------------------------------------------------------------------------------------- |
| **Department**         | Dept_id                    | INT           | PK                                                                                              |
|                        | Dept_name                  | VARCHAR(100)  | UNIQUE, NN                                                                                      |
|                        | Description                | TEXT          |                                                                                                 |
| **Employee**           | Employee_id                | INT           | PK                                                                                              |
|                        | First_name, Last_name      | VARCHAR(50)   | NN                                                                                              |
|                        | Gender                     | VARCHAR(10)   | NN; CHECK in (Male, Female, Other)                                                              |
|                        | DOB                        | DATE          | NN                                                                                              |
|                        | Date_join                  | DATE          | NN; CHECK (Date_join > DOB)                                                                     |
|                        | Mail                       | VARCHAR(100)  | UNIQUE, NN                                                                                      |
|                        | Salary                     | DECIMAL(10,2) | NN; CHECK (Salary >= 0)                                                                         |
|                        | Role                       | VARCHAR(20)   | NN; CHECK in (Doctor, Nurse, Ward_boy, Receptionist, Technician, Pharmacist)                    |
|                        | Is_active                  | BOOLEAN       | NN, DEFAULT TRUE                                                                                |
| **Doctor**             | Employee_id                | INT           | PK; FK → Employee ON DELETE CASCADE                                                             |
|                        | License_no                 | VARCHAR(50)   | UNIQUE, NN                                                                                      |
|                        | Current_appointment_id     | INT           | NULL allowed                                                                                    |
|                        | Dept_id                    | INT           | NN; FK → Department ON DELETE RESTRICT                                                          |
|                        | Consultation_fee           | DECIMAL(10,2) | NN, DEFAULT 200; CHECK (>= 0)                                                                   |
| **Nurse**, **Pharmacist** | Employee_id             | INT           | PK; FK → Employee ON DELETE CASCADE                                                             |
| **Ward**               | Ward_id                    | INT           | PK                                                                                              |
|                        | Ward_name                  | VARCHAR(50)   | UNIQUE, NN                                                                                      |
|                        | Capacity                   | INT           | NN; CHECK (Capacity > 0)                                                                        |
| **Ward_boy**           | Employee_id                | INT           | PK; FK → Employee ON DELETE CASCADE                                                             |
|                        | Ward_id                    | INT           | NN; FK → Ward ON DELETE RESTRICT                                                                |
| **Receptionist**       | Employee_id                | INT           | PK; FK → Employee ON DELETE CASCADE                                                             |
|                        | Desk_no                    | VARCHAR(20)   | NN                                                                                              |
| **Patient**            | Patient_id                 | INT           | PK, AI                                                                                          |
|                        | First_name, Last_name      | VARCHAR(50)   | NN                                                                                              |
|                        | Gender                     | VARCHAR(10)   | NN; CHECK in (Male, Female, Other)                                                              |
|                        | DOB                        | DATE          | NN                                                                                              |
|                        | Mail                       | VARCHAR(100)  |                                                                                                 |
|                        | Contact                    | VARCHAR(20)   | NN                                                                                              |
|                        | Street                     | VARCHAR(100)  |                                                                                                 |
|                        | City, State                | VARCHAR(50)   |                                                                                                 |
|                        | History                    | TEXT          |                                                                                                 |
| **Appointment**        | Appointment_id             | INT           | PK, AI                                                                                          |
|                        | Patient_id                 | INT           | NN; FK → Patient ON DELETE RESTRICT                                                             |
|                        | Doctor_id                  | INT           | NN; FK → Doctor ON DELETE RESTRICT                                                              |
|                        | App_date                   | DATE          | NN                                                                                              |
|                        | App_time                   | TIME          | NN                                                                                              |
|                        | App_status                 | VARCHAR(20)   | NN, DEFAULT 'Scheduled'; CHECK in (Scheduled, Completed, Cancelled)                             |
|                        | Active_slot                | TINYINT       | GENERATED AS (IF(App_status = 'Cancelled', NULL, 1)) STORED                                     |
|                        | *table constraints*        |               | UNIQUE (Doctor_id, App_date, App_time, Active_slot); UNIQUE (Patient_id, App_date, App_time, Active_slot) |
| **Prescription**       | Pres_id                    | INT           | PK, AI                                                                                          |
|                        | Appointment_id             | INT           | UNIQUE, NN; FK → Appointment ON DELETE RESTRICT                                                 |
|                        | Pres_date                  | DATE          | NN                                                                                              |
|                        | Notes                      | TEXT          |                                                                                                 |
|                        | Valid_until                | DATE          | NN                                                                                              |
| **Medicine**           | Med_id                     | INT           | PK                                                                                              |
|                        | Med_name                   | VARCHAR(100)  | NN                                                                                              |
|                        | Price                      | DECIMAL(10,2) | NN; CHECK (Price >= 0)                                                                          |
| **Pres_Details**       | Pres_id                    | INT           | PK (with Med_id); FK → Prescription ON DELETE CASCADE                                           |
|                        | Med_id                     | INT           | PK (with Pres_id); FK → Medicine ON DELETE RESTRICT                                             |
|                        | Dosage                     | VARCHAR(50)   | NN                                                                                              |
|                        | Quantity                   | INT           | NN; CHECK (Quantity > 0)                                                                        |
|                        | Frequency                  | VARCHAR(50)   | NN                                                                                              |
|                        | Unit_price                 | DECIMAL(10,2) | NN, DEFAULT 0; CHECK (>= 0)                                                                     |
| **Bill**               | Bill_id                    | INT           | PK, AI                                                                                          |
|                        | Appointment_id             | INT           | UNIQUE, NN; FK → Appointment ON DELETE RESTRICT                                                 |
|                        | Consultation_fee           | DECIMAL(10,2) | NN, DEFAULT 200; CHECK (>= 0)                                                                   |
|                        | Bill_amount                | DECIMAL(10,2) | NN, DEFAULT 200; CHECK (>= 0)                                                                   |
|                        | Bill_date                  | DATE          | NN                                                                                              |
|                        | Paid_date                  | DATE          | NULL allowed                                                                                    |
|                        | Payment_status             | VARCHAR(10)   | NN, DEFAULT 'Pending'; CHECK in (Pending, Paid)                                                 |
|                        | Payment_mode               | VARCHAR(50)   | CHECK in (Cash, Card, UPI, Insurance, NetBanking)                                               |
|                        | *table constraint*         |               | CHECK (Payment_status = 'Pending' OR Payment_mode IS NOT NULL)                                  |
| **AuthAccount**        | Account_id                 | INT           | PK, AI                                                                                          |
|                        | Email                      | VARCHAR(100)  | UNIQUE, NN                                                                                      |
|                        | Password_hash              | VARCHAR(255)  | NN                                                                                              |
|                        | Role                       | ENUM          | NN; ('patient', 'doctor', 'pharmacist')                                                         |
|                        | User_id                    | INT           | NN; UNIQUE (Role, User_id)                                                                      |
| **AuthSession**        | Token_hash                 | CHAR(64)      | PK                                                                                              |
|                        | Account_id                 | INT           | NN; FK → AuthAccount ON DELETE CASCADE                                                          |
|                        | Expires_at                 | DATETIME      | NN                                                                                              |

</details>

**Design decisions**

- **No double-booking.** `Active_slot` is `1` for a live appointment and `NULL` for a cancelled one. A unique index allows repeated `NULL`s, so the two `UNIQUE` indexes `(Doctor_id, App_date, App_time, Active_slot)` and `(Patient_id, App_date, App_time, Active_slot)` stop a doctor or a patient from having two live appointments in the same slot, while a cancelled slot can be booked again.
- **Bills keep their price.** `Pres_Details.Unit_price` records the price when the medicine was prescribed, so later price changes never alter an issued bill.
- **Staff are deactivated, not deleted.** `ON DELETE RESTRICT` on `Appointment.Doctor_id` protects history; `Is_active = FALSE` stops new bookings instead.
- **Secrets are never stored in plain text.** `Password_hash` holds a salted scrypt hash, and `AuthSession` stores the SHA-256 hash of each session token.
- **Polymorphic login.** `AuthAccount.User_id` points at `Patient` or `Employee` depending on `Role`, so it cannot have a foreign key; the application keeps it consistent.

### 3.1 Definitions

Let R be a relation and X, Y sets of its attributes. A **functional dependency** (FD) X → Y means any two rows that agree on X also agree on Y; it is trivial if Y ⊆ X. A **candidate key** is a minimal set of attributes that determines all of R. An attribute is **prime** if it belongs to some candidate key.

- **1NF**: every attribute holds a single atomic value, and the relation has a key (no duplicate rows).
- **2NF**: 1NF, and no non-prime attribute depends on a proper subset of a candidate key (no partial dependency). A relation whose candidate keys are all single attributes is automatically in 2NF.
- **3NF**: for every non-trivial FD X → A, either X is a superkey or A is prime. This rules out transitive dependencies key → X → A.
- **BCNF**: for every non-trivial FD X → A, X is a superkey.

Same-row checks such as `Date_join > DOB` are constraints, not FDs.

### 3.2 Normal form of each table

| Table          | Candidate keys                         | Non-trivial FDs                          | 1NF | 2NF | 3NF | BCNF | Reason                                                                           |
| -------------- | -------------------------------------- | ---------------------------------------- | :-: | :-: | :-: | :--: | -------------------------------------------------------------------------------- |
| `Department`   | {Dept_id}, {Dept_name}                 | each key → all                           | ✓   | ✓   | ✓   | ✓    | Only keys determine anything                                                     |
| `Employee`     | {Employee_id}, {Mail}                  | each key → all                           | ✓   | ✓   | ✓   | ✓    | Role ↛ Salary (doctors 101 and 102 earn different salaries)                      |
| `Doctor`       | {Employee_id}, {License_no}            | each key → all                           | ✓   | ✓   | ✓   | ✓    | Dept_id ↛ Consultation_fee: the fee is per doctor                                |
| `Nurse`        | {Employee_id}                          | none                                     | ✓   | ✓   | ✓   | ✓    | Single column                                                                    |
| `Ward`         | {Ward_id}, {Ward_name}                 | each key → all                           | ✓   | ✓   | ✓   | ✓    | Only keys determine anything                                                     |
| `Ward_boy`     | {Employee_id}                          | Employee_id → Ward_id                    | ✓   | ✓   | ✓   | ✓    | A ward has many ward boys, so Ward_id is not a key                               |
| `Receptionist` | {Employee_id}                          | Employee_id → Desk_no                    | ✓   | ✓   | ✓   | ✓    | Desks can be shared                                                              |
| `Pharmacist`   | {Employee_id}                          | none                                     | ✓   | ✓   | ✓   | ✓    | Single column                                                                    |
| `Patient`      | {Patient_id}                           | Patient_id → all                         | ✓   | ✓   | ✓   | ✓    | Mail is nullable and not unique; City ↛ State (city names repeat across states)  |
| `Appointment`  | {Appointment_id}                       | key → all; **App_status → Active_slot**  | ✓   | ✓   | ✗   | ✗    | See note 1                                                                       |
| `Prescription` | {Pres_id}, {Appointment_id}            | each key → all                           | ✓   | ✓   | ✓   | ✓    | One prescription per appointment                                                 |
| `Medicine`     | {Med_id}                               | Med_id → all                             | ✓   | ✓   | ✓   | ✓    | Med_name is not unique                                                           |
| `Pres_Details` | {Pres_id, Med_id}                      | (Pres_id, Med_id) → rest                 | ✓   | ✓   | ✓   | ✓    | See note 2                                                                       |
| `Bill`         | {Bill_id}, {Appointment_id}            | each key → all; **∅ → Consultation_fee** | ✓   | ✓   | ✗   | ✗    | See note 3                                                                       |
| `AuthAccount`  | {Account_id}, {Email}, {Role, User_id} | each key → all                           | ✓   | ✓   | ✓   | ✓    | Neither Role nor User_id alone determines anything (no partial dependency)       |
| `AuthSession`  | {Token_hash}                           | Token_hash → all                         | ✓   | ✓   | ✓   | ✓    | An account can have many sessions                                                |

**14 of the 16 tables are in BCNF.** The two exceptions are deliberate or easy to fix:

1. **Appointment** (2NF) stores the derived column `Active_slot`, so `Appointment_id → App_status → Active_slot` is transitive. MySQL computes the column itself (`GENERATED … STORED`), so it can never disagree with `App_status`. It exists only to make the unique index skip cancelled rows, which MySQL can't do any other way. Without it, the table is in BCNF.
2. **Pres_Details** might look like it has the partial dependency `Med_id → Unit_price`. It doesn't: `Unit_price` is the price at the time of prescribing, copied by a trigger, so the same medicine can have different prices in older and newer prescriptions. Dosage and quantity also vary per pair (medicine 1 is 10 tablets in prescription 1 and 6 in prescription 6).
3. **Bill** (2NF): trigger `trg_bill_bi` always sets `Consultation_fee = 200`, so the column is a constant. Any non-key attribute then determines it (for example `Bill_date → Consultation_fee`), which breaks 3NF. Copying the doctor's own `Consultation_fee` into the bill makes the table BCNF.

### 3.3 Derivations

**Method.** For each table we list the FDs that the schema enforces (primary keys, `UNIQUE NOT NULL` columns, generated columns, values forced by triggers). For dependencies one might expect, we show why they do not hold, using the seed data or the application's rules. Checks that compare two values in the same row, such as `Date_join > DOB`, are constraints, not FDs, and do not affect the normal form.

<details>
<summary><b>Table-by-table FD derivations</b></summary>

**Department and Ward.** Department(<u>Dept_id</u>, Dept_name, Description), Ward(<u>Ward_id</u>, Ward_name, Capacity).
FDs: Dept_id → Dept_name, Description and Dept_name → Dept_id, Description (`Dept_name` is `UNIQUE NOT NULL`). The same holds for `Ward_id` and `Ward_name`. `Description` and `Capacity` determine nothing: two wards can have the same capacity.
*Result:* every determinant is a candidate key, so both tables are in **BCNF**.

**Employee.** Employee(<u>Employee_id</u>, First_name, Last_name, Gender, DOB, Date_join, Mail, Salary, Role, Is_active).
FDs: Employee_id → all; Mail → all (`UNIQUE NOT NULL`).
Not FDs: Role ↛ Salary (doctors 101 and 102 earn 120000 and 140000); a name is not unique.
*Result:* both determinants are keys, so **BCNF**.

**Doctor.** Doctor(<u>Employee_id</u>, License_no, Current_appointment_id, Dept_id, Consultation_fee).
FDs: Employee_id → all; License_no → all.
Not FDs: Dept_id ↛ Consultation_fee: the fee is stored per doctor, and departments have several doctors. `Current_appointment_id` is nullable and shared by many doctors as `NULL`, so it determines nothing.
*Result:* **BCNF**.

**Nurse, Pharmacist, Ward_boy and Receptionist.** Nurse and Pharmacist have the single attribute `Employee_id`, so they have no non-trivial FDs. Ward_boy(<u>Employee_id</u>, Ward_id) has only Employee_id → Ward_id; a ward has several ward boys, so Ward_id ↛ Employee_id. Receptionist(<u>Employee_id</u>, Desk_no) has only Employee_id → Desk_no; desks can be shared.
*Result:* all four are in **BCNF**.

**Patient.** Patient(<u>Patient_id</u>, First_name, Last_name, Gender, DOB, Mail, Contact, Street, City, State, History).
FDs: Patient_id → all.
Not FDs: `Mail` and `Contact` are not keys (`Mail` is nullable, and family members may share a phone or email). City ↛ State, because city names repeat across states (Aurangabad is in Maharashtra and in Bihar). The composite ER attributes are already split into atomic columns, so the table is in 1NF.
*Result:* **BCNF**.

**Appointment (2NF).** Appointment(<u>Appointment_id</u>, Patient_id, Doctor_id, App_date, App_time, App_status, Active_slot).
FDs: Appointment_id → all, and App_status → Active_slot, because `Active_slot` is the generated column `IF(App_status = 'Cancelled', NULL, 1)`.
Not keys: (`Doctor_id`, `App_date`, `App_time`) is not a key, since a cancelled appointment and a new booking can share a slot. The `UNIQUE` index that includes `Active_slot` is not a candidate key either, because `Active_slot` is `NULL` for cancelled rows.

| Form | Holds? | Reason |
| ---- | :----: | ------ |
| 1NF  | ✓ | Atomic values, primary key |
| 2NF  | ✓ | The only candidate key is a single attribute |
| 3NF  | ✗ | App_status → Active_slot: App_status is not a superkey and Active_slot is not prime. This is the transitive chain Appointment_id → App_status → Active_slot |
| BCNF | ✗ | Fails for the same FD |

*Why this is acceptable.* The column exists only to stop double-booking: `UNIQUE (Doctor_id, App_date, App_time, Active_slot)` must ignore cancelled appointments, and MySQL has no filtered unique index. Moving `Active_slot` to another table (the 3NF decomposition) would make that constraint span two tables, which SQL cannot enforce. The anomaly 3NF guards against cannot happen here: MySQL computes the column, and nobody can write it. Without `Active_slot` the table is in BCNF.

**Prescription and Medicine.** Prescription(<u>Pres_id</u>, Appointment_id, Pres_date, Notes, Valid_until) has Pres_id → all and Appointment_id → all (`UNIQUE NOT NULL`: one prescription per visit). Pres_date ↛ Valid_until, because the doctor chooses the validity per prescription. Medicine(<u>Med_id</u>, Med_name, Price) has only Med_id → all; `Med_name` is not declared unique.
*Result:* both are in **BCNF**.

**Pres_Details.** Pres_Details(<u>Pres_id, Med_id</u>, Dosage, Quantity, Frequency, Unit_price).
FDs: (Pres_id, Med_id) → Dosage, Quantity, Frequency, Unit_price.
2NF check (partial dependencies):

- Pres_id ↛ Quantity: prescription 1 lists 10 of medicine 1 and 2 of medicine 2.
- Med_id ↛ Quantity: medicine 1 is 10 tablets in prescription 1 and 6 in prescription 6.
- Med_id ↛ Unit_price: trigger `trg_pres_details_bi` copies `Medicine.Price` when the line is inserted and `trg_pres_details_bu` keeps it afterwards. `Unit_price` is the price *at the time of prescribing*, so after a price change the same medicine has different unit prices in old and new prescriptions.

*Result:* the only determinant is the key, so **BCNF**. If `Unit_price` simply mirrored today's price, Med_id → Unit_price would be a partial dependency and the table would drop to 1NF; storing a snapshot is what keeps it normalised.

**Bill (2NF).** Bill(<u>Bill_id</u>, Appointment_id, Consultation_fee, Bill_amount, Bill_date, Paid_date, Payment_status, Payment_mode).
FDs: Bill_id → all; Appointment_id → all (one bill per visit); and ∅ → Consultation_fee, because trigger `trg_bill_bi` sets the fee to 200 on every insert and `trg_bill_bu` never lets it change. A constant column is determined by every set of attributes, for example Bill_date → Consultation_fee.
Not FDs: `Bill_amount` is computed from the visit's prescription, which within Bill is just Appointment_id → Bill_amount, already implied by the key. `Paid_date`, `Payment_status` and `Payment_mode` are not linked by any FD.

| Form | Holds? | Reason |
| ---- | :----: | ------ |
| 1NF  | ✓ | Atomic values, primary key |
| 2NF  | ✓ | All candidate keys are single attributes |
| 3NF  | ✗ | Bill_date → Consultation_fee: the determinant is not a superkey and the fee is not prime |
| BCNF | ✗ | Fails for the same FD |

*Fix.* Make `trg_bill_bi` copy the doctor's own `Doctor.Consultation_fee` instead of the constant 200. The column then records the fee at billing time, the constant FD disappears, and Bill is in BCNF. This also fixes the billing logic, which today ignores per-doctor fees.

**AuthAccount and AuthSession.** AuthAccount(<u>Account_id</u>, Email, Password_hash, Role, User_id) has three candidate keys: {Account_id}, {Email} and {Role, User_id} (`UNIQUE`, both `NOT NULL`). For 2NF, neither part of the composite key determines anything alone: many accounts share a role, and a `User_id` number can be both a patient and an employee. AuthSession(<u>Token_hash</u>, Account_id, Expires_at) has only Token_hash → all; an account can have several sessions.
*Result:* both are in **BCNF**.

</details>

## 4. Triggers

`table.sql` installs 25 triggers and one stored procedure. The definitions are also grouped by topic in [`backend/triggers/`](backend/triggers/); running [`install.sql`](backend/triggers/install.sql) reinstalls them without touching data.

All triggers run `BEFORE` the row is written, once per row. A trigger either rejects the change with `SIGNAL SQLSTATE '45000'`, which cancels the statement and returns a message, or fills in values with `SET NEW.column = …`. The backend turns SQLSTATE 45000 into an HTTP 409 carrying the trigger's message.

| Trigger(s)                            | Table (event)                                                  | Rule                                                                                              |
| ------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Staff roles**                       |                                                                |                                                                                                   |
| `check_employee_role` (procedure)     | —                                                              | Signals unless the employee exists with the given `Role`                                          |
| `trg_<subclass>_role_bi / _bu` (10)   | Doctor, Nurse, Ward_boy, Receptionist, Pharmacist (insert, update) | A subclass row is accepted only if `Employee.Role` matches: the **disjoint** specialisation   |
| `trg_employee_role_lock`              | Employee (update)                                              | `Role` cannot change while the employee still has a subclass row                                  |
| **Dates**                             |                                                                |                                                                                                   |
| `trg_employee_dates_bi / _bu`         | Employee (insert, update)                                      | DOB before today, joining date not in the future, at least 18 when joining                        |
| `trg_patient_dob_bi / _bu`            | Patient (insert, update)                                       | DOB not in the future                                                                             |
| `trg_prescription_bi / _bu`           | Prescription (insert, update)                                  | Not for a cancelled appointment; not dated before the appointment                                 |
| **Prescriptions**                     |                                                                |                                                                                                   |
| `trg_pres_details_bi`                 | Pres_Details (insert)                                          | Refused once the visit is billed; sets `Unit_price` from `Medicine.Price`                         |
| `trg_pres_details_bu`                 | Pres_Details (update)                                          | Refused once billed; re-prices only if the medicine changed                                       |
| `trg_pres_details_bd`                 | Pres_Details (delete)                                          | Refused once billed                                                                               |
| `trg_prescription_bd`                 | Prescription (delete)                                          | A billed prescription cannot be deleted. Needed because MySQL does not fire triggers for rows removed by `ON DELETE CASCADE` |
| **Billing**                           |                                                                |                                                                                                   |
| `trg_bill_bi`                         | Bill (insert)                                                  | Not for a cancelled visit or before its date; sets the fee to 200 and computes `Bill_amount`      |
| `trg_bill_bu`                         | Bill (update)                                                  | Amounts and appointment are frozen; the bill date is validated and payment fields may change      |
| **Appointments**                      |                                                                |                                                                                                   |
| `trg_appointment_bi`                  | Appointment (insert)                                           | The doctor must be active                                                                         |
| `trg_appointment_bu`                  | Appointment (update)                                           | A new doctor must be active; a visit with a prescription or bill cannot be cancelled              |

A `CHECK` constraint cannot express these rules: `CHECK` cannot call `CURDATE()`, read another table, or change a value. The bill trigger shows both kinds of work, rejecting and computing:

```sql
CREATE TRIGGER trg_bill_bi BEFORE INSERT ON Bill FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM Appointment
               WHERE Appointment_id = NEW.Appointment_id AND App_status = 'Cancelled') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'cannot bill a cancelled appointment';
    END IF;
    -- (date check omitted)
    SET NEW.Consultation_fee = 200;
    SET NEW.Bill_amount = NEW.Consultation_fee + (
        SELECT COALESCE(SUM(pd.Quantity * pd.Unit_price), 0)
        FROM Prescription p JOIN Pres_Details pd ON pd.Pres_id = p.Pres_id
        WHERE p.Appointment_id = NEW.Appointment_id);
END
```

`COALESCE` turns the `NULL` sum of a visit with no medicines into 0, so a consultation-only bill is 200.

## 5. Transactions

The SQL for each transaction is also listed in [`backend/transactions/README.md`](backend/transactions/README.md) and [`backend/transactions/sql/`](backend/transactions/sql/). Every transaction is run by the backend through `mysql-connector`: `START TRANSACTION`, the statements with `%s` parameters (never string concatenation, which prevents SQL injection), then `COMMIT`. Failed operations are rolled back explicitly or when their uncommitted connections close.

### 5.1 Login

```sql
START TRANSACTION;
SELECT Account_id, Password_hash, Role, User_id FROM AuthAccount WHERE Email = %s AND Role = %s;
-- no row: ROLLBACK (401). Wrong password: ROLLBACK (401).
INSERT INTO AuthSession (Token_hash, Account_id, Expires_at)
VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY));
COMMIT;
```

The password is verified in Python against the scrypt hash between the two statements. A random 32-byte token is returned to the client; only its SHA-256 hash is stored.

### 5.2 Register a patient

```sql
START TRANSACTION;
SELECT Patient_id FROM Patient WHERE Mail = %s;            -- found: ROLLBACK
INSERT INTO Patient (First_name, Last_name, Mail, Contact, DOB, Gender) VALUES (%s, %s, %s, %s, %s, %s);
INSERT INTO AuthAccount (Email, Password_hash, Role, User_id) VALUES (%s, %s, 'patient', %s);
INSERT INTO AuthSession (Token_hash, Account_id, Expires_at)
VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY));
COMMIT;
```

The three inserts commit together, so a patient never exists without a login. Each new ID comes from `cursor.lastrowid`.

### 5.3 Logout

```sql
DELETE FROM AuthSession WHERE Token_hash = %s;
```

A single statement, so it needs no explicit transaction.

### 5.4 Book an appointment

```sql
START TRANSACTION;
SELECT e.Is_active FROM Doctor d JOIN Employee e ON e.Employee_id = d.Employee_id
WHERE d.Employee_id = %s;                                  -- missing or inactive: ROLLBACK
INSERT INTO Appointment (Patient_id, Doctor_id, App_date, App_time) VALUES (%s, %s, %s, %s);
COMMIT;
```

The slot rules (one of six times, within the next 3 days, in the future) are checked in Python first. There is no "is the slot free?" query: the unique slot indexes reject a clash with error 1062, which the backend returns as 409 "This appointment slot is already occupied". So two patients booking the same slot at the same moment can't both succeed.

### 5.5 View appointments

```sql
SELECT a.Appointment_id, a.App_date, a.App_time, a.App_status, e.First_name, e.Last_name
FROM Appointment a JOIN Employee e ON e.Employee_id = a.Doctor_id
WHERE a.Patient_id = %s ORDER BY a.App_date DESC, a.App_time DESC;
```

A read-only join, so it needs no transaction. The prescription and bill for each visit are fetched afterwards with `IN (…)`.

### 5.6 Cancel and reschedule

```sql
-- cancel: one guarded UPDATE; 0 rows changed means it could not be cancelled
UPDATE Appointment SET App_status = 'Cancelled'
WHERE Appointment_id = %s AND Patient_id = %s AND App_status = 'Scheduled' AND App_date > %s;

-- reschedule
START TRANSACTION;
SELECT Doctor_id, App_status, App_date FROM Appointment
WHERE Appointment_id = %s AND Patient_id = %s FOR UPDATE;
SELECT 1 FROM Prescription WHERE Appointment_id = %s
UNION SELECT 1 FROM Bill WHERE Appointment_id = %s;        -- any row: ROLLBACK
UPDATE Appointment SET App_date = %s, App_time = %s WHERE Appointment_id = %s;
COMMIT;
```

### 5.7 Complete a visit (doctor)

```sql
START TRANSACTION;
SELECT a.App_status, a.App_date FROM Appointment a JOIN Employee e ON a.Doctor_id = e.Employee_id
WHERE a.Appointment_id = %s AND a.Doctor_id = %s AND e.Is_active = TRUE FOR UPDATE;
INSERT INTO Prescription (Appointment_id, Pres_date, Notes, Valid_until) VALUES (%s, %s, %s, %s);
-- for each medicine:
SELECT Price FROM Medicine WHERE Med_id = %s FOR UPDATE;
INSERT INTO Pres_Details (Pres_id, Med_id, Quantity, Dosage, Frequency, Unit_price)
VALUES (%s, %s, %s, %s, %s, %s);
-- then:
INSERT INTO Bill (Appointment_id, Consultation_fee, Bill_amount, Bill_date) VALUES (%s, %s, %s, %s);
UPDATE Appointment SET App_status = 'Completed' WHERE Appointment_id = %s;
UPDATE Doctor SET Current_appointment_id = NULL
WHERE Employee_id = %s AND Current_appointment_id = %s;
COMMIT;
```

This is the largest transaction: five tables change together. `FOR UPDATE` locks the appointment, so a double click can't complete it twice, and the bill trigger recomputes the total. If any step fails (an unknown medicine, a trigger, a lost connection), the prescription, its medicines and the bill are all undone.

### 5.8 Record a payment (pharmacist)

```sql
START TRANSACTION;
SELECT Payment_status FROM Bill WHERE Bill_id = %s FOR UPDATE;   -- missing or not Pending: ROLLBACK
UPDATE Bill SET Payment_status = 'Paid', Payment_mode = 'Cash', Paid_date = %s WHERE Bill_id = %s;
COMMIT;
```

The row lock means two staff members can't both record the same payment (see [6.3](#63-example-two-pharmacists-pay-the-same-bill)).

### 5.9 ACID properties

| Property        | How HealthStack achieves it                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Atomicity**   | Every multi-step action runs between `START TRANSACTION` and `COMMIT`; any failure, including a trigger's `SIGNAL`, leads to `ROLLBACK`. A connection closed without committing is rolled back by the server. |
| **Consistency** | `CHECK`, `UNIQUE` and foreign-key constraints plus the 25 triggers. The bill trigger recomputes the total, so a wrong amount cannot be stored.              |
| **Isolation**   | InnoDB's `REPEATABLE READ` level and `SELECT … FOR UPDATE` on contested rows (section 6).                                                                    |
| **Durability**  | InnoDB writes its redo log to disk on every commit (`innodb_flush_log_at_trx_commit = 1`, the default).                                                      |

## 6. Locking protocols

### 6.1 How InnoDB locks

MySQL's InnoDB engine primarily locks index records (and also uses intention locks), and runs at the `REPEATABLE READ` isolation level by default.

- A plain `SELECT` takes no lock. It reads a consistent snapshot (multi-version concurrency control), so readers never block writers. This is used for all read-only screens.
- `SELECT … FOR UPDATE` takes an exclusive (X) lock on every row it reads. Another transaction that tries to lock or change the same row waits until the first one commits or rolls back.
- `UPDATE`, `DELETE` and `INSERT` take X locks on the rows they change. An `INSERT` that collides with an uncommitted row on a `UNIQUE` index waits for that transaction, then fails with a duplicate-key error if it committed.
- Write locks are generally held until `COMMIT` or `ROLLBACK`, preventing conflicting modifications to locked rows. This does not make every `REPEATABLE READ` transaction schedule serialisable.

### 6.2 Where HealthStack takes locks

| Transaction      | Rows locked (X)                                                           | Race it prevents                                                                                       |
| ---------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Complete a visit | The appointment (`FOR UPDATE`), then each prescribed medicine (`FOR UPDATE`) | Two clicks completing the same visit twice; a medicine's price changing between reading it and storing it |
| Record a payment | The bill (`FOR UPDATE`)                                                   | Two pharmacists recording the same payment                                                             |
| Reschedule       | The appointment (`FOR UPDATE`)                                            | The visit being completed or cancelled while it is being moved                                         |
| Cancel           | The appointment (implicit, from `UPDATE`)                                 | Cancelling a visit that was just completed; the `WHERE` re-checks the status under the lock            |
| Book             | No explicit lock; the `UNIQUE` slot index                                 | Two patients booking the same slot: the second insert waits, then gets error 1062                     |

### 6.3 Example: two pharmacists pay the same bill

| Time | Session A                                                                   | Session B                                                                       |
| :--: | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1    | `START TRANSACTION`                                                         |                                                                                 |
| 2    | `SELECT … FROM Bill WHERE Bill_id = 7 FOR UPDATE` ⇒ Pending, row locked     |                                                                                 |
| 3    |                                                                             | `START TRANSACTION`                                                             |
| 4    |                                                                             | `SELECT … FOR UPDATE` on the same bill: **waits**                               |
| 5    | `UPDATE Bill SET Payment_status = 'Paid' …; COMMIT` (lock released)         |                                                                                 |
| 6    |                                                                             | Gets the row: status is now Paid; returns 409 "Bill is already paid"; `ROLLBACK` |

Without `FOR UPDATE`, both sessions would read Pending at steps 2 and 4 and both would record the payment.

### 6.4 Rules we follow

- **Lock first, check second, write last.** A check is only reliable while the row it read is locked.
- **Keep transactions short.** Locks are held until commit, so no transaction waits for user input.
- **Deadlocks.** If two transactions wait for each other, InnoDB detects the cycle and rolls one back with error 1213; the API returns an error and the user can retry. A lock that is not released within `innodb_lock_wait_timeout` (50 s by default) also fails the waiting statement. Locking medicines in ascending `Med_id` order reduces deadlock risk when doctors prescribe the same medicines in different orders.

## 7. Backend

### 7.1 Architecture

```
Browser (React app) ──HTTP──▶ server.py ──▶ middleware.py ──▶ route: role check + SQL ──%s params──▶ MySQL
                              CORS, routers  who is calling?                                        constraints, triggers
```

The backend is a FastAPI application. Each request passes the CORS check in `server.py`, is matched to a router, and, if the route needs a login, goes through `getCurrentUser` in `middleware.py`. The route checks the caller's role, opens its own database connection, runs its SQL and closes the connection in a `finally` block.

### 7.2 Modules

All modules are in [`backend/transactions/`](backend/transactions/).

| File             | Responsibility                                                                                                                         |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `server.py`      | Creates the app, loads `.env`, configures CORS, defines `getDBconnection()`, the six time slots and the 3-day booking window, and registers the routers |
| `middleware.py`  | `getCurrentUser`: hashes the bearer token and looks up an unexpired session; returns `{accountId, role, userId}` or 401                |
| `helpers.py`     | Password hashing and verification (scrypt with a random 16-byte salt, constant-time comparison)                                        |
| `auth.py`        | Login, patient registration, current profile, logout                                                                                   |
| `patient.py`     | The patient's own profile and dashboard counts                                                                                         |
| `doctor.py`      | Departments, doctor directory and profile, free slots, medicine catalogue, the doctor's queue for today                                |
| `appointment.py` | Book, list, view, cancel, reschedule and complete appointments; maps database errors to HTTP codes                                     |
| `reception.py`   | Pending bills with prescribed medicines; recording a payment                                                                           |

### 7.3 Endpoints

| Method | Path                            | Caller                | Purpose                                                  |
| ------ | ------------------------------- | --------------------- | -------------------------------------------------------- |
| GET    | `/health/db`                    | anyone                | Database connectivity check                              |
| POST   | `/auth/login`                   | anyone                | Log in, returns token and profile                        |
| POST   | `/auth/register`                | anyone                | Patient self-registration                                |
| GET    | `/auth/me`                      | logged in             | Current profile                                          |
| DELETE | `/auth/session`                 | logged in             | Log out                                                  |
| GET    | `/patients/me`                  | patient               | Own details                                              |
| GET    | `/patients/me/dashboard`        | patient               | Upcoming visits, unpaid bills, running prescriptions     |
| GET    | `/patients/me/appointments`     | patient               | All own visits with prescription and bill                |
| GET    | `/departments`                  | anyone                | Department list                                          |
| GET    | `/doctors`                      | anyone                | Active doctors, optional department filter               |
| GET    | `/doctors/{id}`                 | anyone                | Doctor profile                                           |
| GET    | `/doctors/{id}/slots?date=`     | anyone                | Free slots on a date                                     |
| GET    | `/medicines`                    | logged in             | Medicine catalogue                                       |
| GET    | `/doctors/me/appointments`      | doctor                | Today's queue                                            |
| POST   | `/appointments`                 | patient               | Book                                                     |
| GET    | `/appointments/{id}`            | its patient or doctor | Visit details; doctors also get patient history          |
| PATCH  | `/appointments/{id}/cancel`     | patient               | Cancel                                                   |
| PATCH  | `/appointments/{id}/reschedule` | patient               | Reschedule                                               |
| POST   | `/appointments/{id}/complete`   | doctor                | Prescription + bill                                      |
| GET    | `/reception/pending-bills`      | pharmacist            | Unpaid bills with medicines                              |
| POST   | `/bills/{id}/payments`          | pharmacist            | Record payment                                           |

### 7.4 Authentication and errors

- **Passwords** are stored as `scrypt$<salt>$<hash>` (n = 16384, r = 8, p = 1). scrypt is deliberately slow, so a stolen hash is expensive to guess.
- **Sessions:** login creates a random token (`secrets.token_urlsafe(32)`), valid for one day. The client sends it as `Authorization: Bearer <token>`; the server stores and compares only its SHA-256 hash.
- **Authorisation:** every protected route checks the caller's role (403 otherwise), and reads the patient or doctor ID from the session, never from the URL, so users can only see their own records.
- **Error mapping:** duplicate key (1062) ⇒ 409 "slot already occupied"; trigger `SIGNAL` (SQLSTATE 45000) ⇒ 409 with the trigger's message; anything else ⇒ 500.
- **Time:** all "today" checks in Python use Asia/Kolkata time.

## 8. Frontend

### 8.1 Overview

The frontend is a single-page React 19 application built with Vite, styled with Tailwind CSS, routed with React Router and using Lucide icons. It shows only the workflows the backend supports, so no button promises something the server cannot do.

- `src/api/client.js` is the only place that calls the server. It adds the bearer token (kept in `sessionStorage`) and turns error responses into readable messages; a 401 sends the user back to the login page.
- `src/api/normalize.js` maps database column names to the shapes the screens use, and converts rupees to integer paise to avoid rounding errors.
- `src/pages/` holds one folder per area (overview, appointments, doctors, prescriptions, billing); `src/components/` holds shared parts such as the app shell, data tables, dialogs and the slot picker.
- Each route renders a different screen per role, and a role with no screen for a route sees "access denied".
- `npm test` (in `frontend/`) runs 18 tests of the booking rules and the API contract.

| Route                      | Patient                                 | Doctor                                     | Pharmacist                    |
| -------------------------- | --------------------------------------- | ------------------------------------------ | ----------------------------- |
| `/overview`                | Dashboard                               | Today's numbers                            | Pending-bill numbers          |
| `/appointments`            | Own visits by tab, reschedule, cancel   | Today's queue                              | –                             |
| `/appointments/:id`        | Visit, prescription, bill               | Patient details, history, complete visit   | –                             |
| `/doctors`, `/doctors/:id` | Directory, slots, booking               | –                                          | –                             |
| `/prescriptions`           | Running and past prescriptions          | –                                          | –                             |
| `/billing`, `/billing/:id` | Own bills                               | –                                          | Pending bills, record payment |
| `/settings`                | Profile                                 | Profile                                    | Profile                       |

### 8.2 Screenshots

Taken from the running application with the seed data loaded.

**Public pages**

| | |
| :-: | :-: |
| ![Sign in, with a role picker](docs/report/screenshots/01-login.png) Sign in, with a role picker | ![Patient registration](docs/report/screenshots/02-register.png) Patient registration |

**Patient overview**

<p align="center"><img src="docs/report/screenshots/03-patient-overview.png" alt="Patient overview" width="90%"><br>Upcoming visits, running prescriptions and amount due</p>

**Finding a doctor and booking**

| | |
| :-: | :-: |
| ![Doctor directory](docs/report/screenshots/04-doctors.png) Doctor directory | ![Booking dialog](docs/report/screenshots/05-booking.png) Booking dialog with free slots |

**Patient appointments**

| | |
| :-: | :-: |
| ![Appointment list](docs/report/screenshots/06-appointments.png) Appointment list | ![Completed visit](docs/report/screenshots/07-visit-detail.png) A completed visit with its prescription |

**Patient prescriptions and bills**

| | |
| :-: | :-: |
| ![Prescriptions](docs/report/screenshots/08-prescriptions.png) Prescriptions | ![Patient bill](docs/report/screenshots/09-patient-bill.png) Bill: consultation fee plus medicines |

**Doctor screens**

| | |
| :-: | :-: |
| ![Doctor queue](docs/report/screenshots/10-doctor-queue.png) Today's queue | ![Visit history](docs/report/screenshots/11-doctor-visit-history.png) Patient's visit history |

<p align="center"><img src="docs/report/screenshots/12-complete-visit.png" alt="Completing a visit" width="90%"><br>Completing a visit: notes, validity and medicines. Submitting runs the complete-visit transaction</p>

**Pharmacist screens.** The bill created in the previous screenshot appears here as CF-B-0007 (₹244 = 200 + 2 × 2 + 4 × 10).

| | |
| :-: | :-: |
| ![Pending bills](docs/report/screenshots/13-pending-bills.png) Pending bills | ![Record payment](docs/report/screenshots/14-record-payment.png) Recording a payment |

<p align="center"><img src="docs/report/screenshots/15-mobile-overview.png" alt="Mobile layout" width="300"><br>The layout adapts to phone screens</p>

## 9. Concepts from class used here

| Taught in the tutorials and lab                                     | Where HealthStack uses it                                                             |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `SELECT … WHERE … ORDER BY`                                         | Doctor list, free slots, today's queue                                                |
| `JOIN`, `LEFT JOIN`                                                 | Appointments with doctor and department; pending bills with an optional prescription  |
| `COUNT`, `SUM`, subqueries                                          | Dashboard counts; bill total and date checks inside triggers                          |
| `START TRANSACTION`, `COMMIT`, `ROLLBACK`                           | Every write in section 5                                                              |
| `SELECT … FOR UPDATE`                                               | Complete appointment, pay bill, reschedule                                            |
| `BEFORE` triggers with `SIGNAL SQLSTATE '45000'`                    | All 25 triggers                                                                       |
| Trigger that sets `NEW.column`                                      | `Unit_price` and `Bill_amount`                                                        |
| `mysql.connector` with `%s` parameters, `try/except` + `rollback()` | Every endpoint (no string-built SQL, so no SQL injection)                             |

Used beyond the tutorials: one stored procedure, a `STORED` generated column, `ENUM`, `UNION`, and `IF EXISTS` inside triggers.

## 10. Limitations and future work

- **Technician** and **Admission** (ward admissions) are in the ER diagram but not yet implemented as tables; `Employee.Role` still accepts `'Technician'`.
- The consultation fee is fixed at 200 instead of the doctor's own fee; fixing it also brings `Bill` to BCNF (section 3.2, note 3).
- `AuthAccount.Role` does not include receptionists, nurses or ward boys, so only patients, doctors and pharmacists can log in, and only pharmacists can use the billing screens.
- Payments are always recorded as Cash; there is no payment gateway.
